---
type: Feasibility
title: DJI Mic Control Flutter Port Feasibility Analysis
description: Technical feasibility of porting ShadowBitBasher/DJI-Mic-Control to a Linux-first Flutter desktop app built primarily on the core Flutter and Dart standard libraries, with optional runtime OS capability probing and Rust boundary analysis.
status: draft
tags: [flutter, linux, usb, dji-mic, feasibility, rust]
---

# Feasibility Analysis: DJI Mic Control in Flutter

## 1. Executive Verdict

Porting `ShadowBitBasher/DJI-Mic-Control` (`v1.1.0`, commit `9ba7688`, The Unlicense) to a Linux-first Flutter desktop app built primarily on the core Flutter and Dart standard libraries is **highly feasible**.

Key findings:

- **UI and interaction parity is straightforward (near 100% fidelity).** The upstream frontend is ~1,800 lines of vanilla Svelte and CSS with zero third-party UI libraries, zero sliders, and 13 data-driven toggle/enum settings. Every screen, meter, masonry layout, animated battery glyph, and modal maps cleanly to core `flutter/material.dart`, `flutter/widgets.dart`, and `flutter/services.dart`.
- **The hardware protocol is raw USB Bulk, not HID.** The DJI Mic Mini receiver (`VID 0x2ca3`, `PID 0x4011`) exposes vendor Interface `6` with Bulk IN `0x86` and Bulk OUT `0x06`, carrying DUML packets (v1 and v2 dialects). Only Interface `6` is detached and claimed so OS USB Audio (interfaces 1 to 3) stays active.
- **Zero third-party native Flutter plugins are required on Linux.** Flutter's Linux desktop embedder already links GTK3/GLib/Epoxy/Fontconfig. Beyond that unavoidable baseline, zero additional `DT_NEEDED` shared libraries are needed:
  - USB on Linux can run directly in pure Dart over `sysfs` + `usbfs` ioctls via `dart:ffi` against `libc` (`DynamicLibrary.process()`), or via a tiny ~100-LOC Rust `nusb` `cdylib` that links only against glibc.
  - Optional OS features (notifications, system tray, autostart, single-instance lock, config, udev detection) can be implemented via pure Dart (`dart:io`, Unix sockets, XDG files, `notify-send` / D-Bus probing) with graceful degradation and OS-specific install suggestions in-app.
  - The only small native touchpoint is ~40 to 60 lines of C++ inside our own `linux/runner/my_application.cc` (using GTK3 that Flutter already links) to support `--hidden` launch, window show/hide, and close-to-tray interception.
- **Moving off Tauri/WebKitGTK removes an upstream Linux stability hack.** Upstream requires a Unix `/proc` `SIGKILL` + `_exit(0)` workaround for WebKitGTK Mesa EGL teardown segfaults. Flutter avoids WebKitGTK completely.
- **Local environment readiness:** The Lumen Flutter SDK at `/home/chris.guest/sdk/flutter` (Flutter `3.47.7`, Dart `3.13.5`) already has Linux desktop engine artifacts pre-cached and can run headless `flutter test` suites immediately. Compiling a Linux desktop binary (`flutter build linux`) requires installing `clang`, `cmake`, `ninja-build`, and `libgtk-3-dev` on this host.

---

## 2. Upstream Codebase Inventory

Analyzed from a full local clone of `https://github.com/ShadowBitBasher/DJI-Mic-Control` (`v1.1.0`, `9ba7688`).

### 2.1 Size and Dependency Footprint

The entire upstream Rust workspace is **3,443 LOC** (including unit tests), and the Svelte frontend is **~1,800 LOC**:

| Component | Total LOC | Prod LOC | Test LOC | Key Dependencies |
| --- | ---: | ---: | ---: | --- |
| `crates/protocol` | 1,891 | 1,300 | 591 | `serde` only (pure byte codec, zero I/O, zero `unsafe`) |
| `crates/device` | 562 | 562 | 0 | `nusb 0.1.14`, `futures-lite`, `async-channel`, `thiserror`, `serde` |
| `crates/cli` | 263 | 263 | 0 | `clap`, `serde_json`, `anyhow` |
| `gui/src-tauri` | 727 | 727 | 0 | `tauri 2` (`tray-icon`, `image-png`), `image`, `tauri-plugin-single-instance`, `tauri-plugin-autostart`, `libc`, `signal-hook` |
| `gui/src/` (Svelte 5 + CSS) | ~1,800 | ~1,800 | 0 | `@tauri-apps/api` only (zero UI/CSS/icon packages) |

