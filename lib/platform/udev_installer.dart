// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:io';

import '../log/app_logger.dart';
import 'capabilities.dart';

enum UdevInstallStatus {
  installed,
  cancelled,
  unavailable,
  failed,
}

class UdevInstallResult {
  const UdevInstallResult({
    required this.status,
    required this.message,
  });

  final UdevInstallStatus status;
  final String message;

  bool get succeeded => status == UdevInstallStatus.installed;
}

typedef ProcessRunner = Future<ProcessResult> Function(String executable, List<String> arguments);

/// Zero-plugin in-app Linux udev rule installer using standard Polkit `pkexec`.
class UdevInstaller {
  UdevInstaller({
    String? osName,
    Future<bool> Function(String command)? commandExists,
    ProcessRunner? runProcess,
    this.logger,
  })  : _osName = osName ?? Platform.operatingSystem,
        _commandExists = commandExists ?? _defaultCommandExists,
        _runProcess = runProcess ?? Process.run;

  final String _osName;
  final Future<bool> Function(String command) _commandExists;
  final ProcessRunner _runProcess;
  final AppLogger? logger;

  bool get supportedOnPlatform => _osName == 'linux';

  Future<UdevInstallResult> install() async {
    if (_osName != 'linux') {
      return const UdevInstallResult(
        status: UdevInstallStatus.unavailable,
        message: 'Automatic udev installation is only used on Linux.',
      );
    }

    final hasPkexec = await _commandExists('pkexec');
    if (!hasPkexec) {
      return const UdevInstallResult(
        status: UdevInstallStatus.unavailable,
        message: 'pkexec is not available on this system. Copy the shell command below and run it in a terminal.',
      );
    }

    final rule = UdevHelper.generateLinuxUdevRule().trimRight();
    final escapedRule = rule.replaceAll("'", "'\\''");
    final script =
        "printf '%s\\n' '$escapedRule' > ${UdevHelper.rulePath} && "
        'chmod 644 ${UdevHelper.rulePath} && '
        'udevadm control --reload-rules && '
        'udevadm trigger --subsystem-match=usb';

    try {
      logger?.info('Running pkexec to install ${UdevHelper.rulePath}');
      final res = await _runProcess('pkexec', <String>['sh', '-c', script]);
      if (res.exitCode == 0) {
        logger?.info('Installed ${UdevHelper.rulePath} and reloaded udev rules');
        return const UdevInstallResult(
          status: UdevInstallStatus.installed,
          message: 'udev rule installed and reloaded. If your receiver is already plugged in, it should appear shortly (or replug once).',
        );
      }
      if (res.exitCode == 126 || res.exitCode == 127) {
        logger?.info('pkexec authentication cancelled (exit=${res.exitCode})');
        return const UdevInstallResult(
          status: UdevInstallStatus.cancelled,
          message: 'Authentication was cancelled. You can try again or copy the manual command below.',
        );
      }
      final errText = (res.stderr ?? '').toString().trim();
      final detail = errText.isNotEmpty ? errText : 'exit code ${res.exitCode}';
      logger?.warn('udev install failed: $detail');
      return UdevInstallResult(
        status: UdevInstallStatus.failed,
        message: 'Could not install udev rule ($detail). Try the manual command below.',
      );
    } catch (e) {
      logger?.warn('udev install error: $e');
      return UdevInstallResult(
        status: UdevInstallStatus.failed,
        message: 'Could not launch pkexec ($e). Try the manual command below.',
      );
    }
  }

  static Future<bool> _defaultCommandExists(String command) async {
    try {
      final result = await Process.run('which', <String>[command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

/// Deterministic stub installer for tests and demo mode.
class FakeUdevInstaller extends UdevInstaller {
  FakeUdevInstaller({
    this.nextResult = const UdevInstallResult(
      status: UdevInstallStatus.installed,
      message: 'udev rule installed and reloaded (simulated).',
    ),
    this.onInstall,
  }) : super(osName: 'linux');

  UdevInstallResult nextResult;
  final void Function()? onInstall;
  int callCount = 0;

  @override
  Future<UdevInstallResult> install() async {
    callCount++;
    onInstall?.call();
    return nextResult;
  }
}
