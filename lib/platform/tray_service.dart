// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:async';
import 'dart:io';

import '../log/app_logger.dart';
import 'dbus/dbus_wire.dart';

/// Current tray state reflected in the desktop system tray.
class TrayState {
  const TrayState({
    required this.anyConnected,
    required this.worstBattery,
    required this.hasMicMini2,
    required this.tooltip,
  });

  final bool anyConnected;

  /// Worst (highest numeric) battery tier across active TX (1=full..7=critical).
  final int? worstBattery;
  final bool hasMicMini2;
  final String tooltip;
}

/// Abstract system tray service (implemented via pure-Dart D-Bus SNI on Linux).
abstract class TrayService {
  bool get isActive;
  Future<bool> start({required void Function() onActivate});
  Future<void> update(TrayState state);
  Future<void> dispose();
}

/// Zero-plugin Linux tray using `org.kde.StatusNotifierItem` over session D-Bus.
///
/// Degrades cleanly to `isActive == false` when no `StatusNotifierWatcher` is
/// running (for example stock GNOME without the AppIndicator extension).
class DbusTrayService implements TrayService {
  DbusTrayService({this.logger});

  final AppLogger? logger;
  DbusSessionClient? _client;
  bool _active = false;
  TrayState _state = const TrayState(
    anyConnected: false,
    worstBattery: null,
    hasMicMini2: false,
    tooltip: 'DJI Mic Control',
  );
  void Function()? _onActivate;

  static const String _itemPath = '/StatusNotifierItem';

  @override
  bool get isActive => _active;

  @override
  Future<bool> start({required void Function() onActivate}) async {
    _onActivate = onActivate;
    if (!Platform.isLinux) return false;
    final client = await DbusSessionClient.tryConnect();
    if (client == null) return false;

    final hasWatcher = await client.nameHasOwner('org.kde.StatusNotifierWatcher');
    if (!hasWatcher) {
      await client.close();
      return false;
    }

    _client = client;
    client.onMethodCall = _handleMethodCall;

    final serviceName = 'org.kde.StatusNotifierItem-$pid-1';
    await client.call(
      destination: 'org.freedesktop.DBus',
      path: '/org/freedesktop/DBus',
      interfaceName: 'org.freedesktop.DBus',
      member: 'RequestName',
      signature: 'su',
      body: DbusWriter()
        ..writeString(serviceName)
        ..writeUint32(0),
    );

    final reg = await client.call(
      destination: 'org.kde.StatusNotifierWatcher',
      path: '/StatusNotifierWatcher',
      interfaceName: 'org.kde.StatusNotifierWatcher',
      member: 'RegisterStatusNotifierItem',
      signature: 's',
      body: DbusWriter()..writeString(serviceName),
    );
    _active = reg != null && reg.type == DbusMessageType.methodReturn;
    if (!_active) {
      await client.close();
      _client = null;
      return false;
    }
    logger?.info('Registered D-Bus StatusNotifierItem ($serviceName)');
    return true;
  }

  void _handleMethodCall(DbusMessage msg) {
    final client = _client;
    if (client == null) return;

    if (msg.path == _itemPath && msg.interfaceName == 'org.kde.StatusNotifierItem') {
      if (msg.member == 'Activate' || msg.member == 'SecondaryActivate') {
        _onActivate?.call();
        client.sendRaw(
          DbusMessage.methodReturn(
            serial: client.nextSerial(),
            replySerial: msg.serial,
            destination: msg.sender,
          ),
        );
        return;
      }
    }

    if (msg.path == _itemPath && msg.interfaceName == 'org.freedesktop.DBus.Properties') {
      if (msg.member == 'Get' && msg.body.isNotEmpty) {
        final reader = DbusReader(msg.body);
        reader.readString(); // interface
        final prop = reader.readString();
        final body = _encodePropertyVariant(prop);
        if (body != null) {
          client.sendRaw(
            DbusMessage.methodReturn(
              serial: client.nextSerial(),
              replySerial: msg.serial,
              destination: msg.sender,
              signature: 'v',
              body: body,
            ),
          );
          return;
        }
      }
    }

    client.sendRaw(
      DbusMessage.error(
        serial: client.nextSerial(),
        replySerial: msg.serial,
        destination: msg.sender,
        errorName: 'org.freedesktop.DBus.Error.UnknownMethod',
        message: 'Unhandled method ${msg.interfaceName}.${msg.member}',
      ),
    );
  }

  DbusWriter? _encodePropertyVariant(String prop) {
    final w = DbusWriter();
    switch (prop) {
      case 'Category':
        w.writeVariant('s', (v) => v.writeString('Hardware'));
      case 'Id':
        w.writeVariant('s', (v) => v.writeString('dji-mic-control'));
      case 'Title':
        w.writeVariant('s', (v) => v.writeString(_state.tooltip));
      case 'Status':
        final status = (_state.worstBattery != null && _state.worstBattery! >= 6) ? 'NeedsAttention' : 'Active';
        w.writeVariant('s', (v) => v.writeString(status));
      case 'IconName':
        final icon = !_state.anyConnected
            ? 'audio-input-microphone-muted'
            : (_state.worstBattery != null && _state.worstBattery! >= 6)
                ? 'battery-caution'
                : 'audio-input-microphone';
        w.writeVariant('s', (v) => v.writeString(icon));
      case 'ItemIsMenu':
        w.writeVariant('b', (v) => v.writeBool(false));
      default:
        return null;
    }
    return w;
  }

  @override
  Future<void> update(TrayState state) async {
    _state = state;
    final client = _client;
    if (!_active || client == null) return;
    // Emit NewIcon + NewStatus signals so tray hosts refresh immediately.
    client.sendRaw(
      DbusMessage(
        type: DbusMessageType.signal,
        serial: client.nextSerial(),
        path: _itemPath,
        interfaceName: 'org.kde.StatusNotifierItem',
        member: 'NewIcon',
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _active = false;
    final client = _client;
    _client = null;
    await client?.close();
  }
}

class NoopTrayService implements TrayService {
  NoopTrayService({this.available = false});

  final bool available;
  TrayState? lastState;

  @override
  bool get isActive => available;

  @override
  Future<bool> start({required void Function() onActivate}) async => available;

  @override
  Future<void> update(TrayState state) async {
    lastState = state;
  }

  @override
  Future<void> dispose() async {}
}