### 2.2 Hardware Support and Wire Protocol

- **Supported USB product:** `DJI Mic Mini` (`VID 0x2ca3`, `PID 0x4011`) with up to two wireless transmitters (`TX1`, `TX2`). Also supports `DJI Mic Mini 2` transmitters paired to the same receiver on v2 firmware (identified via TLV tag `0x06` ASCII product name, not a separate VID/PID). DJI Mic 1, Mic 2, and Mic 3 are not implemented upstream yet.
- **USB transport:** Raw USB Bulk transfers on Interface `6` (`0x86` IN, 512-byte reads; `0x06` OUT, 19-byte v1 or 22-byte v2 writes). No control transfers, no HID reports, no alternate settings. Detaches kernel driver on Interface `6` only (`detach_interfaces()` is empty).
- **Liveness and polling:** No OS hotplug watcher; enumerates USB every 1000 ms. A device is `connected: true` if a decoded frame arrived within `LIVE_WINDOW_MS = 1500 ms`. Frontend polls a single `snapshot` call every 150 ms.
- **DUML framing:** `0x55` SOF, 1-byte length (`4..=256`), `0x04` version, 1-byte header CRC-8, payload, 2-byte trailing CRC-16 (reflected poly `0x8408`).
- **Two firmware dialects** (detected passively from heartbeat byte `11`: `0x00` = v1, `0x03` = v2):
  - **v1:** 19-byte commands, big-endian command IDs, CRC-16 init `0x0000` / residue `0xbb01`, monolithic ~10 Hz heartbeat (56/70/84 bytes), forward 4-byte firmware versions.
  - **v2:** 22-byte target-addressed commands (`0x0000` RX, `0xffff` all TX, `0x0001`/`0x0002` individual TX), little-endian command IDs, CRC-16 init `0x3692` / residue `0x0000`, split pushes (~10 Hz status 54/86/118 bytes, ~10 Hz TLV audio levels, periodic TLV identity up to ~182 bytes with reversed firmware bytes), adds gain dial readout (`int8` dB), per-TX charging flag, 3-bit inverted battery gauge (`1` full to `7` critical), product name, and 4 new settings (`noise-cancel-power`, `noise-cancel-button`, `tx-auto-off-15m`, `voice-tone`).
- **Protocol subtleties to preserve:**
  - Incoming frames are NOT CRC-verified against the command residue (upstream explicitly notes device-to-host frames do not share the command residue).
  - Outgoing commands await USB `bulk_out` completion and do not block on the 14-byte ACK frame; the UI retires optimistic values when subsequent heartbeats confirm them.
  - `stereo` On is `0x02` (not `0x01`); `mic-leds` is inverted (`0x00` = On, `0x02` = Off); `plug-free` reboots the receiver and triggers USB re-enumeration.
  - On v2, offset `44` bitmask (`0x01` TX1, `0x02` TX2) updates up to 1 tick before the 32-byte TX slot appears, and slots must be indexed by physical unit byte `+1` rather than array index.
  - Wait for the first decoded heartbeat (`protocol_version != null`) before sending commands so a v1 receiver never receives a v2 command.

### 2.3 Upstream UI and OS Features

