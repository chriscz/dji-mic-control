# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-25

Initial standalone Flutter desktop port of [ShadowBitBasher/DJI-Mic-Control](https://github.com/ShadowBitBasher/DJI-Mic-Control), licensed under MIT.

### Added

- **Core Flutter/Dart desktop app** with zero third-party pub.dev runtime dependencies and zero hard-linked OS Flutter plugins.
- **DUML v1 and v2 protocol codec** for DJI Mic Mini and DJI Mic Mini 2 transmitters (VID `0x2ca3`, PID `0x4011`, vendor Interface `6` only, leaving USB Audio interfaces untouched), ported from [ShadowBitBasher/DJI-Mic-Control](https://github.com/ShadowBitBasher/DJI-Mic-Control) (`v1.1.0`, commit `9ba7688`).
- **Mobile Receiver identification and gain controls** (ported from [upstream PR #4](https://github.com/ShadowBitBasher/DJI-Mic-Control/pull/4) by [VaderCheng](https://github.com/VaderCheng)):
  - Identifies the DJI Mic Series Mobile Receiver from RX TLV tag `0x06` unit `0`.
  - Adds `Receiver Gain` (`0x0039`, `-12/-6/0/6/12` dB) and `Monitoring Gain` (`0x0026`, `-12..+12` dB) range sliders with 3-second reported-value confirmation.
  - Renders the `mobile-rx` vector pictogram, `Power: USB` status row, read-only Noise Cancelling display driven by connected TX status bits, and capability write guards blocking unsupported commands.
- **Optional Simplified Chinese (`zh-CN`) UI localization** (ported from [upstream PR #3](https://github.com/ShadowBitBasher/DJI-Mic-Control/pull/3) by [VaderCheng](https://github.com/VaderCheng)), selectable in Preferences with English fallback.
- **Dual USB transport seam (`UsbTransport`)**:
  - Pure-Dart Linux `sysfs` + `usbfs` (`USBDEVFS_BULK` / `USBDEVFS_DISCONNECT_CLAIM`) transport via `dart:ffi` against `libc`.
  - Optional thin Rust `nusb` `cdylib` (`native/dji_mic_usb/`) behind the same interface for cross-platform USB support.
- **Runtime OS capability probing and in-app Linux udev installer**: detects USB permissions, notifications (`notify-send` / D-Bus), system tray (`org.kde.StatusNotifierWatcher`), and autostart, with one-click `pkexec` udev rule installation and copyable setup instructions.
- **Collapsible on-screen Diagnostics fold and hideable Pending Operations strip**: expanded by default, showing live `TX`, `TX OK`, `TX FAIL`, and `Confirmed` protocol events.
- **Byte-level simulator and `--demo` mode**: full DUML v1/v2 hardware simulator plus 55 unit/widget tests and headless GTK3 desktop integration tests.

### Attribution

- **ShadowBitBasher** ([DJI-Mic-Control](https://github.com/ShadowBitBasher/DJI-Mic-Control)): original Tauri/Rust application, DJI DUML v1/v2 wire protocol reverse-engineering, UI design, and device artwork (released under The Unlicense).
- **VaderCheng** ([PR #3](https://github.com/ShadowBitBasher/DJI-Mic-Control/pull/3), [PR #4](https://github.com/ShadowBitBasher/DJI-Mic-Control/pull/4)): DJI Mic Series Mobile Receiver support, Receiver/Monitoring Gain controls, and Simplified Chinese (`zh-CN`) UI localization.

[Unreleased]: https://github.com/chriscz/dji-mic-control/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/chriscz/dji-mic-control/releases/tag/v0.1.0
