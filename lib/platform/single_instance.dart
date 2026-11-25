// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Zero-plugin single-instance guard using a Unix domain socket in
/// `$XDG_RUNTIME_DIR` (preventing two processes from fighting over USB).
class SingleInstance {
  SingleInstance({String? socketPath}) : socketPath = socketPath ?? defaultSocketPath();

  final String socketPath;
  ServerSocket? _server;

  static String defaultSocketPath({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final runtimeDir = env['XDG_RUNTIME_DIR'];
    if (runtimeDir != null && runtimeDir.isNotEmpty) {
      return '$runtimeDir/dji-mic-control.sock';
    }
    final user = env['USER'] ?? 'user';
    return '${Directory.systemTemp.path}/dji-mic-control-$user.sock';
  }

  /// Acquire primary ownership. Returns `true` if this process is the primary
  /// instance, or `false` after forwarding `"show\n"` to an existing instance.
  Future<bool> acquire({required void Function() onActivate}) async {
    if (!Platform.isLinux && !Platform.isMacOS) {
      return true;
    }

    // Attempt to connect to an already-running primary instance first.
    final address = InternetAddress(socketPath, type: InternetAddressType.unix);
    try {
      final client = await Socket.connect(address, 0, timeout: const Duration(milliseconds: 250));
      client.write('show\n');
      await client.flush();
      await client.close();
      return false;
    } on SocketException {
      // No active listener; clean up any stale socket file after a crash.
      final file = File(socketPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    try {
      _server = await ServerSocket.bind(address, 0);
      _server!.listen((socket) {
        socket.cast<List<int>>().transform(utf8.decoder).listen(
          (data) {
            if (data.contains('show')) {
              onActivate();
            }
          },
          onError: (_) {},
        );
      });
      return true;
    } catch (_) {
      // Fall back to allowing launch if socket binding is restricted.
      return true;
    }
  }

  Future<void> dispose() async {
    final server = _server;
    _server = null;
    await server?.close();
    final file = File(socketPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