- **UI surfaces:** Custom window chrome (frameless on Linux/Windows, overlay titlebar on macOS), collapsible `260px` device sidebar with click-to-deselect, warning and error banners, 3 empty placeholder states, device panel header, 3 status cards (RX + TX1 + TX2), 7-tier `BatteryIcon` with charging bolt and 500 ms critical blink, 5-stop animated VU meter, per-TX `Voice Tone` picker (Mic Mini 2 only), composite `NoiseCancelControl`, Compact masonry vs. List view toggle, lock/exclusivity tooltips, and Linux `UdevModal`.
- **OS integrations present upstream:** System tray icon with procedural RGBA overlays (no-signal badge, solid/blinking low-battery badge, Mic Mini 2 photo variant) and live context menu (quick toggles for Mic LEDs, NC mode, NC power, Start at login, Quit); close-to-tray + `--hidden` launch; macOS Dock hiding; single-instance lock; autostart; Linux udev permission detection and `.deb`/`.rpm` packaging rules.
- **Explicitly absent upstream:** Desktop notifications (only tray badging exists today), persistent user preferences/config, structured file logging, and in-app Windows Zadig / macOS setup guidance.

---

## 3. Lumen Flutter SDK and Host Toolchain Audit

Inspected `/home/chris.guest/sdk/flutter` and `apps/hue-controller/`:

- **Installed SDK:** Flutter `3.47.7` (stable, rev `abaf9c5237`), Dart `3.13.5`, DevTools `2.60.0` at `/home/chris.guest/sdk/flutter` (not currently on `$PATH`).
- **Enabled flags:** `enable-linux-desktop`, `enable-macos-desktop`, `enable-windows-desktop`, and `enable-native-assets` are already enabled.
- **Pre-cached Linux engine artifacts:** `linux-x64`, `linux-x64-profile`, and `linux-x64-release` (`libflutter_linux_gtk.so`, `flutter_tester`, `gen_snapshot`, `impellerc`, `icudtl.dat`, headers) are already cached on disk.
- **Host OS (Ubuntu 25.10, x86_64, kernel `6.17.0-23-generic`, glibc `2.42`):**
  - **Already present:** `gcc 15.2.0`, `pkg-config 1.8.1`, `udevadm`, `notify-send`, `dbus-send`, `/usr/include/linux/usbdevice_fs.h`, `rust 1.99.1` (via mise), and runtime libs (`libusb-1.0.so.0`, `libnotify.so.4`, `libdbus-1.so.3`, `libglib-2.0.so.0`, `libfontconfig.so.1`).
  - **Missing for Linux desktop builds (`flutter doctor -v`):** `clang`, `cmake`, `ninja-build`, `libgtk-3-dev` (plus `xvfb`, `liblzma-dev`, `mesa-utils` for headless `-d linux` integration tests, matching `apps/hue-controller/tool/setup_cloud_env.sh`).
- **Immediate test capability:** `flutter_tester` links only against `libdl`, `libpthread`, `libm`, and `libc`. All unit, protocol, widget, and fake-time E2E tests (`flutter test`) can run on this host today without any apt installations.

### Flutter Linux Runtime Baseline vs. Plugin Dependencies

Every Flutter Linux desktop binary links against Flutter's GTK3 embedder baseline (`libgtk-3`, `libgdk-3`, `libpango`, `libatk`, `libcairo`, `libgio`, `libgobject`, `libglib`, `libepoxy`, `libfontconfig`, `libc`/`libm`/`libpthread`/`libdl`). These are present on standard Linux desktops.

By avoiding third-party native Flutter plugins (`tray_manager`, `window_manager`, `local_notifier`, `flutter_secure_storage`, etc.), the compiled binary adds **zero** extra `DT_NEEDED` shared libraries (no hard links to `libayatana-appindicator3`, `libnotify`, `libsecret`, `libusb`, or `webkit2gtk`) and will never fail to launch on a Linux distro missing optional desktop libraries.

---

## 4. Pure-Flutter and Zero-Plugin Technical Feasibility

### 4.1 Hardware Transport on Linux (and Cross-Platform Path)

