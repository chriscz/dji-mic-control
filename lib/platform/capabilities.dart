// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:io';

import '../protocol/device_model.dart';
import 'dbus/dbus_wire.dart';

enum CapabilityStatus {
  active,
  available,
  needsSetup,
  unsupported,
}

/// Status and actionable OS-specific remediation hint for one desktop feature.
class CapabilityReport {
  const CapabilityReport({
    required this.id,
    required this.title,
    required this.status,
    required this.summary,
    required this.osHint,
    this.copyableCommand,
    this.copyableSnippet,
    this.snippetHeader,
    this.steps = const <String>[],
  });

  final String id;
  final String title;
  final CapabilityStatus status;
  final String summary;
  final String osHint;
  final String? copyableCommand;
  final String? copyableSnippet;
  final String? snippetHeader;
  final List<String> steps;
}

/// Complete runtime inspection of optional OS integrations.
class OsCapabilitiesSnapshot {
  const OsCapabilitiesSnapshot({
    required this.osName,
    this.distroId,
    required this.udevRuleInstalled,
    required this.usb,
    required this.notifications,
    required this.tray,
    required this.autostart,
  });

  final String osName;
  final String? distroId;
  final bool udevRuleInstalled;
  final CapabilityReport usb;
  final CapabilityReport notifications;
  final CapabilityReport tray;
  final CapabilityReport autostart;

  List<CapabilityReport> get all => <CapabilityReport>[usb, notifications, tray, autostart];
}

/// Generates OS-specific USB access rules and step-by-step setup instructions.
class UdevHelper {
  UdevHelper._();

  static const String rulePath = '/etc/udev/rules.d/60-dji-mic.rules';
  static const String packagedRulePath = '/usr/lib/udev/rules.d/60-dji-mic.rules';

  static String generateLinuxUdevRule() {
    final lines = <String>[
      '# DJI wireless microphones: allow desktop users to access the control interface.',
    ];
    for (final model in DeviceModelRegistry.models) {
      for (final usb in model.usbIds) {
        lines.add(
          'SUBSYSTEM=="usb", ATTRS{idVendor}=="${usb.vidHex}", ATTRS{idProduct}=="${usb.pidHex}", MODE="0660", TAG+="uaccess"',
        );
      }
    }
    return '${lines.join('\n')}\n';
  }

  static String installCommand() {
    final rule = generateLinuxUdevRule().trimRight();
    return "printf '%s\\n' '$rule' | sudo tee $rulePath >/dev/null && sudo udevadm control --reload-rules && sudo udevadm trigger --action=add --subsystem-match=usb --attr-match=idVendor=2ca3";
  }
}

/// Probes optional OS libraries, binaries, and desktop services at runtime so
/// the Flutter binary never hard-links OS-specific libraries.
class CapabilitiesProbe {
  CapabilitiesProbe({
    String? osName,
    Future<bool> Function(String command)? commandExists,
    Future<bool> Function(String path)? fileExists,
    Future<String?> Function(String path)? readFile,
    Future<bool> Function()? dbusTrayAvailable,
    Future<bool> Function()? dbusNotifyAvailable,
  })  : _osName = osName ?? Platform.operatingSystem,
        _commandExists = commandExists ?? _defaultCommandExists,
        _fileExists = fileExists ?? ((p) => File(p).exists()),
        _readFile = readFile ?? _defaultReadFile,
        _dbusTrayAvailable = dbusTrayAvailable ?? _defaultDbusTrayAvailable,
        _dbusNotifyAvailable = dbusNotifyAvailable ?? _defaultDbusNotifyAvailable;

  final String _osName;
  final Future<bool> Function(String command) _commandExists;
  final Future<bool> Function(String path) _fileExists;
  final Future<String?> Function(String path) _readFile;
  final Future<bool> Function() _dbusTrayAvailable;
  final Future<bool> Function() _dbusNotifyAvailable;

  Future<OsCapabilitiesSnapshot> inspect({bool usbPermissionIssue = false}) async {
    final distro = _osName == 'linux' ? await _detectLinuxDistro() : null;
    final hasRule = _osName == 'linux' &&
        (await _fileExists(UdevHelper.rulePath) || await _fileExists(UdevHelper.packagedRulePath));
    final usb = await _inspectUsb(usbPermissionIssue: usbPermissionIssue, hasRule: hasRule);
    final notifications = await _inspectNotifications(distro);
    final tray = await _inspectTray(distro);
    final autostart = _inspectAutostart();

    return OsCapabilitiesSnapshot(
      osName: _osName,
      distroId: distro,
      udevRuleInstalled: hasRule,
      usb: usb,
      notifications: notifications,
      tray: tray,
      autostart: autostart,
    );
  }

  Future<String?> _detectLinuxDistro() async {
    final content = await _readFile('/etc/os-release');
    if (content == null) return null;
    String? id;
    String? idLike;
    for (final line in content.split('\n')) {
      if (line.startsWith('ID=')) {
        id = line.substring(3).replaceAll('"', '').trim().toLowerCase();
      } else if (line.startsWith('ID_LIKE=')) {
        idLike = line.substring(8).replaceAll('"', '').trim().toLowerCase();
      }
    }
    return id ?? idLike;
  }

