// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/crc.dart';
import '../protocol/packet.dart';
import '../protocol/state.dart';
import '../transport/usb_transport.dart';

/// Configuration for a simulated transmitter slot.
class SimulatedTxConfig {
  const SimulatedTxConfig({
    required this.serial,
    this.firmware = const Firmware(2, 3, 17, 0),
    this.productName = 'DJI Mic Mini',
    this.voiceTone = 'standard',
    this.battery = 2,
    this.charging = false,
    this.level = 36,
  });

  final String serial;
  final Firmware firmware;
  final String productName;
  final String voiceTone;
  final int battery;
  final bool charging;
  final int level;
}

class SimulatedTxState {
  SimulatedTxState(SimulatedTxConfig c)
      : serial = c.serial,
        firmware = c.firmware,
        productName = c.productName,
        voiceTone = c.voiceTone,
        battery = c.battery,
        charging = c.charging,
        level = c.level;

  String serial;
  Firmware firmware;
  String productName;
  String voiceTone;
  int battery;
  bool charging;
  int level;
}

/// Byte-level simulator speaking real DUML v1/v2 packets for DJI Mic Mini.
class SimulatedDjiMic {
  SimulatedDjiMic({
    required this.serial,
    this.busNumber = 1,
    this.deviceAddress = 7,
    this.dialect = Dialect.v2,
    this.rxFirmware = const Firmware(2, 3, 17, 0),
    this.rxProductName = 'DJI Mic Mini',
    this.gainDial = 0,
    this.monitoringGain = 0,
    SimulatedTxConfig? tx1,
    SimulatedTxConfig? tx2,
    this.permissionDenied = false,
    this.attached = true,
    this.failWrites = false,
  }) {
    tx[0] = tx1 != null ? SimulatedTxState(tx1) : null;
    tx[1] = tx2 != null ? SimulatedTxState(tx2) : null;
  }

  final String serial;
  final int busNumber;
  int deviceAddress;
  Dialect dialect;
  Firmware rxFirmware;
  String rxProductName;
  int gainDial;
  int monitoringGain;
  final List<SimulatedTxState?> tx = <SimulatedTxState?>[null, null];

  bool permissionDenied;
  bool attached;
  bool failWrites;

  // Controllable hardware state.
  bool ncEnabled = true;
  bool ncStrong = true;
  bool ncButton = true;
  bool lowCut = false;
  bool stereo = false;
  bool safetyTrack = false;
  bool clipLimiter = true;
  bool autoOffRx = true;
  bool autoOffTx = true;
  bool cameraPower = false;
  bool plugFree = false;
  bool micLedsOn = true;

  _SimulatedHandle? _activeHandle;

  UsbDeviceInfo get deviceInfo => UsbDeviceInfo(
        id: 'usb-$busNumber-$deviceAddress',
        busNumber: busNumber,
        deviceAddress: deviceAddress,
        vendorId: 0x2ca3,
        productId: 0x4011,
        serial: serial,
        devicePath: '/dev/bus/usb/${busNumber.toString().padLeft(3, '0')}/${deviceAddress.toString().padLeft(3, '0')}',
      );

  /// Emit a full heartbeat cycle (status + identity + levels on v2, or monolithic on v1).
  void emitAll() {
    final handle = _activeHandle;
    if (handle == null || handle.isClosed) return;
    if (dialect == Dialect.v1) {
      handle.push(buildV1Heartbeat());
    } else {
      handle.push(buildV2StatusPush());
      handle.push(buildV2IdentityPush());
      handle.push(buildV2LevelPush());
    }
  }

  void emitStatusAndLevels() {
    final handle = _activeHandle;
    if (handle == null || handle.isClosed) return;
    if (dialect == Dialect.v1) {
      handle.push(buildV1Heartbeat());
    } else {
      handle.push(buildV2StatusPush());
      handle.push(buildV2LevelPush());
    }
  }

  void unplug() {
    attached = false;
    _activeHandle?.closeFromDevice();
  }

  void replug() {
    deviceAddress++;
    attached = true;
  }

