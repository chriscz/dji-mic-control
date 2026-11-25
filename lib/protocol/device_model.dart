// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:typed_data';

import 'mic_mini_model.dart';
import 'packet.dart';
import 'settings.dart';
import 'state.dart';

/// USB vendor/product identifier pair.
class UsbId {
  const UsbId(this.vendorId, this.productId);

  final int vendorId;
  final int productId;

  String get vidHex => vendorId.toRadixString(16).padLeft(4, '0');
  String get pidHex => productId.toRadixString(16).padLeft(4, '0');

  @override
  bool operator ==(Object other) => other is UsbId && vendorId == other.vendorId && productId == other.productId;

  @override
  int get hashCode => Object.hash(vendorId, productId);
}

/// Extension point describing a supported DJI microphone product.
abstract class DeviceModel {
  const DeviceModel();

  String get id;
  String get name;
  String get pictogramKey;
  List<UsbId> get usbIds;
  int get interfaceNumber;
  int get bulkInEndpoint;
  int get bulkOutEndpoint;
  List<SettingDefinition> get settings;

  SettingDefinition? settingById(String settingId) {
    for (final s in settings) {
      if (s.id == settingId) return s;
    }
    return null;
  }

  /// Decode an incoming frame, merging with [previous] when required.
  DeviceStatus? decode(DeviceStatus previous, Uint8List frame);

  /// Build an outgoing setting command packet for [dialect], or null if invalid
  /// or unsupported on [dialect].
  Uint8List? buildCommand(
    int seq,
    Dialect dialect,
    String settingId,
    String value, {
    int? tx,
  }) {
    final setting = settingById(settingId);
    if (setting == null) return null;
    final opt = setting.optionByValue(value);
    if (opt == null) return null;

    switch (dialect) {
      case Dialect.v1:
        final cmd = setting.v1Command;
        if (cmd == null) return null;
        return DumlPacket.buildV1Command(seq, cmd, opt.wire);
      case Dialect.v2:
        final int target;
        switch (setting.v2Target) {
          case FixedTarget(:final address):
            target = address;
          case PerTxTarget():
            if (tx == null || tx < 0 || tx > 1) return null;
            target = tx + 1;
        }
        return DumlPacket.buildV2Command(seq, target, setting.v2Command, opt.wire);
    }
  }
}

/// Registry of supported models.
class DeviceModelRegistry {
  DeviceModelRegistry._();

  static const List<DeviceModel> models = <DeviceModel>[
    MicMiniModel(),
  ];

  static DeviceModel? matchUsb(int vendorId, int productId) {
    for (final model in models) {
      for (final usb in model.usbIds) {
        if (usb.vendorId == vendorId && usb.productId == productId) {
          return model;
        }
      }
    }
    return null;
  }

  static DeviceModel? byId(String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}