  Future<CapabilityReport> _inspectUsb({
    required bool usbPermissionIssue,
    required bool hasRule,
  }) async {
    if (_osName == 'linux') {
      final rule = UdevHelper.generateLinuxUdevRule();
      final cmd = UdevHelper.installCommand();
      if (usbPermissionIssue) {
        if (hasRule) {
          return CapabilityReport(
            id: 'usb',
            title: 'USB Device Access',
            status: CapabilityStatus.needsSetup,
            summary: 'A udev rule is installed, but the receiver still returned permission denied. Unplug and replug the receiver (or trigger udev).',
            osHint: 'Reload udev rules and replug the DJI Mic receiver so the new USB permissions take effect.',
            copyableCommand: 'sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=usb',
            copyableSnippet: rule,
            snippetHeader: UdevHelper.rulePath,
            steps: const <String>[
              'Run the udevadm trigger command below (or unplug and replug the USB receiver).',
              'Wait a second for the receiver to appear automatically in the sidebar.',
            ],
          );
        }
        return CapabilityReport(
          id: 'usb',
          title: 'USB Device Access',
          status: CapabilityStatus.needsSetup,
          summary: 'A DJI microphone was detected on USB, but your user does not have permission to open /dev/bus/usb.',
          osHint: 'Install the udev rule below so your desktop session can control Interface 6 without root.',
          copyableCommand: cmd,
          copyableSnippet: rule,
          snippetHeader: UdevHelper.rulePath,
          steps: const <String>[
            'Save the rule below to /etc/udev/rules.d/60-dji-mic.rules (or run the one-line command).',
            'Reload udev rules with: sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=usb',
            'Unplug and replug the DJI Mic receiver if it does not appear immediately.',
          ],
        );
      }
      return CapabilityReport(
        id: 'usb',
        title: 'USB Device Access',
        status: hasRule ? CapabilityStatus.active : CapabilityStatus.available,
        summary: hasRule
            ? 'Pure-Dart Linux usbfs ready; DJI udev rule is installed.'
            : 'Pure-Dart Linux usbfs ready; install the udev rule if your receiver reports permission denied.',
        osHint: 'Uses Linux /sys/bus/usb and /dev/bus/usb directly with zero external USB libraries.',
        copyableCommand: cmd,
        copyableSnippet: rule,
        snippetHeader: UdevHelper.rulePath,
        steps: const <String>[
          'Save the rule below to /etc/udev/rules.d/60-dji-mic.rules.',
          'Run: sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=usb',
          'Unplug and replug the DJI Mic receiver.',
        ],
      );
    }

    if (_osName == 'windows') {
      return CapabilityReport(
        id: 'usb',
        title: 'USB Device Access (Windows)',
        status: usbPermissionIssue ? CapabilityStatus.needsSetup : CapabilityStatus.available,
        summary: 'Windows binds Interface 6 to the HID driver by default; WinUSB is required for control traffic.',
        osHint: 'Use Zadig to replace the driver for Interface 6 ONLY with WinUSB. Leave the USB Audio interfaces untouched.',
        steps: const <String>[
          'Download and open Zadig as Administrator.',
          'Enable Options -> List All Devices.',
          'Select DJI Mic Mini (Interface 6) only, choose WinUSB, and click Replace Driver.',
          'Unplug and replug the receiver.',
        ],
      );
    }

    return const CapabilityReport(
      id: 'usb',
      title: 'USB Device Access (macOS)',
      status: CapabilityStatus.available,
      summary: 'macOS accesses Interface 6 via IOKit without replacing drivers.',
      osHint: 'If macOS quarantines an unsigned build, run: xattr -rd com.apple.quarantine "DJI Mic Control.app"',
      copyableCommand: 'xattr -rd com.apple.quarantine "DJI Mic Control.app"',
    );
  }

  Future<CapabilityReport> _inspectNotifications(String? distro) async {
    if (_osName == 'linux') {
      final hasNotifySend = await _commandExists('notify-send');
      final hasDbusNotify = await _dbusNotifyAvailable();
      if (hasNotifySend || hasDbusNotify) {
        final via = hasNotifySend ? 'notify-send' : 'session D-Bus (org.freedesktop.Notifications)';
        return CapabilityReport(
          id: 'notifications',
          title: 'Desktop Notifications',
          status: CapabilityStatus.active,
          summary: 'Available via $via. Critical battery and optional disconnect alerts are enabled.',
          osHint: 'No linked notification libraries are required.',
        );
      }
      final installCmd = _linuxNotifyInstallCommand(distro);
      return CapabilityReport(
        id: 'notifications',
        title: 'Desktop Notifications',
        status: CapabilityStatus.needsSetup,
        summary: 'No notification tool or session D-Bus notification daemon was detected. In-app warnings still work.',
        osHint: 'Install libnotify so the app can send desktop alerts for critical transmitter battery or unexpected disconnects.',
        copyableCommand: installCmd,
      );
    }

    if (_osName == 'macos') {
      return const CapabilityReport(
        id: 'notifications',
        title: 'Desktop Notifications',
        status: CapabilityStatus.active,
        summary: 'Available via built-in macOS osascript notifications.',
        osHint: 'Grant notification permission in System Settings if prompted.',
      );
    }

    return const CapabilityReport(
      id: 'notifications',
      title: 'Desktop Notifications',
      status: CapabilityStatus.available,
      summary: 'Windows toast notifications can be enabled when running on Windows.',
      osHint: 'No extra libraries required on Windows 10/11.',
    );
  }

