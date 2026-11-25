// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:io';

import 'package:dji_mic_control/transport/nusb_ffi_transport.dart';
import 'package:dji_mic_control/transport/usb_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NusbFfiTransport', () {
    test('returns null cleanly when explicit library path does not exist', () {
      expect(NusbFfiTransport.tryLoad(explicitPath: '/nonexistent/libdji_mic_usb.so'), isNull);
    });

    test('loads compiled libdji_mic_usb.so and enumerates USB bus via dart:ffi', () async {
      final libFile = File('native/dji_mic_usb/target/release/${NusbFfiTransport.defaultLibraryFileName}');
      if (!libFile.existsSync()) {
        // Skip only if native cdylib was not compiled yet.
        return;
      }

      final transport = NusbFfiTransport.tryLoad(explicitPath: libFile.path);
      expect(transport, isNotNull);
      expect(transport!.backendName, 'nusb-cdylib (Rust FFI)');

      final devices = await transport.listDevices();
      expect(devices, isA<List<UsbDeviceInfo>>());

      // Opening a non-existent bus/address returns UsbDisconnectedException cleanly.
      await expectLater(
        () => transport.open(
          const UsbDeviceInfo(
            id: 'usb-255-255',
            busNumber: 255,
            deviceAddress: 255,
            vendorId: 0x2ca3,
            productId: 0x4011,
          ),
          interfaceNumber: 6,
          bulkInEndpoint: 0x86,
          bulkOutEndpoint: 0x06,
        ),
        throwsA(isA<UsbDisconnectedException>()),
      );

      await transport.dispose();
    });
  });
}
