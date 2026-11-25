---
type: Spec
title: DJI Mic Control Flutter Application Specification
description: Functional, UI/UX, hardware protocol, OS capability probing, and testing specification for the Linux-first Flutter port of DJI-Mic-Control.
status: draft
tags: [flutter, linux, usb, dji-mic, spec]
---

# Specification: DJI Mic Control (Flutter)

## 1. Purpose and Goals

Build a Linux-first (and cross-platform structured) desktop Flutter application at `apps/dji-mic-control/` that provides full functional and visual parity with `ShadowBitBasher/DJI-Mic-Control` (`v1.1.0`), plus graceful runtime detection and OS-specific install guidance for optional desktop capabilities (notifications, system tray, USB permissions).

### Core Design Principles

1. **Core Flutter and Dart standard library first:** No third-party UI frameworks, no third-party state management packages, and **zero** third-party native/OS Flutter plugins. Prefer in-house MIT code or license-compatible vendored code over external packages; only trusted Dart/Flutter team packages (`flutter`, `flutter_test`, `flutter_lints`, `integration_test`, `meta`, `ffi`) are allowed as dependencies. Only Flutter's unavoidable Linux desktop embedder libraries (GTK3/GLib/Epoxy/Fontconfig) may be linked at build time.
2. **Graceful OS capability probing:** Optional OS features (notifications, tray host, autostart, USB permissions) are probed at runtime. When a capability or library is absent on the user's OS, the app continues working without crashing and displays actionable, OS-specific install/setup instructions in-app.
3. **Transport-neutral architecture:** Protocol decoding, device state, and UI live in pure Dart/Flutter behind a narrow `AppServices` and `UsbTransport` seam. Linux starts with a pure-Dart `sysfs` + `usbfs` implementation; once the full app is complete and verified, a thin Rust `nusb` `cdylib` drops in behind the same `UsbTransport` seam for cross-platform USB support without touching protocol or UI code. Deterministic byte-level hardware simulation (`--demo` mode) and fast headless testing follow `apps/hue-controller/`.
4. **Preserve USB audio functionality:** USB access must detach and claim vendor Interface `6` only, never disturbing USB Audio interfaces (interfaces 1 to 3).

### Non-Goals (Initial Release)

- Firmware flashing / DFU updates for DJI microphones.
- Audio recording, DSP processing, or replacing PipeWire/PulseAudio/ALSA mixer controls.
- Supporting DJI Mic 1, DJI Mic 2, or DJI Mic 3 until their wire protocols are documented (architecture must preserve the `DeviceModel` extension point).
- Bundling third-party native desktop Flutter plugins (`tray_manager`, `window_manager`, `local_notifier`, `shared_preferences`, `path_provider`).

---

## 2. Project Layout

Target app directory: `apps/dji-mic-control/` (leveraging the existing Flutter `3.47.7` / Dart `3.13.5` SDK at `/home/chris.guest/sdk/flutter`).

| Path | Responsibility |
| --- | --- |
| `lib/protocol/` | Pure Dart DUML framing, CRC-8, v1/v2 CRC-16, `DeviceModel`, `MicMiniModel`, setting definitions, `DeviceStatus`, `TxInfo`, `RxInfo`, `Firmware`. Zero Flutter or FFI imports. |
| `lib/transport/` | Narrow `UsbTransport` interface, `DeviceManager` (1000 ms scan, per-device actor, 1500 ms liveness window), `LinuxUsbfsTransport` (`sysfs` + `usbfs` ioctl via `dart:ffi` `libc`), and optional `RustNusbTransport` adapter if enabled. |
| `lib/platform/` | Zero-plugin OS integrations and runtime capability probes: `CapabilitiesProbe`, `Notifier`, `TrayService`, `WindowController`, `AutostartService`, `SingleInstance`, `ConfigStore`, `UdevHelper`. |
| `lib/sim/` | Byte-level `SimulatedDjiMic` speaking real v1/v2 DUML frames (with fault injection: `EACCES`, unplug, no-signal, critical battery, Mic Mini 2 TX) and `--demo` mode fixture. |
| `lib/state/` | `AppServices` dependency container and `MicController` (`ChangeNotifier`) managing selection, polling/streams, optimistic writes, rollback, banners, and diagnostics log. |
| `lib/ui/` | Pure Flutter widgets matching upstream visual design (`ThemeExtension<AppColors>`, `AppShell`, `Sidebar`, `DevicePanel`, `BatteryIcon`, `AudioLevelMeter`, `SettingControl`, `NoiseCancelControl`, `SetupModal`, `CapabilitiesSheet`, `DiagnosticsView`). |
| `linux/runner/` | Standard Flutter GTK3 runner plus ~40 to 60 lines in `my_application.cc` for `--hidden` startup, `delete-event` close-to-tray interception, and `dji_mic/window` `FlMethodChannel`. |
| `assets/devices/` | Device artwork (`mic-mini-rx.png`, `mic-mini-tx.png`, `mic-mini-2-tx.png`) and app icon (`128x128.png`). |
| `test/` & `integration_test/` | Protocol hex-vector tests, transport/capability unit tests, widget tests, and dual-mode E2E tests (`flutter_tester` headless + `-d linux`). |
| `packaging/` | `60-dji-mic.rules`, `.desktop` entry, postinstall/postremove scripts, and Linux release bundle script. |

