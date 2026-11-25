// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:typed_data';

import 'package:dji_mic_control/protocol/crc.dart';
import 'package:dji_mic_control/protocol/mic_mini_model.dart';
import 'package:dji_mic_control/protocol/packet.dart';
import 'package:dji_mic_control/protocol/state.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _hexBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List _sample2TxV1() {
  final body = Uint8List.fromList([
    0x55, 0x54, 0x04, 0xf6, 0x5a, 0x02, 0x0e, 0x79, 0x00, 0x5b, 0x03,
    0x00, 0x47, 0x00,
    // TX1, serial "BBBBBBBBBBBBBB"
    0xb0, 0x25, 0x38, 0x00, 0x01, 0x01, 0x00, 0x38, 0x0e, 0x42, 0x42,
    0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
    0x42,
    // TX2, serial "CCCCCCCCCCCCCC"
    0xb0, 0x25, 0x38, 0x00, 0x01, 0x01, 0x00, 0x38, 0x0e, 0x43, 0x43,
    0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43,
    0x43,
    // RX, serial "AAAAAAAAAAAAAA"
    0x32, 0x20, 0x01, 0x01, 0x00, 0x38, 0x0e, 0x41, 0x41, 0x41, 0x41,
    0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x00,
  ]);
  return DjiCrc16.append(body, DjiCrc16.v1Init, DjiCrc16.v1Residue);
}

