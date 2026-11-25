// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:dji_mic_control/protocol/packet.dart';
import 'package:dji_mic_control/sim/simulated_dji_mic.dart';
import 'package:dji_mic_control/transport/device_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceManager + SimulatedDjiMic (byte-level)', () {
    test('discovers v2 receiver, decodes status/identity/level, and applies settings over DUML bytes', () async {
      var clock = DateTime(2026, 11, 25, 12, 0, 0);
      final sim = SimulatedDjiMic(
        serial: 'RXSIM000000001',
        dialect: Dialect.v2,
        tx1: const SimulatedTxConfig(
          serial: 'TX1SIM00000001',
          productName: 'DJI Mic Mini',
          battery: 2,
          level: 40,
        ),
        tx2: const SimulatedTxConfig(
          serial: 'TX2SIM00000002',
          productName: 'DJI Mic Mini 2',
          battery: 6,
          charging: false,
          voiceTone: 'standard',
          level: 55,
        ),
        gainDial: 6,
      );
      final transport = SimulatedUsbTransport([sim]);
      final manager = DeviceManager(transport: transport, now: () => clock);

      await manager.refresh();
      sim.emitAll();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final snap = manager.snapshot('RXSIM000000001');
      expect(snap.devices, hasLength(1));
      expect(snap.status, isNotNull);
      expect(snap.status!.connected, isTrue);
      expect(snap.status!.protocolVersion, 2);
      expect(snap.status!.gainDial, 6);
      expect(snap.status!.rx!.serial, 'RXSIM000000001');
      expect(snap.status!.tx[0]!.productName, 'DJI Mic Mini');
      expect(snap.status!.tx[1]!.productName, 'DJI Mic Mini 2');
      expect(snap.status!.tx[1]!.battery, 6);
      expect(snap.status!.tx[0]!.level, 40);

      // Toggle stereo -> mutually excludes safety-track on real hardware bytes
      await manager.setSetting('RXSIM000000001', 'stereo', 'stereo');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      var updated = manager.snapshot('RXSIM000000001').status!;
      expect(updated.settings['stereo'], 'stereo');
      expect(updated.settings['safety-track'], 'off');

      // Enabling safety-track switches stereo back to mono
      await manager.setSetting('RXSIM000000001', 'safety-track', 'on');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      updated = manager.snapshot('RXSIM000000001').status!;
      expect(updated.settings['safety-track'], 'on');
      expect(updated.settings['stereo'], 'mono');

      // Per-TX Voice Tone on Mic Mini 2 (TX2)
      await manager.setTxSetting('RXSIM000000001', 1, 'voice-tone', 'bright');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      updated = manager.snapshot('RXSIM000000001').status!;
      expect(updated.tx[1]!.voiceTone, 'bright');
      expect(updated.tx[0]!.voiceTone, 'standard');

      // Inverted Mic LEDs toggle
      await manager.setSetting('RXSIM000000001', 'mic-leds', 'off');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      updated = manager.snapshot('RXSIM000000001').status!;
      expect(updated.settings['mic-leds'], 'off');

      // Liveness window: >1500ms without frames reports connected=false
      clock = clock.add(const Duration(milliseconds: 1600));
      final stale = manager.snapshot('RXSIM000000001');
      expect(stale.status!.connected, isFalse);

      await manager.dispose();
    });

    test('supports v1 firmware heartbeat and rejects v2-only writes cleanly', () async {
      final sim = SimulatedDjiMic(
        serial: 'V1RX0000000001',
        dialect: Dialect.v1,
        tx1: const SimulatedTxConfig(serial: 'V1TX1000000001', level: 32),
      );
      final transport = SimulatedUsbTransport([sim]);
      final manager = DeviceManager(transport: transport);

      await manager.refresh();
      sim.emitAll();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final st = manager.snapshot('V1RX0000000001').status!;
      expect(st.protocolVersion, 1);
      expect(st.connected, isTrue);
      expect(st.tx[0]!.serial, 'V1TX1000000001');

      await expectLater(
        () => manager.setSetting('V1RX0000000001', 'noise-cancel-power', 'off'),
        throwsA(isA<UnsupportedSettingException>()),
      );

      await manager.setSetting('V1RX0000000001', 'low-cut', 'on');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(manager.snapshot('V1RX0000000001').status!.settings['low-cut'], 'on');

      await manager.dispose();
    });

    test('flags permissionIssue on EACCES and recovers on plug-free reboot', () async {
      final blocked = SimulatedDjiMic(
        serial: 'BLOCKED0000001',
        permissionDenied: true,
      );
      final transport = SimulatedUsbTransport([blocked]);
      final manager = DeviceManager(transport: transport);

      await manager.refresh();
      final blockedSnap = manager.snapshot(null);
      expect(blockedSnap.probe.permissionIssue, isTrue);
      expect(blockedSnap.devices, isEmpty);

      // Grant permission and test plug-free reboot re-enumeration
      blocked.permissionDenied = false;
      await manager.refresh();
      blocked.emitAll();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(manager.snapshot('BLOCKED0000001').status!.connected, isTrue);

      await manager.setSetting('BLOCKED0000001', 'plug-free', 'on');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Reboot disconnects old handle; next refresh adopts the re-enumerated receiver
      await manager.refresh();
      blocked.emitAll();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final recovered = manager.snapshot('BLOCKED0000001');
      expect(recovered.status!.connected, isTrue);
      expect(recovered.status!.settings['plug-free'], 'on');

      await manager.dispose();
    });
  });
}
