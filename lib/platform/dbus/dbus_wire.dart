// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// D-Bus message types per the D-Bus wire specification.
enum DbusMessageType {
  invalid(0),
  methodCall(1),
  methodReturn(2),
  error(3),
  signal(4);

  const DbusMessageType(this.code);
  final int code;

  static DbusMessageType fromCode(int code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    return DbusMessageType.invalid;
  }
}

/// Little-endian D-Bus wire serializer (MIT, zero external dependencies).
class DbusWriter {
  final List<int> _bytes = <int>[];

  int get length => _bytes.length;

  void align(int boundary) {
    final rem = _bytes.length % boundary;
    if (rem != 0) {
      final pad = boundary - rem;
      for (var i = 0; i < pad; i++) {
        _bytes.add(0);
      }
    }
  }

  void writeByte(int v) => _bytes.add(v & 0xff);

  void writeBool(bool v) => writeUint32(v ? 1 : 0);

  void writeInt32(int v) {
    align(4);
    final bd = ByteData(4)..setInt32(0, v, Endian.little);
    _bytes.addAll(bd.buffer.asUint8List());
  }

  void writeUint32(int v) {
    align(4);
    final bd = ByteData(4)..setUint32(0, v, Endian.little);
    _bytes.addAll(bd.buffer.asUint8List());
  }

  void writeString(String s) {
    final utf = utf8.encode(s);
    writeUint32(utf.length);
    _bytes.addAll(utf);
    _bytes.add(0);
  }

  void writeObjectPath(String path) => writeString(path);

  void writeSignature(String sig) {
    final utf = utf8.encode(sig);
    writeByte(utf.length);
    _bytes.addAll(utf);
    _bytes.add(0);
  }

  void writeBytes(List<int> raw) {
    _bytes.addAll(raw);
  }

  /// Write an array whose element alignment is [elemAlign].
  void writeArray(int elemAlign, void Function(DbusWriter w) buildElements) {
    align(4);
    final lenPos = _bytes.length;
    writeUint32(0); // placeholder for byte length
    align(elemAlign);
    final dataStart = _bytes.length;
    buildElements(this);
    final dataLen = _bytes.length - dataStart;
    final bd = ByteData(4)..setUint32(0, dataLen, Endian.little);
    final lenBytes = bd.buffer.asUint8List();
    for (var i = 0; i < 4; i++) {
      _bytes[lenPos + i] = lenBytes[i];
    }
  }

  void writeVariant(String signature, void Function(DbusWriter w) writeValue) {
    writeSignature(signature);
    writeValue(this);
  }

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}

/// Little-endian D-Bus wire deserializer.
class DbusReader {
  DbusReader(this.bytes, [this.offset = 0]);

  final Uint8List bytes;
  int offset;

  int get remaining => bytes.length - offset;

  void align(int boundary) {
    final rem = offset % boundary;
    if (rem != 0) {
      offset += boundary - rem;
    }
  }

  int readByte() => bytes[offset++];

  bool readBool() => readUint32() != 0;

  int readInt32() {
    align(4);
    final bd = ByteData.sublistView(bytes, offset, offset + 4);
    offset += 4;
    return bd.getInt32(0, Endian.little);
  }

  int readUint32() {
    align(4);
    final bd = ByteData.sublistView(bytes, offset, offset + 4);
    offset += 4;
    return bd.getUint32(0, Endian.little);
  }

  String readString() {
    final len = readUint32();
    final str = utf8.decode(bytes.sublist(offset, offset + len), allowMalformed: true);
    offset += len + 1; // trailing NUL
    return str;
  }

  String readSignature() {
    final len = readByte();
    final sig = utf8.decode(bytes.sublist(offset, offset + len), allowMalformed: true);
    offset += len + 1; // trailing NUL
    return sig;
  }
}

class DecodedDbusMessage {
  const DecodedDbusMessage(this.message, this.consumedBytes);

  final DbusMessage message;
  final int consumedBytes;
}

