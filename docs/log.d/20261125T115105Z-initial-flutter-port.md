## 2026-11-25: Feasibility analysis, spec, plan, and Linux Flutter port


Completed feasibility analysis, product specification, and phased development plan for porting `ShadowBitBasher/DJI-Mic-Control` (`v1.1.0`) to a Linux-first Flutter desktop app built on core Flutter and Dart libraries with zero third-party runtime packages.

Implemented `apps/dji-mic-control/` using the Lumen Flutter `3.47.7` / Dart `3.13.5` SDK:

- Ported DUML framing, v1/v2 CRC-16, all 13 `MicMini` settings, Mic Mini 2 per-TX Voice Tone, and all upstream hex-vector unit tests into `lib/protocol/`.
- Built a byte-level `SimulatedDjiMic` (`--demo` / `--dart-define=DEMO=true`) and `DeviceManager` behind a narrow `UsbTransport` interface.
- Implemented `LinuxUsbfsTransport` (pure-Dart `sysfs` + `usbfs` ioctl worker isolate via `dart:ffi` `libc`) plus zero-plugin runtime OS capability probing (`CapabilitiesProbe`, `UdevHelper`, MIT pure-Dart D-Bus wire codec for `StatusNotifierWatcher`/`StatusNotifierItem`, `notify-send` notifier, XDG autostart, Unix socket single-instance guard, XDG JSON config, and ~55-line GTK3 window channel in `linux/runner/my_application.cc`).
- Built the complete Flutter UI with light/dark upstream tokens, collapsible sidebar, RX/TX1/TX2 cards, 7-tier `BatteryIcon`, 5-stop `AudioLevelMeter`, Compact masonry vs. List views, and **System & Capabilities** / **Diagnostics** / **USB Setup** dialogs.
- Added the post-completion thin Rust `nusb` `cdylib` (`native/dji_mic_usb/`) and `NusbFfiTransport` FFI loader (`AppServices.production()` prefers `libdji_mic_usb.so` when bundled and falls back to `LinuxUsbfsTransport`).
- Verified `flutter analyze` (0 issues), `flutter test` (41/41 passing), `flutter build linux --release` (25 KB binary with zero non-Flutter `DT_NEEDED` libraries), and `xvfb-run -a flutter test integration_test/app_desktop_test.dart -d linux` (passing on real Linux GTK3 desktop). Note: compiling `native/dji_mic_usb` requires `crates.io` network access.
