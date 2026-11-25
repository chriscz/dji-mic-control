// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:convert';
import 'dart:typed_data';

import 'device_model.dart';
import 'packet.dart';
import 'settings.dart';
import 'state.dart';

/// DJI Mic Mini (USB-C receiver + up to two transmitters, v1 and v2 firmware,
/// including DJI Mic Mini 2 transmitters paired on v2 firmware).
class MicMiniModel extends DeviceModel {
  const MicMiniModel();

  static const String modelId = 'dji-mic-mini';

  static const V2Target _targetRx = FixedTarget(0x0000);
  static const V2Target _targetTxAll = FixedTarget(0xffff);
  static const V2Target _targetTxOne = PerTxTarget();

  static const List<SettingOption> _offOn = <SettingOption>[
    SettingOption(value: 'off', label: 'Off', wire: 0x00),
    SettingOption(value: 'on', label: 'On', wire: 0x01),
  ];

  static const List<SettingOption> _ncOpts = <SettingOption>[
    SettingOption(value: 'basic', label: 'Basic', wire: 0x00),
    SettingOption(value: 'strong', label: 'Strong', wire: 0x01),
  ];

  static const List<SettingOption> _audioChannelOpts = <SettingOption>[
    SettingOption(value: 'mono', label: 'Mono', wire: 0x00),
    SettingOption(value: 'stereo', label: 'Stereo', wire: 0x02),
  ];

  static const List<SettingOption> _ledOpts = <SettingOption>[
    SettingOption(value: 'off', label: 'Off', wire: 0x02),
    SettingOption(value: 'on', label: 'On', wire: 0x00),
  ];

  static const List<SettingOption> _voiceToneOpts = <SettingOption>[
    SettingOption(value: 'standard', label: 'Standard', wire: 0x00),
    SettingOption(value: 'rich', label: 'Rich', wire: 0x01),
    SettingOption(value: 'bright', label: 'Bright', wire: 0x02),
  ];

  static const List<SettingOption> _rxGainOpts = <SettingOption>[
    SettingOption(value: '-12', label: '-12 dB', wire: 0xf4),
    SettingOption(value: '-6', label: '-6 dB', wire: 0xfa),
    SettingOption(value: '0', label: '0 dB', wire: 0x00),
    SettingOption(value: '6', label: '+6 dB', wire: 0x06),
    SettingOption(value: '12', label: '+12 dB', wire: 0x0c),
  ];

  static const List<SettingOption> _monitorGainOpts = <SettingOption>[
    SettingOption(value: '-12', label: '-12 dB', wire: 0xf4),
    SettingOption(value: '-11', label: '-11 dB', wire: 0xf5),
    SettingOption(value: '-10', label: '-10 dB', wire: 0xf6),
    SettingOption(value: '-9', label: '-9 dB', wire: 0xf7),
    SettingOption(value: '-8', label: '-8 dB', wire: 0xf8),
    SettingOption(value: '-7', label: '-7 dB', wire: 0xf9),
    SettingOption(value: '-6', label: '-6 dB', wire: 0xfa),
    SettingOption(value: '-5', label: '-5 dB', wire: 0xfb),
    SettingOption(value: '-4', label: '-4 dB', wire: 0xfc),
    SettingOption(value: '-3', label: '-3 dB', wire: 0xfd),
    SettingOption(value: '-2', label: '-2 dB', wire: 0xfe),
    SettingOption(value: '-1', label: '-1 dB', wire: 0xff),
    SettingOption(value: '0', label: '0 dB', wire: 0x00),
    SettingOption(value: '1', label: '+1 dB', wire: 0x01),
    SettingOption(value: '2', label: '+2 dB', wire: 0x02),
    SettingOption(value: '3', label: '+3 dB', wire: 0x03),
    SettingOption(value: '4', label: '+4 dB', wire: 0x04),
    SettingOption(value: '5', label: '+5 dB', wire: 0x05),
    SettingOption(value: '6', label: '+6 dB', wire: 0x06),
    SettingOption(value: '7', label: '+7 dB', wire: 0x07),
    SettingOption(value: '8', label: '+8 dB', wire: 0x08),
    SettingOption(value: '9', label: '+9 dB', wire: 0x09),
    SettingOption(value: '10', label: '+10 dB', wire: 0x0a),
    SettingOption(value: '11', label: '+11 dB', wire: 0x0b),
    SettingOption(value: '12', label: '+12 dB', wire: 0x0c),
  ];

