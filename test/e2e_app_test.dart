// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:dji_mic_control/main.dart';
import 'package:dji_mic_control/platform/capabilities.dart';
import 'package:dji_mic_control/platform/notifier.dart';
import 'package:dji_mic_control/platform/tray_service.dart';
import 'package:dji_mic_control/platform/udev_installer.dart';
import 'package:dji_mic_control/platform/window_controller.dart';
import 'package:dji_mic_control/protocol/packet.dart';
import 'package:dji_mic_control/sim/simulated_dji_mic.dart';
import 'package:dji_mic_control/state/app_services.dart';
import 'package:dji_mic_control/ui/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> setDesktopSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('DjiMicApp end-to-end (real DUML bytes)', () {
    testWidgets('renders v2 RX/TX cards, toggles settings, enforces mutual exclusion, switches views', (tester) async {
      await setDesktopSurface(tester);

      final mic = SimulatedDjiMic(
        serial: 'E2ERX000000001',
        dialect: Dialect.v2,
        gainDial: 6,
        tx1: const SimulatedTxConfig(
          serial: 'E2ETX100000001',
          productName: 'DJI Mic Mini',
          battery: 2,
          level: 44,
        ),
        tx2: const SimulatedTxConfig(
          serial: 'E2ETX200000002',
          productName: 'DJI Mic Mini 2',
          battery: 4,
          charging: true,
          voiceTone: 'standard',
          level: 52,
        ),
      );
      final win = NoopWindowController();
      final services = AppServices.simulated(
        transport: SimulatedUsbTransport([mic]),
        windowController: win,
      );
      final controller = await bootstrap(services, startPolling: false);
      mic.emitAll();
      await tester.pumpWidget(DjiMicApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('DJI Mic Mini'), findsWidgets);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);
      expect(find.text('+6 dB'), findsOneWidget);
      expect(find.text('DJI Mic Mini (TX1)'), findsOneWidget);
      expect(find.text('DJI Mic Mini 2 (TX2)'), findsOneWidget);

      // Voice Tone appears on Mic Mini 2 TX card; tap Bright and verify hardware state.
      await tester.tap(find.text('Bright'));
      await tester.pumpAndSettle();
      expect(mic.tx[1]!.voiceTone, 'bright');

      // Toggle Low Cut switch and verify hardware state.
      final lowCutSwitch = find.byKey(const Key('setting-switch-low-cut'));
      await tester.ensureVisible(lowCutSwitch);
      await tester.pumpAndSettle();
      await tester.tap(lowCutSwitch);
      await tester.pumpAndSettle();
      expect(mic.lowCut, isTrue);

      // Switch Audio Channels to Stereo -> hardware disables Safety Track and UI locks it.
      final stereoBtn = find.text('Stereo');
      await tester.ensureVisible(stereoBtn);
      await tester.pumpAndSettle();
      await tester.tap(stereoBtn);
      await tester.pumpAndSettle();
      expect(mic.stereo, isTrue);
      expect(mic.safetyTrack, isFalse);

      // Switch to List view and verify inline Plug-Free note appears.
      final listBtn = find.text('List');
      await tester.ensureVisible(listBtn);
      await tester.pumpAndSettle();
      await tester.tap(listBtn);
      await tester.pumpAndSettle();
      expect(find.text('Changing this reboots the receiver.'), findsOneWidget);

      // Collapse and re-expand sidebar via inline toggle buttons.
      await tester.tap(find.byKey(const Key('sidebar-toggle-btn')));
      await tester.pumpAndSettle();
      expect(controller.sidebarOpen, isFalse);
      await tester.tap(find.byKey(const Key('sidebar-expand-btn')));
      await tester.pumpAndSettle();
      expect(controller.sidebarOpen, isTrue);

      // On-screen Diagnostics fold is expanded by default and shows TX / TX OK / Confirmed logs.
      expect(find.byKey(const Key('diagnostics-fold-body')), findsOneWidget);
      expect(find.textContaining('TX [E2ERX000000001] low-cut=on'), findsOneWidget);
      expect(find.textContaining('TX OK [E2ERX000000001] low-cut=on'), findsOneWidget);
      expect(find.textContaining('Confirmed low-cut=on'), findsOneWidget);
      await tester.tap(find.byKey(const Key('diagnostics-fold-header')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diagnostics-fold-body')), findsNothing);
      await tester.tap(find.byKey(const Key('diagnostics-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diagnostics-fold-body')), findsOneWidget);

      // Deselect device by clicking empty sidebar space -> placeholder shows.
      controller.selectDevice(null);
      await tester.pumpAndSettle();
      expect(find.text('No device selected'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(() => services.deviceManager.dispose());
    });

    testWidgets('shows permission banner and opens copyable udev setup modal on Linux EACCES', (tester) async {
      await setDesktopSurface(tester);

      final blocked = SimulatedDjiMic(
        serial: 'E2EBLOCKED0001',
        permissionDenied: true,
      );
      final probe = CapabilitiesProbe(
        osName: 'linux',
        commandExists: (_) async => false,
        fileExists: (_) async => false,
        readFile: (_) async => 'ID=ubuntu\n',
        dbusTrayAvailable: () async => false,
        dbusNotifyAvailable: () async => false,
      );
      final win = NoopWindowController();
      final services = AppServices.simulated(
        transport: SimulatedUsbTransport([blocked]),
        capabilitiesProbe: probe,
        tray: NoopTrayService(available: false),
        windowController: win,
        isDemo: false,
      );
      final controller = await bootstrap(services, startPolling: false);

      await tester.pumpWidget(DjiMicApp(controller: controller));
      await tester.pumpAndSettle();

      // Close-to-tray must be disabled automatically when no tray host is present.
      expect(win.closeToTrayEnabled, isFalse);
      expect(find.byKey(const Key('usb-permission-banner')), findsOneWidget);
      expect(find.text('Permission needed'), findsOneWidget);

      // Open USB Setup modal.
      await tester.tap(find.byKey(const Key('show-setup-cta')));
      await tester.pumpAndSettle();
      expect(find.text('Enable USB access'), findsOneWidget);
      expect(find.textContaining('ATTRS{idVendor}=="2ca3"'), findsWidgets);
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();

      // Open System & Capabilities modal and verify OS-specific install suggestions
      // plus dedicated scrollbar gutter so controls never overlap the scrollbar.
      await tester.tap(find.byKey(const Key('capabilities-btn')));
      await tester.pumpAndSettle();
      expect(find.text('System & Capabilities'), findsOneWidget);
      expect(find.byKey(const Key('capabilities-scrollbar')), findsOneWidget);
      expect(find.textContaining('apt install libnotify-bin'), findsOneWidget);
      expect(find.textContaining('AppIndicator'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(() => services.deviceManager.dispose());
    });

    testWidgets('fires debounced critical battery notification when TX reaches tier 7', (tester) async {
      await setDesktopSurface(tester);

      final notifier = RecordingNotifier();
      final mic = SimulatedDjiMic(
        serial: 'E2EBATT0000001',
        dialect: Dialect.v2,
        tx1: const SimulatedTxConfig(
          serial: 'E2EBATTTX10001',
          battery: 7,
          charging: false,
          level: 20,
        ),
      );
      final services = AppServices.simulated(
        transport: SimulatedUsbTransport([mic]),
        notifier: notifier,
      );
      final controller = await bootstrap(services, startPolling: false);
      mic.emitAll();

      await tester.pumpWidget(DjiMicApp(controller: controller));
      await tester.pump(const Duration(milliseconds: 50));

      expect(notifier.sent, hasLength(1));
      expect(notifier.sent.first.title, contains('Critical'));

      // Subsequent ticks at same tier must not spam duplicate notifications.
      mic.emitStatusAndLevels();
      await tester.pump(const Duration(milliseconds: 50));
      expect(notifier.sent, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(() => services.deviceManager.dispose());
    });

    testWidgets('shows getting-started guidance and one-click udev installer on empty Linux screen', (tester) async {
      await setDesktopSurface(tester);

      var ruleInstalled = false;
      final probe = CapabilitiesProbe(
        osName: 'linux',
        commandExists: (_) async => true,
        fileExists: (path) async => ruleInstalled && path == UdevHelper.rulePath,
        readFile: (_) async => 'ID=ubuntu\n',
        dbusTrayAvailable: () async => true,
        dbusNotifyAvailable: () async => true,
      );
      final installer = FakeUdevInstaller(
        onInstall: () => ruleInstalled = true,
      );
      final services = AppServices.simulated(
        transport: SimulatedUsbTransport(const <SimulatedDjiMic>[]),
        capabilitiesProbe: probe,
        udevInstaller: installer,
        isDemo: false,
      );
      final controller = await bootstrap(services, startPolling: false);

      await tester.pumpWidget(DjiMicApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('No microphone connected'), findsOneWidget);
      expect(find.text('GETTING STARTED'), findsOneWidget);
      expect(find.text('First-time Linux setup recommended'), findsOneWidget);
      final installBtn = find.byKey(const Key('main-install-udev-btn'));
      expect(installBtn, findsOneWidget);

      await tester.ensureVisible(installBtn);
      await tester.pumpAndSettle();
      await tester.tap(installBtn);
      await tester.pumpAndSettle();

      expect(installer.callCount, 1);
      expect(find.text('Linux USB permissions (udev rule) are installed and ready.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(() => services.deviceManager.dispose());
    });

    testWidgets('renders Mobile Receiver with gain sliders, read-only NC, Power USB, and zh-CN switch', (tester) async {
      await setDesktopSurface(tester);

      final mobileMic = SimulatedDjiMic(
        serial: 'MOBILERX000001',
        dialect: Dialect.v2,
        rxProductName: 'DJI Mic Mini 2',
        gainDial: -6,
        monitoringGain: 3,
        tx1: const SimulatedTxConfig(
          serial: 'MOBILETX100001',
          productName: 'DJI Mic Mini 2',
          battery: 3,
          level: 36,
        ),
      );
      final services = AppServices.simulated(
        transport: SimulatedUsbTransport([mobileMic]),
      );
      final controller = await bootstrap(services, startPolling: false);
      mobileMic.emitAll();

      await tester.pumpWidget(DjiMicApp(controller: controller));
      await tester.pumpAndSettle();

      // Mobile receiver identity, USB power row, read-only NC, and gain sliders.
      expect(find.text('DJI Mic Series Mobile Receiver'), findsWidgets);
      expect(find.text('Power'), findsOneWidget);
      expect(find.text('USB'), findsOneWidget);
      expect(find.byKey(const Key('mobile-nc-readonly')), findsOneWidget);
      expect(find.byKey(const Key('setting-range-receiver-gain')), findsOneWidget);
      expect(find.byKey(const Key('setting-range-monitoring-gain')), findsOneWidget);
      expect(find.text('Auto Off RX (15 min)'), findsNothing);
      expect(find.text('RX On/Off follows Camera'), findsNothing);

      // Update gain via controller and confirm hardware state updates.
      await controller.setSetting('receiver-gain', '6');
      await tester.pumpAndSettle();
      expect(mobileMic.gainDial, 6);

      await controller.setSetting('monitoring-gain', '-4');
      await tester.pumpAndSettle();
      expect(mobileMic.monitoringGain, -4);

      // Switch language to Simplified Chinese in Preferences modal.
      await tester.tap(find.byKey(const Key('capabilities-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('接收器增益'), findsOneWidget);
      expect(find.text('监听增益'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(() => services.deviceManager.dispose());
    });
  });
}
