---
type: Plan
title: DJI Mic Control Flutter Port Development Plan
description: Phased implementation roadmap, upfront architectural decisions, Rust boundary strategy, and verification gates for apps/dji-mic-control.
status: draft
tags: [flutter, linux, usb, dji-mic, plan]
---

# Development Plan: DJI Mic Control (Flutter)

## 1. Locked-In Decisions

| # | Decision | Selected Approach |
| --- | --- | --- |
| 1 | **USB transport language boundary** | **Pure Dart on Linux first (`sysfs` + `usbfs` via `dart:ffi` `libc`) behind a narrow `UsbTransport` interface.** Once the full Flutter app is built and verified, implement **Phase 6** wrapping a thin Rust `nusb` `cdylib` behind the exact same `UsbTransport` interface for cross-platform USB support. |
| 2 | **Dependency & vendoring policy** | **Zero third-party pub.dev runtime packages.** Keep only trusted Dart/Flutter SDK/team packages (`flutter`, `flutter_test`, `flutter_lints`, `integration_test`, `meta`, `ffi`). Implement minimal MIT-licensed D-Bus wire framing (`StatusNotifierItem`, `com.canonical.dbusmenu`, `org.freedesktop.Notifications`) directly in `lib/platform/dbus/` (or vendor license-compatible code only when verified MIT/BSD/Apache-2.0; avoid copyleft MPL-2.0 vendoring unless explicitly approved). |
| 3 | **Window chrome & window actions** | **Native OS titlebar + slim in-app toolbar** (simplest and most maintainable across X11 and Wayland). Preserves standard OS minimize, maximize, resize, and drag behavior; native close hides to tray only when close-to-tray is enabled and a tray host is active. |

---

## 2. Where Keeping Rust Makes the Most Sense

If you choose to keep any Rust from upstream `ShadowBitBasher/DJI-Mic-Control`, keep **only** the USB hardware layer (and optionally the wire codec alongside it), and rewrite everything else in Dart/Flutter:

- **Keep in Dart/Flutter (always):** All UI widgets, state management, device simulator, and **all OS integrations** (tray, notifications, autostart, single-instance, config, udev guide, badge rendering). Upstream's Rust OS crates (`tauri`, `tray-icon`, `muda`) hard-link GTK and `libayatana-appindicator3` at compile time and would fight Flutter's GTK loop.
- **Where keeping Rust buys real leverage:** `crates/device` uses **`nusb`**, which is pure Rust with **zero C `libusb` dependency** and native backends for Linux (`usbfs`), macOS (IOKit), and Windows (WinUSB).
  - For a **Linux-only** target today, pure Dart `usbfs` (~250 LOC) is simple enough that avoiding a second build toolchain and avoiding glibc-version pinning (`2.42` on this Ubuntu 25.10 host) is a net win.
  - For **cross-platform desktop (Linux + macOS + Windows)** or **fast upstream tracking** (when upstream adds DJI Mic 2 / Mic 3), wrapping upstream `crates/device` + `crates/protocol` in a ~100-LOC `extern "C"` JSON `cdylib` (`libdji_mic_core.so/.dylib/.dll`, loaded via `dart:ffi`, no `flutter_rust_bridge`) is strictly better than reimplementing macOS IOKit and Windows WinUSB in raw Dart FFI.

Because the app sits behind a narrow `UsbTransport` / `MicBackend` interface, Phases 1 and 2 are completely independent of this choice and run 100% in Dart.

---

## 3. Phased Roadmap

All implementation follows red-green TDD (failing test first, minimal pass, refactor) using the existing Lumen Flutter SDK at `/home/chris.guest/sdk/flutter`.

### Phase 0: Environment, Project Scaffold, and ABI Spike
- **Goal:** Create `apps/dji-mic-control/` using `/home/chris.guest/sdk/flutter/bin/flutter`, copy the three upstream device PNG assets + app icon (licensed under The Unlicense), add `mise.toml` or helper script pointing to the Flutter SDK, and verify `flutter test` and `flutter analyze` run cleanly on this host.
- **Spikes (fast, targeted verification):**
  1. Document and (when ready to build Linux binaries) install the missing Linux desktop C++ build packages (`clang`, `cmake`, `ninja-build`, `libgtk-3-dev`, `xvfb`), matching `apps/hue-controller/tool/setup_cloud_env.sh`.
  2. Verify Linux `usbfs` struct layouts (`usbdevfs_urb`, `usbdevfs_disconnect_claim`) and ioctl numbers against `/usr/include/linux/usbdevice_fs.h` via a tiny C/Dart alignment check test.
