// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';
import '../platform/capabilities.dart';
import '../platform/config_store.dart';
import '../platform/notifier.dart';
import '../platform/tray_service.dart';
import '../platform/udev_installer.dart';
import '../protocol/state.dart';
import '../transport/device_manager.dart';
import 'app_services.dart';

/// Describes an in-flight USB command or confirmation wait shown in the UI.
class PendingOperation {
  const PendingOperation({
    required this.key,
    required this.label,
    required this.value,
    required this.stage,
    required this.startedAt,
  });

  final String key;
  final String label;
  final String value;
  final String stage;
  final DateTime startedAt;
}

/// Single source of truth for UI state, optimistic writes, OS probing, and alerts.
class MicController extends ChangeNotifier {
  MicController(
    this.services, {
    this.pollInterval = const Duration(milliseconds: 1000),
    this.optimisticTimeout = const Duration(seconds: 3),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppServices services;
  final Duration pollInterval;
  final Duration optimisticTimeout;
  final DateTime Function() _now;

  ManagerSnapshot _snapshot = const ManagerSnapshot(
    probe: BusProbe(),
    devices: <DeviceSummary>[],
  );
  OsCapabilitiesSnapshot? _capabilities;
  AppConfig _config = const AppConfig();
  bool _autostartEnabled = false;
  bool _sidebarOpen = true;
  String? _selectedId;
  bool _userDeselected = false;
  String? _error;
  bool _installingUdev = false;
  UdevInstallResult? _udevInstallResult;

  final Map<String, String> _optimistic = <String, String>{};
  final Map<String, String> _confirmingGain = <String, String>{};
  final Map<String, Timer> _optimisticTimers = <String, Timer>{};
  final Set<String> _pending = <String>{};

  final Map<int, String> _optimisticVoiceTone = <int, String>{};
  final Map<int, Timer> _optimisticTxTimers = <int, Timer>{};
  final Set<int> _pendingTx = <int>{};
  final Map<String, PendingOperation> _pendingOps = <String, PendingOperation>{};

  // Alert deduplication state.
  final Map<String, int> _lastAlertedBatteryTier = <String, int>{};
  final Set<String> _previouslyConnectedIds = <String>{};
  DateTime? _suppressDisconnectAlertsUntil;

  StreamSubscription<void>? _managerSub;
  Timer? _pollTimer;
  bool _disposed = false;

  ManagerSnapshot get snapshot => _snapshot;
  OsCapabilitiesSnapshot? get capabilities => _capabilities;
  AppConfig get config => _config;
  bool get autostartEnabled => _autostartEnabled;
  bool get sidebarOpen => _sidebarOpen;
  String? get selectedId => _selectedId;
  String? get error => _error;
  bool get isDemo => services.isDemo;
  bool get trayActive => services.tray.isActive;
  bool get installingUdev => _installingUdev;
  UdevInstallResult? get udevInstallResult => _udevInstallResult;
  bool get canInstallUdevInApp => services.udevInstaller.supportedOnPlatform;
  List<PendingOperation> get pendingOperations => List<PendingOperation>.unmodifiable(_pendingOps.values);

  /// Translate a UI string according to the persisted locale (`en` or `zh-CN`).
  String t(String key, [Map<String, Object>? params]) => AppStrings.tr(_config.locale, key, params);

  bool isPending(String settingId) => _pending.contains(settingId);
  bool isTxPending(int txIndex) => _pendingTx.contains(txIndex);

  /// Merged settings map overlaying optimistic clicks onto confirmed hardware values.
  Map<String, String> get effectiveSettings {
    final base = _snapshot.status?.settings ?? const <String, String>{};
    if (_optimistic.isEmpty) return base;
    return <String, String>{...base, ..._optimistic};
  }

  /// Effective Voice Tone for TX [txIndex] (0 or 1), including optimistic override.
  String? effectiveVoiceTone(int txIndex) {
    final override = _optimisticVoiceTone[txIndex];
    if (override != null) return override;
    final txList = _snapshot.status?.tx;
    if (txList == null || txIndex < 0 || txIndex >= txList.length) return null;
    return txList[txIndex]?.voiceTone;
  }

  bool get effectiveNcEnabled {
    final power = effectiveSettings['noise-cancel-power'];
    if (power == 'on') return true;
    if (power == 'off') return false;
    return _snapshot.status?.ncEnabled ?? false;
  }

  bool get hasCapabilityNeedingSetup {
    final caps = _capabilities;
    if (caps == null) return false;
    return caps.all.any((c) => c.status == CapabilityStatus.needsSetup);
  }

  Future<void> initialize({bool startPolling = true}) async {
    _config = await services.configStore.load();
    services.logger.debugEnabled = _config.debugLogging;
    _autostartEnabled = await services.autostart.isEnabled();

    await services.tray.start(onActivate: () {
      services.windowController.show();
    });

    _managerSub = services.deviceManager.changes.listen((_) {
      _refreshSnapshot();
    });

    await services.deviceManager.refresh();
    _refreshSnapshot();
    await recheckCapabilities();

    await _syncCloseToTray();

    if (startPolling) {
      _pollTimer = Timer.periodic(pollInterval, (_) {
        services.deviceManager.refresh();
      });
    }
  }

  Future<void> recheckCapabilities() async {
    _capabilities = await services.capabilitiesProbe.inspect(
      usbPermissionIssue: _snapshot.probe.permissionIssue,
    );
    await _syncCloseToTray();
    _safeNotify();
  }

  Future<void> refreshNow() async {
    await services.deviceManager.refresh();
    _refreshSnapshot();
  }

  Future<UdevInstallResult> installUdevRule() async {
    if (_installingUdev) {
      return const UdevInstallResult(
        status: UdevInstallStatus.failed,
        message: 'Installation is already in progress.',
      );
    }
    _installingUdev = true;
    _udevInstallResult = null;
    _safeNotify();

    try {
      final result = await services.udevInstaller.install();
      _udevInstallResult = result;
      if (result.succeeded) {
        await recheckCapabilities();
        await refreshNow();
      }
      return result;
    } finally {
      _installingUdev = false;
      _safeNotify();
    }
  }

  void toggleSidebar() {
    _sidebarOpen = !_sidebarOpen;
    _safeNotify();
  }

  void selectDevice(String? deviceId) {
    if (deviceId == null) {
      _selectedId = null;
      _userDeselected = true;
    } else {
      _selectedId = deviceId;
      _userDeselected = false;
    }
    _clearOptimistic();
    _refreshSnapshot();
  }

  void dismissError() {
    _error = null;
    _safeNotify();
  }

  Future<void> setViewMode(ViewMode mode) async {
    if (_config.viewMode == mode) return;
    _config = _config.copyWith(viewMode: mode);
    await services.configStore.save(_config);
    _safeNotify();
  }

  Future<void> setThemePreference(AppThemePreference pref) async {
    if (_config.themeMode == pref) return;
    _config = _config.copyWith(themeMode: pref);
    await services.configStore.save(_config);
    _safeNotify();
  }

  Future<void> setCloseToTray(bool enabled) async {
    _config = _config.copyWith(closeToTray: enabled);
    await services.configStore.save(_config);
    await _syncCloseToTray();
    _safeNotify();
  }

  Future<void> setNotifyCriticalBattery(bool enabled) async {
    _config = _config.copyWith(notifyCriticalBattery: enabled);
    await services.configStore.save(_config);
    _safeNotify();
  }

  Future<void> setNotifyDisconnect(bool enabled) async {
    _config = _config.copyWith(notifyDisconnect: enabled);
    await services.configStore.save(_config);
    _safeNotify();
  }

  Future<void> setDebugLogging(bool enabled) async {
    _config = _config.copyWith(debugLogging: enabled);
    services.logger.debugEnabled = enabled;
    await services.configStore.save(_config);
    _safeNotify();
  }

  Future<void> toggleDiagnosticsFold() async {
    _config = _config.copyWith(showDiagnosticsFold: !_config.showDiagnosticsFold);
    await services.configStore.save(_config);
    _safeNotify();
  }

  Future<void> setShowPendingStrip(bool visible) async {
    if (_config.showPendingStrip == visible) return;
    _config = _config.copyWith(showPendingStrip: visible);
    await services.configStore.save(_config);
    _safeNotify();
  }

  Future<void> setLocale(String locale) async {
    final normalized = locale == 'zh-CN' ? 'zh-CN' : 'en';
    if (_config.locale == normalized) return;
    _config = _config.copyWith(locale: normalized);
    await services.configStore.save(_config);
    _safeNotify();
  }

  Future<void> setAutostart(bool enabled) async {
    try {
      await services.autostart.setEnabled(enabled);
      _autostartEnabled = await services.autostart.isEnabled();
      _safeNotify();
    } catch (e) {
      _error = 'Failed to update start at login: $e';
      _safeNotify();
    }
  }

  Future<void> minimizeWindow() => services.windowController.minimize();
  Future<void> showWindow() => services.windowController.show();

  String _labelForSetting(String settingId) {
    for (final s in _snapshot.settings) {
      if (s.id == settingId) return s.label;
    }
    return settingId;
  }

  static const Set<String> _gainConfirmIds = <String>{
    'receiver-gain',
    'monitoring-gain',
  };

  Future<void> setSetting(String settingId, String value) async {
    final devId = _selectedId;
    if (devId == null || _pending.contains(settingId)) return;

    final confirmGain = _gainConfirmIds.contains(settingId);
    _error = null;
    _pending.add(settingId);
    final label = _labelForSetting(settingId);
    _pendingOps[settingId] = PendingOperation(
      key: settingId,
      label: label,
      value: value,
      stage: 'Sending',
      startedAt: _now(),
    );
    if (confirmGain) {
      // Upstream PR #4: do not show an optimistic value for gain sliders; wait
      // up to 3s for the receiver's reported heartbeat to confirm the change.
      _confirmingGain[settingId] = value;
    } else {
      _optimistic[settingId] = value;
    }
    _optimisticTimers.remove(settingId)?.cancel();
    _optimisticTimers[settingId] = Timer(optimisticTimeout, () {
      _optimistic.remove(settingId);
      final timedOutGain = _confirmingGain.remove(settingId);
      _optimisticTimers.remove(settingId);
      _pendingOps.remove(settingId);
      if (timedOutGain != null) {
        _error = t('The receiver did not confirm the gain change. The displayed value is the reported value.');
      }
      _safeNotify();
    });

    if (settingId == 'plug-free') {
      _suppressDisconnectAlertsUntil = _now().add(const Duration(seconds: 6));
    }
    _safeNotify();

    try {
      await services.deviceManager.setSetting(devId, settingId, value);
      if (_optimistic.containsKey(settingId) || _confirmingGain.containsKey(settingId)) {
        _pendingOps[settingId] = PendingOperation(
          key: settingId,
          label: label,
          value: value,
          stage: 'Waiting for confirm',
          startedAt: _now(),
        );
      }
    } catch (e) {
      _optimistic.remove(settingId);
      _confirmingGain.remove(settingId);
      _optimisticTimers.remove(settingId)?.cancel();
      _pendingOps.remove(settingId);
      _error = e.toString();
      services.logger.error('Failed to set $settingId=$value: $e');
    } finally {
      _pending.remove(settingId);
      _refreshSnapshot();
    }
  }

  Future<void> setTxSetting(int txIndex, String settingId, String value) async {
    final devId = _selectedId;
    if (devId == null || _pendingTx.contains(txIndex)) return;

    final opKey = 'tx$txIndex:$settingId';
    _error = null;
    _pendingTx.add(txIndex);
    _pendingOps[opKey] = PendingOperation(
      key: opKey,
      label: 'TX${txIndex + 1} ${_labelForSetting(settingId)}',
      value: value,
      stage: 'Sending',
      startedAt: _now(),
    );
    if (settingId == 'voice-tone') {
      _optimisticVoiceTone[txIndex] = value;
      _optimisticTxTimers.remove(txIndex)?.cancel();
      _optimisticTxTimers[txIndex] = Timer(optimisticTimeout, () {
        _optimisticVoiceTone.remove(txIndex);
        _optimisticTxTimers.remove(txIndex);
        _pendingOps.remove(opKey);
        _safeNotify();
      });
    }
    _safeNotify();

    try {
      await services.deviceManager.setTxSetting(devId, txIndex, settingId, value);
      if (_optimisticVoiceTone.containsKey(txIndex)) {
        _pendingOps[opKey] = PendingOperation(
          key: opKey,
          label: 'TX${txIndex + 1} ${_labelForSetting(settingId)}',
          value: value,
          stage: 'Waiting for confirm',
          startedAt: _now(),
        );
      }
    } catch (e) {
      _optimisticVoiceTone.remove(txIndex);
      _optimisticTxTimers.remove(txIndex)?.cancel();
      _pendingOps.remove(opKey);
      _error = e.toString();
      services.logger.error('Failed to set TX${txIndex + 1} $settingId=$value: $e');
    } finally {
      _pendingTx.remove(txIndex);
      _refreshSnapshot();
    }
  }

  void _refreshSnapshot() {
    final prevPermission = _snapshot.probe.permissionIssue;
    var snap = services.deviceManager.snapshot(_selectedId);

    // Auto-select the first available device unless the user explicitly deselected.
    if (!_userDeselected && (_selectedId == null || !snap.devices.any((d) => d.id == _selectedId))) {
      if (snap.devices.isNotEmpty) {
        _selectedId = snap.devices.first.id;
        snap = services.deviceManager.snapshot(_selectedId);
      } else {
        _selectedId = null;
      }
    } else if (_selectedId != null && !snap.devices.any((d) => d.id == _selectedId)) {
      _selectedId = null;
    }

    _snapshot = snap;
    _retireConfirmedOptimistic(snap.status);
    _processAlertsAndTray(snap);

    if (prevPermission != snap.probe.permissionIssue) {
      recheckCapabilities();
    }
    _safeNotify();
  }

  void _retireConfirmedOptimistic(DeviceStatus? status) {
    if (status == null) return;
    final confirmed = status.settings;
    final doneKeys = <String>[];
    _optimistic.forEach((k, v) {
      if (confirmed[k] == v) {
        doneKeys.add(k);
      }
    });
    for (final k in doneKeys) {
      _optimistic.remove(k);
      _optimisticTimers.remove(k)?.cancel();
      _pendingOps.remove(k);
      services.logger.info('Confirmed $k=${confirmed[k]}');
    }

    final doneGainKeys = <String>[];
    _confirmingGain.forEach((k, v) {
      if (confirmed[k] == v) {
        doneGainKeys.add(k);
      }
    });
    for (final k in doneGainKeys) {
      _confirmingGain.remove(k);
      _optimisticTimers.remove(k)?.cancel();
      _pendingOps.remove(k);
      services.logger.info('Confirmed $k=${confirmed[k]}');
    }

    final doneTx = <int>[];
    _optimisticVoiceTone.forEach((idx, v) {
      if (idx >= 0 && idx < status.tx.length && status.tx[idx]?.voiceTone == v) {
        doneTx.add(idx);
      }
    });
    for (final idx in doneTx) {
      _optimisticVoiceTone.remove(idx);
      _optimisticTxTimers.remove(idx)?.cancel();
      _pendingOps.remove('tx$idx:voice-tone');
      services.logger.info('Confirmed TX${idx + 1} voice-tone=${status.tx[idx]?.voiceTone}');
    }
  }

  void _processAlertsAndTray(ManagerSnapshot snap) {
    var anyConnected = false;
    var hasMicMini2 = false;
    int? worstBattery;
    final currentConnectedIds = <String>{};

    for (final d in snap.devices) {
      if (d.connected) {
        anyConnected = true;
        currentConnectedIds.add(d.id);
      }
      for (var i = 0; i < d.tx.length; i++) {
        final tx = d.tx[i];
        if (tx == null) continue;
        if (tx.productName == 'DJI Mic Mini 2') {
          hasMicMini2 = true;
        }
        final batt = tx.battery;
        if (batt != null && batt > 0 && tx.charging != true) {
          if (worstBattery == null || batt > worstBattery) {
            worstBattery = batt;
          }
          final alertKey = '${d.id}:tx$i';
          final prevTier = _lastAlertedBatteryTier[alertKey] ?? 0;
          if (_config.notifyCriticalBattery && batt >= 6 && batt > prevTier) {
            _lastAlertedBatteryTier[alertKey] = batt;
            final label = batt >= 7 ? 'Critical' : 'Very Low';
            services.notifier.send(
              title: 'DJI Mic TX${i + 1} Battery $label',
              body: '${tx.productName ?? 'Transmitter ${i + 1}'} battery is $label. Dock to charge soon.',
              urgency: batt >= 7 ? NotificationUrgency.critical : NotificationUrgency.normal,
            );
          } else if (batt < 6) {
            _lastAlertedBatteryTier.remove(alertKey);
          }
        }
      }
    }

    // Optional unexpected disconnect notification.
    final suppressed = _suppressDisconnectAlertsUntil != null && _now().isBefore(_suppressDisconnectAlertsUntil!);
    if (_config.notifyDisconnect && !suppressed) {
      for (final oldId in _previouslyConnectedIds) {
        if (!currentConnectedIds.contains(oldId)) {
          services.notifier.send(
            title: 'DJI Mic Disconnected',
            body: 'Receiver $oldId disconnected from USB.',
          );
        }
      }
    }
    _previouslyConnectedIds
      ..clear()
      ..addAll(currentConnectedIds);

    services.tray.update(
      TrayState(
        anyConnected: anyConnected,
        worstBattery: worstBattery,
        hasMicMini2: hasMicMini2,
        tooltip: anyConnected ? 'DJI Mic Control (Connected)' : 'DJI Mic Control (No signal)',
      ),
    );
  }

  Future<void> _syncCloseToTray() async {
    final effectiveCloseToTray = _config.closeToTray && services.tray.isActive;
    await services.windowController.setCloseToTray(effectiveCloseToTray);
  }

  void _clearOptimistic() {
    for (final t in _optimisticTimers.values) {
      t.cancel();
    }
    _optimisticTimers.clear();
    _optimistic.clear();
    _confirmingGain.clear();
    for (final t in _optimisticTxTimers.values) {
      t.cancel();
    }
    _optimisticTxTimers.clear();
    _optimisticVoiceTone.clear();
    _pendingOps.clear();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _managerSub?.cancel();
    _clearOptimistic();
    super.dispose();
  }
}
