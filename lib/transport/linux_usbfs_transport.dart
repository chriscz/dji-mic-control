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

  static const int sizeofDisconnectClaim = 264;
  static const int disconnectClaimInterfaceOffset = 0;
  static const int disconnectClaimFlagsOffset = 4;
  static const int disconnectClaimDriverOffset = 8;

  static const int sizeofUrb = 56;
  static const int urbTypeOffset = 0;
  static const int urbEndpointOffset = 1;
  static const int urbStatusOffset = 4;
  static const int urbFlagsOffset = 8;
  static const int urbBufferOffset = 16;
  static const int urbBufferLengthOffset = 24;
  static const int urbActualLengthOffset = 28;
  static const int urbUserContextOffset = 48;

  static const int sizeofPollFd = 8;
  static const int pollFdOffset = 0;
  static const int pollEventsOffset = 4;
  static const int pollReventsOffset = 6;

  static const int ioctlSubmitUrb = 0x8038550a;
  static const int ioctlDiscardUrb = 0x550b;
  static const int ioctlReapUrbNdelay = 0x4008550d;
  static const int ioctlReleaseInterface = 0x80045510;
  static const int ioctlDisconnectClaim = 0x8108551b;

  static const int disconnectClaimExceptDriver = 0x02;
  static const int urbTypeBulk = 3;

  static const int oRdwr = 2;
  static const int oCloexec = 524288;
  static const int efdNonblock = 2048;
  static const int efdCloexec = 524288;

  static const int pollIn = 1;
  static const int pollOut = 4;
  static const int pollErr = 8;
  static const int pollHup = 16;

  static const int eacces = 13;
  static const int eagain = 11;
  static const int eintr = 4;
  static const int enodev = 19;
  static const int enoent = 2;
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

// Direct libc FFI bindings using DynamicLibrary.process() (zero external libs).
typedef _OpenNative = Int32 Function(Pointer<Uint8>, Int32, Int32);
typedef _OpenDart = int Function(Pointer<Uint8>, int, int);

typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

typedef _IoctlPtrNative = Int32 Function(Int32, Uint64, Pointer<Void>);
typedef _IoctlPtrDart = int Function(int, int, Pointer<Void>);

typedef _PollNative = Int32 Function(Pointer<Void>, Uint64, Int32);
typedef _PollDart = int Function(Pointer<Void>, int, int);

typedef _EventfdNative = Int32 Function(Uint32, Int32);
typedef _EventfdDart = int Function(int, int);

typedef _ReadWriteNative = IntPtr Function(Int32, Pointer<Void>, IntPtr);
typedef _ReadWriteDart = int Function(int, Pointer<Void>, int);

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
    poll = lib.lookupFunction<_PollNative, _PollDart>('poll');
    eventfd = lib.lookupFunction<_EventfdNative, _EventfdDart>('eventfd');
    read = lib.lookupFunction<_ReadWriteNative, _ReadWriteDart>('read');
    write = lib.lookupFunction<_ReadWriteNative, _ReadWriteDart>('write');
    calloc = lib.lookupFunction<_CallocNative, _CallocDart>('calloc');
    free = lib.lookupFunction<_FreeNative, _FreeDart>('free');
    errnoLocation = lib.lookupFunction<_ErrnoLocNative, _ErrnoLocDart>('__errno_location');
  }

  static final _Libc instance = _Libc._();

  late final _OpenDart open;
  late final _CloseDart close;
  late final _IoctlPtrDart ioctl;
  late final _PollDart poll;
  late final _EventfdDart eventfd;
  late final _ReadWriteDart read;
  late final _ReadWriteDart write;
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