  static const String groupAudio = 'Audio';
  static const String groupPower = 'Power & Startup';
  static const String groupDevice = 'Device';

  static const List<SettingDefinition> allSettings = <SettingDefinition>[
    SettingDefinition(
      id: 'noise-cancel',
      label: 'Noise Cancel',
      group: groupAudio,
      kind: SettingKind.segmented,
      v1Command: 0x031d,
      v2Command: 0x0037,
      v2Target: _targetTxAll,
      options: _ncOpts,
    ),
    SettingDefinition(
      id: 'noise-cancel-power',
      label: 'Noise Cancelling',
      group: groupAudio,
      kind: SettingKind.toggle,
      v1Command: null,
      v2Command: 0x0038,
      v2Target: _targetTxAll,
      options: _offOn,
    ),
    SettingDefinition(
      id: 'noise-cancel-button',
      label: 'Toggle via TX power button',
      group: groupAudio,
      kind: SettingKind.toggle,
      v1Command: null,
      v2Command: 0x000f,
      v2Target: _targetTxAll,
      options: _offOn,
    ),
    SettingDefinition(
      id: 'low-cut',
      label: 'Low Cut',
      group: groupAudio,
      kind: SettingKind.toggle,
      v1Command: 0x0303,
      v2Command: 0x0003,
      v2Target: _targetTxAll,
      options: _offOn,
    ),
    SettingDefinition(
      id: 'stereo',
      label: 'Audio Channels',
      group: groupAudio,
      kind: SettingKind.segmented,
      v1Command: 0x0008,
      v2Command: 0x0008,
      v2Target: _targetRx,
      options: _audioChannelOpts,
      exclusiveWith: <String>['safety-track'],
    ),
    SettingDefinition(
      id: 'safety-track',
      label: 'Safety Track',
      group: groupAudio,
      kind: SettingKind.toggle,
      v1Command: 0x0021,
      v2Command: 0x0021,
      v2Target: _targetRx,
      options: _offOn,
      exclusiveWith: <String>['stereo'],
    ),
    SettingDefinition(
      id: 'clip-limiter',
      label: 'Clipping Control',
      group: groupAudio,
      kind: SettingKind.toggle,
      v1Command: 0x001e,
      v2Command: 0x001e,
      v2Target: _targetRx,
      options: _offOn,
    ),
    SettingDefinition(
      id: 'auto-off-15m',
      label: 'Auto Off RX (15 min)',
      group: groupPower,
      kind: SettingKind.toggle,
      v1Command: 0x0010,
      v2Command: 0x0010,
      v2Target: _targetRx,
      options: _offOn,
    ),
    SettingDefinition(
      id: 'tx-auto-off-15m',
      label: 'Auto Off TX (15 min)',
      group: groupPower,
      kind: SettingKind.toggle,
      v1Command: null,
      v2Command: 0x0010,
      v2Target: _targetTxAll,
      options: _offOn,
    ),
    SettingDefinition(
      id: 'camera-power',
      label: 'RX On/Off follows Camera',
      group: groupPower,
      kind: SettingKind.toggle,
      v1Command: 0x0020,
      v2Command: 0x0020,
      v2Target: _targetRx,
      options: _offOn,
    ),
    SettingDefinition(
      id: 'plug-free',
      label: 'Plug-Free Ext. Speaker',
      group: groupDevice,
      kind: SettingKind.toggle,
      v1Command: 0x0023,
      v2Command: 0x0023,
      v2Target: _targetRx,
      options: _offOn,
      note: 'Changing this reboots the receiver.',
    ),
    SettingDefinition(
      id: 'mic-leds',
      label: 'Mic LEDs',
      group: groupDevice,
      kind: SettingKind.toggle,
      v1Command: 0x030a,
      v2Command: 0x000a,
      v2Target: _targetTxAll,
      options: _ledOpts,
    ),
    SettingDefinition(
      id: 'voice-tone',
      label: 'Voice Tone',
      group: groupAudio,
      kind: SettingKind.segmented,
      v1Command: null,
      v2Command: 0x0029,
      v2Target: _targetTxOne,
      options: _voiceToneOpts,
    ),
    SettingDefinition(
      id: 'receiver-gain',
      label: 'Receiver Gain',
      group: groupAudio,
      kind: SettingKind.range,
      v1Command: null,
      v2Command: 0x0039,
      v2Target: _targetRx,
      options: _rxGainOpts,
    ),
    SettingDefinition(
      id: 'monitoring-gain',
      label: 'Monitoring Gain',
      group: groupAudio,
      kind: SettingKind.range,
      v1Command: null,
      v2Command: 0x0026,
      v2Target: _targetRx,
      options: _monitorGainOpts,
    ),
  ];