/// Minimal D-Bus message envelope supporting method calls, replies, errors, signals.
class DbusMessage {
  DbusMessage({
    required this.type,
    required this.serial,
    this.flags = 0,
    this.path,
    this.interfaceName,
    this.member,
    this.errorName,
    this.replySerial,
    this.destination,
    this.sender,
    this.signature,
    Uint8List? body,
  }) : body = body ?? Uint8List(0);

  factory DbusMessage.methodCall({
    required int serial,
    required String destination,
    required String path,
    required String interfaceName,
    required String member,
    String? signature,
    DbusWriter? body,
  }) {
    return DbusMessage(
      type: DbusMessageType.methodCall,
      serial: serial,
      destination: destination,
      path: path,
      interfaceName: interfaceName,
      member: member,
      signature: signature,
      body: body?.toBytes(),
    );
  }

  factory DbusMessage.methodReturn({
    required int serial,
    required int replySerial,
    String? destination,
    String? signature,
    DbusWriter? body,
  }) {
    return DbusMessage(
      type: DbusMessageType.methodReturn,
      serial: serial,
      replySerial: replySerial,
      destination: destination,
      signature: signature,
      body: body?.toBytes(),
    );
  }

  factory DbusMessage.error({
    required int serial,
    required int replySerial,
    required String errorName,
    String? destination,
    String? message,
  }) {
    final writer = message != null ? (DbusWriter()..writeString(message)) : null;
    return DbusMessage(
      type: DbusMessageType.error,
      serial: serial,
      replySerial: replySerial,
      errorName: errorName,
      destination: destination,
      signature: message != null ? 's' : null,
      body: writer?.toBytes(),
    );
  }

  final DbusMessageType type;
  final int serial;
  final int flags;
  final String? path;
  final String? interfaceName;
  final String? member;
  final String? errorName;
  final int? replySerial;
  final String? destination;
  final String? sender;
  final String? signature;
  final Uint8List body;

  Uint8List encode() {
    final w = DbusWriter();
    w.writeByte(0x6c); // 'l' little-endian
    w.writeByte(type.code);
    w.writeByte(flags);
    w.writeByte(1); // D-Bus protocol version 1
    w.writeUint32(body.length);
    w.writeUint32(serial);

    w.writeArray(8, (aw) {
      void addField(int code, String sig, void Function(DbusWriter) writeVal) {
        aw.align(8);
        aw.writeByte(code);
        aw.writeVariant(sig, writeVal);
      }

      if (path != null) addField(1, 'o', (v) => v.writeObjectPath(path!));
      if (interfaceName != null) addField(2, 's', (v) => v.writeString(interfaceName!));
      if (member != null) addField(3, 's', (v) => v.writeString(member!));
      if (errorName != null) addField(4, 's', (v) => v.writeString(errorName!));
      if (replySerial != null) addField(5, 'u', (v) => v.writeUint32(replySerial!));
      if (destination != null) addField(6, 's', (v) => v.writeString(destination!));
      if (sender != null) addField(7, 's', (v) => v.writeString(sender!));
      if (signature != null && signature!.isNotEmpty) {
        addField(8, 'g', (v) => v.writeSignature(signature!));
      }
    });

    w.align(8);
    w.writeBytes(body);
    return w.toBytes();
  }

