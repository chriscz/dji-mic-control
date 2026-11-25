// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import '../log/app_logger.dart';
import '../platform/autostart_service.dart';
import '../platform/capabilities.dart';
import '../platform/config_store.dart';
import '../platform/notifier.dart';
import '../platform/single_instance.dart';
import '../platform/tray_service.dart';
import '../platform/udev_installer.dart';
import '../platform/window_controller.dart';
import '../sim/simulated_dji_mic.dart';
import '../transport/device_manager.dart';
import '../transport/linux_usbfs_transport.dart';
import '../transport/nusb_ffi_transport.dart';
import '../transport/usb_transport.dart';

/// Dependency container wired by `main.dart`, `--demo`, and tests.
class AppServices {
  const AppServices({
    required this.deviceManager,
    required this.configStore,
    required this.autostart,
    required this.capabilitiesProbe,
    required this.notifier,
    required this.tray,
    required this.windowController,
    required this.udevInstaller,
    required this.logger,
    this.singleInstance,
    this.isDemo = false,
  });

  final DeviceManager deviceManager;
  final ConfigStore configStore;
  final AutostartService autostart;
  final CapabilitiesProbe capabilitiesProbe;
  final DesktopNotifier notifier;
  final TrayService tray;
  final WindowController windowController;
  final UdevInstaller udevInstaller;
  final AppLogger logger;
  final SingleInstance? singleInstance;
  final bool isDemo;

  factory AppServices.production({UsbTransport? transport}) {
    final logger = AppLogger(logFile: ConfigStore.defaultLogFile());
    // Prefer the cross-platform Rust nusb cdylib when bundled; otherwise use
    // the zero-dependency pure-Dart Linux usbfs transport.
    final activeTransport = transport ?? NusbFfiTransport.tryLoad() ?? LinuxUsbfsTransport();
    return AppServices(
      deviceManager: DeviceManager(transport: activeTransport, logger: logger),
      configStore: ConfigStore(),
      autostart: AutostartService(),
      capabilitiesProbe: CapabilitiesProbe(),
      notifier: ProcessDesktopNotifier(logger: logger),
      tray: DbusTrayService(logger: logger),
      windowController: MethodChannelWindowController(),
      udevInstaller: UdevInstaller(logger: logger),
      logger: logger,
      singleInstance: SingleInstance(),
      isDemo: false,
    );
  }

  factory AppServices.simulated({
    UsbTransport? transport,
    CapabilitiesProbe? capabilitiesProbe,
    DesktopNotifier? notifier,
    TrayService? tray,
    WindowController? windowController,
    UdevInstaller? udevInstaller,
    DateTime Function()? now,
    bool isDemo = true,
  }) {
    final logger = AppLogger(now: now);
    final simTransport = transport ?? DemoFixture.createTransport();
    return AppServices(
      deviceManager: DeviceManager(transport: simTransport, now: now, logger: logger),
      configStore: MemoryConfigStore(),
      autostart: MemoryAutostartService(),
      capabilitiesProbe: capabilitiesProbe ??
          CapabilitiesProbe(
            osName: 'linux',
            commandExists: (_) async => true,
            fileExists: (_) async => true,
            readFile: (_) async => 'ID=ubuntu\n',
            dbusTrayAvailable: () async => true,
            dbusNotifyAvailable: () async => true,
          ),
      notifier: notifier ?? RecordingNotifier(),
      tray: tray ?? NoopTrayService(available: true),
      windowController: windowController ?? NoopWindowController(),
      udevInstaller: udevInstaller ?? FakeUdevInstaller(),
      logger: logger,
      isDemo: isDemo,
    );
  }
}
