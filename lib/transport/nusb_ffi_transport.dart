// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'usb_transport.dart';

typedef _ListJsonNative = Pointer<Uint8> Function();
typedef _ListJsonDart = Pointer<Uint8> Function();

typedef _StrFreeNative = Void Function(Pointer<Uint8>);
typedef _StrFreeDart = void Function(Pointer<Uint8>);

typedef _OpenNative = Pointer<Void> Function(Uint8, Uint8, Uint8, Uint8, Uint8, Pointer<Int32>);
typedef _OpenDart = Pointer<Void> Function(int, int, int, int, int, Pointer<Int32>);

typedef _BulkInNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _BulkInDart = int Function(Pointer<Void>, Pointer<Uint8>, int);

typedef _BulkOutNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _BulkOutDart = int Function(Pointer<Void>, Pointer<Uint8>, int);

typedef _CloseNative = Void Function(Pointer<Void>);
typedef _CloseDart = void Function(Pointer<Void>);

typedef _CallocNative = Pointer<Void> Function(IntPtr, IntPtr);
typedef _CallocDart = Pointer<Void> Function(int, int);

typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

class _NusbSymbols {
  _NusbSymbols(DynamicLibrary lib)
      : listJson = lib.lookupFunction<_ListJsonNative, _ListJsonDart>('dji_usb_list_json'),
        strFree = lib.lookupFunction<_StrFreeNative, _StrFreeDart>('dji_usb_str_free'),
        open = lib.lookupFunction<_OpenNative, _OpenDart>('dji_usb_open'),
        bulkIn = lib.lookupFunction<_BulkInNative, _BulkInDart>('dji_usb_bulk_in'),
        bulkOut = lib.lookupFunction<_BulkOutNative, _BulkOutDart>('dji_usb_bulk_out'),
        close = lib.lookupFunction<_CloseNative, _CloseDart>('dji_usb_close') {
    final proc = DynamicLibrary.process();
    calloc = proc.lookupFunction<_CallocNative, _CallocDart>('calloc');
    free = proc.lookupFunction<_FreeNative, _FreeDart>('free');
  }

  final _ListJsonDart listJson;
  final _StrFreeDart strFree;
  final _OpenDart open;
  final _BulkInDart bulkIn;
  final _BulkOutDart bulkOut;
  final _CloseDart close;
  late final _CallocDart calloc;
  late final _FreeDart free;

