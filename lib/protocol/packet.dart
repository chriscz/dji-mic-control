// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:typed_data';

import 'crc.dart';

/// Firmware wire dialect detected passively from incoming heartbeats.
enum Dialect {
  /// v1 firmware: 19-byte commands, big-endian command IDs, CRC init 0x0000.
  v1(1, DjiCrc16.v1Init, DjiCrc16.v1Residue),

  /// v2 firmware: 22-byte target-addressed commands, LE command IDs, init 0x3692.
  v2(2, DjiCrc16.v2Init, DjiCrc16.v2Residue);

  const Dialect(this.versionNumber, this.crcInit, this.crcResidue);

  final int versionNumber;
  final int crcInit;
  final int crcResidue;
}

/// Role of a DUML frame determined by offset 8 (ACK-flag byte).
enum FrameKind {
  command,
  ack,
  heartbeat,
  other,
}

/// DUML packet framing helpers shared by DJI microphone models.
class DumlPacket {
  DumlPacket._();

  static const int sof = 0x55;
  static const int version = 0x04;
  static const int v1CommandLen = 19;
  static const int v2CommandLen = 22;
  static const int minFrame = 4;
  static const int maxFrame = 256;

  /// Detect a heartbeat frame's dialect from marker bytes [8..12].
  static Dialect? heartbeatDialect(List<int> frame) {
    if (frame.length < 12 || frame[8] != 0x00 || frame[9] != 0x5b || frame[10] != 0x03) {
      return null;
    }
    return switch (frame[11]) {
      0x00 => Dialect.v1,
      0x03 => Dialect.v2,
      _ => null,
    };
  }

  /// Classify a complete frame by its offset-8 ACK-flag byte.
  static FrameKind frameKind(List<int> frame) {
    if (frame.length <= 8) return FrameKind.other;
    return switch (frame[8]) {
      0x40 => FrameKind.command,
      0x80 => FrameKind.ack,
      0x00 => FrameKind.heartbeat,
      _ => FrameKind.other,
    };
  }

  /// Drain and return the next complete DUML frame from [buf], resyncing past
  /// invalid bytes and retaining any trailing partial frame.
  static Uint8List? takeFrame(List<int> buf) {
    while (true) {
      int? start;
      for (var i = 0; i < buf.length; i++) {
        if (buf[i] == sof) {
          if (i + 2 >= buf.length) {
            if (i > 0) buf.removeRange(0, i);
            return null;
          }
          if (buf[i + 2] == version) {
            start = i;
            break;
          }
        }
      }

      if (start == null) {
        if (buf.isNotEmpty && buf.last == sof) {
          buf.removeRange(0, buf.length - 1);
        } else {
          buf.clear();
        }
        return null;
      }

      if (start > 0) {
        buf.removeRange(0, start);
      }

      final len = buf[1];
      if (len < minFrame || len > maxFrame) {
        buf.removeAt(0);
        continue;
      }
      if (buf.length < len) {
        return null;
      }

      final frame = Uint8List.fromList(buf.sublist(0, len));
      buf.removeRange(0, len);
      return frame;
    }
  }

  /// Build a 19-byte v1 setting command packet (big-endian command ID).
  static Uint8List buildV1Command(int seq, int command, int value) {
    final body = <int>[
      sof,
      v1CommandLen,
      version,
      0x03, // header CRC-8 for 19-byte frame
      0x02, // audio subsystem
      0x5a, // attribute flags
      seq & 0xff,
      (seq >> 8) & 0xff,
      0x40, // ACK requested
      0x5b,
      0x01,
      0x00,
      (command >> 8) & 0xff, // big-endian command ID
      command & 0xff,
      0x00,
      0x01, // payload length
      value & 0xff,
    ];
    return DjiCrc16.append(body, Dialect.v1.crcInit, Dialect.v1.crcResidue);
  }

  /// Build a 22-byte v2 target-addressed setting command (LE command ID).
  static Uint8List buildV2Command(int seq, int target, int command, int value) {
    final body = <int>[
      sof,
      v2CommandLen,
      version,
      0xfc, // header CRC-8 for 22-byte frame
      0x02, // audio subsystem
      0x5a, // attribute flags
      seq & 0xff,
      (seq >> 8) & 0xff,
      0x40, // ACK requested
      0x5b,
      0x01,
      0x02, // v2 target-addressed sub-type
      target & 0xff, // LE target
      (target >> 8) & 0xff,
      0x00,
      0x00,
      command & 0xff, // LE command ID
      (command >> 8) & 0xff,
      0x01, // payload length
      value & 0xff,
    ];
    return DjiCrc16.append(body, Dialect.v2.crcInit, Dialect.v2.crcResidue);
  }

  /// Build a 14-byte ACK frame echoing [seq] (used by simulator/tests).
  static Uint8List buildAck(int seq, Dialect dialect) {
    final body = <int>[
      sof,
      0x0e,
      version,
      0x66, // header CRC-8 for 14-byte frame
      0x5a,
      0x02,
      seq & 0xff,
      (seq >> 8) & 0xff,
      0x80, // ACK flag
      0x5b,
      0x01,
      0x00,
    ];
    return DjiCrc16.append(body, dialect.crcInit, dialect.crcResidue);
  }
}