| Option | Extra Runtime Libs | Code Size & Complexity | Cross-Platform Story | Verdict |
| --- | --- | --- | --- | --- |
| **A. Pure Dart `sysfs` + `usbfs` (`dart:ffi` to `libc`)** | **Zero** (`DynamicLibrary.process()`) | ~250 to 350 LOC; scans `/sys/bus/usb/devices/*` via `dart:io`, opens `/dev/bus/usb/BBB/DDD`, uses `USBDEVFS_DISCONNECT_CLAIM` + `USBDEVFS_SUBMITURB`/`REAPURBNDELAY` + `eventfd`/`poll` in a background `Isolate` | Linux only; macOS IOKit and Windows WinUSB would require ~800 to 1,000 LOC of fragile OS FFI later | **Best for Linux-first single-language purity** |
| **B. Runtime `dlopen(libusb-1.0.so.0)`** | Soft runtime dep (`libusb-1.0-0`); falls back to install hint if missing | ~200 LOC sync FFI with short read timeout | Works on macOS/Windows if `libusb` is bundled or installed | Viable fallback, but unnecessary on Linux when `usbfs` is simpler and dep-free |
| **C. Thin Rust `nusb` `cdylib` (`dart:ffi`)** | **Zero non-glibc libs** on Linux (`nusb` speaks `usbfs` directly, no `libusb`) | ~100 LOC `extern "C"` wrapper around upstream `crates/device` (+ optionally `crates/protocol`) | Linux (`usbfs`), macOS (IOKit), and Windows (WinUSB) work immediately | **Best if macOS/Windows or upstream tracking is day-one** |

Note: `/dev/hidraw*` is **not usable** because the DJI Mic Mini uses raw USB Bulk endpoints `0x86`/`0x06`, not HID reports. On Windows, raw Bulk access to Interface `6` still requires replacing the Windows HID class driver on Interface `6` with WinUSB (via Zadig), regardless of whether Dart or Rust performs the USB call.

### 4.2 Optional OS Integrations with Runtime Detection and In-App Suggestions

Instead of hard-linking OS libraries, every optional desktop integration is probed at runtime behind a clean Dart service interface. Missing capabilities degrade gracefully and surface OS-specific remediation commands inside a dedicated **System & Capabilities** dialog/section.

| Capability | Linux Zero-Plugin Mechanism | Fallback When Unavailable | In-App OS Suggestion | macOS / Windows Path |
| --- | --- | --- | --- | --- |
| **USB access** | Pure `dart:io` + `EACCES` detection on `/dev/bus/usb/...`; check `/etc/udev/rules.d/60-dji-mic.rules` and `/usr/lib/udev/rules.d/60-dji-mic.rules` | Warning banner + empty-state CTA opening udev instructions (distinguishes "missing rule" vs. "rule installed, replug needed") | Copyable udev rule + `udevadm` commands | macOS: works via IOKit (show quarantine hint if needed); Windows: in-app Zadig guide for Interface `6` only |
| **Desktop notifications** | Probe `notify-send` on `PATH` (or call `org.freedesktop.Notifications.Notify` directly over session D-Bus Unix socket) | Disable notification alerts; keep in-app banners and battery warnings | `sudo apt install libnotify-bin` / `dnf install libnotify` / `pacman -S libnotify` | macOS: `osascript` / `UNUserNotificationCenter`; Windows: WinRT toast / tray balloon |
| **System tray & menu** | Session D-Bus Unix socket (`$DBUS_SESSION_BUS_ADDRESS`) speaking `org.kde.StatusNotifierItem` + `com.canonical.dbusmenu` (raw ARGB32 `IconPixmap` for dynamic badges). Probe `org.kde.StatusNotifierWatcher` first | Automatically disable close-to-tray so closing the window exits cleanly instead of stranding a hidden process | GNOME: install AppIndicator extension (`gnome-shell-extension-appindicator`); WMs: enable SNI tray widget (Waybar/etc.) | macOS: `NSStatusItem` in `macos/Runner/`; Windows: `Shell_NotifyIconW` via `dart:ffi` or runner |
| **Close-to-tray & `--hidden`** | ~40 to 60 LOC in `linux/runner/my_application.cc` (`delete-event`, `gtk_widget_hide`, `gtk_window_present`, `dji_mic/window` `FlMethodChannel`) | If tray unavailable, close exits normally | Explain why close-to-tray is disabled until a tray host is active | macOS: `NSWindow` + `NSApp.setActivationPolicy`; Windows: `WM_CLOSE` + `ShowWindow` |
| **Autostart** | Pure `dart:io` writing `~/.config/autostart/dji-mic-control.desktop` (`Exec=<exe> --hidden`) | Show manual `.desktop` snippet if config dir is unwritable | Note Flatpak portal requirement if ever sandboxed | macOS: `~/Library/LaunchAgents/*.plist`; Windows: `HKCU\...\Run` via `advapi32.dll` |
| **Single-instance lock** | Pure `dart:io` Unix domain socket at `$XDG_RUNTIME_DIR/dji-mic-control.sock`; second launch sends `"show\n"` and exits | Stale socket cleanup on `ECONNREFUSED` | None needed | macOS: LaunchServices; Windows: `CreateMutexW` + focus |
| **Config & logs** | Pure `dart:io` JSON in `$XDG_CONFIG_HOME/dji-mic-control/config.json` (atomic `.tmp` rename) + rotating log in `$XDG_STATE_HOME/dji-mic-control/logs/` | In-memory defaults if unwritable | None needed | macOS: `Application Support` / `Logs`; Windows: `%APPDATA%` / `%LOCALAPPDATA%` |