  Uint8List buildV1Heartbeat() {
    final bytes = <int>[
      0x55, 0x00, 0x04, 0xf6, 0x5a, 0x02, 0x01, 0x00, 0x00, 0x5b, 0x03, 0x00, 0x47, 0x00,
    ];
    final txState = (ncStrong ? 0x20 : 0x00) | (lowCut ? 0x04 : 0x00);
    final baseFlags = ncEnabled ? 0x01 : 0x00;

    for (var i = 0; i < 2; i++) {
      final slot = tx[i];
      if (slot != null) {
        bytes.addAll(<int>[
          txState,
          baseFlags | 0x20,
          slot.level & 0xff,
          micLedsOn ? 0x00 : 0x80,
          slot.firmware.a,
          slot.firmware.b,
          slot.firmware.c,
          slot.firmware.d,
          0x0e,
          ..._fixedAscii(slot.serial, 14),
        ]);
      } else {
        bytes.addAll(<int>[txState, baseFlags | 0x40, 0, 0, 0, 0, 0, 0, 0]);
      }
    }

    final rxFlags0 = (cameraPower ? 0x01 : 0x00) |
        (autoOffRx ? 0x02 : 0x00) |
        (stereo ? 0x08 : 0x00);
    final rxFlags1 = (safetyTrack ? 0x80 : 0x00) | (clipLimiter ? 0x20 : 0x00);
    bytes.addAll(<int>[
      rxFlags0,
      rxFlags1,
      rxFirmware.a,
      rxFirmware.b,
      rxFirmware.c,
      rxFirmware.d,
      0x0e,
      ..._fixedAscii(serial, 14),
      plugFree ? 0x01 : 0x00,
    ]);
    bytes[1] = bytes.length + 2;
    return DjiCrc16.append(bytes, DjiCrc16.v1Init, DjiCrc16.v1Residue);
  }

  Uint8List buildV2StatusPush() {
    final presentIndices = <int>[
      for (var i = 0; i < 2; i++)
        if (tx[i] != null) i,
    ];
    final totalLen = 52 + 32 * presentIndices.length + 2;
    final body = Uint8List(totalLen - 2);
    body[0] = 0x55;
    body[1] = totalLen;
    body[2] = 0x04;
    body[3] = 0xa6;
    body[4] = 0x5a;
    body[5] = 0x02;
    body[8] = 0x00;
    body[9] = 0x5b;
    body[10] = 0x03;
    body[11] = 0x03;
    body[12] = switch (presentIndices.length) {
      0 => 0x26,
      1 => 0x46,
      _ => 0x66,
    };

    body[20] = (ncStrong ? 0x08 : 0x00) |
        (ncEnabled ? 0x20 : 0x00) |
        (cameraPower ? 0x80 : 0x00);
    body[21] = (autoOffRx ? 0x01 : 0x00) | (stereo ? 0x04 : 0x00);
    body[22] = gainDial & 0xff;
    body[27] = monitoringGain & 0xff;
    body[44] = (tx[0] != null ? 0x01 : 0x00) | (tx[1] != null ? 0x02 : 0x00);
    body[48] = (plugFree ? 0x02 : 0x00) |
        (clipLimiter ? 0x10 : 0x00) |
        (safetyTrack ? 0x40 : 0x00);

    for (var pos = 0; pos < presentIndices.length; pos++) {
      final idx = presentIndices[pos];
      final slot = tx[idx]!;
      final off = 52 + pos * 32;
      body[off] = 0x02;
      body[off + 1] = idx + 1;
      body[off + 5] = 0x1a;
      body[off + 6] = (micLedsOn ? 0x00 : 0x02) |
          (autoOffTx ? 0x10 : 0x00) |
          (ncStrong ? 0x20 : 0x00) |
          (ncButton ? 0x80 : 0x00);
      body[off + 7] = (ncEnabled ? 0x01 : 0x00) |
          (slot.charging ? 0x02 : 0x00) |
          ((slot.battery & 0x07) << 2) |
          0x20;
      body[off + 8] = clipLimiter ? 0x04 : 0x00;
      final toneBits = switch (slot.voiceTone) {
        'bright' => 0x80,
        'rich' => 0x40,
        _ => 0x00,
      };
      body[off + 9] = (lowCut ? 0x20 : 0x00) | toneBits | 0x01;
      body[off + 11] = 0x78;
    }

    return DjiCrc16.append(body, DjiCrc16.v2Init, DjiCrc16.v2Residue);
  }

  Uint8List buildV2IdentityPush() {
    final records = <int>[];
    void addUnit(int unitIndex, Firmware fw, String ser, String prodName) {
      final serBytes = _fixedAscii(ser, 14);
      records.addAll(<int>[
        0x01, unitIndex, 0, 0, 0, 4 + serBytes.length,
        fw.d, fw.c, fw.b, fw.a,
        ...serBytes,
      ]);
      final nameBytes = utf8.encode(prodName);
      records.addAll(<int>[
        0x06, unitIndex, 0, 0, 0, nameBytes.length,
        ...nameBytes,
      ]);
    }

    addUnit(0, rxFirmware, serial, rxProductName);
    for (var i = 0; i < 2; i++) {
      final slot = tx[i];
      if (slot != null) {
        addUnit(i + 1, slot.firmware, slot.serial, slot.productName);
      }
    }

    final totalLen = 14 + records.length + 2;
    final body = <int>[
      0x55, totalLen, 0x04, 0x29, 0x5a, 0x02, 0x00, 0x00, 0x00, 0x5b, 0x03, 0x03,
      records.length & 0xff, (records.length >> 8) & 0xff,
      ...records,
    ];
    return DjiCrc16.append(body, DjiCrc16.v2Init, DjiCrc16.v2Residue);
  }

