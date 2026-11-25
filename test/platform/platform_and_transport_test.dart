// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:io';

import 'package:dji_mic_control/platform/autostart_service.dart';
import 'package:dji_mic_control/platform/capabilities.dart';
import 'package:dji_mic_control/platform/config_store.dart';
import 'package:dji_mic_control/platform/dbus/dbus_wire.dart';
import 'package:dji_mic_control/platform/single_instance.dart';
import 'package:dji_mic_control/transport/linux_usbfs_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConfigStore', () {
    test('persists and reloads AppConfig atomically in temp directory', () async {
      final tmp = await Directory.systemTemp.createTemp('dji_mic_cfg_');
      addTearDown(() => tmp.delete(recursive: true));

      final store = ConfigStore(configFile: File('${tmp.path}/config.json'));
      final defaults = await store.load();
      expect(defaults.viewMode, ViewMode.compact);
      expect(defaults.closeToTray, isTrue);
      expect(defaults.showDiagnosticsFold, isTrue);

      final updated = defaults.copyWith(
        viewMode: ViewMode.list,
        themeMode: AppThemePreference.dark,
        notifyCriticalBattery: false,
        closeToTray: false,
      );
      await store.save(updated);

      final reloaded = await store.load();
      expect(reloaded.viewMode, ViewMode.list);
      expect(reloaded.themeMode, AppThemePreference.dark);
      expect(reloaded.notifyCriticalBattery, isFalse);
      expect(reloaded.closeToTray, isFalse);
    });
  });

  group('AutostartService', () {
    test('creates and removes Linux XDG .desktop entry with --hidden', () async {
      final tmp = await Directory.systemTemp.createTemp('dji_mic_auto_');
      addTearDown(() => tmp.delete(recursive: true));

      final svc = AutostartService(
        osName: 'linux',
        autostartDir: tmp,
        executablePath: '/opt/dji-mic-control/dji_mic_control',
      );
      expect(await svc.isEnabled(), isFalse);

      await svc.setEnabled(true);
      expect(await svc.isEnabled(), isTrue);
      final file = File('${tmp.path}/dji-mic-control.desktop');
      final text = await file.readAsString();
      expect(text, contains('Exec="/opt/dji-mic-control/dji_mic_control" --hidden'));
      expect(text, contains('X-GNOME-Autostart-enabled=true'));

      await svc.setEnabled(false);
      expect(await svc.isEnabled(), isFalse);
    });
  });

  group('SingleInstance', () {
    test('hands off show command from secondary launch to primary instance', () async {
      final tmp = await Directory.systemTemp.createTemp('dji_mic_sock_');
      addTearDown(() => tmp.delete(recursive: true));
      final sockPath = '${tmp.path}/app.sock';

      var showCount = 0;
      final primary = SingleInstance(socketPath: sockPath);
      final isPrimary = await primary.acquire(onActivate: () => showCount++);
      expect(isPrimary, isTrue);

      final secondary = SingleInstance(socketPath: sockPath);
      final secondaryIsPrimary = await secondary.acquire(onActivate: () {});
      expect(secondaryIsPrimary, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(showCount, 1);

      await primary.dispose();
    });
  });

  group('CapabilitiesProbe & UdevHelper', () {
    test('generates distro-specific install hints when notify-send and tray are missing', () async {
      final probe = CapabilitiesProbe(
        osName: 'linux',
        commandExists: (cmd) async => false,
        fileExists: (path) async => false,
        readFile: (path) async => 'ID=ubuntu\nID_LIKE=debian\n',
        dbusTrayAvailable: () async => false,
        dbusNotifyAvailable: () async => false,
      );

      final snap = await probe.inspect(usbPermissionIssue: true);
      expect(snap.usb.status, CapabilityStatus.needsSetup);
      expect(snap.usb.copyableSnippet, contains('ATTRS{idVendor}=="2ca3"'));
      expect(snap.notifications.status, CapabilityStatus.needsSetup);
      expect(snap.notifications.copyableCommand, contains('apt install libnotify-bin'));
      expect(snap.tray.status, CapabilityStatus.needsSetup);
      expect(snap.tray.osHint, contains('AppIndicator'));
    });

    test('distinguishes installed udev rule needing replug on Linux', () async {
      final probe = CapabilitiesProbe(
        osName: 'linux',
        commandExists: (cmd) async => cmd == 'notify-send',
        fileExists: (path) async => path == '/etc/udev/rules.d/60-dji-mic.rules',
        readFile: (path) async => 'ID=fedora\n',
        dbusTrayAvailable: () async => true,
        dbusNotifyAvailable: () async => true,
      );

      final snap = await probe.inspect(usbPermissionIssue: true);
      expect(snap.usb.summary, contains('replug'));
      expect(snap.notifications.status, CapabilityStatus.active);
      expect(snap.tray.status, CapabilityStatus.active);
    });

    test('produces Zadig Interface 6 guidance on Windows', () async {
      final probe = CapabilitiesProbe(
        osName: 'windows',
        commandExists: (_) async => false,
        fileExists: (_) async => false,
        readFile: (_) async => null,
        dbusTrayAvailable: () async => false,
        dbusNotifyAvailable: () async => false,
      );

      final snap = await probe.inspect(usbPermissionIssue: true);
      expect(snap.usb.osHint, contains('Zadig'));
      expect(snap.usb.osHint, contains('Interface 6'));
    });
  });

  group('LinuxSysfsScanner & Usbfs ABI', () {
    test('scans fake sysfs tree and finds DJI Mic Mini matching 2ca3:4011', () async {
      final tmp = await Directory.systemTemp.createTemp('dji_sysfs_');
      addTearDown(() => tmp.delete(recursive: true));

      final devDir = await Directory('${tmp.path}/1-2').create();
      await File('${devDir.path}/idVendor').writeAsString('2ca3\n');
      await File('${devDir.path}/idProduct').writeAsString('4011\n');
      await File('${devDir.path}/busnum').writeAsString('1\n');
      await File('${devDir.path}/devnum').writeAsString('14\n');
      await File('${devDir.path}/serial').writeAsString('SERIAL12345678\n');

      final otherDir = await Directory('${tmp.path}/1-3').create();
      await File('${otherDir.path}/idVendor').writeAsString('1d6b\n');
      await File('${otherDir.path}/idProduct').writeAsString('0002\n');
      await File('${otherDir.path}/busnum').writeAsString('1\n');
      await File('${otherDir.path}/devnum').writeAsString('1\n');

      final devices = await LinuxSysfsScanner.scan(sysfsRoot: tmp.path);
      expect(devices, hasLength(2));
      final mic = devices.firstWhere((d) => d.vendorId == 0x2ca3 && d.productId == 0x4011);
      expect(mic.busNumber, 1);
      expect(mic.deviceAddress, 14);
      expect(mic.serial, 'SERIAL12345678');
      expect(mic.devicePath, '/dev/bus/usb/001/014');
    });

    test('usbfs ABI constants match x86_64 kernel headers', () {
      expect(LinuxUsbfsAbi.sizeofBulkTransfer, 24);
      expect(LinuxUsbfsAbi.bulkDataOffset, 16);
      expect(LinuxUsbfsAbi.ioctlBulk, 0xc0185502);
      expect(LinuxUsbfsAbi.sizeofDisconnectClaim, 264);
      expect(LinuxUsbfsAbi.sizeofUrb, 56);
      expect(LinuxUsbfsAbi.sizeofPollFd, 8);
      expect(LinuxUsbfsAbi.ioctlDisconnectClaim, 0x8108551b);
      expect(LinuxUsbfsAbi.ioctlSubmitUrb, 0x8038550a);
      expect(LinuxUsbfsAbi.ioctlDiscardUrb, 0x550b);
      expect(LinuxUsbfsAbi.ioctlReapUrbNdelay, 0x4008550d);
    });
  });

  group('DbusWire', () {
    test('encodes and decodes a D-Bus method call and boolean reply', () {
      final msg = DbusMessage.methodCall(
        serial: 1,
        destination: 'org.freedesktop.DBus',
        path: '/org/freedesktop/DBus',
        interfaceName: 'org.freedesktop.DBus',
        member: 'NameHasOwner',
        signature: 's',
        body: DbusWriter()..writeString('org.kde.StatusNotifierWatcher'),
      );
      final bytes = msg.encode();
      final decoded = DbusMessage.tryDecode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.consumedBytes, bytes.length);
      expect(decoded.message.type, DbusMessageType.methodCall);
      expect(decoded.message.serial, 1);
      expect(decoded.message.member, 'NameHasOwner');
      final reader = DbusReader(decoded.message.body);
      expect(reader.readString(), 'org.kde.StatusNotifierWatcher');
    });
  });
}
