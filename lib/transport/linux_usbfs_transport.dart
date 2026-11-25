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

/// Verified Linux x86_64/arm64 `usbfs` ABI constants from `<linux/usbdevice_fs.h>`.
class LinuxUsbfsAbi {
  LinuxUsbfsAbi._();

  static const int sizeofBulkTransfer = 24;
  static const int bulkEpOffset = 0;
  static const int bulkLenOffset = 4;
  static const int bulkTimeoutOffset = 8;
  static const int bulkDataOffset = 16;

  static const int sizeofDisconnectClaim = 264;
  static const int disconnectClaimInterfaceOffset = 0;
  static const int disconnectClaimFlagsOffset = 4;
  static const int disconnectClaimDriverOffset = 8;

  static const int sizeofUrb = 56;
  static const int sizeofPollFd = 8;

  static const int ioctlBulk = 0xc0185502;
  static const int ioctlSubmitUrb = 0x8038550a;
  static const int ioctlDiscardUrb = 0x550b;
  static const int ioctlReapUrbNdelay = 0x4008550d;
  static const int ioctlReleaseInterface = 0x80045510;
  static const int ioctlDisconnectClaim = 0x8108551b;

  static const int disconnectClaimExceptDriver = 0x02;

  static const int oRdwr = 2;
  static const int oCloexec = 524288;

  static const int eacces = 13;
  static const int eagain = 11;
  static const int eintr = 4;
  static const int enodev = 19;
  static const int enoent = 2;
  static const int eshutdown = 108;
  static const int etimedout = 110;
}

/// Pure `dart:io` Linux USB bus scanner reading `/sys/bus/usb/devices/*`.
class LinuxSysfsScanner {
  LinuxSysfsScanner._();

  static Future<List<UsbDeviceInfo>> scan({String sysfsRoot = '/sys/bus/usb/devices'}) async {
    final root = Directory(sysfsRoot);
    if (!await root.exists()) return const <UsbDeviceInfo>[];

    final results = <UsbDeviceInfo>[];
    await for (final entity in root.list(followLinks: false)) {
      final path = entity.path;
      final vidStr = await _readTrimmed('$path/idVendor');
      final pidStr = await _readTrimmed('$path/idProduct');
      if (vidStr == null || pidStr == null) continue;

      final vid = int.tryParse(vidStr, radix: 16);
      final pid = int.tryParse(pidStr, radix: 16);
      final busStr = await _readTrimmed('$path/busnum');
      final devStr = await _readTrimmed('$path/devnum');
      if (vid == null || pid == null || busStr == null || devStr == null) continue;

      final bus = int.tryParse(busStr);
      final dev = int.tryParse(devStr);
      if (bus == null || dev == null) continue;

      final serial = await _readTrimmed('$path/serial');
      final busPad = bus.toString().padLeft(3, '0');
      final devPad = dev.toString().padLeft(3, '0');

      results.add(
        UsbDeviceInfo(
          id: 'usb-$bus-$dev',
          busNumber: bus,
          deviceAddress: dev,
          vendorId: vid,
          productId: pid,
          serial: (serial != null && serial.isNotEmpty) ? serial : null,
          devicePath: '/dev/bus/usb/$busPad/$devPad',
        ),
      );
    }
    return results;
  }

  static Future<String?> _readTrimmed(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      return (await file.readAsString()).trim();
    } catch (_) {
      return null;
    }
  }
}

typedef _OpenNative = Int32 Function(Pointer<Uint8>, Int32, Int32);
typedef _OpenDart = int Function(Pointer<Uint8>, int, int);

typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

typedef _IoctlPtrNative = Int32 Function(Int32, Uint64, Pointer<Void>);
typedef _IoctlPtrDart = int Function(int, int, Pointer<Void>);

typedef _CallocNative = Pointer<Void> Function(IntPtr, IntPtr);
typedef _CallocDart = Pointer<Void> Function(int, int);

typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

typedef _ErrnoLocNative = Pointer<Int32> Function();
typedef _ErrnoLocDart = Pointer<Int32> Function();