### 4.3 Pure-Dart D-Bus Scope Trade-Off

Speaking `StatusNotifierItem` + `com.canonical.dbusmenu` + `org.freedesktop.Notifications` over `/run/user/$UID/bus` requires D-Bus binary wire framing and SASL `EXTERNAL` auth:

- **Strict zero-pub.dev approach:** Writing a minimal D-Bus wire codec + SNI/DBusMenu server in pure Dart is feasible (~800 to 1,200 LOC, zero external dependencies).
- **Pragmatic pure-Dart package option:** Allowing a single pure-Dart (zero native code, zero C/OS plugin) package (`package:dbus`) cuts the tray and notification code to ~150 LOC while still adding zero OS-specific native libraries.

This is a clean architectural choice to settle before Phase 4 (see `plan.md`).

---

## 5. Where Keeping Rust Might Be Best (Layer-by-Layer Verdict)

Because `rust 1.99.1` is already installed on this machine and upstream `DJI-Mic-Control` is cleanly factored into `crates/protocol` (1,300 prod LOC), `crates/device` (562 prod LOC), and `gui/src-tauri` (727 prod LOC), we evaluated keeping Rust at every layer:

| Layer | Keep in Rust? | Rationale |
| --- | --- | --- |
| **UI and state management** | **No (rewrite in Flutter/Dart)** | Goal of the project; pure Flutter widgets achieve near-100% fidelity with hot reload, fast widget tests, and no WebKitGTK quirks. |
| **OS integrations (tray, autostart, single-instance, notifications, udev helper, badge drawing)** | **Definitely No (rewrite in Dart)** | Upstream's Rust OS crates (`tauri`, `tray-icon`, `muda`) hard-link `libayatana-appindicator3` and GTK at compile time, directly violating the zero-OS-library goal and conflicting with Flutter's own GTK main loop. Pure Dart D-Bus/XDG + tiny runner channel is far cleaner. |
| **Wire protocol (`crates/protocol`)** | **Prefer Pure Dart (unless tracking fast upstream model churn)** | Only 1,300 prod LOC of simple bitmasks and CRC-16, with 591 LOC of hex-vector unit tests that port 1:1 to `dart test`. Rewriting in Dart enables millisecond unit tests, byte-level simulation (`--demo`), and zero FFI marshaling. Only keep in Rust if you want near-zero-effort git pulls when upstream adds DJI Mic 2/3. |
| **USB hardware transport (`crates/device` + `nusb`)** | **Best candidate for keeping Rust (especially for macOS/Windows)** | Upstream uses `nusb`, which is pure Rust with **zero C `libusb` dependency** (direct Linux `usbfs`, macOS IOKit, Windows WinUSB). On Linux alone, pure Dart `usbfs` is small (~250 LOC) and eliminates the second toolchain. Once macOS and Windows are in scope, keeping `nusb` as a tiny ~100-LOC C-ABI `cdylib` (`libdji_mic_core.so/.dylib/.dll`, no `flutter_rust_bridge` needed) avoids writing and maintaining ~1,000 LOC of fragile macOS IOKit + Windows WinUSB FFI in Dart. |