/// Pure-Dart Linux USB bulk transport over `sysfs` + `usbfs` ioctls (zero
/// external USB libraries or pub.dev plugins).
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

    final wakeFd = libc.eventfd(0, LinuxUsbfsAbi.efdNonblock | LinuxUsbfsAbi.efdCloexec);
    if (wakeFd < 0) {
      libc.close(fd);
      throw UsbException('Failed to create eventfd', errno: libc.errno);
    }

    final handle = await _LinuxUsbfsHandle.start(
      fd: fd,
      wakeFd: wakeFd,
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

class _WorkerInit {
  const _WorkerInit({
    required this.fd,
    required this.wakeFd,
    required this.interfaceNumber,
    required this.bulkInEndpoint,
    required this.bulkOutEndpoint,
    required this.mainPort,
  });

  final int fd;
  final int wakeFd;
  final int interfaceNumber;
  final int bulkInEndpoint;
  final int bulkOutEndpoint;
  final SendPort mainPort;
}

class _LinuxUsbfsHandle implements UsbDeviceHandle {
  _LinuxUsbfsHandle._({
    required this.wakeFd,
    required this.isolate,
    required this.workerPort,
    required this.receivePort,
    required this.streamController,
  });

  final int wakeFd;
  final Isolate isolate;
  final SendPort workerPort;
  final ReceivePort receivePort;
  final StreamController<Uint8List> streamController;
  final Map<int, Completer<void>> _pendingWrites = <int, Completer<void>>{};
  int _nextWriteId = 1;
  bool _closed = false;

  static Future<_LinuxUsbfsHandle> start({
    required int fd,
    required int wakeFd,
    required int interfaceNumber,
    required int bulkInEndpoint,
    required int bulkOutEndpoint,
  }) async {
    final receivePort = ReceivePort();
    final streamController = StreamController<Uint8List>();
    final ready = Completer<SendPort>();

    final isolate = await Isolate.spawn(
      _usbfsWorkerEntry,
      _WorkerInit(
        fd: fd,
        wakeFd: wakeFd,
        interfaceNumber: interfaceNumber,
        bulkInEndpoint: bulkInEndpoint,
        bulkOutEndpoint: bulkOutEndpoint,
        mainPort: receivePort.sendPort,
      ),
    );

    late final _LinuxUsbfsHandle handle;
    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is Uint8List) {
        if (!streamController.isClosed) streamController.add(message);
        return;
      }
      if (message is List && message.isNotEmpty) {
        final kind = message[0] as String;
        if (kind == 'write_ok') {
          final id = message[1] as int;
          handle._pendingWrites.remove(id)?.complete();
        } else if (kind == 'write_err') {
          final id = message[1] as int;
          final err = message[2] as String;
          handle._pendingWrites.remove(id)?.completeError(UsbException(err));
        } else if (kind == 'closed') {
          handle._markClosed();
        }
      }
    });

    final workerPort = await ready.future;
    handle = _LinuxUsbfsHandle._(
      wakeFd: wakeFd,
      isolate: isolate,
      workerPort: workerPort,
      receivePort: receivePort,
      streamController: streamController,
    );
    return handle;
  }

  void _wakeWorker() {
    final libc = _Libc.instance;
    final ptr = libc.calloc(1, 8).cast<Uint64>();
    try {
      ptr.value = 1;
      libc.write(wakeFd, ptr.cast<Void>(), 8);
    } finally {
      libc.free(ptr.cast<Void>());
    }
  }

  void _markClosed() {
    if (_closed) return;
    _closed = true;
    for (final c in _pendingWrites.values) {
      if (!c.isCompleted) {
        c.completeError(const UsbDisconnectedException('USB device closed'));
      }
    }
    _pendingWrites.clear();
    if (!streamController.isClosed) {
      streamController.close();
    }
    receivePort.close();
  }

  @override
  Stream<Uint8List> get bulkInStream => streamController.stream;

  @override
  Future<void> bulkOut(Uint8List data) {
    if (_closed) {
      return Future<void>.error(const UsbDisconnectedException('USB handle is closed'));
    }
    final id = _nextWriteId++;
    final completer = Completer<void>();
    _pendingWrites[id] = completer;
    workerPort.send(<Object>['write', id, data]);
    _wakeWorker();
    return completer.future;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    workerPort.send(<Object>['close']);
    _wakeWorker();
    _markClosed();
    isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

void _usbfsWorkerEntry(_WorkerInit init) {
  final libc = _Libc.instance;
  final commandPort = ReceivePort();
  final pendingWrites = <(int, Uint8List)>[];
  var stopRequested = false;

  commandPort.listen((dynamic msg) {
    if (msg is List && msg.isNotEmpty) {
      final kind = msg[0] as String;
      if (kind == 'write') {
        pendingWrites.add((msg[1] as int, msg[2] as Uint8List));
      } else if (kind == 'close') {
        stopRequested = true;
      }
    }
  });

  init.mainPort.send(commandPort.sendPort);

  final inBuf = libc.calloc(1, 512).cast<Uint8>();
  final inUrb = libc.calloc(1, LinuxUsbfsAbi.sizeofUrb).cast<Uint8>();
  final outUrb = libc.calloc(1, LinuxUsbfsAbi.sizeofUrb).cast<Uint8>();
  final reapedPtr = libc.calloc(1, 8).cast<Pointer<Void>>();
  final pollFds = libc.calloc(2, LinuxUsbfsAbi.sizeofPollFd).cast<Uint8>();
  final drainBuf = libc.calloc(1, 8);

  bool inFlight = false;

  bool submitInUrb() {
    final view = inUrb.asTypedList(LinuxUsbfsAbi.sizeofUrb);
    view.fillRange(0, view.length, 0);
    final bd = ByteData.sublistView(view);
    view[LinuxUsbfsAbi.urbTypeOffset] = LinuxUsbfsAbi.urbTypeBulk;
    view[LinuxUsbfsAbi.urbEndpointOffset] = init.bulkInEndpoint;
    bd.setUint64(LinuxUsbfsAbi.urbBufferOffset, inBuf.address, Endian.host);
    bd.setInt32(LinuxUsbfsAbi.urbBufferLengthOffset, 512, Endian.host);
    bd.setUint64(LinuxUsbfsAbi.urbUserContextOffset, 1, Endian.host);
    final rc = libc.ioctl(init.fd, LinuxUsbfsAbi.ioctlSubmitUrb, inUrb.cast<Void>());
    inFlight = rc == 0;
    return inFlight;
  }

  void runSyncOut(int writeId, Uint8List data) {
    final outBuf = libc.calloc(1, data.length).cast<Uint8>();
    try {
      outBuf.asTypedList(data.length).setAll(0, data);
      final view = outUrb.asTypedList(LinuxUsbfsAbi.sizeofUrb);
      view.fillRange(0, view.length, 0);
      final bd = ByteData.sublistView(view);
      view[LinuxUsbfsAbi.urbTypeOffset] = LinuxUsbfsAbi.urbTypeBulk;
      view[LinuxUsbfsAbi.urbEndpointOffset] = init.bulkOutEndpoint;
      bd.setUint64(LinuxUsbfsAbi.urbBufferOffset, outBuf.address, Endian.host);
      bd.setInt32(LinuxUsbfsAbi.urbBufferLengthOffset, data.length, Endian.host);
      bd.setUint64(LinuxUsbfsAbi.urbUserContextOffset, 2, Endian.host);

      final rc = libc.ioctl(init.fd, LinuxUsbfsAbi.ioctlSubmitUrb, outUrb.cast<Void>());
      if (rc < 0) {
        init.mainPort.send(<Object>['write_err', writeId, 'USBDEVFS_SUBMITURB OUT failed (errno=${libc.errno})']);
        return;
      }

      // Wait briefly for the OUT URB to reap (also forwarding any IN URB that completes first).
      final deadline = DateTime.now().add(const Duration(milliseconds: 1000));
      while (DateTime.now().isBefore(deadline)) {
        final reapRc = libc.ioctl(init.fd, LinuxUsbfsAbi.ioctlReapUrbNdelay, reapedPtr.cast<Void>());
        if (reapRc == 0) {
          final doneUrb = reapedPtr.value.cast<Uint8>();
          final doneBd = ByteData.sublistView(doneUrb.asTypedList(LinuxUsbfsAbi.sizeofUrb));
          final ctx = doneBd.getUint64(LinuxUsbfsAbi.urbUserContextOffset, Endian.host);
          final status = doneBd.getInt32(LinuxUsbfsAbi.urbStatusOffset, Endian.host);
          if (ctx == 2) {
            if (status == 0) {
              init.mainPort.send(<Object>['write_ok', writeId]);
            } else {
              init.mainPort.send(<Object>['write_err', writeId, 'USB bulk OUT status=$status']);
            }
            return;
          } else if (ctx == 1) {
            inFlight = false;
            final actual = doneBd.getInt32(LinuxUsbfsAbi.urbActualLengthOffset, Endian.host);
            if (status == 0 && actual > 0) {
              init.mainPort.send(Uint8List.fromList(inBuf.asTypedList(actual)));
            }
          }
        } else {
          final err = libc.errno;
          if (err == LinuxUsbfsAbi.enodev) {
            stopRequested = true;
            init.mainPort.send(<Object>['write_err', writeId, 'USB device detached (ENODEV)']);
            return;
          }
          sleep(const Duration(milliseconds: 2));
        }
      }
      libc.ioctl(init.fd, LinuxUsbfsAbi.ioctlDiscardUrb, outUrb.cast<Void>());
      init.mainPort.send(<Object>['write_err', writeId, 'USB bulk OUT timed out']);
    } finally {
      libc.free(outBuf.cast<Void>());
    }
  }

  try {
    if (!submitInUrb()) {
      stopRequested = true;
    }

    final pollBd = ByteData.sublistView(pollFds.asTypedList(2 * LinuxUsbfsAbi.sizeofPollFd));
    while (!stopRequested) {
      if (!inFlight && !submitInUrb()) {
        break;
      }

      // pollfd[0] = usbfs fd (POLLOUT signals reaped URB in Linux usbfs)
      pollBd.setInt32(LinuxUsbfsAbi.pollFdOffset, init.fd, Endian.host);
      pollBd.setInt16(LinuxUsbfsAbi.pollEventsOffset, LinuxUsbfsAbi.pollOut | LinuxUsbfsAbi.pollErr | LinuxUsbfsAbi.pollHup, Endian.host);
      pollBd.setInt16(LinuxUsbfsAbi.pollReventsOffset, 0, Endian.host);

      // pollfd[1] = eventfd (wakes immediately on outgoing command or close)
      final p1 = LinuxUsbfsAbi.sizeofPollFd;
      pollBd.setInt32(p1 + LinuxUsbfsAbi.pollFdOffset, init.wakeFd, Endian.host);
      pollBd.setInt16(p1 + LinuxUsbfsAbi.pollEventsOffset, LinuxUsbfsAbi.pollIn, Endian.host);
      pollBd.setInt16(p1 + LinuxUsbfsAbi.pollReventsOffset, 0, Endian.host);

      final prc = libc.poll(pollFds.cast<Void>(), 2, 100);
      if (prc < 0) {
        if (libc.errno == LinuxUsbfsAbi.eintr) continue;
        break;
      }

      // Drain eventfd counter if woken.
      final wakeRevents = pollBd.getInt16(p1 + LinuxUsbfsAbi.pollReventsOffset, Endian.host);
      if ((wakeRevents & LinuxUsbfsAbi.pollIn) != 0) {
        libc.read(init.wakeFd, drainBuf, 8);
      }

      // Drain queued commands from main isolate.
      while (pendingWrites.isNotEmpty && !stopRequested) {
        final (writeId, data) = pendingWrites.removeAt(0);
        runSyncOut(writeId, data);
      }
      if (stopRequested) break;

      // Reap completed IN URB if available.
      final usbRevents = pollBd.getInt16(LinuxUsbfsAbi.pollReventsOffset, Endian.host);
      if ((usbRevents & (LinuxUsbfsAbi.pollOut | LinuxUsbfsAbi.pollErr | LinuxUsbfsAbi.pollHup)) != 0) {
        final reapRc = libc.ioctl(init.fd, LinuxUsbfsAbi.ioctlReapUrbNdelay, reapedPtr.cast<Void>());
        if (reapRc == 0) {
          inFlight = false;
          final doneUrb = reapedPtr.value.cast<Uint8>();
          final doneBd = ByteData.sublistView(doneUrb.asTypedList(LinuxUsbfsAbi.sizeofUrb));
          final status = doneBd.getInt32(LinuxUsbfsAbi.urbStatusOffset, Endian.host);
          final actual = doneBd.getInt32(LinuxUsbfsAbi.urbActualLengthOffset, Endian.host);
          if (status == 0) {
            if (actual > 0) {
              init.mainPort.send(Uint8List.fromList(inBuf.asTypedList(actual)));
            }
          } else if (status == -LinuxUsbfsAbi.enodev || status == -LinuxUsbfsAbi.enoent) {
            break;
          }
        } else {
          final err = libc.errno;
          if (err == LinuxUsbfsAbi.enodev) break;
        }
      }
    }
  } finally {
    if (inFlight) {
      libc.ioctl(init.fd, LinuxUsbfsAbi.ioctlDiscardUrb, inUrb.cast<Void>());
    }
    final ifacePtr = libc.calloc(1, 4).cast<Uint32>();
    try {
      ifacePtr.value = init.interfaceNumber;
      libc.ioctl(init.fd, LinuxUsbfsAbi.ioctlReleaseInterface, ifacePtr.cast<Void>());
    } finally {
      libc.free(ifacePtr.cast<Void>());
    }
    libc.close(init.fd);
    libc.close(init.wakeFd);
    libc.free(inBuf.cast<Void>());
    libc.free(inUrb.cast<Void>());
    libc.free(outUrb.cast<Void>());
    libc.free(reapedPtr.cast<Void>());
    libc.free(pollFds.cast<Void>());
    libc.free(drainBuf);
    commandPort.close();
    init.mainPort.send(<Object>['closed']);
  }
}
