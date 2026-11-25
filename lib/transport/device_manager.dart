// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:async';
import 'dart:typed_data';

import '../log/app_logger.dart';
import '../protocol/device_model.dart';
import '../protocol/packet.dart';
import '../protocol/settings.dart';
import '../protocol/state.dart';
import 'usb_transport.dart';

/// Thrown when a setting or value is invalid or unsupported on the active dialect.
class UnsupportedSettingException implements Exception {
  const UnsupportedSettingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Result of scanning the USB bus for supported DJI microphones.
class BusProbe {
  const BusProbe({
    this.matchedCount = 0,
    this.inaccessibleCount = 0,
    this.permissionIssue = false,
  });

  final int matchedCount;
  final int inaccessibleCount;
  final bool permissionIssue;
}

/// Sidebar summary for a single tracked microphone receiver.
class DeviceSummary {
  const DeviceSummary({
    required this.id,
    required this.modelId,
    required this.modelName,
    required this.pictogramKey,
    required this.connected,
    this.rxSerial,
    required this.tx,
  });

  final String id;
  final String modelId;
  final String modelName;
  final String pictogramKey;
  final bool connected;
  final String? rxSerial;
  final List<TxInfo?> tx;
}

/// Atomic UI snapshot of all tracked devices and the currently selected device.
class ManagerSnapshot {
  const ManagerSnapshot({
    required this.probe,
    required this.devices,
    this.selectedId,
    this.status,
    this.settings = const <SettingDefinition>[],
    this.backendName = '',
  });

  final BusProbe probe;
  final List<DeviceSummary> devices;
  final String? selectedId;
  final DeviceStatus? status;
  final List<SettingDefinition> settings;
  final String backendName;
}

class _TrackedDevice {
  _TrackedDevice({
    required this.info,
    required this.model,
    required this.handle,
  }) : status = DeviceStatus.disconnected(model.id);

  final UsbDeviceInfo info;
  final DeviceModel model;
  final UsbDeviceHandle handle;
  final List<int> rxBuffer = <int>[];
  StreamSubscription<Uint8List>? subscription;
  DeviceStatus status;
  Dialect? dialect;
  DateTime? lastFrameAt;
  int sequence = 1;
  bool alive = true;
}

/// Manages USB discovery, per-device DUML framing, liveness tracking, and writes.
class DeviceManager {
  DeviceManager({
    required this.transport,
    DateTime Function()? now,
    this.logger,
  }) : _now = now ?? DateTime.now;

  /// Matches upstream LIVE_WINDOW_MS = 1500 ms to avoid flicker on bursty USB ticks.
  static const Duration liveWindow = Duration(milliseconds: 1500);

  final UsbTransport transport;
  final DateTime Function() _now;
  final AppLogger? logger;

  final Map<String, _TrackedDevice> _devices = <String, _TrackedDevice>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  BusProbe _probe = const BusProbe();
  bool _disposed = false;
  bool _refreshing = false;

  /// Emits whenever device list, telemetry, or probe state changes.
  Stream<void> get changes => _changes.stream;

  /// Enumerate the USB bus, prune dead handles, and adopt newly attached devices.
  Future<void> refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      // Remove dead devices first.
      final deadIds = _devices.entries
          .where((e) => !e.value.alive)
          .map((e) => e.key)
          .toList();
      for (final id in deadIds) {
        final removed = _devices.remove(id);
        await removed?.subscription?.cancel();
        await removed?.handle.close();
      }

      List<UsbDeviceInfo> busDevices;
      try {
        busDevices = await transport.listDevices();
      } catch (e) {
        logger?.warn('USB enumeration failed: $e');
        return;
      }

      var matchedCount = 0;
      var inaccessibleCount = 0;
      var permissionIssue = false;
      final seenIds = <String>{};

      for (final info in busDevices) {
        final model = DeviceModelRegistry.matchUsb(info.vendorId, info.productId);
        if (model == null) continue;
        matchedCount++;
        final devId = info.displayId;
        seenIds.add(devId);

        if (_devices.containsKey(devId)) continue;

        try {
          final handle = await transport.open(
            info,
            interfaceNumber: model.interfaceNumber,
            bulkInEndpoint: model.bulkInEndpoint,
            bulkOutEndpoint: model.bulkOutEndpoint,
          );
          final tracked = _TrackedDevice(info: info, model: model, handle: handle);
          _attachStream(devId, tracked);
          _devices[devId] = tracked;
          logger?.info('Opened ${model.name} ($devId) via ${transport.backendName}');
        } on UsbPermissionException catch (e) {
          inaccessibleCount++;
          permissionIssue = true;
          logger?.warn('Permission denied for $devId: ${e.message}');
        } catch (e) {
          inaccessibleCount++;
          logger?.warn('Failed to open $devId: $e');
        }
      }