  static const int _headerLen = 14;
  static const int _presentTxLen = 23;
  static const int _absentTxLen = 9;
  static const int _rxLen = 22;

  static const int _v2HeaderLen = 52;
  static const int _v2TxSlotLen = 32;
  static const int _v2TxConnectedOffset = 44;

  static const int _recordsStart = 14;
  static const int _recordHeaderLen = 6;

  @override
  String get id => modelId;

  @override
  String get name => 'DJI Mic Mini';

  @override
  String get pictogramKey => 'mic-mini';

  @override
  List<UsbId> get usbIds => const <UsbId>[UsbId(0x2ca3, 0x4011)];

  @override
  int get interfaceNumber => 6;

  @override
  int get bulkInEndpoint => 0x86;

  @override
  int get bulkOutEndpoint => 0x06;

  @override
  List<SettingDefinition> get settings => allSettings;

  @override
  DeviceStatus? decode(DeviceStatus previous, Uint8List frame) {
    final dialect = DumlPacket.heartbeatDialect(frame);
    if (dialect == null) return null;
    final decoded = switch (dialect) {
      Dialect.v1 => _decodeV1(frame),
      Dialect.v2 => _decodeV2(previous, frame),
    };
    if (decoded == null) return null;
    return decoded.copyWith(protocolVersion: dialect.versionNumber);
  }

  static String _readAsciiField(Uint8List bytes, int start, int end) {
    var actualEnd = end;
    for (var i = start; i < end; i++) {
      if (bytes[i] == 0) {
        actualEnd = i;
        break;
      }
    }
    return utf8.decode(bytes.sublist(start, actualEnd), allowMalformed: true).trim();
  }

  static _V1Slot? _parseV1Slot(Uint8List f, int off) {
    if (off + 1 >= f.length) return null;
    final flags = f[off + 1];
    if ((flags & 0x20) != 0) {
      final end = off + _presentTxLen;
      if (f.length < end) return null;
      final state = f[off];
      final level = f[off + 2];
      final ledOff = (f[off + 3] & 0x80) != 0;
      final firmware = Firmware(f[off + 4], f[off + 5], f[off + 6], f[off + 7]);
      final serial = _readAsciiField(f, off + 9, off + 23);
      return _V1Slot(
        tx: TxInfo(level: level, serial: serial, firmware: firmware),
        state: state,
        flags: flags,
        ledOff: ledOff,
        len: _presentTxLen,
      );
    } else {
      final end = off + _absentTxLen;
      if (f.length < end) return null;
      return _V1Slot(
        tx: null,
        state: f[off],
        flags: flags,
        ledOff: null,
        len: _absentTxLen,
      );
    }
  }

