// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:flutter/material.dart';

import '../platform/capabilities.dart';
import '../platform/config_store.dart';
import '../state/mic_controller.dart';
import 'theme.dart';
import 'widgets/device_panel.dart';
import 'widgets/modals.dart';
import 'widgets/sidebar.dart';

/// Root Material application wired to [MicController].
class DjiMicApp extends StatelessWidget {
  const DjiMicApp({super.key, required this.controller});

  final MicController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final themeMode = switch (controller.config.themeMode) {
          AppThemePreference.light => ThemeMode.light,
          AppThemePreference.dark => ThemeMode.dark,
          AppThemePreference.system => ThemeMode.system,
        };
        return MaterialApp(
          title: 'DJI Mic Control',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: themeMode,
          home: AppShell(controller: controller),
        );
      },
    );
  }
}

/// Top toolbar, banners, collapsible sidebar, and main device/placeholder pane.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.controller});

  final MicController controller;

  void _openUsbSetup(BuildContext context) {
    final usbReport = controller.capabilities?.usb ??
        CapabilityReport(
          id: 'usb',
          title: 'USB Device Access',
          status: CapabilityStatus.needsSetup,
          summary: 'Install the DJI udev rule so desktop users can control the microphone over USB.',
          osHint: 'Reload udev rules and replug the receiver.',
          copyableSnippet: UdevHelper.generateLinuxUdevRule(),
          snippetHeader: UdevHelper.rulePath,
          copyableCommand: UdevHelper.installCommand(),
        );
    showDialog<void>(
      context: context,
      builder: (_) => UsbSetupDialog(usbReport: usbReport),
    );
  }

  void _openCapabilities(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => CapabilitiesDialog(controller: controller),
    );
  }

  void _openDiagnostics(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => DiagnosticsDialog(
        logger: controller.services.logger,
        backendName: controller.snapshot.backendName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final snap = controller.snapshot;
    final showPermissionBanner = snap.probe.permissionIssue && snap.devices.isEmpty;
    final selectedDevice = snap.devices.where((d) => d.id == snap.selectedId).firstOrNull;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: <Widget>[
          if (showPermissionBanner)
            InkWell(
              key: const Key('usb-permission-banner'),
              onTap: () => _openUsbSetup(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                color: colors.warn.withValues(alpha: 0.16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.usb_off_rounded, size: 16, color: colors.warn),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A microphone is connected but not accessible. Click to fix USB permissions.',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.text),
                      ),
                    ),
                    Text(
                      'Setup guide',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.warn),
                    ),
                  ],
                ),
              ),
            ),
          if (controller.error != null)
            Container(
              key: const Key('error-banner'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              color: colors.danger.withValues(alpha: 0.16),
              child: Row(
                children: <Widget>[
                  Icon(Icons.error_outline, size: 16, color: colors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.error!,
                      style: TextStyle(fontSize: 13, color: colors.text),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 15, color: colors.textDim),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                    onPressed: controller.dismissError,
                  ),
                ],
              ),
            ),
          Expanded(
            child: Row(
              children: <Widget>[
                DeviceSidebar(
                  open: controller.sidebarOpen,
                  devices: snap.devices,
                  selectedId: snap.selectedId,
                  onSelect: controller.selectDevice,
                  onToggle: controller.toggleSidebar,
                ),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      _buildActionStrip(context, colors),
                      Expanded(
                        child: (selectedDevice != null && snap.status != null)
                            ? DevicePanel(
                                controller: controller,
                                device: selectedDevice,
                                status: snap.status!,
                                settings: snap.settings,
                              )
                            : _buildPlaceholder(context, colors, showPermissionBanner, snap.devices.isNotEmpty),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Slim, borderless inline utility row (avoids stacking a second titlebar
  /// underneath the native OS window titlebar).
  Widget _buildActionStrip(BuildContext context, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 18, 0),
      child: Row(
        children: <Widget>[
          if (!controller.sidebarOpen)
            IconButton(
              key: const Key('sidebar-expand-btn'),
              tooltip: 'Show sidebar',
              icon: Icon(Icons.menu, size: 18, color: colors.textDim),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: controller.toggleSidebar,
            ),
          if (controller.isDemo) ...<Widget>[
            if (!controller.sidebarOpen) const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'DEMO',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: colors.accent),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            key: const Key('diagnostics-btn'),
            tooltip: 'Diagnostics log',
            icon: Icon(Icons.terminal_rounded, size: 17, color: colors.textDim),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            onPressed: () => _openDiagnostics(context),
          ),
          const SizedBox(width: 2),
          Stack(
            children: <Widget>[
              IconButton(
                key: const Key('capabilities-btn'),
                tooltip: 'System & Capabilities',
                icon: Icon(Icons.tune_rounded, size: 17, color: colors.textDim),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                onPressed: () => _openCapabilities(context),
              ),
              if (controller.hasCapabilityNeedingSetup)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: colors.warn),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(
    BuildContext context,
    AppColors colors,
    bool permissionIssue,
    bool hasDevices,
  ) {
    final String heading;
    final String body;
    if (permissionIssue) {
      heading = 'Permission needed';
      body = 'A DJI microphone is plugged in, but USB access is blocked by system permissions.';
    } else if (hasDevices) {
      heading = 'No device selected';
      body = 'Choose a device from the sidebar.';
    } else {
      heading = 'No microphone connected';
      body = 'Connect a supported DJI microphone over USB to get started.';
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                heading,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.text),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: colors.textDim),
              ),
              if (permissionIssue) ...<Widget>[
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('show-setup-cta'),
                  onPressed: () => _openUsbSetup(context),
                  child: const Text('Show setup instructions'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
