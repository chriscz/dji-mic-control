// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:io';

/// Zero-plugin start-at-login manager using XDG autostart on Linux and
/// LaunchAgent plist on macOS.
class AutostartService {
  AutostartService({
    String? osName,
    Directory? autostartDir,
    String? executablePath,
    Map<String, String>? environment,
  })  : _osName = osName ?? Platform.operatingSystem,
        _executablePath = executablePath ?? Platform.resolvedExecutable,
        _autostartDir = autostartDir ?? _defaultDir(osName ?? Platform.operatingSystem, environment ?? Platform.environment);

  static const String desktopFileName = 'dji-mic-control.desktop';
  static const String launchAgentName = 'dev.miscai.dji-mic-control.plist';

  final String _osName;
  final Directory _autostartDir;
  final String _executablePath;

  static Directory _defaultDir(String os, Map<String, String> env) {
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    if (os == 'macos') {
      return Directory('$home/Library/LaunchAgents');
    }
    final xdgConfig = env['XDG_CONFIG_HOME'];
    final base = (xdgConfig != null && xdgConfig.isNotEmpty) ? xdgConfig : '$home/.config';
    return Directory('$base/autostart');
  }

  bool get supported => _osName == 'linux' || _osName == 'macos';

  File get entryFile => File(
        '${_autostartDir.path}/${_osName == 'macos' ? launchAgentName : desktopFileName}',
      );

  Future<bool> isEnabled() async {
    if (!supported) return false;
    return entryFile.exists();
  }

  Future<void> setEnabled(bool enabled) async {
    if (!supported) return;
    if (!enabled) {
      if (await entryFile.exists()) {
        await entryFile.delete();
      }
      return;
    }
    await _autostartDir.create(recursive: true);
    final content = _osName == 'macos' ? _buildLaunchAgent() : _buildDesktopEntry();
    await entryFile.writeAsString(content, flush: true);
  }

  String _buildDesktopEntry() {
    return '''
[Desktop Entry]
Type=Application
Name=DJI Mic Control
Comment=Control DJI wireless microphones
Exec="$_executablePath" --hidden
Icon=dji-mic-control
Terminal=false
Categories=AudioVideo;Audio;Utility;
X-GNOME-Autostart-enabled=true
''';
  }

  String _buildLaunchAgent() {
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.miscai.dji-mic-control</string>
  <key>ProgramArguments</key>
  <array>
    <string>$_executablePath</string>
    <string>--hidden</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
''';
  }
}

/// In-memory autostart stub for tests and demo mode.
class MemoryAutostartService extends AutostartService {
  MemoryAutostartService({bool initial = false})
      : _enabled = initial,
        super(osName: 'linux', autostartDir: Directory.systemTemp, executablePath: 'dji_mic_control');

  bool _enabled;

  @override
  Future<bool> isEnabled() async => _enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
  }
}
