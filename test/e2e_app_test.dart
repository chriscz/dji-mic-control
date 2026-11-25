// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:dji_mic_control/main.dart';
import 'package:dji_mic_control/platform/capabilities.dart';
import 'package:dji_mic_control/platform/notifier.dart';
import 'package:dji_mic_control/platform/tray_service.dart';
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
      await tester.tap(find.byKey(const Key('setting-switch-low-cut')));
      await tester.pumpAndSettle();
      expect(mic.lowCut, isTrue);

      // Switch Audio Channels to Stereo -> hardware disables Safety Track and UI locks it.
      await tester.tap(find.text('Stereo'));
      await tester.pumpAndSettle();
      expect(mic.stereo, isTrue);
      expect(mic.safetyTrack, isFalse);

      // Switch to List view and verify inline Plug-Free note appears.
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      expect(find.text('Changing this reboots the receiver.'), findsOneWidget);

      // Collapse and re-expand sidebar via inline toggle buttons.
      await tester.tap(find.byKey(const Key('sidebar-toggle-btn')));
      await tester.pumpAndSettle();
      expect(controller.sidebarOpen, isFalse);
      await tester.tap(find.byKey(const Key('sidebar-expand-btn')));
      await tester.pumpAndSettle();
      expect(controller.sidebarOpen, isTrue);

      // Open Diagnostics dialog and verify entries render.
      await tester.tap(find.byKey(const Key('diagnostics-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Diagnostics'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();

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
  });
}
