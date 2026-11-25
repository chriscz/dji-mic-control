// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:io';

import '../log/app_logger.dart';

enum NotificationUrgency {
  low('low'),
  normal('normal'),
  critical('critical');

  const NotificationUrgency(this.cliValue);
  final String cliValue;
}

/// Zero-plugin desktop notification dispatcher with runtime fallback.
abstract class DesktopNotifier {
  Future<bool> send({
    required String title,
    required String body,
    NotificationUrgency urgency = NotificationUrgency.normal,
  });
}

/// Dispatches notifications via `notify-send` (Linux) or `osascript` (macOS)
/// without linking libnotify or any native Flutter plugin.
class ProcessDesktopNotifier implements DesktopNotifier {
  ProcessDesktopNotifier({
    String? osName,
    this.logger,
  }) : _osName = osName ?? Platform.operatingSystem;

  final String _osName;
  final AppLogger? logger;

  @override
  Future<bool> send({
    required String title,
    required String body,
    NotificationUrgency urgency = NotificationUrgency.normal,
  }) async {
    try {
      if (_osName == 'linux') {
        final result = await Process.run('notify-send', <String>[
          '--app-name=DJI Mic Control',
          '--urgency=${urgency.cliValue}',
          title,
          body,
        ]);
        return result.exitCode == 0;
      }
      if (_osName == 'macos') {
        final escapedTitle = title.replaceAll('"', '\\"');
        final escapedBody = body.replaceAll('"', '\\"');
        final result = await Process.run('osascript', <String>[
          '-e',
          'display notification "$escapedBody" with title "$escapedTitle"',
        ]);
        return result.exitCode == 0;
      }
      return false;
    } catch (e) {
      logger?.debug('Desktop notification skipped ($e)');
      return false;
    }
  }
}

/// Recording notifier for tests and demo mode.
class RecordingNotifier implements DesktopNotifier {
  final List<({String title, String body, NotificationUrgency urgency})> sent =
      <({String title, String body, NotificationUrgency urgency})>[];

  @override
  Future<bool> send({
    required String title,
    required String body,
    NotificationUrgency urgency = NotificationUrgency.normal,
  }) async {
    sent.add((title: title, body: body, urgency: urgency));
    return true;
  }
}