  Uint8List buildV2LevelPush() {
    final records = <int>[];
    for (var i = 0; i < 2; i++) {
      final slot = tx[i];
      if (slot != null) {
        records.addAll(<int>[0x05, i + 1, 0, 0, 0, 0x01, slot.level & 0xff]);
      }
    }
    final totalLen = 14 + records.length + 2;
    final body = <int>[
      0x55, totalLen, 0x04, 0x8a, 0x5a, 0x02, 0x00, 0x00, 0x00, 0x5b, 0x03, 0x03,
      records.length & 0xff, (records.length >> 8) & 0xff,
      ...records,
    ];
    return DjiCrc16.append(body, DjiCrc16.v2Init, DjiCrc16.v2Residue);
  }

  void _handleIncomingCommand(Uint8List packet) {
    if (failWrites) {
      throw const UsbException('Simulated USB bulk OUT failure');
    }
    if (!DjiCrc16.verify(packet, dialect.crcInit, dialect.crcResidue)) {
      throw const UsbException('Invalid CRC-16 on outgoing command');
    }

    final seq = packet[6] | (packet[7] << 8);
    var triggerReboot = false;

    if (dialect == Dialect.v1 && packet.length == DumlPacket.v1CommandLen) {
      final cmd = (packet[12] << 8) | packet[13];
      final val = packet[16];
      triggerReboot = _applyV1Command(cmd, val);
    } else if (dialect == Dialect.v2 && packet.length == DumlPacket.v2CommandLen) {
      final target = packet[12] | (packet[13] << 8);
      final cmd = packet[16] | (packet[17] << 8);
      final val = packet[19];
      triggerReboot = _applyV2Command(target, cmd, val);
    } else {
      throw const UsbException('Unexpected command length for active dialect');
    }

    final handle = _activeHandle;
    if (handle != null && !handle.isClosed) {
      handle.push(DumlPacket.buildAck(seq, dialect));
      if (triggerReboot) {
        // Real hardware drops off USB and re-enumerates after plug-free toggle.
        deviceAddress++;
        handle.closeFromDevice();
      } else {
        emitStatusAndLevels();
      }
    }
  }

  bool _applyV1Command(int cmd, int val) {
    switch (cmd) {
      case 0x031d:
        ncStrong = val == 0x01;
      case 0x0303:
        lowCut = val == 0x01;
      case 0x0008:
        stereo = val == 0x02;
        if (stereo) safetyTrack = false;
      case 0x0021:
        safetyTrack = val == 0x01;
        if (safetyTrack) stereo = false;
      case 0x001e:
        clipLimiter = val == 0x01;
      case 0x0010:
        autoOffRx = val == 0x01;
      case 0x0020:
        cameraPower = val == 0x01;
      case 0x0023:
        plugFree = val == 0x01;
        return true;
      case 0x030a:
        micLedsOn = val == 0x00;
    }
    return false;
  }

  bool _applyV2Command(int target, int cmd, int val) {
    switch (cmd) {
      case 0x0037:
        ncStrong = val == 0x01;
      case 0x0038:
        ncEnabled = val == 0x01;
      case 0x000f:
        ncButton = val == 0x01;
      case 0x0003:
        lowCut = val == 0x01;
      case 0x0008:
        stereo = val == 0x02;
        if (stereo) safetyTrack = false;
      case 0x0021:
        safetyTrack = val == 0x01;
        if (safetyTrack) stereo = false;
      case 0x001e:
        clipLimiter = val == 0x01;
      case 0x0010:
        if (target == 0x0000) {
          autoOffRx = val == 0x01;
        } else {
          autoOffTx = val == 0x01;
        }
      case 0x0020:
        cameraPower = val == 0x01;
      case 0x0023:
        plugFree = val == 0x01;
        return true;
      case 0x000a:
        micLedsOn = val == 0x00;
      case 0x0029:
        final idx = target - 1;
        if (idx >= 0 && idx < 2 && tx[idx] != null) {
          tx[idx]!.voiceTone = switch (val) {
            0x01 => 'rich',
            0x02 => 'bright',
            _ => 'standard',
          };
        }
      case 0x0039:
        gainDial = val.toSigned(8);
      case 0x0026:
        monitoringGain = val.toSigned(8);
    }
    return false;
  }

  static List<int> _fixedAscii(String text, int length) {
    final raw = utf8.encode(text);
    final out = List<int>.filled(length, 0);
    for (var i = 0; i < length && i < raw.length; i++) {
      out[i] = raw[i];
    }
    return out;
  }
}