  static DeviceStatus? _decodeV1(Uint8List f) {
    if (f.length < _headerLen + _rxLen) return null;
    final slotA = _parseV1Slot(f, _headerLen);
    if (slotA == null) return null;
    final slotB = _parseV1Slot(f, _headerLen + slotA.len);
    if (slotB == null) return null;

    final rxOff = _headerLen + slotA.len + slotB.len;
    if (f.length < rxOff + _rxLen) return null;

    final state = slotA.tx != null ? slotA.state : slotB.state;
    final flags = slotA.tx != null ? slotA.flags : slotB.flags;
    final ledOff = slotA.ledOff ?? slotB.ledOff;

    final rxFlags0 = f[rxOff];
    final rxFlags1 = f[rxOff + 1];
    final rx = RxInfo(
      firmware: Firmware(f[rxOff + 2], f[rxOff + 3], f[rxOff + 4], f[rxOff + 5]),
      serial: _readAsciiField(f, rxOff + 7, rxOff + 21),
    );
    final plugFreeOn = f[rxOff + 21] == 0x01;
    final ncEnabled = (flags & 0x01) != 0;

    final map = <String, String>{
      'noise-cancel': (state & 0x20) != 0 ? 'strong' : 'basic',
      'noise-cancel-power': _onOff(ncEnabled),
      'low-cut': _onOff((state & 0x04) != 0),
      'stereo': (rxFlags0 & 0x08) != 0 ? 'stereo' : 'mono',
      'camera-power': _onOff((rxFlags0 & 0x01) != 0),
      'auto-off-15m': _onOff((rxFlags0 & 0x02) != 0),
      'safety-track': _onOff((rxFlags1 & 0x80) != 0),
      'clip-limiter': _onOff((rxFlags1 & 0x20) != 0),
      'plug-free': _onOff(plugFreeOn),
    };
    if (ledOff != null) {
      map['mic-leds'] = ledOff ? 'off' : 'on';
    }

    return DeviceStatus(
      modelId: modelId,
      connected: true,
      ncEnabled: ncEnabled,
      tx: <TxInfo?>[slotA.tx, slotB.tx],
      rx: rx,
      settings: map,
    );
  }

  static DeviceStatus? _decodeV2(DeviceStatus previous, Uint8List f) {
    return _decodeV2Status(previous, f) ?? _decodeV2Records(previous, f);
  }

  static DeviceStatus? _decodeV2Status(DeviceStatus previous, Uint8List f) {
    if (f.length < _v2HeaderLen + 2) return null;
    final remainder = f.length - (_v2HeaderLen + 2);
    if (remainder % _v2TxSlotLen != 0) return null;
    final txCount = (remainder ~/ _v2TxSlotLen).clamp(0, 2);

    final flags1 = f[20];
    final flags2 = f[21];
    final gainDial = f[22].toSigned(8);
    final flags3 = f[48];

    final txFlags = txCount > 0 ? f[_v2HeaderLen + 6] : null;
    final lowCutFlags = txCount > 0 ? f[_v2HeaderLen + 9] : null;

    final connectedMask = f[_v2TxConnectedOffset];
    final txSlots = List<TxInfo?>.generate(2, (i) {
      if ((connectedMask & (1 << i)) == 0) return null;
      return previous.tx[i] ?? const TxInfo();
    });

    for (var slotPos = 0; slotPos < txCount; slotPos++) {
      final slotOff = _v2HeaderLen + _v2TxSlotLen * slotPos;
      final unit = f[slotOff + 1];
      if (unit != 1 && unit != 2) continue;
      final idx = unit - 1;
      final existing = txSlots[idx];
      if (existing == null) continue;

      final toneByte = f[slotOff + 9];
      final voiceTone = (toneByte & 0x80) != 0
          ? 'bright'
          : (toneByte & 0x40) != 0
              ? 'rich'
              : 'standard';

      final battByte = f[slotOff + 7];
      final charging = (battByte & 0x02) != 0;
      final battery = (battByte >> 2) & 0x07;

      txSlots[idx] = existing.copyWith(
        voiceTone: voiceTone,
        charging: charging,
        battery: battery,
      );
    }

    final rx = previous.rx ?? const RxInfo();
    final mobile = rx.productName == 'DJI Mic Mini 2' || rx.productName == 'DJI Mic Series Mobile Receiver';

    // On the mobile receiver the physical O/L/H switch is reflected in the
    // first connected TX slot's +7 bit 0x01 (enabled) and +6 bit 0x20 (strong).
    (bool enabled, bool strong)? mobileNc;
    if (mobile) {
      for (var slotPos = 0; slotPos < txCount; slotPos++) {
        final slotOff = _v2HeaderLen + _v2TxSlotLen * slotPos;
        final unit = f[slotOff + 1];
        if ((unit == 1 || unit == 2) && (connectedMask & (1 << (unit - 1))) != 0) {
          mobileNc = ((f[slotOff + 7] & 0x01) != 0, (f[slotOff + 6] & 0x20) != 0);
          break;
        }
      }
    }

    final monitoringGain = f[27].toSigned(8);
    final map = <String, String>{
      'receiver-gain': gainDial.toString(),
      'monitoring-gain': monitoringGain.toString(),
      'camera-power': _onOff((flags1 & 0x80) != 0),
      'auto-off-15m': _onOff((flags2 & 0x01) != 0),
      'stereo': (flags2 & 0x04) != 0 ? 'stereo' : 'mono',
      'plug-free': _onOff((flags3 & 0x02) != 0),
      'clip-limiter': _onOff((flags3 & 0x10) != 0),
      'safety-track': _onOff((flags3 & 0x40) != 0),
    };
    if (mobile) {
      if (mobileNc != null) {
        map['noise-cancel'] = mobileNc.$2 ? 'strong' : 'basic';
        map['noise-cancel-power'] = _onOff(mobileNc.$1);
      }
    } else {
      map['noise-cancel'] = (flags1 & 0x08) != 0 ? 'strong' : 'basic';
      map['noise-cancel-power'] = _onOff((flags1 & 0x20) != 0);
    }
    if (txFlags != null) {
      map['mic-leds'] = (txFlags & 0x02) != 0 ? 'off' : 'on';
      map['tx-auto-off-15m'] = _onOff((txFlags & 0x10) != 0);
      map['noise-cancel-button'] = _onOff((txFlags & 0x80) != 0);
    }
    if (lowCutFlags != null) {
      map['low-cut'] = _onOff((lowCutFlags & 0x20) != 0);
    }

    return DeviceStatus(
      modelId: modelId,
      connected: true,
      ncEnabled: mobile ? (mobileNc?.$1 ?? false) : (flags1 & 0x20) != 0,
      tx: txSlots,
      rx: rx,
      settings: map,
      gainDial: gainDial,
    );
  }