### Concrete Trade-Off Summary

1. **Linux-first, pure-Flutter priority (Recommended Default: Option C1):**
   - Put a narrow 5-method `UsbTransport` interface (`listDevices`, `open`, `bulkIn`, `bulkOut`, `close`) between the pure-Dart DUML protocol/manager and the OS.
   - Implement `LinuxUsbfsTransport` in pure Dart (~250 LOC via `dart:io` + `dart:ffi` `libc`).
   - Result: **100% Dart/Flutter repository**, zero Rust build complexity, zero glibc-version mismatch across Linux distros (inherits only Flutter's baseline), full hot-reload, and byte-level hardware simulation out of the box.
   - **Escape hatch:** If macOS or Windows support is added later, compile a ~100-LOC `nusb`-only Rust `cdylib` behind the exact same `UsbTransport` interface without touching a single line of protocol or UI code.

2. **Cross-platform day-one or upstream-sync priority (Alternative: Option C2):**
   - Keep upstream `crates/protocol` + `crates/device` verbatim behind a ~100-LOC `extern "C"` JSON `cdylib` (`dji_mgr_new`, `dji_mgr_refresh`, `dji_mgr_snapshot_json`, `dji_mgr_set`, `dji_mgr_set_tx`, `dji_mgr_free`, `dji_str_free`), hidden behind a Dart `MicBackend` interface with a pure-Dart `SimulatedMicBackend` for tests and `--demo` mode.
   - Trade-off: requires Rust + Cargo on every dev/CI machine and building release `.so` artifacts against an older glibc baseline (this host's Ubuntu 25.10 ships glibc `2.42`, which would not load on Ubuntu 24.04/Debian 12 without a container/zigbuild target).

3. **Why NOT a Rust CLI sidecar:**
   - Upstream `crates/cli` (`djimic`) is one-shot (opens USB, waits up to 5s, exits), so polling it would thrash USB interface claims and break 10 Hz audio metering. Turning it into a persistent daemon requires new Rust IPC code anyway while adding orphan-process cleanup bugs, making a `cdylib` strictly cleaner whenever Rust is used.

---

## 6. Key Risks and Early Validation Items

1. **Missing Linux C++/GTK build toolchain on host:** Installing `clang`, `cmake`, `ninja-build`, `libgtk-3-dev` (and `xvfb` for headless `-d linux` tests) is required before the first `flutter build linux` run.
2. **GTK3 `--hidden` launch with `FlView`:** Verify on real X11 and Wayland sessions that keeping `GtkWindow` hidden on `--hidden` startup still initializes the Dart isolate (USB manager + tray) cleanly without flashing a window or hitting EGL errors.
3. **`usbfs` ABI layout and `eventfd` wakeup:** Verify `sizeof`/`offsetof` and `_IOR`/`_IOWR` ioctl numbers for `usbdevfs_urb` and `usbdevfs_disconnect_claim` against `/usr/include/linux/usbdevice_fs.h` on `x86_64` (and `aarch64` if targeted) before coding full transfers.
4. **Physical hardware verification:** Simulation verifies wire bytes and UI flows, but one real-hardware pass on a physical DJI Mic Mini is required to confirm Interface `6` detachment leaves PipeWire/ALSA audio uninterrupted and hot-unplug cleanly terminates the isolate with `ENODEV`.
5. **Wayland tray and focus policies:** Stock GNOME without AppIndicator has no `StatusNotifierWatcher` (handled by automatic close-to-tray disable + in-app hint). On Wayland, restoring a hidden window via `gtk_window_present` may raise a desktop activation notification instead of stealing focus.
6. **Flutter Linux release artifact shape:** `flutter build linux --release` emits a relocatable bundle directory (`dji_mic_control`, `lib/`, `data/`), not a single statically linked file. Packaging as AppImage / `.deb` / `.rpm` (bundling `60-dji-mic.rules` and `.desktop`) gives users a single installable artifact.
