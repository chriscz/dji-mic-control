// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:convert';
import 'dart:io';

enum ViewMode {
  compact('compact'),
  list('list');

  const ViewMode(this.slug);
  final String slug;

  static ViewMode fromSlug(String? slug) {
    return slug == 'list' ? ViewMode.list : ViewMode.compact;
  }
}

enum AppThemePreference {
  system('system'),
  light('light'),
  dark('dark');

  const AppThemePreference(this.slug);
  final String slug;

  static AppThemePreference fromSlug(String? slug) {
    return switch (slug) {
      'light' => AppThemePreference.light,
      'dark' => AppThemePreference.dark,
      _ => AppThemePreference.system,
    };
  }
}

/// Persisted user preferences stored in JSON via pure dart:io.
class AppConfig {
  const AppConfig({
    this.viewMode = ViewMode.compact,
    this.themeMode = AppThemePreference.system,
    this.closeToTray = true,
    this.notifyCriticalBattery = true,
    this.notifyDisconnect = false,
    this.debugLogging = false,
    this.showDiagnosticsFold = true,
    this.showPendingStrip = true,
    this.locale = 'en',
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      viewMode: ViewMode.fromSlug(json['viewMode'] as String?),
      themeMode: AppThemePreference.fromSlug(json['themeMode'] as String?),
      closeToTray: json['closeToTray'] as bool? ?? true,
      notifyCriticalBattery: json['notifyCriticalBattery'] as bool? ?? true,
      notifyDisconnect: json['notifyDisconnect'] as bool? ?? false,
      debugLogging: json['debugLogging'] as bool? ?? false,
      showDiagnosticsFold: json['showDiagnosticsFold'] as bool? ?? true,
      showPendingStrip: json['showPendingStrip'] as bool? ?? true,
      locale: (json['locale'] as String?) == 'zh-CN' ? 'zh-CN' : 'en',
    );
  }

  final ViewMode viewMode;
  final AppThemePreference themeMode;
  final bool closeToTray;
  final bool notifyCriticalBattery;
  final bool notifyDisconnect;
  final bool debugLogging;
  final bool showDiagnosticsFold;
  final bool showPendingStrip;
  final String locale;

  AppConfig copyWith({
    ViewMode? viewMode,
    AppThemePreference? themeMode,
    bool? closeToTray,
    bool? notifyCriticalBattery,
    bool? notifyDisconnect,
    bool? debugLogging,
    bool? showDiagnosticsFold,
    bool? showPendingStrip,
    String? locale,
  }) {
    return AppConfig(
      viewMode: viewMode ?? this.viewMode,
      themeMode: themeMode ?? this.themeMode,
      closeToTray: closeToTray ?? this.closeToTray,
      notifyCriticalBattery: notifyCriticalBattery ?? this.notifyCriticalBattery,
      notifyDisconnect: notifyDisconnect ?? this.notifyDisconnect,
      debugLogging: debugLogging ?? this.debugLogging,
      showDiagnosticsFold: showDiagnosticsFold ?? this.showDiagnosticsFold,
      showPendingStrip: showPendingStrip ?? this.showPendingStrip,
      locale: locale ?? this.locale,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'viewMode': viewMode.slug,
        'themeMode': themeMode.slug,
        'closeToTray': closeToTray,
        'notifyCriticalBattery': notifyCriticalBattery,
        'notifyDisconnect': notifyDisconnect,
        'debugLogging': debugLogging,
        'showDiagnosticsFold': showDiagnosticsFold,
        'showPendingStrip': showPendingStrip,
        'locale': locale,
      };
}

/// Pure dart:io XDG/OS config store with atomic temp-file writes.
class ConfigStore {
  ConfigStore({File? configFile}) : _configFile = configFile ?? defaultConfigFile();

  final File _configFile;

  File get configFile => _configFile;

  static File defaultConfigFile({Map<String, String>? environment, String? osName}) {
    final env = environment ?? Platform.environment;
    final os = osName ?? Platform.operatingSystem;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    if (os == 'macos') {
      return File('$home/Library/Application Support/dji-mic-control/config.json');
    }
    if (os == 'windows') {
      final appData = env['APPDATA'] ?? '$home\\AppData\\Roaming';
      return File('$appData\\dji-mic-control\\config.json');
    }
    final xdgConfig = env['XDG_CONFIG_HOME'];
    final base = (xdgConfig != null && xdgConfig.isNotEmpty) ? xdgConfig : '$home/.config';
    return File('$base/dji-mic-control/config.json');
  }

  static File defaultLogFile({Map<String, String>? environment, String? osName}) {
    final env = environment ?? Platform.environment;
    final os = osName ?? Platform.operatingSystem;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    if (os == 'macos') {
      return File('$home/Library/Logs/dji-mic-control/app.log');
    }
    if (os == 'windows') {
      final localAppData = env['LOCALAPPDATA'] ?? '$home\\AppData\\Local';
      return File('$localAppData\\dji-mic-control\\logs\\app.log');
    }
    final xdgState = env['XDG_STATE_HOME'];
    final base = (xdgState != null && xdgState.isNotEmpty) ? xdgState : '$home/.local/state';
    return File('$base/dji-mic-control/logs/app.log');
  }

  Future<AppConfig> load() async {
    try {
      if (!await _configFile.exists()) return const AppConfig();
      final raw = await _configFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AppConfig.fromJson(decoded);
      }
      return const AppConfig();
    } catch (_) {
      return const AppConfig();
    }
  }

  Future<void> save(AppConfig config) async {
    await _configFile.parent.create(recursive: true);
    final tmp = File('${_configFile.path}.tmp');
    final encoded = const JsonEncoder.withIndent('  ').convert(config.toJson());
    await tmp.writeAsString('$encoded\n', flush: true);
    await tmp.rename(_configFile.path);
  }
}

/// In-memory config store for tests and demo mode.
class MemoryConfigStore extends ConfigStore {
  MemoryConfigStore([this._current = const AppConfig()]) : super(configFile: File('/dev/null'));

  AppConfig _current;

  @override
  Future<AppConfig> load() async => _current;

  @override
  Future<void> save(AppConfig config) async {
    _current = config;
  }
}