  static DecodedDbusMessage? tryDecode(Uint8List buf) {
    if (buf.length < 16) return null;
    if (buf[0] != 0x6c) return null; // only little-endian supported (x86_64/arm64 Linux)

    final type = DbusMessageType.fromCode(buf[1]);
    final flags = buf[2];
    final bd = ByteData.sublistView(buf, 0, 16);
    final bodyLen = bd.getUint32(4, Endian.little);
    final serial = bd.getUint32(8, Endian.little);
    final fieldsLen = bd.getUint32(12, Endian.little);

    final fieldsEnd = 16 + fieldsLen;
    final headerEnd = (fieldsEnd + 7) & ~7;
    final totalLen = headerEnd + bodyLen;
    if (buf.length < totalLen) return null;

    final r = DbusReader(buf, 16);
    String? path;
    String? iface;
    String? member;
    String? errorName;
    int? replySerial;
    String? destination;
    String? sender;
    String? signature;

    while (r.offset < fieldsEnd) {
      r.align(8);
      if (r.offset >= fieldsEnd) break;
      final code = r.readByte();
      final sig = r.readSignature();
      switch (code) {
        case 1:
          path = r.readString();
        case 2:
          iface = r.readString();
        case 3:
          member = r.readString();
        case 4:
          errorName = r.readString();
        case 5:
          replySerial = r.readUint32();
        case 6:
          destination = r.readString();
        case 7:
          sender = r.readString();
        case 8:
          signature = r.readSignature();
        default:
          // Skip unknown header fields safely.
          if (sig == 's' || sig == 'o') {
            r.readString();
          } else if (sig == 'u' || sig == 'i') {
            r.readUint32();
          } else if (sig == 'g') {
            r.readSignature();
          } else {
            r.offset = fieldsEnd;
          }
      }
    }

    final bodyBytes = Uint8List.fromList(buf.sublist(headerEnd, totalLen));
    return DecodedDbusMessage(
      DbusMessage(
        type: type,
        serial: serial,
        flags: flags,
        path: path,
        interfaceName: iface,
        member: member,
        errorName: errorName,
        replySerial: replySerial,
        destination: destination,
        sender: sender,
        signature: signature,
        body: bodyBytes,
      ),
      totalLen,
    );
  }
}

/// Minimal pure-Dart Unix-socket D-Bus session bus client (SASL EXTERNAL).
class DbusSessionClient {
  DbusSessionClient._(this._socket);

  final Socket _socket;
  final List<int> _buffer = <int>[];
  final Map<int, Completer<DbusMessage>> _pending = <int, Completer<DbusMessage>>{};
  StreamSubscription<Uint8List>? _sub;
  void Function(DbusMessage message)? onMethodCall;
  int _nextSerial = 1;
  bool _closed = false;

  /// Resolve the Unix domain socket path from `$DBUS_SESSION_BUS_ADDRESS`.
  static String? resolveSessionSocketPath({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final addr = env['DBUS_SESSION_BUS_ADDRESS'];
    if (addr != null && addr.startsWith('unix:path=')) {
      final raw = addr.substring('unix:path='.length);
      final comma = raw.indexOf(',');
      return comma == -1 ? raw : raw.substring(0, comma);
    }
    final runtimeDir = env['XDG_RUNTIME_DIR'];
    if (runtimeDir != null && runtimeDir.isNotEmpty) {
      return '$runtimeDir/bus';
    }
    return null;
  }

  /// Connect and complete SASL EXTERNAL + `org.freedesktop.DBus.Hello`.
  /// Returns null cleanly if no session bus is available.
  static Future<DbusSessionClient?> tryConnect({
    String? socketPath,
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    if (!Platform.isLinux) return null;
    final path = socketPath ?? resolveSessionSocketPath();
    if (path == null || !File(path).existsSync()) return null;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: timeout,
      );
      final client = DbusSessionClient._(socket);
      final ok = await client._authenticateAndHello(timeout);
      if (!ok) {
        await client.close();
        return null;
      }
      return client;
    } catch (_) {
      try {
        await socket?.close();
      } catch (_) {}
      return null;
    }
  }

