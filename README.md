# DJI Mic Control (Flutter)

A Linux-first desktop controller for DJI wireless microphones (DJI Mic Mini and DJI Mic Mini 2 transmitters on v1 and v2 firmware), ported from [ShadowBitBasher/DJI-Mic-Control](https://github.com/ShadowBitBasher/DJI-Mic-Control) to core Flutter and Dart libraries with zero third-party native Flutter plugins.

## Highlights

- **Core Flutter/Dart standard library only:** Zero third-party pub.dev runtime dependencies and zero hard-linked OS plugin libraries (`libappindicator`, `libnotify`, `libusb`, `webkit2gtk`).
- **Dual USB transport behind one seam (`UsbTransport`):**
  - Default on Linux: pure-Dart `sysfs` + `usbfs` ioctl transport (`lib/transport/linux_usbfs_transport.dart`) using `dart:ffi` against `libc`.
  - Optional cross-platform backend: thin Rust `nusb` `cdylib` (`native/dji_mic_usb/` + `lib/transport/nusb_ffi_transport.dart`) linking only glibc on Linux, IOKit on macOS, and WinUSB on Windows.
- **Runtime OS capability probing with in-app setup hints:** Automatically probes USB permissions (udev/Zadig), notifications (`notify-send` / session D-Bus), system tray (`org.kde.StatusNotifierWatcher`), and autostart, gracefully degrading when optional OS tools are absent and showing copyable install commands inside **System & Capabilities**.
- **Byte-level simulator and demo mode:** Run with `--dart-define=DEMO=true` or `--demo` to exercise real DUML v1/v2 packets without physical hardware.

## Running and Testing

Use the existing Flutter `3.47.7` installation from Lumen:

```sh
export PATH="/home/chris.guest/sdk/flutter/bin:$PATH"

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
bash tool/build_linux.sh --debug
bash tool/build_linux.sh --with-nusb --debug    # also compile & bundle libdji_mic_usb.so
```

## Linux USB Permissions (udev)

Install `packaging/60-dji-mic.rules` so non-root desktop sessions can open vendor Interface `6` while leaving USB Audio interfaces untouched:

```sh
sudo cp packaging/60-dji-mic.rules /etc/udev/rules.d/60-dji-mic.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb
```
