// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Log severity levels for the in-app Diagnostics view and optional log file.
enum LogLevel {
  debug('DEBUG'),
  info('INFO'),
  warn('WARN'),
  error('ERROR');

  const LogLevel(this.tag);
  final String tag;
}

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String message;

  String format() => '${timestamp.toIso8601String()} [${level.tag}] $message';
}

/// Lightweight ring-buffer logger with optional file persistence (pure dart:io).
class AppLogger extends ChangeNotifier {
  AppLogger({
    this.maxEntries = 400,
    this.logFile,
    this.debugEnabled = false,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxEntries;
  final File? logFile;
  final DateTime Function() _now;
  bool debugEnabled;

  final ListQueue<LogEntry> _entries = ListQueue<LogEntry>();

  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  void debug(String message) {
    if (!debugEnabled) return;
    _record(LogLevel.debug, message);
  }

  void info(String message) => _record(LogLevel.info, message);
  void warn(String message) => _record(LogLevel.warn, message);
  void error(String message) => _record(LogLevel.error, message);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  String dumpText() => _entries.map((e) => e.format()).join('\n');

  void _record(LogLevel level, String message) {
    final entry = LogEntry(timestamp: _now(), level: level, message: message);
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    notifyListeners();
    final file = logFile;
    if (file != null) {
      try {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('${entry.format()}\n', mode: FileMode.append, flush: false);
      } catch (_) {
        // Logging must never crash the app.
      }
    }
  }
}