  Future<CapabilityReport> _inspectTray(String? distro) async {
    if (_osName == 'linux') {
      final hasTrayHost = await _dbusTrayAvailable();
      if (hasTrayHost) {
        return const CapabilityReport(
          id: 'tray',
          title: 'System Tray & Close-to-Tray',
          status: CapabilityStatus.active,
          summary: 'Session D-Bus StatusNotifierWatcher detected. Tray icon, quick toggles, and close-to-tray are active.',
          osHint: 'Uses pure-Dart D-Bus StatusNotifierItem with zero libappindicator dependency.',
        );
      }
      final installCmd = _linuxTrayInstallCommand(distro);
      return CapabilityReport(
        id: 'tray',
        title: 'System Tray & Close-to-Tray',
        status: CapabilityStatus.needsSetup,
        summary: 'No StatusNotifierWatcher tray host detected. Close-to-tray is automatically disabled so closing the window exits safely.',
        osHint: 'On GNOME, install and enable the AppIndicator extension (gnome-shell-extension-appindicator). On Wayland compositors (Sway/Hyprland), enable the Waybar tray module.',
        copyableCommand: installCmd,
      );
    }

    return CapabilityReport(
      id: 'tray',
      title: 'System Tray & Close-to-Tray',
      status: CapabilityStatus.available,
      summary: _osName == 'macos'
          ? 'Uses macOS menu bar status item.'
          : 'Uses Windows notification area tray icon.',
      osHint: 'Supported natively by the desktop shell.',
    );
  }

  CapabilityReport _inspectAutostart() {
    if (_osName == 'linux') {
      return const CapabilityReport(
        id: 'autostart',
        title: 'Start at Login (--hidden)',
        status: CapabilityStatus.active,
        summary: 'Writes a standard XDG autostart entry in ~/.config/autostart/dji-mic-control.desktop.',
        osHint: 'Works across GNOME, KDE, XFCE, and most Linux desktop environments without extra libraries.',
      );
    }
    if (_osName == 'macos') {
      return const CapabilityReport(
        id: 'autostart',
        title: 'Start at Login (--hidden)',
        status: CapabilityStatus.active,
        summary: 'Writes a user LaunchAgent plist in ~/Library/LaunchAgents/.',
        osHint: 'No extra helper libraries required.',
      );
    }
    return const CapabilityReport(
      id: 'autostart',
      title: 'Start at Login (--hidden)',
      status: CapabilityStatus.available,
      summary: 'Available via HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run on Windows.',
      osHint: 'Can also be placed in shell:startup manually.',
    );
  }

  static String _linuxNotifyInstallCommand(String? distro) {
    final d = distro ?? '';
    if (d.contains('fedora') || d.contains('rhel') || d.contains('centos')) {
      return 'sudo dnf install libnotify';
    }
    if (d.contains('arch') || d.contains('manjaro') || d.contains('endeavour')) {
      return 'sudo pacman -S libnotify';
    }
    if (d.contains('opensuse') || d.contains('suse')) {
      return 'sudo zypper install libnotify-tools';
    }
    return 'sudo apt install libnotify-bin';
  }

  static String _linuxTrayInstallCommand(String? distro) {
    final d = distro ?? '';
    if (d.contains('fedora') || d.contains('rhel')) {
      return 'sudo dnf install gnome-shell-extension-appindicator';
    }
    if (d.contains('arch') || d.contains('manjaro')) {
      return 'sudo pacman -S gnome-shell-extension-appindicator';
    }
    return 'sudo apt install gnome-shell-extension-appindicator';
  }

  static Future<bool> _defaultCommandExists(String command) async {
    try {
      final result = await Process.run('which', <String>[command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _defaultReadFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _defaultDbusTrayAvailable() async {
    final client = await DbusSessionClient.tryConnect();
    if (client == null) return false;
    try {
      return await client.nameHasOwner('org.kde.StatusNotifierWatcher');
    } finally {
      await client.close();
    }
  }

  static Future<bool> _defaultDbusNotifyAvailable() async {
    final client = await DbusSessionClient.tryConnect();
    if (client == null) return false;
    try {
      return await client.nameHasOwner('org.freedesktop.Notifications');
    } finally {
      await client.close();
    }
  }
}