      // Drop devices that are no longer present on the bus.
      final vanishedIds = _devices.keys.where((id) => !seenIds.contains(id)).toList();
      for (final id in vanishedIds) {
        final removed = _devices.remove(id);
        if (removed != null) {
          removed.alive = false;
          await removed.subscription?.cancel();
          await removed.handle.close();
          logger?.info('Device detached: $id');
        }
      }

      _probe = BusProbe(
        matchedCount: matchedCount,
        inaccessibleCount: inaccessibleCount,
        permissionIssue: permissionIssue,
      );
      _notify();
    } finally {
      _refreshing = false;
    }
  }

  void _attachStream(String devId, _TrackedDevice tracked) {
    tracked.subscription = tracked.handle.bulkInStream.listen(
      (chunk) {
        tracked.rxBuffer.addAll(chunk);
        var updated = false;
        while (true) {
          final frame = DumlPacket.takeFrame(tracked.rxBuffer);
          if (frame == null) break;
          final kind = DumlPacket.frameKind(frame);
          if (kind == FrameKind.ack) {
            continue;
          }
          final dialect = DumlPacket.heartbeatDialect(frame);
          if (dialect != null) {
            tracked.dialect = dialect;
          }
          final decoded = tracked.model.decode(tracked.status, frame);
          if (decoded != null) {
            tracked.status = decoded;
            tracked.lastFrameAt = _now();
            updated = true;
          }
        }
        if (updated) {
          _notify();
        }
      },
      onError: (Object error) {
        logger?.warn('Bulk IN error on $devId: $error');
        tracked.alive = false;
        _notify();
      },
      onDone: () {
        tracked.alive = false;
        _notify();
      },
      cancelOnError: true,
    );
  }

  bool _isLive(_TrackedDevice tracked) {
    if (!tracked.alive) return false;
    final last = tracked.lastFrameAt;
    if (last == null) return false;
    return _now().difference(last) <= liveWindow;
  }

  /// Build an atomic snapshot for UI and tray consumers.
  ManagerSnapshot snapshot(String? selectedId) {
    final summaries = <DeviceSummary>[];
    final sortedIds = _devices.keys.toList()..sort();

    for (final id in sortedIds) {
      final tracked = _devices[id]!;
      if (!tracked.alive) continue;
      final live = _isLive(tracked);
      summaries.add(
        DeviceSummary(
          id: id,
          modelId: tracked.model.id,
          modelName: tracked.model.name,
          pictogramKey: tracked.model.pictogramKey,
          connected: live,
          rxSerial: tracked.status.rx?.serial,
          tx: tracked.status.tx,
        ),
      );
    }

    DeviceStatus? status;
    var settings = const <SettingDefinition>[];
    String? effectiveSelected;
    if (selectedId != null && _devices.containsKey(selectedId)) {
      final tracked = _devices[selectedId]!;
      if (tracked.alive) {
        effectiveSelected = selectedId;
        status = tracked.status.copyWith(connected: _isLive(tracked));
        settings = tracked.model.settings;
      }
    }

    return ManagerSnapshot(
      probe: _probe,
      devices: summaries,
      selectedId: effectiveSelected,
      status: status,
      settings: settings,
      backendName: transport.backendName,
    );
  }

  /// Send a shared setting command to [deviceId].
  Future<void> setSetting(String deviceId, String settingId, String value) {
    return _sendCommand(deviceId, settingId, value);
  }

  /// Send a per-transmitter setting command (e.g. `voice-tone`) to [deviceId].
  Future<void> setTxSetting(String deviceId, int tx, String settingId, String value) {
    return _sendCommand(deviceId, settingId, value, tx: tx);
  }

  Future<void> _sendCommand(
    String deviceId,
    String settingId,
    String value, {
    int? tx,
  }) async {
    final tracked = _devices[deviceId];
    if (tracked == null || !tracked.alive) {
      throw UsbDisconnectedException('Device $deviceId is not connected');
    }
    final dialect = tracked.dialect;
    if (dialect == null) {
      throw const UnsupportedSettingException('Waiting for device handshake before changing settings');
    }

    final seq = tracked.sequence;
    tracked.sequence = (tracked.sequence + 1) & 0xffff;

    final packet = tracked.model.buildCommand(seq, dialect, settingId, value, tx: tx);
    if (packet == null) {
      throw UnsupportedSettingException(
        'Setting "$settingId" = "$value" is not supported on protocol v${dialect.versionNumber}',
      );
    }

    logger?.debug('TX [$deviceId] $settingId=$value${tx != null ? ' (tx=${tx + 1})' : ''} seq=$seq');
    await tracked.handle.bulkOut(packet);
  }

  void _notify() {
    if (!_disposed && !_changes.isClosed) {
      _changes.add(null);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final tracked in _devices.values) {
      tracked.alive = false;
      await tracked.subscription?.cancel();
      await tracked.handle.close();
    }
    _devices.clear();
    await _changes.close();
    await transport.dispose();
  }
}