---

## 3. Hardware Protocol and Device Management Specification

### 3.1 Supported Devices and Transport Contract

- **Model:** `MicMini` (`id: "dji-mic-mini"`, `name: "DJI Mic Mini"`, `VID: 0x2ca3`, `PID: 0x4011`).
- **USB interface:** Interface `6` (`bulkIn: 0x86`, `bulkOut: 0x06`, read buffer `>= 512` bytes, default alt setting `0`).
- **Kernel driver detach:** Detach kernel driver on Interface `6` only (`USBDEVFS_DISCONNECT_CLAIM` with `EXCEPT_DRIVER="usbfs"` on Linux). Never touch USB Audio interfaces.
- **Device ID:** USB descriptor serial string when non-empty, else `usb-<bus>-<address>`.
- **Discovery and liveness:**
  - Scan USB bus every `1000 ms`, pruning dead device actors and adopting newly attached receivers.
  - Mark device `connected = true` only when a decoded heartbeat/status frame arrived within `LIVE_WINDOW_MS = 1500 ms`.
  - Detect `EACCES` (`errno 13`) on open and surface `Probe.permissionIssue = true` with count of detected-but-inaccessible devices.
- **Concurrency:** Each open device runs in a background Dart `Isolate` (or native worker thread) so continuous 10 Hz bulk reads and command writes never block UI rendering. On Linux `usbfs`, `poll([usbfs_fd, eventfd])` wakes immediately when a command is queued or the device is closed.

### 3.2 DUML Framing and Dialects

- **Frame envelope:** `[0x55][len][0x04][hdr_crc8][payload...][crc16_lo][crc16_hi]`, where `4 <= len <= 256` (must allow `>= 182` bytes for 2-TX Mic Mini 2 v2 identity pushes).
- **Resync rule:** Scan for `buf[i] == 0x55 && buf[i + 2] == 0x04 && 4 <= buf[i + 1] <= 256`. Do NOT reject incoming device-to-host frames by command CRC-16 residue.
- **CRC-16:** Reflected polynomial `0x8408` with reverse-solved trailing bytes:
  - v1: `init = 0x0000`, `residue = 0xbb01`, header CRC-8 `0x03`, 19-byte commands, **big-endian** command ID.
  - v2: `init = 0x3692`, `residue = 0x0000`, header CRC-8 `0xfc`, 22-byte commands with LE target (`0x0000` RX, `0xffff` broadcast TX, `0x0001` TX1, `0x0002` TX2), **little-endian** command ID.
- **Dialect detection:** Passive from heartbeat byte `11` (`0x00` = v1, `0x03` = v2). Block outgoing commands until `protocolVersion != null`.
- **Sequence numbers:** 16-bit LE per actor starting at `1`, wrapping mod `65536`. Incoming 14-byte ACKs (`role == 0x80`) are ignored; optimistic state confirms from subsequent heartbeats.

### 3.3 Telemetry Decoding Rules