class _Libc {
  _Libc._() {
    final lib = DynamicLibrary.process();
    open = lib.lookupFunction<_OpenNative, _OpenDart>('open');
    close = lib.lookupFunction<_CloseNative, _CloseDart>('close');
    ioctl = lib.lookupFunction<_IoctlPtrNative, _IoctlPtrDart>('ioctl');
    calloc = lib.lookupFunction<_CallocNative, _CallocDart>('calloc');
    free = lib.lookupFunction<_FreeNative, _FreeDart>('free');
    errnoLocation = lib.lookupFunction<_ErrnoLocNative, _ErrnoLocDart>('__errno_location');
  }

  static final _Libc instance = _Libc._();

  late final _OpenDart open;
  late final _CloseDart close;
  late final _IoctlPtrDart ioctl;
  late final _CallocDart calloc;
  late final _FreeDart free;
  late final _ErrnoLocDart errnoLocation;

  int get errno => errnoLocation().value;

  Pointer<Uint8> allocCString(String s) {
    final encoded = utf8.encode(s);
    final ptr = calloc(encoded.length + 1, 1).cast<Uint8>();
    ptr.asTypedList(encoded.length).setAll(0, encoded);
    ptr[encoded.length] = 0;
    return ptr;
  }
}

/// Pure-Dart Linux USB bulk transport over `sysfs` + `USBDEVFS_BULK` ioctls.
///
/// Bulk IN runs in a dedicated reader isolate using 200ms timed `USBDEVFS_BULK`
/// reads checked against a shared stop flag; Bulk OUT runs independently via
/// `Isolate.run` (`USBDEVFS_BULK` on endpoint 0x06) so writes never stall on
/// the reader loop or starve any Dart isolate event loop.
class LinuxUsbfsTransport implements UsbTransport {
  LinuxUsbfsTransport({this.sysfsRoot = '/sys/bus/usb/devices'});

  final String sysfsRoot;
  final List<_LinuxUsbfsHandle> _openHandles = <_LinuxUsbfsHandle>[];

  @override
  String get backendName => 'linux-usbfs (pure Dart)';

  @override
  Future<List<UsbDeviceInfo>> listDevices() {
    return LinuxSysfsScanner.scan(sysfsRoot: sysfsRoot);
  }

  @override
  Future<UsbDeviceHandle> open(
    UsbDeviceInfo device, {
    required int interfaceNumber,
    required int bulkInEndpoint,
    required int bulkOutEndpoint,
  }) async {
    final path = device.devicePath;
    if (path == null) {
      throw UsbException('Missing /dev/bus/usb path for ${device.id}');
    }

    final libc = _Libc.instance;
    final pathPtr = libc.allocCString(path);
    int fd;
    int err = 0;
    try {
      fd = libc.open(pathPtr, LinuxUsbfsAbi.oRdwr | LinuxUsbfsAbi.oCloexec, 0);
      if (fd < 0) err = libc.errno;
    } finally {
      libc.free(pathPtr.cast<Void>());
    }

    if (fd < 0) {
      if (err == LinuxUsbfsAbi.eacces) {
        throw UsbPermissionException('Permission denied opening $path', errno: err);
      }
      throw UsbException('Failed to open $path', errno: err);
    }

    // Detach any kernel driver on Interface 6 only and claim it atomically.
    final dcPtr = libc.calloc(1, LinuxUsbfsAbi.sizeofDisconnectClaim).cast<Uint8>();
    int claimRc;
    int claimErr = 0;
    try {
      final bd = ByteData.sublistView(dcPtr.asTypedList(LinuxUsbfsAbi.sizeofDisconnectClaim));
      bd.setUint32(LinuxUsbfsAbi.disconnectClaimInterfaceOffset, interfaceNumber, Endian.host);
      bd.setUint32(
        LinuxUsbfsAbi.disconnectClaimFlagsOffset,
        LinuxUsbfsAbi.disconnectClaimExceptDriver,
        Endian.host,
      );
      final drv = ascii.encode('usbfs');
      for (var i = 0; i < drv.length; i++) {
        dcPtr[LinuxUsbfsAbi.disconnectClaimDriverOffset + i] = drv[i];
      }
      claimRc = libc.ioctl(fd, LinuxUsbfsAbi.ioctlDisconnectClaim, dcPtr.cast<Void>());
      if (claimRc < 0) claimErr = libc.errno;
    } finally {
      libc.free(dcPtr.cast<Void>());
    }

    if (claimRc < 0) {
      libc.close(fd);
      if (claimErr == LinuxUsbfsAbi.eacces) {
        throw UsbPermissionException('Permission denied claiming interface $interfaceNumber', errno: claimErr);
      }
      throw UsbException('Failed to claim USB interface $interfaceNumber', errno: claimErr);
    }

    final handle = await _LinuxUsbfsHandle.start(
      fd: fd,
      interfaceNumber: interfaceNumber,
      bulkInEndpoint: bulkInEndpoint,
      bulkOutEndpoint: bulkOutEndpoint,
    );
    _openHandles.add(handle);
    return handle;
  }