Uint8List _sample2TxV2() {
  const hex =
      '557604a65a020000005b0303660003000000002028310c00000000000000'
      '0000000000000000000000000000030000001c00000002010000001ab825'
      '04010078000000000000000000000000000000000000000002020000001a'
      'b825040100780000000000000000000000000000000000000000';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sample2TxV2NegativeGain() {
  const hex =
      '557604a65a020000005b030366000300000000202831f400000000000000'
      '0000000000000000000000000000030000001c00000002010000001ab825'
      '04010078000000000000000000000000000000000000000002020000001a'
      'b825040100780000000000000000000000000000000000000000';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sample2TxV2DistinctTones() {
  const hex =
      '557604a65a020000005b0303660003000000002028310c00000000000000'
      '0000000000000000000000000000030000001c00000002010000001ab825'
      '04410078000000000000000000000000000000000000000002020000001a'
      'b825048100780000000000000000000000000000000000000000';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sample2TxV2Tx2Charging() {
  const hex =
      '557604a65a020000005b0303660003000000002028310c00000000000000'
      '0000000000000000000000000000030000001c00000002010000001ab825'
      '04010078000000000000000000000000000000000000000002020000001a'
      'b827040100780000000000000000000000000000000000000000';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sample2TxV2Tx2Battery(int tx2Plus7) {
  final byteHex = tx2Plus7.toRadixString(16).padLeft(2, '0');
  final hex =
      '557604a65a020000005b0303660003000000002028310c00000000000000'
      '0000000000000000000000000000030000001c00000002010000001ab825'
      '04010078000000000000000000000000000000000000000002020000001a'
      'b8${byteHex}040100780000000000000000000000000000000000000000';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sampleIdentityRxOnly() {
  const hex =
      '5546048b5a020000005b0303360001000000001200110302444444444444444444'
      '444444444404000000000630303030303006000000000c444a49204d6963204d69'
      '6e69';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sampleIdentityRxAndTx() {
  const hex =
      '557c04415a020000005b03036c0001000000001200110302444444444444444444'
      '444444444404000000000630303030303006000000000c444a49204d6963204d69'
      '6e6901010000001200110302454545454545454545454545454504010000000630'
      '303030303006010000000c444a49204d6963204d696e69';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sampleIdentityRxAndTwoTx() {
  const hex =
      '55b204295a020000005b0303a20001000000001200110302444444444444444444'
      '444444444404000000000630303030303006000000000c444a49204d6963204d69'
      '6e6901010000001200110302454545454545454545454545454504010000000630'
      '303030303006010000000c444a49204d6963204d696e6901020000001200110302'
      '464646464646464646464646464604020000000630303030303006020000000c44'
      '4a49204d6963204d696e69';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sampleIdentityRxAndTxV2Model() {
  const hex =
      '557e040000000000005b0303000001000000001200110302444444444444444444'
      '444444444404000000000637626165386606000000000c444a49204d6963204d69'
      '6e69010100000012000b0302454545454545454545454545454504010000000661'
      '376330313206010000000e444a49204d6963204d696e692032';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sampleLevel2Tx() {
  const hex = '551e048a5a020000005b03030e000501000000013005020000000130';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sampleTx2OnlyV2() {
  const hex =
      '555604a65a020000005b0303460003000000002028310c00000000000000000000'
      '0000000000000000000000020000001c00000002020000001ab825040100780000'
      '000000000000000000000000000000000000';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sampleTx1OnlyV2() {
  const hex =
      '555604a65a020000005b0303460003000000002028310c00000000000000000000'
      '0000000000000000000000010000001c00000002010000001ab825040100780000'
      '000000000000000000000000000000000000';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

Uint8List _sampleTx2FlaggedNoSlotV2() {
  const hex =
      '553604a65a020000005b0303260003000000002028310c00000000000000000000'
      '0000000000000000000000020000001c000000';
  return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
}

void main() {
  const model = MicMiniModel();
  DeviceStatus fresh() => DeviceStatus.disconnected(model.id);

  group('MicMiniModel decoding', () {
    test('decodes two-TX v1 heartbeat', () {
      final st = model.decode(fresh(), _sample2TxV1())!;
      expect(st.connected, isTrue);
      expect(st.protocolVersion, 1);
      expect(st.txCount, 2);
      expect(st.tx[0]!.serial, 'BBBBBBBBBBBBBB');
      expect(st.tx[0]!.firmware.toString(), '01.01.00.56');
      expect(st.tx[1]!.serial, 'CCCCCCCCCCCCCC');
      expect(st.rx!.serial, 'AAAAAAAAAAAAAA');
      expect(st.settings['noise-cancel'], 'strong');
      expect(st.settings['low-cut'], 'off');
      expect(st.ncEnabled, isTrue);
      expect(st.settings['noise-cancel-power'], 'on');
      expect(st.settings['auto-off-15m'], 'on');
      expect(st.settings['stereo'], 'mono');
      expect(st.settings['clip-limiter'], 'on');
      expect(st.settings['safety-track'], 'off');
      expect(st.settings['plug-free'], 'off');
      expect(st.settings['mic-leds'], 'on');
    });

    test('decodes two-TX v2 status push', () {
      final st = model.decode(fresh(), _sample2TxV2())!;
      expect(st.connected, isTrue);
      expect(st.protocolVersion, 2);
      expect(st.txCount, 2);
      expect(st.tx[0]!.serial, isNull);
      expect(st.rx!.serial, isNull);
      expect(st.settings['noise-cancel'], 'strong');
      expect(st.settings['noise-cancel-power'], 'on');
      expect(st.ncEnabled, isTrue);
      expect(st.settings['camera-power'], 'off');
      expect(st.settings['auto-off-15m'], 'on');
      expect(st.settings['stereo'], 'mono');
      expect(st.gainDial, 12);
      expect(st.settings['plug-free'], 'off');
      expect(st.settings['clip-limiter'], 'on');
      expect(st.settings['safety-track'], 'off');
      expect(st.settings['mic-leds'], 'on');
      expect(st.settings['tx-auto-off-15m'], 'on');
      expect(st.settings['noise-cancel-button'], 'on');
      expect(st.settings['low-cut'], 'off');
      expect(st.tx[0]!.voiceTone, 'standard');
      expect(st.tx[1]!.voiceTone, 'standard');
    });

    test('decodes negative gain dial as signed int8', () {
      final st = model.decode(fresh(), _sample2TxV2NegativeGain())!;
      expect(st.gainDial, -12);
    });

    test('decodes voice tone independently per TX', () {
      final st = model.decode(fresh(), _sample2TxV2DistinctTones())!;
      expect(st.tx[0]!.voiceTone, 'rich');
      expect(st.tx[1]!.voiceTone, 'bright');
    });

    test('decodes charging independently per TX', () {
      final st = model.decode(fresh(), _sample2TxV2Tx2Charging())!;
      expect(st.tx[0]!.charging, isFalse);
      expect(st.tx[1]!.charging, isTrue);
    });

    test('decodes 3-bit battery gauge independently per TX', () {
      var st = model.decode(fresh(), _sample2TxV2Tx2Battery(0x39))!;
      expect(st.tx[0]!.battery, 1);
      expect(st.tx[1]!.battery, 6);

      st = model.decode(fresh(), _sample2TxV2Tx2Battery(0x31))!;
      expect(st.tx[1]!.battery, 4);

      st = model.decode(fresh(), _sample2TxV2Tx2Battery(0x3d))!;
      expect(st.tx[1]!.battery, 7);

      st = model.decode(fresh(), _sample2TxV2Tx2Battery(0x21))!;
      expect(st.tx[1]!.battery, 0);
    });

    test('decodes v2 identity pushes (RX only, RX+1TX, RX+2TX, Mic Mini 2)', () {
      final rxOnly = model.decode(fresh(), _sampleIdentityRxOnly())!;
      expect(rxOnly.rx!.serial, 'DDDDDDDDDDDDDD');
      expect(rxOnly.rx!.firmware.toString(), '02.03.17.00');

      final rxTx = model.decode(fresh(), _sampleIdentityRxAndTx())!;
      expect(rxTx.tx[0]!.serial, 'EEEEEEEEEEEEEE');
      expect(rxTx.tx[0]!.firmware.toString(), '02.03.17.00');
      expect(rxTx.tx[0]!.productName, 'DJI Mic Mini');

      final rxTwoTx = model.decode(fresh(), _sampleIdentityRxAndTwoTx())!;
      expect(rxTwoTx.tx[0]!.serial, 'EEEEEEEEEEEEEE');
      expect(rxTwoTx.tx[1]!.serial, 'FFFFFFFFFFFFFF');
      expect(rxTwoTx.tx[1]!.productName, 'DJI Mic Mini');

      final v2Model = model.decode(fresh(), _sampleIdentityRxAndTxV2Model())!;
      expect(v2Model.tx[0]!.productName, 'DJI Mic Mini 2');
    });

    test('takeFrame does not drop 178-byte 2-TX identity push', () {
      final buf = _sampleIdentityRxAndTwoTx().toList();
      final frame = DumlPacket.takeFrame(buf);
      expect(frame, isNotNull);
      expect(frame!.length, 178);
      expect(buf, isEmpty);
    });

    test('decodes v2 level push and preserves identity/level across status pushes', () {
      final afterIdentity = model.decode(fresh(), _sampleIdentityRxAndTx())!;
      final withLevel = model.decode(afterIdentity, _sampleLevel2Tx())!;
      expect(withLevel.tx[0]!.level, 0x30);
      expect(withLevel.tx[1]!.level, 0x30);

      final statusPush = model.decode(withLevel, _sample2TxV2())!;
      expect(statusPush.rx!.serial, 'DDDDDDDDDDDDDD');
      expect(statusPush.rx!.firmware.toString(), '02.03.17.00');
      expect(statusPush.tx[0]!.serial, 'EEEEEEEEEEEEEE');
      expect(statusPush.tx[0]!.level, 0x30);
      expect(statusPush.tx[1]!.level, 0x30);
      expect(statusPush.settings['noise-cancel'], 'strong');
    });

    test('decodes solo TX status pushes by physical unit byte and resolves disconnect immediately', () {
      final tx1 = model.decode(fresh(), _sampleTx1OnlyV2())!;
      expect(tx1.tx[0], isNotNull);
      expect(tx1.tx[1], isNull);

      final tx2 = model.decode(fresh(), _sampleTx2OnlyV2())!;
      expect(tx2.tx[0], isNull);
      expect(tx2.tx[1], isNotNull);

      final afterIdentity = model.decode(fresh(), _sampleIdentityRxAndTwoTx())!;
      final both = model.decode(afterIdentity, _sample2TxV2())!;
      final after = model.decode(both, _sampleTx2OnlyV2())!;
      expect(after.tx[0], isNull);
      expect(after.tx[1]!.serial, 'FFFFFFFFFFFFFF');
    });

    test('shows TX connected from offset 44 bitmask before slot appears', () {
      final st = model.decode(fresh(), _sampleTx2FlaggedNoSlotV2())!;
      expect(st.tx[0], isNull);
      expect(st.tx[1], isNotNull);
      expect(st.tx[1]!.serial, isNull);
      expect(st.tx[1]!.level, isNull);

      final after = model.decode(st, _sampleTx2OnlyV2())!;
      expect(after.tx[1], isNotNull);
    });
  });

  group('MicMiniModel command building', () {
    test('builds v1 and v2 commands from setting slug', () {
      final v1 = model.buildCommand(1, Dialect.v1, 'noise-cancel', 'strong');
      expect(v1, isNotNull);
      expect(v1!.length, DumlPacket.v1CommandLen);
      expect(v1[16], 0x01);
      expect(model.buildCommand(1, Dialect.v1, 'bogus', 'x'), isNull);
      expect(model.buildCommand(1, Dialect.v1, 'stereo', 'maybe'), isNull);

      final v2 = model.buildCommand(1, Dialect.v2, 'noise-cancel', 'strong');
      expect(v2, isNotNull);
      expect(v2!.length, DumlPacket.v2CommandLen);
      expect(v2[19], 0x01);
    });

    test('v2-only setting has no v1 command', () {
      expect(model.buildCommand(1, Dialect.v1, 'noise-cancel-power', 'on'), isNull);
      expect(model.buildCommand(1, Dialect.v2, 'noise-cancel-power', 'on'), isNotNull);
    });

    test('builds voice-tone command targeted at specific TX', () {
      expect(model.buildCommand(1, Dialect.v2, 'voice-tone', 'rich'), isNull);

      final tx1 = model.buildCommand(1, Dialect.v2, 'voice-tone', 'rich', tx: 0)!;
      expect(tx1[12], 0x01);
      expect(tx1[13], 0x00);
      expect(tx1[19], 0x01);

      final tx2 = model.buildCommand(1, Dialect.v2, 'voice-tone', 'bright', tx: 1)!;
      expect(tx2[12], 0x02);
      expect(tx2[19], 0x02);

      expect(model.buildCommand(1, Dialect.v1, 'voice-tone', 'rich', tx: 0), isNull);
    });
  });

  group('Mobile receiver support (upstream PR #4)', () {
    Uint8List sampleMobileIdentity() {
      const hex =
          '557e040000000000005b03030000010000000012000b0302444444444444444444'
          '444444444404000000000637626165386606000000000e444a49204d6963204d69'
          '6e692032010100000012000b030245454545454545454545454545450401000000'
          '0661376330313206010000000e444a49204d6963204d696e692032';
      return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
    }

    Uint8List sampleMobileStatusWithGains({
      int rxGainByte = 0xfa, // -6 dB
      int monitorGainByte = 0xfc, // -4 dB
      int txPlus6 = 0x80,
      int txPlus7 = 0x20,
    }) {
      final rxHex = rxGainByte.toRadixString(16).padLeft(2, '0');
      final monHex = monitorGainByte.toRadixString(16).padLeft(2, '0');
      final p6 = txPlus6.toRadixString(16).padLeft(2, '0');
      final p7 = txPlus7.toRadixString(16).padLeft(2, '0');
      final hex =
          '555604a65a020000005b030346000300000000202831${rxHex}00000000${monHex}0000'
          '0000000000000000000000000000010000001c00000002010000001a$p6$p7'
          '040100780000000000000000000000000000000000000000';
      return DjiCrc16.append(_hexBytes(hex), DjiCrc16.v2Init, DjiCrc16.v2Residue);
    }

    test('mobile receiver identity is distinct from transmitter model', () {
      final standardWithV2Tx = model.decode(fresh(), _sampleIdentityRxAndTxV2Model())!;
      expect(standardWithV2Tx.rx!.productName, 'DJI Mic Mini');
      expect(standardWithV2Tx.tx[0]!.productName, 'DJI Mic Mini 2');
      expect(standardWithV2Tx.isMobileReceiver, isFalse);

      final mobile = model.decode(fresh(), sampleMobileIdentity())!;
      expect(mobile.rx!.productName, 'DJI Mic Mini 2');
      expect(mobile.isMobileReceiver, isTrue);

      // RX productName must survive subsequent status heartbeats.
      final afterStatus = model.decode(mobile, sampleMobileStatusWithGains())!;
      expect(afterStatus.isMobileReceiver, isTrue);
    });

    test('mobile gain commands target receiver and validate ranges', () {
      final rxGain = model.buildCommand(1, Dialect.v2, 'receiver-gain', '-6')!;
      expect(rxGain[12], 0x00);
      expect(rxGain[13], 0x00);
      expect(rxGain[16], 0x39);
      expect(rxGain[17], 0x00);
      expect(rxGain[19], 0xfa);
      expect(model.buildCommand(1, Dialect.v2, 'receiver-gain', '3'), isNull);
      expect(model.buildCommand(1, Dialect.v1, 'receiver-gain', '0'), isNull);

      final monGain = model.buildCommand(1, Dialect.v2, 'monitoring-gain', '-1')!;
      expect(monGain[12], 0x00);
      expect(monGain[13], 0x00);
      expect(monGain[16], 0x26);
      expect(monGain[17], 0x00);
      expect(monGain[19], 0xff);
      expect(model.buildCommand(1, Dialect.v2, 'monitoring-gain', '13'), isNull);
    });

    test('mobile gains decode signed values', () {
      final st = model.decode(fresh(), sampleMobileStatusWithGains(rxGainByte: 0xfa, monitorGainByte: 0xfc))!;
      expect(st.gainDial, -6);
      expect(st.settings['receiver-gain'], '-6');
      expect(st.settings['monitoring-gain'], '-4');
    });

    test('mobile capabilities block ineffective commands', () {
      final standard = model.decode(fresh(), _sampleIdentityRxAndTx())!;
      expect(standard.settingWriteError('noise-cancel'), isNull);
      expect(standard.settingWriteError('auto-off-15m'), isNull);
      expect(standard.settingWriteError('receiver-gain'), isNotNull);
      expect(standard.settingWriteError('monitoring-gain'), isNotNull);

      final mobile = model.decode(fresh(), sampleMobileIdentity())!;
      expect(mobile.settingWriteError('noise-cancel'), isNotNull);
      expect(mobile.settingWriteError('noise-cancel-power'), isNotNull);
      expect(mobile.settingWriteError('noise-cancel-button'), isNotNull);
      expect(mobile.settingWriteError('auto-off-15m'), isNotNull);
      expect(mobile.settingWriteError('camera-power'), isNotNull);
      expect(mobile.settingWriteError('receiver-gain'), isNull);
      expect(mobile.settingWriteError('monitoring-gain'), isNull);
    });

    test('mobile noise status uses connected TX bits', () {
      final mobile = model.decode(fresh(), sampleMobileIdentity())!;

      final off = model.decode(mobile, sampleMobileStatusWithGains(txPlus6: 0x80, txPlus7: 0x20))!;
      expect(off.ncEnabled, isFalse);
      expect(off.settings['noise-cancel-power'], 'off');
      expect(off.settings['noise-cancel'], 'basic');

      final basic = model.decode(mobile, sampleMobileStatusWithGains(txPlus6: 0x80, txPlus7: 0x21))!;
      expect(basic.ncEnabled, isTrue);
      expect(basic.settings['noise-cancel-power'], 'on');
      expect(basic.settings['noise-cancel'], 'basic');

      final strong = model.decode(mobile, sampleMobileStatusWithGains(txPlus6: 0xa0, txPlus7: 0x21))!;
      expect(strong.ncEnabled, isTrue);
      expect(strong.settings['noise-cancel-power'], 'on');
      expect(strong.settings['noise-cancel'], 'strong');
    });
  });
}