- **v1 monolithic heartbeat (~10 Hz, 56/70/84 bytes):**
  - Decode two variable-size TX slots (23 bytes when `flags & 0x20 != 0`, 9-byte stub otherwise) followed by 22-byte RX block.
  - Forward 4-byte firmware `[a, b, c, d]` formatted `aa.bb.cc.dd`.
- **v2 split pushes (all marked `[8..12] = 00 5b 03 03`):**
  - Try `decodeV2Status` first (`len >= 54 && (len - 54) % 32 == 0`); otherwise fall back to `decodeV2Records` (TLV records starting at offset `14`: tag `0x01` reversed-byte firmware + 14-byte ASCII serial, tag `0x05` 1-byte audio level, tag `0x06` ASCII product name, skip tag `0x04`).
  - Stateful merge: carry forward learned RX/TX identity and TX audio levels across status ticks; use offset `44` bitmask (`0x01` TX1, `0x02` TX2) as authoritative TX connection state; index 32-byte TX slots by physical unit byte `slot[+1] - 1` (never loop index).
  - Parse `gainDial` at offset `22` as signed `int8` dB (`+12`, `+6`, `0`, `-6`, `-12`).
  - Parse per-TX `charging` (`slot[+7] & 0x02 != 0`) and `battery` (`(slot[+7] >> 2) & 0x07`, 1 = full to 7 = critical).

### 3.4 Complete Settings Matrix (13 Settings)

| Setting ID | UI Label | Group | Kind | v1 Cmd (BE) | v2 Cmd (LE) | v2 Target | Values (wire hex) | Constraints / Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `noise-cancel-power` | Noise Cancelling | Audio | Toggle | Read-only | `0x0038` | `0xffff` | `off: 0x00`, `on: 0x01` | Locked on v1; parent row of composite NC block |
| `noise-cancel` | Mode (Noise Cancel) | Audio | Enum | `0x031d` | `0x0037` | `0xffff` | `basic: 0x00`, `strong: 0x01` | Locked when `ncEnabled == false`; sub-row 1 |
| `noise-cancel-button` | Toggle via TX power button | Audio | Toggle | None | `0x000f` | `0xffff` | `off: 0x00`, `on: 0x01` | Locked on v1; sub-row 2 |
| `low-cut` | Low Cut | Audio | Toggle | `0x0303` | `0x0003` | `0xffff` | `off: 0x00`, `on: 0x01` | Readable on v2 when >=1 TX connected |
| `stereo` | Audio Channels | Audio | Enum | `0x0008` | `0x0008` | `0x0000` | `mono: 0x00`, `stereo: 0x02` | Mutually exclusive with `safety-track` |
| `safety-track` | Safety Track | Audio | Toggle | `0x0021` | `0x0021` | `0x0000` | `off: 0x00`, `on: 0x01` | Mutually exclusive with `stereo` |
| `clip-limiter` | Clipping Control | Audio | Toggle | `0x001e` | `0x001e` | `0x0000` | `off: 0x00`, `on: 0x01` | |
| `auto-off-15m` | Auto Off RX (15 min) | Power & Startup | Toggle | `0x0010` | `0x0010` | `0x0000` | `off: 0x00`, `on: 0x01` | |
| `tx-auto-off-15m` | Auto Off TX (15 min) | Power & Startup | Toggle | None | `0x0010` | `0xffff` | `off: 0x00`, `on: 0x01` | Locked on v1; readable when >=1 TX connected |
| `camera-power` | RX On/Off follows Camera | Power & Startup | Toggle | `0x0020` | `0x0020` | `0x0000` | `off: 0x00`, `on: 0x01` | |
| `plug-free` | Plug-Free Ext. Speaker | Device | Toggle | `0x0023` | `0x0023` | `0x0000` | `off: 0x00`, `on: 0x01` | Note: "Changing this reboots the receiver." USB drops & re-enumerates |
| `mic-leds` | Mic LEDs | Device | Toggle | `0x030a` | `0x000a` | `0xffff` | `off: 0x02`, `on: 0x00` | Inverted wire values & status bit |
| `voice-tone` | Voice Tone | Audio (TX card) | Enum | None | `0x0029` | `0x0001`/`0x0002` | `standard: 0x00`, `rich: 0x01`, `bright: 0x02` | Rendered per-TX on Mic Mini 2 TX cards only (v2) |

---

