// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:io';

import 'package:dji_mic_control/platform/udev_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UdevInstaller', () {
    test('installs rule via pkexec and reloads udevadm on Linux', () async {
      String? invokedExe;
      List<String>? invokedArgs;

      final installer = UdevInstaller(
        osName: 'linux',
        commandExists: (cmd) async => cmd == 'pkexec',
        runProcess: (exe, args) async {
          invokedExe = exe;
          invokedArgs = args;
          return ProcessResult(0, 0, '', '');
        },
      );

      final result = await installer.install();
      expect(result.status, UdevInstallStatus.installed);
      expect(invokedExe, 'pkexec');
      expect(invokedArgs, isNotNull);
      expect(invokedArgs!.join(' '), contains('/etc/udev/rules.d/60-dji-mic.rules'));
      expect(invokedArgs!.join(' '), contains('udevadm control --reload-rules'));
      expect(invokedArgs!.join(' '), contains('2ca3'));
    });

    test('reports cancelled cleanly when Polkit returns exit code 126', () async {
      final installer = UdevInstaller(
        osName: 'linux',
        commandExists: (_) async => true,
        runProcess: (_, _) async => ProcessResult(0, 126, '', 'Not authorized'),
      );

      final result = await installer.install();
      expect(result.status, UdevInstallStatus.cancelled);
      expect(result.message.toLowerCase(), contains('cancel'));
    });

    test('reports unavailable cleanly when pkexec is missing', () async {
      final installer = UdevInstaller(
        osName: 'linux',
        commandExists: (_) async => false,
        runProcess: (_, _) async => throw StateError('should not run'),
      );

      final result = await installer.install();
      expect(result.status, UdevInstallStatus.unavailable);
      expect(result.message, contains('pkexec'));
    });

    test('reports failed with stderr on unexpected error', () async {
      final installer = UdevInstaller(
        osName: 'linux',
        commandExists: (_) async => true,
        runProcess: (_, _) async => ProcessResult(0, 1, '', 'read-only filesystem'),
      );

      final result = await installer.install();
      expect(result.status, UdevInstallStatus.failed);
      expect(result.message, contains('read-only filesystem'));
    });
  });
}