  @override
  Future<void> dispose() async {
    for (final h in List<_LinuxUsbfsHandle>.from(_openHandles)) {
      await h.close();
    }
    _openHandles.clear();
  }
}

class _ReaderInit {
  const _ReaderInit({
    required this.fd,
    required this.interfaceNumber,
    required this.bulkInEndpoint,
    required this.stopFlagAddress,
    required this.mainPort,
  });

  final int fd;
  final int interfaceNumber;
  final int bulkInEndpoint;
  final int stopFlagAddress;
  final SendPort mainPort;
}

class _LinuxUsbfsHandle implements UsbDeviceHandle {
  _LinuxUsbfsHandle._({
    required this.fd,
    required this.bulkOutEndpoint,
    required this.stopFlag,
    required this.receivePort,
    required this.streamController,
    required this.readerDone,
  });

  final int fd;
  final int bulkOutEndpoint;
  final Pointer<Uint32> stopFlag;
  final ReceivePort receivePort;
  final StreamController<Uint8List> streamController;
  final Completer<void> readerDone;
  Future<void>? _activeWrite;
  bool _closed = false;

  static Future<_LinuxUsbfsHandle> start({
    required int fd,
    required int interfaceNumber,
    required int bulkInEndpoint,
    required int bulkOutEndpoint,
  }) async {
    final libc = _Libc.instance;
    final stopFlag = libc.calloc(1, 4).cast<Uint32>();
    stopFlag.value = 0;

    final receivePort = ReceivePort();
    final streamController = StreamController<Uint8List>.broadcast();
    final readerDone = Completer<void>();

    final handle = _LinuxUsbfsHandle._(
      fd: fd,
      bulkOutEndpoint: bulkOutEndpoint,
      stopFlag: stopFlag,
      receivePort: receivePort,
      streamController: streamController,
      readerDone: readerDone,
    );

    receivePort.listen((dynamic message) {
      if (message is Uint8List) {
        if (!streamController.isClosed) streamController.add(message);
      } else if (message == 'closed') {
        handle._onReaderClosed();
      }
    });

    await Isolate.spawn(
      _usbfsReaderEntry,
      _ReaderInit(
        fd: fd,
        interfaceNumber: interfaceNumber,
        bulkInEndpoint: bulkInEndpoint,
        stopFlagAddress: stopFlag.address,
        mainPort: receivePort.sendPort,
      ),
    );

    return handle;
  }

  void _onReaderClosed() {
    _closed = true;
    if (!streamController.isClosed) {
      streamController.close();
    }
    receivePort.close();
    if (!readerDone.isCompleted) {
      readerDone.complete();
    }
  }

  @override
  Stream<Uint8List> get bulkInStream => streamController.stream;

  @override
  Future<void> bulkOut(Uint8List data) async {
    if (_closed) {
      throw const UsbDisconnectedException('USB handle is closed');
    }
    final previous = _activeWrite;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    if (_closed) {
      throw const UsbDisconnectedException('USB handle is closed');
    }

    final targetFd = fd;
    final ep = bulkOutEndpoint;
    final payload = Uint8List.fromList(data);

    final writeFuture = Isolate.run(() => _usbfsBulkOutSync(targetFd, ep, payload));
    _activeWrite = writeFuture.then((_) {});
    try {
      final err = await writeFuture;
      if (err != 0) {
        if (err == LinuxUsbfsAbi.enodev || err == LinuxUsbfsAbi.eshutdown) {
          throw UsbDisconnectedException('USB device disconnected during bulk OUT (errno=$err)', errno: err);
        }
        throw UsbException('USBDEVFS_BULK OUT failed (errno=$err)', errno: err);
      }
    } finally {
      _activeWrite = null;
    }
  }