## 4. UI and Interaction Specification

### 4.1 Window, Theme, and Design Tokens

- **Window geometry:** Default `1300 x 775`, minimum `760 x 540`. Respect `--hidden` / `--minimized` CLI flags on launch.
- **Window chrome:** Use native OS window decorations (simplest, most maintainable option across X11/Wayland/macOS/Windows, giving native minimize, maximize/restore, snapping, and edge-resize for free), paired with a slim `38px` in-app top toolbar hosting the sidebar toggle, centered `DJI Mic Control` title, and quick access to the **System & Capabilities** and **Diagnostics** dialogs. Native minimize minimizes to the taskbar normally; native close either quits normally or hides to the system tray when close-to-tray is enabled and an active tray host is detected.
- **Theme:** Follow OS light/dark theme (`ThemeMode.system`) with an optional manual Light/Dark/System override in app preferences. Exact upstream palette via `ThemeExtension<AppColors>`:
  - **Light:** `bg #f4f5f7`, `bgPanel #ffffff`, `bgElev #fbfbfc`, `border #e2e4e9`, `borderStrong #cfd3da`, `text #1b1d21`, `textDim #6b7280`, `textFaint #9aa0aa`, `accent #2f7de1`, `accentContrast #ffffff`, `accentSoft rgba(47,125,225,0.12)`, `good #21a065`, `warn #d98324`, `danger #d64545`.
  - **Dark:** `bg #16181d`, `bgPanel #1e2127`, `bgElev #23262e`, `border #2c313a`, `borderStrong #3a4048`, `text #e9ebef`, `textDim #9aa1ad`, `textFaint #6d7682`, `accent #5b9bf0`, `accentContrast #0d1117`, `accentSoft rgba(91,155,240,0.16)`, `good #37c185`, `warn #e0a250`, `danger #eb6a6a`.
  - **Radii:** `12px` panels/cards, `8px` controls/inner pills, `999px` switches/badges.
  - **Typography:** OS system UI font, `14px` base, `FontFeature.tabularFigures()` for serials, firmware versions, and gain dB values; system monospace for udev rules and diagnostic logs.

### 4.2 Layout and Screens

1. **Collapsible Sidebar (`260px` animated to `0px` over `220ms`, `Curves.ease`):**
   - Header `"DEVICES"`; empty text `"No devices"`.
   - Device rows: `40x40` RX pictogram, bold model name, serial/ID subtitle, inline `TX1`/`TX2` mini `BatteryIcon` (`16px`) when present, and `9x9` status dot (green with translucent halo when connected, gray when connecting).
   - Clicking empty sidebar space deselects (`selected = null`, `userDeselected = true`) without auto-reselecting on subsequent updates.
2. **Top-Stacked Banners:**
   - **OS USB Access Banner (amber):** Shown when `permissionIssue == true` and `devices.isEmpty` (Linux udev banner; on Windows, optional driver guidance if USB open fails). Clicking opens the OS USB Setup Modal.
   - **Error Banner (red):** Shown on USB/command error; dismissible or cleared on next setting write.
3. **Empty / Placeholder Main States (centered `maxWidth: 340`):**
   - USB permission issue: `"Permission needed"` + CTA `"Show setup instructions"`.
   - User deselected while devices exist: `"No device selected"` / `"Choose a device from the sidebar."`
   - No devices: `"No microphone connected"` / `"Connect a supported DJI microphone over USB to get started."`
