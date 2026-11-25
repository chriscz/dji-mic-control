// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:typed_data';

import 'package:dji_mic_control/protocol/packet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DumlPacket', () {
    test('builds documented v1 NC Strong command', () {
      final pkt = DumlPacket.buildV1Command(1, 0x031d, 0x01);
      expect(
        pkt,
        equals([
          0x55, 0x13, 0x04, 0x03, 0x02, 0x5a, 0x01, 0x00, 0x40, 0x5b, 0x01,
          0x00, 0x03, 0x1d, 0x00, 0x01, 0x01, 0x91, 0xfb,
        ]),
      );
    });

    test('classifies frames by ACK-flag byte', () {
      final cmd = DumlPacket.buildV1Command(1, 0x031d, 0x01);
      expect(DumlPacket.frameKind(cmd), FrameKind.command);
      expect(
        DumlPacket.frameKind(Uint8List.fromList([0x55, 0x0e, 0x04, 0x66, 0x5a, 0x02, 1, 0, 0x80])),
        FrameKind.ack,
      );
      expect(
        DumlPacket.frameKind(Uint8List.fromList([0x55, 0x38, 0x04, 0xe1, 0x5a, 0x02, 0, 0, 0x00])),
        FrameKind.heartbeat,
      );
      expect(DumlPacket.frameKind(Uint8List.fromList([0x55, 0x04])), FrameKind.other);
    });

    test('extracts frame and resyncs past leading junk', () {
      final cmd = DumlPacket.buildV1Command(7, 0x0303, 0x01);
      final buf = <int>[0xaa, 0xbb, ...cmd, 0x55];
      final frame = DumlPacket.takeFrame(buf);
      expect(frame, equals(cmd));
      expect(buf, equals([0x55]));
      expect(DumlPacket.takeFrame(buf), isNull);
    });

    test('skips stray 0x55 inside payload (e.g. ASCII U in serial)', () {
      final cmd = DumlPacket.buildV1Command(3, 0x031d, 0x01);
      final buf = <int>[0x55, 0x30, 0x31, 0x34, 0x51, ...cmd];
      final frame = DumlPacket.takeFrame(buf);
      expect(frame, equals(cmd));
      expect(buf, isEmpty);
    });

    test('builds documented v2 NC Basic broadcast command', () {
      final pkt = DumlPacket.buildV2Command(0xb640, 0xffff, 0x0037, 0x00);
      expect(
        pkt,
        equals([
          0x55, 0x16, 0x04, 0xfc, 0x02, 0x5a, 0x40, 0xb6, 0x40, 0x5b, 0x01,
          0x02, 0xff, 0xff, 0x00, 0x00, 0x37, 0x00, 0x01, 0x00, 0xdd, 0xe2,
        ]),
      );
    });

    test('detects dialect from heartbeat marker', () {
      final v1 = Uint8List.fromList([0x55, 0x38, 0x04, 0xe1, 0x5a, 0x02, 0, 0, 0, 0x5b, 0x03, 0x00]);
      final v2 = Uint8List.fromList([0x55, 0x36, 0x04, 0x3d, 0x5a, 0x02, 0, 0, 0, 0x5b, 0x03, 0x03]);
      expect(DumlPacket.heartbeatDialect(v1), Dialect.v1);
      expect(DumlPacket.heartbeatDialect(v2), Dialect.v2);
      expect(DumlPacket.heartbeatDialect(DumlPacket.buildV1Command(1, 0x031d, 0x01)), isNull);
    });
  });
}