  static DeviceStatus? _decodeV2Records(DeviceStatus previous, Uint8List f) {
    if (f.length < _recordsStart + 2) return null;
    final end = f.length - 2;
    final txSlots = List<TxInfo?>.from(previous.tx);
    var rx = previous.rx;
    var matched = false;
    var i = _recordsStart;

    while (i + _recordHeaderLen <= end) {
      final tag = f[i];
      final index = f[i + 1];
      final length = f[i + 5];
      final dataStart = i + _recordHeaderLen;
      final dataEnd = dataStart + length;
      if (dataEnd > end) break;

      if (tag == 0x01 && length > 4) {
        final fw = Firmware(
          f[dataStart + 3],
          f[dataStart + 2],
          f[dataStart + 1],
          f[dataStart],
        );
        final serial = _readAsciiField(f, dataStart + 4, dataEnd);
        if (index == 0) {
          rx = (rx ?? const RxInfo()).copyWith(serial: serial, firmware: fw);
        } else if (index == 1 || index == 2) {
          final slotIdx = index - 1;
          txSlots[slotIdx] = (txSlots[slotIdx] ?? const TxInfo()).copyWith(
            serial: serial,
            firmware: fw,
          );
        }
        matched = true;
      } else if (tag == 0x05 && length == 1 && (index == 1 || index == 2)) {
        final slotIdx = index - 1;
        txSlots[slotIdx] = (txSlots[slotIdx] ?? const TxInfo()).copyWith(
          level: f[dataStart],
        );
        matched = true;
      } else if (tag == 0x06 && index == 0) {
        rx = (rx ?? const RxInfo()).copyWith(
          productName: _readAsciiField(f, dataStart, dataEnd),
        );
        matched = true;
      } else if (tag == 0x06 && (index == 1 || index == 2)) {
        final slotIdx = index - 1;
        txSlots[slotIdx] = (txSlots[slotIdx] ?? const TxInfo()).copyWith(
          productName: _readAsciiField(f, dataStart, dataEnd),
        );
        matched = true;
      }

      i = dataEnd;
    }

    if (!matched) return null;
    return previous.copyWith(tx: txSlots, rx: rx);
  }

  static String _onOff(bool v) => v ? 'on' : 'off';
}

class _V1Slot {
  const _V1Slot({
    required this.tx,
    required this.state,
    required this.flags,
    required this.ledOff,
    required this.len,
  });

  final TxInfo? tx;
  final int state;
  final int flags;
  final bool? ledOff;
  final int len;
}