- **Exit gate:** `flutter analyze` and `flutter test` green in `apps/dji-mic-control/`.

### Phase 1: Pure-Dart Protocol Codec, State Model, and Byte-Level Simulator
- **Goal:** Port `crates/protocol` (1,300 prod LOC) and its full test suite (591 LOC of hex vectors) into `lib/protocol/` with zero Flutter/FFI imports, plus a byte-level `SimulatedDjiMic` in `lib/sim/`.
- **Deliverables:**
  - `crc.dart` (v1/v2 CRC-16 + reverse solver, header CRC-8).
  - `packet.dart` (`takeFrame` stream resync, v1 19-byte and v2 22-byte command builders, dialect/role classifiers).
  - `state.dart`, `settings.dart`, `device_model.dart`, and `mic_mini_model.dart` (all 13 settings, v1 heartbeat decoder, v2 stateful split-push status/identity/level decoders, edge cases: 1-tick TX bitmask lag, physical unit indexing, reversed v2 firmware bytes, inverted `mic-leds`, Mic Mini 2 Voice Tone).
  - `SimulatedDjiMic` + `SimulatedUsbTransport` supporting v1/v2 modes, Mic Mini 2 TX, live synthetic audio levels, `plug-free` reboot simulation, `EACCES` permission simulation, and critical battery simulation.
- **Exit gate:** 100% of ported upstream hex-vector tests and simulator round-trip tests pass via `flutter test test/protocol test/sim`.

