// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:dji_mic_control/main.dart';
import 'package:dji_mic_control/platform/window_controller.dart';
import 'package:dji_mic_control/protocol/packet.dart';
import 'package:dji_mic_control/sim/simulated_dji_mic.dart';
import 'package:dji_mic_control/state/app_services.dart';
import 'package:dji_mic_control/ui/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runs full app on real Linux GTK3 desktop device', (tester) async {
    final mic = SimulatedDjiMic(
      serial: 'LINUXRX0000001',
      dialect: Dialect.v2,
      gainDial: 0,
      tx1: const SimulatedTxConfig(
        serial: 'LINUXTX1000001',
        productName: 'DJI Mic Mini',
        battery: 1,
        level: 40,
      ),
      tx2: const SimulatedTxConfig(
        serial: 'LINUXTX2000002',
        productName: 'DJI Mic Mini 2',
        battery: 3,
        voiceTone: 'standard',
        level: 50,
      ),
    );

    final services = AppServices.simulated(
      transport: SimulatedUsbTransport(<SimulatedDjiMic>[mic]),
      windowController: MethodChannelWindowController(),
    );
    final controller = await bootstrap(services, startPolling: false);
    mic.emitAll();

    await tester.pumpWidget(DjiMicApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('DJI Mic Mini'), findsWidgets);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('0 dB'), findsOneWidget);
    expect(find.text('DJI Mic Mini 2 (TX2)'), findsOneWidget);

    // Exercise real DUML byte command + UI state update on Linux desktop.
    await tester.tap(find.text('Rich'));
    await tester.pumpAndSettle();
    expect(mic.tx[1]!.voiceTone, 'rich');

    await tester.tap(find.byKey(const Key('setting-switch-low-cut')));
    await tester.pumpAndSettle();
    expect(mic.lowCut, isTrue);

    // Open System & Capabilities dialog on real desktop.
    await tester.tap(find.byKey(const Key('capabilities-btn')));
    await tester.pumpAndSettle();
    expect(find.text('System & Capabilities'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await services.deviceManager.dispose();
  });
}
