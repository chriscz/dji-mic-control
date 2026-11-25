// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:io';

import 'package:flutter/widgets.dart';

import 'state/app_services.dart';
import 'state/mic_controller.dart';
import 'ui/app_shell.dart';

const bool _kDemoDefine = bool.fromEnvironment('DEMO', defaultValue: false);

/// Shared bootstrap used by `main()` and integration tests.
Future<MicController> bootstrap(
  AppServices services, {
  bool startPolling = true,
}) async {
  final controller = MicController(services);
  await controller.initialize(startPolling: startPolling);
  return controller;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final demoMode = _kDemoDefine || args.contains('--demo');
  final services = demoMode ? AppServices.simulated(isDemo: true) : AppServices.production();

  // Enforce single-instance ownership in production so two processes never
  // contend for USB Interface 6.
  if (!demoMode && services.singleInstance != null) {
    final isPrimary = await services.singleInstance!.acquire(
      onActivate: () => services.windowController.show(),
    );
    if (!isPrimary) {
      exit(0);
    }
  }

  final controller = await bootstrap(services);
  runApp(DjiMicApp(controller: controller));
}