  @override
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      final inFlight = _activeWrite;
      if (inFlight != null) {
        try {
          await inFlight.timeout(const Duration(milliseconds: 500));
        } catch (_) {}
      }
      stopFlag.value = 1;
      try {
        await readerDone.future.timeout(const Duration(milliseconds: 600));
      } catch (_) {}
    }
  }
}

/// Runs synchronously inside `Isolate.run` so bulk OUT never blocks the UI or
/// waits on the bulk IN reader loop. Returns `0` on success or `errno`.
int _usbfsBulkOutSync(int fd, int endpoint, Uint8List data) {
  final libc = _Libc.instance;
  final outBuf = libc.calloc(1, data.length).cast<Uint8>();
  final bulkPtr = libc.calloc(1, LinuxUsbfsAbi.sizeofBulkTransfer).cast<Uint8>();
  try {
    outBuf.asTypedList(data.length).setAll(0, data);
    final bd = ByteData.sublistView(bulkPtr.asTypedList(LinuxUsbfsAbi.sizeofBulkTransfer));
    bd.setUint32(LinuxUsbfsAbi.bulkEpOffset, endpoint, Endian.host);
    bd.setUint32(LinuxUsbfsAbi.bulkLenOffset, data.length, Endian.host);
    bd.setUint32(LinuxUsbfsAbi.bulkTimeoutOffset, 1500, Endian.host);
    bd.setUint64(LinuxUsbfsAbi.bulkDataOffset, outBuf.address, Endian.host);

    final rc = libc.ioctl(fd, LinuxUsbfsAbi.ioctlBulk, bulkPtr.cast<Void>());
    if (rc < 0) {
      final err = libc.errno;
      return err == 0 ? 1 : err;
    }
    return 0;
  } finally {
    libc.free(bulkPtr.cast<Void>());
    libc.free(outBuf.cast<Void>());
  }
}

void _usbfsReaderEntry(_ReaderInit init) {
  final libc = _Libc.instance;
  final stopFlag = Pointer<Uint32>.fromAddress(init.stopFlagAddress);
  final inBuf = libc.calloc(1, 512).cast<Uint8>();
  final bulkPtr = libc.calloc(1, LinuxUsbfsAbi.sizeofBulkTransfer).cast<Uint8>();

  try {
    final bd = ByteData.sublistView(bulkPtr.asTypedList(LinuxUsbfsAbi.sizeofBulkTransfer));
    while (stopFlag.value == 0) {
      bd.setUint32(LinuxUsbfsAbi.bulkEpOffset, init.bulkInEndpoint, Endian.host);
      bd.setUint32(LinuxUsbfsAbi.bulkLenOffset, 512, Endian.host);
      bd.setUint32(LinuxUsbfsAbi.bulkTimeoutOffset, 200, Endian.host);
      bd.setUint64(LinuxUsbfsAbi.bulkDataOffset, inBuf.address, Endian.host);

      final rc = libc.ioctl(init.fd, LinuxUsbfsAbi.ioctlBulk, bulkPtr.cast<Void>());
      if (rc > 0) {
        init.mainPort.send(Uint8List.fromList(inBuf.asTypedList(rc)));
      } else if (rc < 0) {
        final err = libc.errno;
        if (err == LinuxUsbfsAbi.etimedout ||
            err == LinuxUsbfsAbi.eagain ||
            err == LinuxUsbfsAbi.eintr) {
          continue;
        }
        // ENODEV / ESHUTDOWN / fatal transfer error -> device unplugged or rebooted.
        break;
      }
    }
  } finally {
    final ifacePtr = libc.calloc(1, 4).cast<Uint32>();
    try {
      ifacePtr.value = init.interfaceNumber;
      libc.ioctl(init.fd, LinuxUsbfsAbi.ioctlReleaseInterface, ifacePtr.cast<Void>());
    } finally {
      libc.free(ifacePtr.cast<Void>());
    }
    libc.close(init.fd);
    libc.free(inBuf.cast<Void>());
    libc.free(bulkPtr.cast<Void>());
    libc.free(stopFlag.cast<Void>());
    init.mainPort.send('closed');
  }
}