class _SimulatedHandle implements UsbDeviceHandle {
  _SimulatedHandle(this.mic);

  final SimulatedDjiMic mic;
  final StreamController<Uint8List> _controller = StreamController<Uint8List>.broadcast();
  bool isClosed = false;

  void push(Uint8List frame) {
    if (!isClosed && !_controller.isClosed) {
      _controller.add(frame);
    }
  }

  void closeFromDevice() {
    if (isClosed) return;
    isClosed = true;
    _controller.close();
  }

  @override
  Stream<Uint8List> get bulkInStream => _controller.stream;

  @override
  Future<void> bulkOut(Uint8List data) async {
    if (isClosed) {
      throw const UsbDisconnectedException('Simulated handle is closed');
    }
    mic._handleIncomingCommand(data);
  }

  @override
  Future<void> close() async {
    closeFromDevice();
  }
}

/// In-memory [UsbTransport] backed by one or more [SimulatedDjiMic] devices.
class SimulatedUsbTransport implements UsbTransport {
  SimulatedUsbTransport(
    this.mics, {
    this.autoTick = false,
    this.tickInterval = const Duration(milliseconds: 120),
  });

  final List<SimulatedDjiMic> mics;
  final bool autoTick;
  final Duration tickInterval;

  Timer? _timer;
  int _tick = 0;

  @override
  String get backendName => 'simulated';

  void _ensureTimer() {
    if (!autoTick || _timer != null) return;
    _timer = Timer.periodic(tickInterval, (_) {
      _tick++;
      for (final mic in mics) {
        if (!mic.attached || mic._activeHandle == null || mic._activeHandle!.isClosed) {
          continue;
        }
        // Animate synthetic live voice levels in demo mode.
        if (mic.tx[0] != null) {
          mic.tx[0]!.level = (28 + (sin(_tick * 0.45) * 20).round()).clamp(8, 78);
        }
        if (mic.tx[1] != null) {
          mic.tx[1]!.level = (36 + (cos(_tick * 0.35) * 26).round()).clamp(8, 78);
        }
        if (_tick % 10 == 1) {
          mic.emitAll();
        } else {
          mic.emitStatusAndLevels();
        }
      }
    });
  }

  @override
  Future<List<UsbDeviceInfo>> listDevices() async {
    return mics.where((m) => m.attached).map((m) => m.deviceInfo).toList();
  }

  @override
  Future<UsbDeviceHandle> open(
    UsbDeviceInfo device, {
    required int interfaceNumber,
    required int bulkInEndpoint,
    required int bulkOutEndpoint,
  }) async {
    final mic = mics.firstWhere(
      (m) => m.attached && m.deviceInfo.displayId == device.displayId,
      orElse: () => throw const UsbDisconnectedException('Simulated device not attached'),
    );
    if (mic.permissionDenied) {
      throw const UsbPermissionException('Permission denied (simulated EACCES)', errno: 13);
    }
    final handle = _SimulatedHandle(mic);
    mic._activeHandle = handle;
    if (autoTick) {
      scheduleMicrotask(mic.emitAll);
      _ensureTimer();
    }
    return handle;
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    for (final mic in mics) {
      mic._activeHandle?.closeFromDevice();
    }
  }
}

/// Ready-to-run demo fixture for `--dart-define=DEMO=true` or `--demo`.
class DemoFixture {
  DemoFixture._();

  static SimulatedUsbTransport createTransport() {
    final v2Rig = SimulatedDjiMic(
      serial: 'DJIMM24A001928',
      busNumber: 1,
      deviceAddress: 4,
      dialect: Dialect.v2,
      gainDial: 0,
      tx1: const SimulatedTxConfig(
        serial: 'DJITX1A0041122',
        productName: 'DJI Mic Mini',
        battery: 2,
        charging: false,
        level: 34,
      ),
      tx2: const SimulatedTxConfig(
        serial: 'DJITX2B0098877',
        productName: 'DJI Mic Mini 2',
        battery: 4,
        charging: true,
        voiceTone: 'rich',
        level: 48,
      ),
    );

    final v1Rig = SimulatedDjiMic(
      serial: 'DJIV1RX0007741',
      busNumber: 1,
      deviceAddress: 9,
      dialect: Dialect.v1,
      rxFirmware: const Firmware(1, 1, 0, 56),
      tx1: const SimulatedTxConfig(
        serial: 'DJIV1TX0007742',
        firmware: Firmware(1, 1, 0, 56),
        level: 28,
      ),
    );

    return SimulatedUsbTransport(<SimulatedDjiMic>[v2Rig, v1Rig], autoTick: true);
  }
}