4. **Device Panel:**
   - **Header:** `54x54` RX pictogram, model title (`20px`), RX serial/ID subtitle, and right-aligned `"Connected"` (green) or `"No signal"` (gray) pill.
   - **Status Cards Grid (`repeat(auto-fit, minmax(200px, 1fr))`, `14px` gap):**
     - **Receiver card:** `40x40` RX pictogram, `Serial`, `Firmware` (`"Unknown"` when null), `Protocol` pill (`v1` blue / `v2` purple `#a855f7`), and `Gain` dB readout on v2 (highlighted `--warn` at `0 dB`).
     - **TX1 and TX2 cards:** Dynamic label (`"<productName> (TX1)"` once known, else `"TX1"`), inline `20px` `BatteryIcon`, `38x38` TX pictogram (`mic-mini-2-tx.png` for Mic Mini 2; suppressed on v2 while `productName == null` to prevent flicker), `"Disconnected"` when absent, or `Serial`, `Firmware`, **Audio Level VU Meter**, and per-TX **Voice Tone** segmented control (Mic Mini 2 on v2 only).
   - **Audio Level VU Meter:** Maps raw `u8` level via `clamp(0, 100, round((v / 80) * 100))`. `8px` pill bar with 5-stop horizontal gradient (`#2ea043 0%`, `#57b846 35%`, `#e0b400 68%`, `#e8863a 85%`, `#e5484d 100%`) masked on the right by an animated `--bg` overlay (`90ms`, `Curves.linear`). Pauses animation when window is hidden.
   - **BatteryIcon (`CustomPainter`):**
     - `1`: `"Fully Charged"` (`--good`, 100%).
     - `2..4`: `"Good"` (`--good`, 75% / 50% / 25%).
     - `5`: `"Low"` (`--warn`, 25%).
     - `6`: `"Very Low"` (`--danger`, 0%).
     - `7`: `"Critical"` (`--danger`, 0%, hard-cut 500 ms on / 500 ms off blinking `!` unless charging).
     - Charging bolt overlays battery center with `--bg-panel` knockout stroke (takes priority over `!`). Hover tooltip shows `"Battery: <label>"` + `" (charging)"`.
   - **Settings Section:**
     - Header `"SETTINGS"` + `Compact | List` segmented view toggle (persisted in `config.json`).
     - **Compact view (default):** Balanced multi-column masonry (`MIN_COL = 260`, `COL_GAP = 18`, height heuristic `items.length + 1.5`) grouping `Audio`, `Power & Startup`, and `Device` cards with compact pill switches (`36x21`; `28x17` sub-switch) and `⚠` tooltip for notes.
     - **List view:** Single full-width card with `1px` dividers, full switches (`42x25`; `32x19` sub-switch), and inline note text.
     - **Composite Noise Cancelling block:** Main `Noise Cancelling` switch (`noise-cancel-power`) with two indented sub-rows: `Mode` (`Basic` / `Strong`) and `Toggle via TX power button`.
     - **Locking & exclusivity:** Locked controls dim to `0.4` opacity, ignore pointer events, and display a lock icon with hover tooltip explaining the reason (v2 firmware required, Noise Cancelling off, or mutually exclusive setting active).
     - **Unknown values:** Render a subtle `--` placeholder (using double hyphen, avoiding em-dashes per repo rules).
     - **Optimistic updates:** Flip immediately on click, show progress cursor while USB write is in flight, retire optimistic override once a subsequent heartbeat confirms the value (plus a 3-second safety timeout so silently rejected writes never stick indefinitely), and revert immediately with an error banner on write failure.

---

## 5. Optional OS Capabilities and In-App Suggestions Specification

The app includes a **System & Capabilities** modal/panel (accessible from the top bar and from relevant banners/toggles) that inspects the running OS at startup and on demand, reporting the live status of each capability (`Active`, `Available`, `Unavailable / Setup Needed`) with copyable OS-specific commands.

### 5.1 Capability Probe Contract

