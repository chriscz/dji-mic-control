// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:flutter/services.dart';

/// Thin MethodChannel bridge to the host runner (`linux/runner/my_application.cc`).
///
/// Requires zero third-party Flutter plugins and links only GTK3 already used
/// by Flutter's Linux embedder.
abstract class WindowController {
  Future<void> show();
  Future<void> hide();
  Future<void> minimize();
  Future<void> setCloseToTray(bool enabled);
  Future<void> quit();
}

class MethodChannelWindowController implements WindowController {
  MethodChannelWindowController({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('dji_mic/window');

  final MethodChannel _channel;

  @override
  Future<void> show() => _invoke('show');

  @override
  Future<void> hide() => _invoke('hide');

  @override
  Future<void> minimize() => _invoke('minimize');

  @override
  Future<void> setCloseToTray(bool enabled) => _invoke('setCloseToTray', <String, Object>{'enabled': enabled});

  @override
  Future<void> quit() => _invoke('quit');

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Safe no-op in headless flutter_tester or platforms without runner hooks.
    }
  }
}

class NoopWindowController implements WindowController {
  bool visible = true;
  bool minimized = false;
  bool closeToTrayEnabled = false;
  bool quitRequested = false;

  @override
  Future<void> show() async {
    visible = true;
    minimized = false;
  }

  @override
  Future<void> hide() async {
    visible = false;
  }

  @override
  Future<void> minimize() async {
    minimized = true;
  }

  @override
  Future<void> setCloseToTray(bool enabled) async {
    closeToTrayEnabled = enabled;
  }

  @override
  Future<void> quit() async {
    quitRequested = true;
  }
}
