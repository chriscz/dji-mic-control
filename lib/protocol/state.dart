// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

/// Four-component firmware version formatted as `aa.bb.cc.dd`.
class Firmware {
  const Firmware(this.a, this.b, this.c, this.d);

  final int a;
  final int b;
  final int c;
  final int d;

  static String _p(int n) => n.toString().padLeft(2, '0');

  @override
  String toString() => '${_p(a)}.${_p(b)}.${_p(c)}.${_p(d)}';

  @override
  bool operator ==(Object other) =>
      other is Firmware && a == other.a && b == other.b && c == other.c && d == other.d;

  @override
  int get hashCode => Object.hash(a, b, c, d);
}

/// Decoded state of one connected transmitter slot (TX1 or TX2).
class TxInfo {
  const TxInfo({
    this.level,
    this.serial,
    this.firmware,
    this.productName,
    this.voiceTone,
    this.charging,
    this.battery,
  });

  final int? level;
  final String? serial;
  final Firmware? firmware;
  final String? productName;
  final String? voiceTone;
  final bool? charging;

  /// Battery gauge: 1 (full) through 7 (critical before shutoff).
  final int? battery;

  TxInfo copyWith({
    int? level,
    String? serial,
    Firmware? firmware,
    String? productName,
    String? voiceTone,
    bool? charging,
    int? battery,
  }) {
    return TxInfo(
      level: level ?? this.level,
      serial: serial ?? this.serial,
      firmware: firmware ?? this.firmware,
      productName: productName ?? this.productName,
      voiceTone: voiceTone ?? this.voiceTone,
      charging: charging ?? this.charging,
      battery: battery ?? this.battery,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TxInfo &&
      level == other.level &&
      serial == other.serial &&
      firmware == other.firmware &&
      productName == other.productName &&
      voiceTone == other.voiceTone &&
      charging == other.charging &&
      battery == other.battery;

  @override
  int get hashCode => Object.hash(level, serial, firmware, productName, voiceTone, charging, battery);
}

/// Decoded state of the USB-C receiver.
class RxInfo {
  const RxInfo({this.productName, this.serial, this.firmware});

  final String? productName;
  final String? serial;
  final Firmware? firmware;

  RxInfo copyWith({String? productName, String? serial, Firmware? firmware}) {
    return RxInfo(
      productName: productName ?? this.productName,
      serial: serial ?? this.serial,
      firmware: firmware ?? this.firmware,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RxInfo &&
      productName == other.productName &&
      serial == other.serial &&
      firmware == other.firmware;

  @override
  int get hashCode => Object.hash(productName, serial, firmware);
}

/// Model-agnostic snapshot of a connected microphone's telemetry and settings.
class DeviceStatus {
  DeviceStatus({
    required this.modelId,
    required this.connected,
    required this.ncEnabled,
    required List<TxInfo?> tx,
    this.rx,
    required Map<String, String> settings,
    this.protocolVersion,
    this.gainDial,
  })  : assert(tx.length == 2),
        tx = List<TxInfo?>.unmodifiable(tx),
        settings = Map<String, String>.unmodifiable(settings);

  factory DeviceStatus.disconnected(String modelId) {
    return DeviceStatus(
      modelId: modelId,
      connected: false,
      ncEnabled: false,
      tx: const <TxInfo?>[null, null],
      settings: const <String, String>{},
    );
  }

  final String modelId;
  final bool connected;
  final bool ncEnabled;
  final List<TxInfo?> tx;
  final RxInfo? rx;
  final Map<String, String> settings;
  final int? protocolVersion;
  final int? gainDial;

  int get txCount => tx.where((t) => t != null).length;

  /// The DJI Mic Series Mobile Receiver shares VID/PID 2ca3:4011 and identifies
  /// itself in RX tag 0x06 as "DJI Mic Mini 2" or "DJI Mic Series Mobile Receiver".
  bool get isMobileReceiver {
    final name = rx?.productName;
    return name == 'DJI Mic Mini 2' || name == 'DJI Mic Series Mobile Receiver';
  }

  /// Capability check shared by controller and transport before sending writes.
  String? settingWriteError(String settingId) {
    if (isMobileReceiver) {
      if (settingId == 'noise-cancel' ||
          settingId == 'noise-cancel-power' ||
          settingId == 'noise-cancel-button') {
        return 'Use the O/L/H switch on the mobile receiver to change noise cancellation.';
      }
      if (settingId == 'auto-off-15m' || settingId == 'camera-power') {
        return 'This setting is not available on the USB-powered mobile receiver.';
      }
    } else if (settingId == 'receiver-gain' || settingId == 'monitoring-gain') {
      return 'This control requires an identified mobile receiver.';
    }
    return null;
  }

  DeviceStatus copyWith({
    String? modelId,
    bool? connected,
    bool? ncEnabled,
    List<TxInfo?>? tx,
    RxInfo? rx,
    Map<String, String>? settings,
    int? protocolVersion,
    int? gainDial,
  }) {
    return DeviceStatus(
      modelId: modelId ?? this.modelId,
      connected: connected ?? this.connected,
      ncEnabled: ncEnabled ?? this.ncEnabled,
      tx: tx ?? this.tx,
      rx: rx ?? this.rx,
      settings: settings ?? this.settings,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      gainDial: gainDial ?? this.gainDial,
    );
  }
}
