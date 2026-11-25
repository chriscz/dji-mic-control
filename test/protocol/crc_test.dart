// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:typed_data';

import 'package:dji_mic_control/protocol/crc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DjiCrc16', () {
    test('appended packet has valid v1 residue', () {
      final body = Uint8List.fromList([0x55, 0x13, 0x04, 0x03, 0x02, 0x5a]);
      final packet = DjiCrc16.append(body, DjiCrc16.v1Init, DjiCrc16.v1Residue);
      expect(DjiCrc16.verify(packet, DjiCrc16.v1Init, DjiCrc16.v1Residue), isTrue);
      expect(packet.length, body.length + 2);
    });

    test('matches documented v1 command CRC (NC -> Strong)', () {
      final full = Uint8List.fromList([
        0x55, 0x13, 0x04, 0x03, 0x02, 0x5a, 0x01, 0x00, 0x40, 0x5b, 0x01,
        0x00, 0x03, 0x1d, 0x00, 0x01, 0x01, 0x91, 0xfb,
      ]);
      expect(DjiCrc16.verify(full, DjiCrc16.v1Init, DjiCrc16.v1Residue), isTrue);
      expect(
        DjiCrc16.crcBytes(full.sublist(0, full.length - 2), DjiCrc16.v1Init, DjiCrc16.v1Residue),
        equals([0x91, 0xfb]),
      );
    });

    test('matches documented v2 command CRC (NC -> Basic, broadcast)', () {
      final full = Uint8List.fromList([
        0x55, 0x16, 0x04, 0xfc, 0x02, 0x5a, 0x40, 0xb6, 0x40, 0x5b, 0x01,
        0x02, 0xff, 0xff, 0x00, 0x00, 0x37, 0x00, 0x01, 0x00, 0xdd, 0xe2,
      ]);
      expect(DjiCrc16.verify(full, DjiCrc16.v2Init, DjiCrc16.v2Residue), isTrue);
      expect(
        DjiCrc16.crcBytes(full.sublist(0, full.length - 2), DjiCrc16.v2Init, DjiCrc16.v2Residue),
        equals([0xdd, 0xe2]),
      );
    });

    test('rejects short and corrupted packets', () {
      expect(DjiCrc16.verify(Uint8List.fromList([0x55]), DjiCrc16.v1Init, DjiCrc16.v1Residue), isFalse);
      final corrupted = Uint8List.fromList([
        0x55, 0x13, 0x04, 0x03, 0x02, 0x5a, 0x01, 0x00, 0x40, 0x5b, 0x01,
        0x00, 0x03, 0x1d, 0x00, 0x01, 0x00, 0x91, 0xfb,
      ]);
      expect(DjiCrc16.verify(corrupted, DjiCrc16.v1Init, DjiCrc16.v1Residue), isFalse);
    });
  });
}
