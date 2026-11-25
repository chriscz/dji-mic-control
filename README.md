# DJI Mic Control (Flutter)

A Linux-first desktop controller for DJI wireless microphones (DJI Mic Mini, DJI Mic Mini 2 transmitters, and DJI Mic Series Mobile Receiver on v1 and v2 firmware), built on core Flutter and Dart libraries with zero third-party native Flutter plugins.

Repository: [chriscz/dji-mic-control](https://github.com/chriscz/dji-mic-control)

## Origin and Attribution

This project is a ground-up Flutter/Dart port of [ShadowBitBasher/DJI-Mic-Control](https://github.com/ShadowBitBasher/DJI-Mic-Control) (`v1.1.0`, commit `9ba7688`), originally written in Rust + Svelte + Tauri and dedicated to the public domain under [The Unlicense](https://unlicense.org).

It also incorporates protocol, UI, and localization work from two upstream pull requests authored by [VaderCheng](https://github.com/VaderCheng):

- **[PR #4](https://github.com/ShadowBitBasher/DJI-Mic-Control/pull/4) (VaderCheng):** DJI Mic Series Mobile Receiver identification, `Receiver Gain` (`-12/-6/0/6/12` dB) and `Monitoring Gain` (`-12..+12` dB) sliders with confirmation wait, `mobile-rx` pictogram, `Power: USB` readout, read-only O/L/H switch noise cancellation status, and unsupported-command guards.
- **[PR #3](https://github.com/ShadowBitBasher/DJI-Mic-Control/pull/3) (VaderCheng):** Optional Simplified Chinese (`zh-CN`) UI localization with English fallback.

All protocol reverse-engineering, DUML framing, UI layout concepts, and original device PNG artwork originate from **ShadowBitBasher**, and the Mobile Receiver / gain control / Chinese translation additions originate from **VaderCheng**.

## Highlights

- **Core Flutter and Dart standard library only:** Zero third-party pub.dev runtime dependencies and zero hard-linked OS plugin libraries (`libappindicator`, `libnotify`, `libusb`, `webkit2gtk`).
- **Dual USB transport behind one seam (`UsbTransport`):**
  - Default on Linux: pure-Dart `sysfs` + `usbfs` ioctl transport (`lib/transport/linux_usbfs_transport.dart`) using `dart:ffi` against `libc`.
  - Optional cross-platform backend: thin Rust `nusb` `cdylib` (`native/dji_mic_usb/` + `lib/transport/nusb_ffi_transport.dart`) linking only glibc on Linux, IOKit on macOS, and WinUSB on Windows.
- **Runtime OS capability probing with in-app setup hints:** Automatically probes USB permissions (udev/Zadig), notifications (`notify-send` / session D-Bus), system tray (`org.kde.StatusNotifierWatcher`), and autostart, gracefully degrading when optional OS tools are absent and offering one-click Linux udev rule installation (`pkexec`) plus copyable commands inside **System & Capabilities**.
- **On-screen Diagnostics and Pending Operations:** Collapsible bottom Diagnostics fold (expanded by default) showing live `TX`, `TX OK`, `TX FAIL`, and `Confirmed` logs, paired with a hideable Pending Operations strip.
- **English and Simplified Chinese UI:** Switch between `English` and `简体中文` in **System & Capabilities > Preferences**.
- **Byte-level simulator and demo mode:** Run with `--dart-define=DEMO=true` or `--demo` to exercise real DUML v1/v2 packets without physical hardware.

## Running and Testing

```sh
flutter analyze
flutter test                                    # unit, protocol, platform, and headless E2E tests
flutter run -d linux --dart-define=DEMO=true    # launch UI with simulated v1 + v2 microphones
flutter run -d linux                            # launch with real USB hardware
```

### Linux Desktop Build Prerequisites

Headless `flutter test` works immediately with no extra system packages. Building a Linux binary (`flutter build linux`) requires:

```sh
sudo apt install clang cmake ninja-build libgtk-3-dev xvfb
```

Then build and audit shared-library dependencies:

```sh
bash tool/build_linux.sh --release
bash tool/build_linux.sh --with-nusb --release   # also compile & bundle libdji_mic_usb.so
```

## Linux USB Permissions (udev)

You can install the udev rule directly inside the app via the **Install udev rule** button (`pkexec`), or manually copy `packaging/60-dji-mic.rules` so non-root desktop sessions can open vendor Interface `6` while leaving USB Audio interfaces untouched:

```sh
sudo cp packaging/60-dji-mic.rules /etc/udev/rules.d/60-dji-mic.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add --subsystem-match=usb --attr-match=idVendor=2ca3
```

## License

This repository (`chriscz/dji-mic-control`) is licensed under the [MIT License](LICENSE). See [LICENSE](LICENSE) and [CHANGELOG.md](CHANGELOG.md) for upstream origin and attribution details.