  static String readCString(Pointer<Uint8> ptr) {
    final bytes = <int>[];
    var i = 0;
    while (true) {
      final b = ptr[i++];
      if (b == 0) break;
      bytes.add(b);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// Thin `dart:ffi` adapter wrapping `native/dji_mic_usb` (`nusb` cdylib)
/// behind the exact same [UsbTransport] seam as [LinuxUsbfsTransport].
class NusbFfiTransport implements UsbTransport {
  NusbFfiTransport._(this.libraryPath, this._symbols);

  final String libraryPath;
  final _NusbSymbols _symbols;
  final List<_NusbDeviceHandle> _openHandles = <_NusbDeviceHandle>[];

  @override
  String get backendName => 'nusb-cdylib (Rust FFI)';

  static String get defaultLibraryFileName {
    if (Platform.isMacOS) return 'libdji_mic_usb.dylib';
    if (Platform.isWindows) return 'dji_mic_usb.dll';
    return 'libdji_mic_usb.so';
  }

  /// Attempt to load `libdji_mic_usb` from standard bundle/dev paths.
  /// Returns null cleanly if not present so Linux can fall back to pure Dart usbfs.
  static NusbFfiTransport? tryLoad({String? explicitPath}) {
    final candidates = <String>[
      ?explicitPath,
      '${File(Platform.resolvedExecutable).parent.path}/lib/$defaultLibraryFileName',
      '${File(Platform.resolvedExecutable).parent.path}/$defaultLibraryFileName',
      'native/dji_mic_usb/target/release/$defaultLibraryFileName',
      defaultLibraryFileName,
    ];

    for (final path in candidates) {
      try {
        final lib = DynamicLibrary.open(path);
        return NusbFfiTransport._(path, _NusbSymbols(lib));
      } catch (_) {
        // Try next candidate.
      }
    }
    return null;
  }

  @override
  Future<List<UsbDeviceInfo>> listDevices() async {
    final ptr = _symbols.listJson();
    if (ptr == nullptr) return const <UsbDeviceInfo>[];
    final String raw;
    try {
      raw = _NusbSymbols.readCString(ptr);
    } finally {
      _symbols.strFree(ptr);
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <UsbDeviceInfo>[];
    final out = <UsbDeviceInfo>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final bus = (item['bus'] as num).toInt();
      final addr = (item['address'] as num).toInt();
      out.add(
        UsbDeviceInfo(
          id: item['id'] as String? ?? 'usb-$bus-$addr',
          busNumber: bus,
          deviceAddress: addr,
          vendorId: (item['vid'] as num).toInt(),
          productId: (item['pid'] as num).toInt(),
          serial: item['serial'] as String?,
        ),
      );
    }
    return out;
  }

  @override
  Future<UsbDeviceHandle> open(
    UsbDeviceInfo device, {
    required int interfaceNumber,
    required int bulkInEndpoint,
    required int bulkOutEndpoint,
  }) async {
    final errPtr = _symbols.calloc(1, 4).cast<Int32>();
    Pointer<Void> handlePtr;
    int errCode;
    try {
      handlePtr = _symbols.open(
        device.busNumber,
        device.deviceAddress,
        interfaceNumber,
        bulkInEndpoint,
        bulkOutEndpoint,
        errPtr,
      );
      errCode = errPtr.value;
    } finally {
      _symbols.free(errPtr.cast<Void>());
    }

    if (handlePtr == nullptr) {
      if (errCode == -13) {
        throw UsbPermissionException('Permission denied opening ${device.displayId}', errno: 13);
      }
      if (errCode == -19) {
        throw UsbDisconnectedException('Device ${device.displayId} not found', errno: 19);
      }
      throw UsbException('nusb open failed for ${device.displayId} (code=$errCode)');
    }

    final handle = await _NusbDeviceHandle.start(
      libraryPath: libraryPath,
      handleAddress: handlePtr.address,
      symbols: _symbols,
    );
    _openHandles.add(handle);
    return handle;
  }

  @override
  Future<void> dispose() async {
    for (final h in List<_NusbDeviceHandle>.from(_openHandles)) {
      await h.close();
    }
    _openHandles.clear();
  }
}

class _NusbReaderInit {
  const _NusbReaderInit(this.libraryPath, this.handleAddress, this.port);

  final String libraryPath;
  final int handleAddress;
  final SendPort port;
}

class _NusbDeviceHandle implements UsbDeviceHandle {
  _NusbDeviceHandle._({
    required this.handleAddress,
    required this.symbols,
    required this.isolate,
    required this.receivePort,
    required this.controller,
  });

  final int handleAddress;
  final _NusbSymbols symbols;
  final Isolate isolate;
  final ReceivePort receivePort;
  final StreamController<Uint8List> controller;
  bool _closed = false;

  static Future<_NusbDeviceHandle> start({
    required String libraryPath,
    required int handleAddress,
    required _NusbSymbols symbols,
  }) async {
    final receivePort = ReceivePort();
    final controller = StreamController<Uint8List>.broadcast();
    final isolate = await Isolate.spawn(
      _nusbReaderEntry,
      _NusbReaderInit(libraryPath, handleAddress, receivePort.sendPort),
    );
    final handle = _NusbDeviceHandle._(
      handleAddress: handleAddress,
      symbols: symbols,
      isolate: isolate,
      receivePort: receivePort,
      controller: controller,
    );
    receivePort.listen((dynamic msg) {
      if (msg is Uint8List) {
        if (!controller.isClosed) controller.add(msg);
      } else if (msg == 'closed') {
        handle._finish();
      }
    });
    return handle;
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    if (!controller.isClosed) controller.close();
    receivePort.close();
  }

  @override
  Stream<Uint8List> get bulkInStream => controller.stream;

  @override
  Future<void> bulkOut(Uint8List data) async {
    if (_closed) {
      throw const UsbDisconnectedException('nusb handle is closed');
    }
    final buf = symbols.calloc(1, data.length).cast<Uint8>();
    try {
      buf.asTypedList(data.length).setAll(0, data);
      final rc = symbols.bulkOut(Pointer<Void>.fromAddress(handleAddress), buf, data.length);
      if (rc != 0) {
        throw UsbDisconnectedException('nusb bulk_out failed (rc=$rc)');
      }
    } finally {
      symbols.free(buf.cast<Void>());
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _finish();
    isolate.kill(priority: Isolate.immediate);
    symbols.close(Pointer<Void>.fromAddress(handleAddress));
  }
}

void _nusbReaderEntry(_NusbReaderInit init) {
  final lib = DynamicLibrary.open(init.libraryPath);
  final symbols = _NusbSymbols(lib);
  final handle = Pointer<Void>.fromAddress(init.handleAddress);
  final buf = symbols.calloc(1, 512).cast<Uint8>();
  try {
    while (true) {
      final n = symbols.bulkIn(handle, buf, 512);
      if (n < 0) break;
      if (n > 0) {
        init.port.send(Uint8List.fromList(buf.asTypedList(n)));
      }
    }
  } finally {
    symbols.free(buf.cast<Void>());
    init.port.send('closed');
  }
}