  Future<bool> _authenticateAndHello(Duration timeout) async {
    final authCompleter = Completer<bool>();
    final lineBuf = <int>[];
    var authDone = false;

    _sub = _socket.listen(
      (chunk) {
        if (!authDone) {
          lineBuf.addAll(chunk);
          final text = ascii.decode(lineBuf, allowInvalid: true);
          final crlf = text.indexOf('\r\n');
          if (crlf != -1) {
            final line = text.substring(0, crlf);
            final leftoverStart = crlf + 2;
            authDone = true;
            if (line.startsWith('OK ')) {
              _socket.add(ascii.encode('BEGIN\r\n'));
              if (leftoverStart < lineBuf.length) {
                _buffer.addAll(lineBuf.sublist(leftoverStart));
              }
              if (!authCompleter.isCompleted) authCompleter.complete(true);
              _drainMessages();
            } else {
              if (!authCompleter.isCompleted) authCompleter.complete(false);
            }
          }
          return;
        }
        _buffer.addAll(chunk);
        _drainMessages();
      },
      onError: (_) {
        if (!authCompleter.isCompleted) authCompleter.complete(false);
        _failAllPending();
      },
      onDone: () {
        if (!authCompleter.isCompleted) authCompleter.complete(false);
        _failAllPending();
      },
    );

    // Send NUL + SASL EXTERNAL with hex-encoded UID (or empty EXTERNAL fallback).
    final uidHex = _currentUidHex();
    _socket.add(<int>[0]);
    if (uidHex != null) {
      _socket.add(ascii.encode('AUTH EXTERNAL $uidHex\r\n'));
    } else {
      _socket.add(ascii.encode('AUTH EXTERNAL\r\n'));
    }

    final authed = await authCompleter.future.timeout(timeout, onTimeout: () => false);
    if (!authed) return false;

    final helloReply = await call(
      destination: 'org.freedesktop.DBus',
      path: '/org/freedesktop/DBus',
      interfaceName: 'org.freedesktop.DBus',
      member: 'Hello',
      timeout: timeout,
    );
    return helloReply != null && helloReply.type == DbusMessageType.methodReturn;
  }

  static String? _currentUidHex() {
    try {
      final status = File('/proc/self/status').readAsStringSync();
      for (final line in status.split('\n')) {
        if (line.startsWith('Uid:')) {
          final uid = line.substring(4).trim().split(RegExp(r'\s+')).first;
          final hex = uid.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
          return hex;
        }
      }
    } catch (_) {}
    return null;
  }

  void _drainMessages() {
    while (_buffer.length >= 16) {
      final raw = Uint8List.fromList(_buffer);
      final decoded = DbusMessage.tryDecode(raw);
      if (decoded == null) break;
      _buffer.removeRange(0, decoded.consumedBytes);
      final msg = decoded.message;
      if (msg.replySerial != null && _pending.containsKey(msg.replySerial)) {
        final completer = _pending.remove(msg.replySerial);
        if (completer != null && !completer.isCompleted) {
          completer.complete(msg);
        }
      } else if (msg.type == DbusMessageType.methodCall) {
        onMethodCall?.call(msg);
      }
    }
  }

  Future<DbusMessage?> call({
    required String destination,
    required String path,
    required String interfaceName,
    required String member,
    String? signature,
    DbusWriter? body,
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    if (_closed) return null;
    final serial = _nextSerial++;
    final msg = DbusMessage.methodCall(
      serial: serial,
      destination: destination,
      path: path,
      interfaceName: interfaceName,
      member: member,
      signature: signature,
      body: body,
    );
    final completer = Completer<DbusMessage>();
    _pending[serial] = completer;
    _socket.add(msg.encode());
    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      _pending.remove(serial);
      return null;
    }
  }

  void sendRaw(DbusMessage message) {
    if (_closed) return;
    _socket.add(message.encode());
  }

  int nextSerial() => _nextSerial++;

  Future<bool> nameHasOwner(String busName) async {
    final reply = await call(
      destination: 'org.freedesktop.DBus',
      path: '/org/freedesktop/DBus',
      interfaceName: 'org.freedesktop.DBus',
      member: 'NameHasOwner',
      signature: 's',
      body: DbusWriter()..writeString(busName),
    );
    if (reply == null || reply.type != DbusMessageType.methodReturn || reply.body.length < 4) {
      return false;
    }
    return DbusReader(reply.body).readBool();
  }

  void _failAllPending() {
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(const SocketException('D-Bus connection closed'));
      }
    }
    _pending.clear();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _failAllPending();
    await _sub?.cancel();
    try {
      await _socket.close();
    } catch (_) {}
  }
}
