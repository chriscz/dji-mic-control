// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:typed_data';

/// Descriptor of a USB device discovered on the host bus.
class UsbDeviceInfo {
  const UsbDeviceInfo({
    required this.id,
    required this.busNumber,
    required this.deviceAddress,
    required this.vendorId,
    required this.productId,
    this.serial,
    this.devicePath,
  });

  final String id;
  final int busNumber;
  final int deviceAddress;
  final int vendorId;
  final int productId;
  final String? serial;
  final String? devicePath;

  String get displayId => (serial != null && serial!.isNotEmpty) ? serial! : id;
}

/// Base exception for USB transport errors.
class UsbException implements Exception {
  const UsbException(this.message, {this.errno});

  final String message;
  final int? errno;

  @override
  String toString() => errno != null ? 'UsbException($message, errno=$errno)' : 'UsbException($message)';
}

/// Thrown when the OS denies access to the USB device node (e.g. Linux EACCES).
class UsbPermissionException extends UsbException {
  const UsbPermissionException(super.message, {super.errno});
}

/// Thrown when the USB device disappears or a transfer fails because it detached.
class UsbDisconnectedException extends UsbException {
  const UsbDisconnectedException(super.message, {super.errno});
}

/// An open handle to a single claimed USB interface with bulk IN/OUT endpoints.
abstract class UsbDeviceHandle {
  /// Stream of raw byte chunks read from the bulk IN endpoint.
  /// Closes cleanly when the device disconnects or [close] is called.
  Stream<Uint8List> get bulkInStream;

  /// Write [data] to the bulk OUT endpoint.
  Future<void> bulkOut(Uint8List data);

  /// Release the interface and close the underlying handle.
  Future<void> close();
}

/// Narrow OS-agnostic USB transport seam.
///
/// Implemented by:
/// - [SimulatedUsbTransport] (tests and demo mode)
/// - [LinuxUsbfsTransport] (pure Dart Linux sysfs + usbfs ioctls)
/// - [RustNusbTransport] (Phase 6 thin Rust nusb cdylib over dart:ffi)
abstract class UsbTransport {
  String get backendName;

  Future<List<UsbDeviceInfo>> listDevices();

  Future<UsbDeviceHandle> open(
    UsbDeviceInfo device, {
    required int interfaceNumber,
    required int bulkInEndpoint,
    required int bulkOutEndpoint,
  });

  Future<void> dispose();
}