### Phase 2: Complete Flutter UI, Controller, and Headless E2E Suite
- **Goal:** Build the entire UI in pure core Flutter widgets (`lib/ui/`) and state controller (`lib/state/`) backed by `SimulatedDjiMic` (`--dart-define=DEMO=true`), reaching full visual and interactive parity before touching kernel USB code.
- **Deliverables:**
  - `AppColors` light/dark `ThemeExtension` with exact upstream hex tokens and tabular numerals.
  - `MicController` (`ChangeNotifier`) with selection, click-to-deselect, optimistic updates, confirmation retirement + safety timeout, rollback on error, and 1500 ms liveness handling.
  - `AppShell` + animated collapsible `Sidebar` + banners + 3 empty placeholder states.
  - `DevicePanel` header, responsive RX/TX1/TX2 status cards, 7-tier `BatteryIcon` (`CustomPainter` with charging bolt and 500 ms blinking `!`), and 5-stop animated `AudioLevelMeter`.
  - `SettingControl`, composite `NoiseCancelControl`, per-TX `Voice Tone` on Mic Mini 2 cards, Compact masonry vs. List view switcher, lock/exclusivity tooltips, and `plug-free` warning indicator.
  - `SetupModal` (Linux udev / Windows Zadig instructions with one-click copy) and `DiagnosticsView` (ring-buffer log viewer, reusing Lumen's `Logger`).
  - Dual-mode E2E test suite (`integration_test/` + `test/e2e_test.dart`) exercising every setting, mutual exclusion, v1 lock, `plug-free` reboot recovery, Mic Mini 2 TX card, critical battery blink, and permission banner.
- **Exit gate:** All widget and headless E2E tests pass via `flutter test` (no GTK3 required yet); demo mode runs cleanly when Linux toolchain is installed.

### Phase 3: Real Linux USB Transport (`usbfs` or Optional Rust `nusb` `cdylib`)
- **Goal:** Wire real USB hardware communication behind `UsbTransport` and validate against a physical DJI Mic Mini receiver.
- **Deliverables (Default Pure-Dart Path):**
  - Pure `dart:io` `sysfs` enumerator (`/sys/bus/usb/devices/*`) matching `2ca3:4011` and detecting `EACCES` (`errno 13`).
  - Background `Isolate` worker using `libc` `open`/`ioctl`/`poll`/`eventfd`/`close` (`USBDEVFS_DISCONNECT_CLAIM` on Interface `6` only, `USBDEVFS_SUBMITURB` + `USBDEVFS_REAPURBNDELAY` + `USBDEVFS_DISCARDURB` on endpoints `0x86` and `0x06`).
  - `DeviceManager` 1000 ms scan loop, clean teardown on `ENODEV`/unplug and `plug-free` reboot re-enumeration.
  - *(Alternative if Decision 1 selects Rust)*: Thin ~100-LOC `crates/dji_mic_ffi` `cdylib` wrapping upstream `crates/device` (`nusb`) + `dart:ffi` loader behind the exact same Dart interface.
- **Exit gate:** Transport unit tests pass; live test on physical DJI Mic Mini confirms telemetry, setting writes, `plug-free` reboot recovery, and uninterrupted PipeWire/ALSA audio capture.

### Phase 4: Optional OS Capabilities, Runner Window Control, and In-App Suggestions
- **Goal:** Implement all optional desktop integrations with zero hard-linked OS plugin libraries, runtime probing, graceful degradation, and OS-specific install hints.
- **Deliverables:**
  - `ConfigStore` (`$XDG_CONFIG_HOME/dji-mic-control/config.json`) persisting Compact/List view, theme override, notification preferences, and close-to-tray preference.
  - `SingleInstance` (`$XDG_RUNTIME_DIR/dji-mic-control.sock`) forwarding `"show\n"` from secondary launches to focus the primary window.
  - `AutostartService` (`~/.config/autostart/dji-mic-control.desktop` launching with `--hidden`).
  - `CapabilitiesProbe` + **System & Capabilities** UI sheet showing live status and distro-aware install/setup commands for USB udev rules, `libnotify-bin` / D-Bus notifications, and GNOME/Wayland tray hosts.
  - `Notifier` (probing `notify-send` or `org.freedesktop.Notifications`) firing debounced low/critical battery and optional disconnect alerts when available.
  - ~40 to 60 lines in `linux/runner/my_application.cc` exposing `dji_mic/window` (`show`, `hide`, `setCloseToTray`, `quit`) and supporting `--hidden` launch.
  - `TrayService` speaking `org.kde.StatusNotifierItem` + `com.canonical.dbusmenu` over session D-Bus with dynamic ARGB32 badged/blinking icons and live quick toggles (auto-disabling close-to-tray if no `StatusNotifierWatcher` is present).
- **Exit gate:** Capability probe, config, autostart, and single-instance unit tests pass; real-window `-d linux` E2E tests pass under `xvfb-run`; manual X11/Wayland check confirms `--hidden`, close-to-tray, tray quick toggles, and graceful fallback when tray/notify-send are absent.

### Phase 5: Linux Packaging and Release Audit
- **Goal:** Produce clean, reproducible Linux distribution bundles using the pure-Dart `usbfs` transport and verify zero unexpected runtime dependencies.
- **Deliverables:**
  - Release build script (`tool/build_linux.sh` with `--help`, `--debug`, `--dry-run`) running `flutter build linux --release` and verifying `ldd` reports zero unexpected shared libraries beyond Flutter's GTK3 embedder baseline.
  - Packaging assets in `packaging/`: `60-dji-mic.rules`, `dji-mic-control.desktop`, AppImage / `.deb` packaging helpers, and `README.md` setup instructions.
  - Stubbed macOS/Windows capability guides (Zadig Interface `6` walkthrough on Windows, Gatekeeper note on macOS).
- **Exit gate:** Clean release bundle built, `ldd` audit verified, `flutter analyze`, `flutter test`, and `-d linux` integration tests all green.

### Phase 6: Thin Rust `nusb` `cdylib` Backend (Post-Completion Swap-In)
- **Goal:** After the full pure-Dart Linux app is complete and verified, add a thin ~100-LOC Rust `nusb` `cdylib` (`native/dji_mic_usb/`) behind the existing `UsbTransport` interface so Linux, macOS, and Windows share one native USB transport with zero `libusb` dependency while keeping all protocol decoding, UI, simulator, and OS integrations in pure Dart.
- **Deliverables:**
  - `native/dji_mic_usb/` Rust crate exposing a tiny C ABI (`dji_usb_list_json`, `dji_usb_open`, `dji_usb_bulk_in`, `dji_usb_bulk_out`, `dji_usb_close`, `dji_usb_str_free`) using `nusb` only (zero Tauri, zero OS UI crates, glibc-only linkage on Linux).
  - `lib/transport/nusb_ffi_transport.dart` implementing `UsbTransport` via `dart:ffi` (`DynamicLibrary.open`) with automatic fallback to `LinuxUsbfsTransport` if the `.so` is absent.
  - Build script hook and glibc linkage audit for release binaries.
- **Exit gate:** `cargo test`, `flutter test`, and `ldd` verification (confirming glibc-only linkage on `libdji_mic_usb.so`) all pass.