| Capability | Linux Detection | Linux In-App Suggestion When Missing | macOS / Windows Equivalent |
| --- | --- | --- | --- |
| **USB Device Access** | Check `/sys/bus/usb/devices/*` for `2ca3:4011`; attempt `O_RDWR` on `/dev/bus/usb/BBB/DDD`; check presence of `60-dji-mic.rules` in `/etc/udev/rules.d/` or `/usr/lib/udev/rules.d/` | If rule missing: show exact udev rule + `sudo tee /etc/udev/rules.d/60-dji-mic.rules` + `udevadm` commands with Copy buttons. If rule exists: instruct user to replug receiver or run `udevadm trigger`. | macOS: ready out of box (note quarantine removal for unsigned builds). Windows: show Interface `6` Zadig WinUSB walkthrough (explicitly warning not to touch audio interfaces). |
| **Desktop Notifications** | Probe `notify-send` on `PATH` and/or `org.freedesktop.Notifications` on `$DBUS_SESSION_BUS_ADDRESS` | Offer distro-detected install command (`apt install libnotify-bin`, `dnf install libnotify`, `pacman -S libnotify`) and explain which alerts require it (critical battery, disconnect). | macOS: built-in (`osascript`); Windows: built-in toast/balloon. |
| **System Tray & Close-to-Tray** | Query `org.kde.StatusNotifierWatcher` (`NameHasOwner` + `IsStatusNotifierHostRegistered`) on session D-Bus | Disable close-to-tray safely; show desktop-specific tip (Ubuntu/GNOME: install `gnome-shell-extension-appindicator` / AppIndicator extension; Wayland WMs: enable SNI tray module). | macOS: built-in menu bar (`NSStatusItem`); Windows: built-in notification area. |
| **Start at Login (`--hidden`)** | Check writeability of `${XDG_CONFIG_HOME:-~/.config}/autostart/` and existence of `dji-mic-control.desktop` | Show manual `.desktop` file contents if autostart dir is restricted or sandboxed. | macOS: LaunchAgent plist; Windows: HKCU Run key. |
| **Single Instance** | Bind `$XDG_RUNTIME_DIR/dji-mic-control.sock` (fallback `/tmp/dji-mic-control-$UID.sock`) | Automatic; report active socket path in Diagnostics. | macOS: native app instance; Windows: named mutex. |

### 5.2 Notification Triggers (Opt-In, Disabled When Backend Missing)

- **Low / Critical TX Battery:** Fire once per transition into tier `6` (Very Low) or tier `7` (Critical) while not charging (debounced so it does not spam every second).
- **Device Disconnected (optional, off by default):** Fire when an active receiver drops off the bus unexpectedly (suppressed right after a `plug-free` reboot toggle).

### 5.3 System Tray Parity (When Tray Host Available)

- Dynamic icon: base app icon, switching to Mic Mini 2 icon when any TX reports `DJI Mic Mini 2`, composited in Dart into an ARGB32 pixmap with a red/white `X` badge when no device is connected or a red/white battery badge when worst-case TX battery is tier `6` (solid) or tier `7` (blinking every `1000 ms`).
- Dynamic menu: `Open DJI Mic Control`, separator, quick toggles when exactly 1 device is connected (`Mic LEDs`, `Noise Cancel Mode`, and `Noise Cancelling` on v2), separator, `Start at login (hidden)` checkbox, separator, `Quit`.

---

## 6. Testing, Simulation, and Quality Gates

Follow `misc-ai` testing rules (red-green TDD) and reuse Lumen's (`apps/hue-controller/`) test architecture:

1. **Protocol unit tests (`test/protocol/`):** Port all 591 lines of upstream hex-vector tests covering CRC-16 v1/v2, `takeFrame` resync (including stray `0x55` bytes and >178-byte identity frames), v1/v2 command encoding, v1 heartbeat decoding, v2 split-push stateful merging, 1-tick TX bitmask lag, reversed v2 firmware bytes, Mic Mini 2 Voice Tone, and inverted `mic-leds`.
2. **Transport and platform unit tests (`test/transport/`, `test/platform/`):**
   - `usbfs` struct layout and ioctl constant tests verified against `/usr/include/linux/usbdevice_fs.h`.
   - `CapabilitiesProbe`, `UdevHelper` (missing rule vs. present rule), `AutostartService`, `ConfigStore`, `SingleInstance` socket handoff, and `Notifier` fallback tests against temporary directories and fake command runners.
3. **Byte-level simulator (`lib/sim/`):** `SimulatedDjiMic` parses outgoing DUML command bytes, validates CRCs, mutates internal device state (including `plug-free` disconnect/reconnect and `stereo`/`safety-track` mutual exclusion), and emits realistic v1/v2 heartbeat streams. Exposed in the app via `--dart-define=DEMO=true` or `--demo`.
4. **Headless and real-window E2E tests (`integration_test/` + `test/e2e_test.dart`):**
   - `flutter test` runs unit, widget, and full fake-time E2E suites headlessly on `flutter_tester` (works immediately without GTK3/Xvfb).
   - `xvfb-run -a flutter test integration_test -d linux` runs the exact same E2E suite in a real GTK3 desktop window once the Linux toolchain is installed.
   - `flutter analyze` must pass with zero warnings.
