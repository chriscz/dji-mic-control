// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:flutter/material.dart';

import '../platform/capabilities.dart';
import '../platform/config_store.dart';
import '../platform/udev_installer.dart';
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
      builder: (_) => UsbSetupDialog(
        controller: controller,
        usbReport: usbReport,
      ),
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
    final caps = controller.capabilities;
    final isLinux = (caps?.osName ?? 'linux') == 'linux';
    final hasUdevRule = caps?.udevRuleInstalled ?? false;
    final installResult = controller.udevInstallResult;

    if (hasDevices && !permissionIssue) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'No device selected',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.text),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a device from the sidebar to view live telemetry and adjust settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: colors.textDim),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                permissionIssue ? Icons.usb_off_rounded : Icons.mic_none_rounded,
                size: 38,
                color: permissionIssue ? colors.warn : colors.accent,
              ),
              const SizedBox(height: 12),
              Text(
                permissionIssue ? 'Permission needed' : 'No microphone connected',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: colors.text),
              ),
              const SizedBox(height: 6),
              Text(
                permissionIssue
                    ? 'A DJI microphone is plugged in, but Linux is blocking non-root access to its USB control interface.'
                    : 'Connect a supported DJI Mic Mini receiver over USB-C and it will appear automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: colors.textDim),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.bgPanel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      permissionIssue ? 'FIX USB PERMISSIONS' : 'GETTING STARTED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.7,
                        color: colors.textFaint,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!permissionIssue) ...<Widget>[
                      _GuideStepRow(
                        number: '1',
                        text: 'Plug the DJI Mic Mini USB-C receiver into your computer using a data-capable cable.',
                        colors: colors,
                      ),
                      const SizedBox(height: 8),
                      _GuideStepRow(
                        number: '2',
                        text: 'Power on one or both transmitters (DJI Mic Mini or DJI Mic Mini 2) so they link with the receiver.',
                        colors: colors,
                      ),
                      const SizedBox(height: 8),
                      _GuideStepRow(
                        number: '3',
                        text: 'Only USB control Interface 6 is claimed, so your microphone keeps working normally for audio input.',
                        colors: colors,
                      ),
                    ] else ...<Widget>[
                      Text(
                        hasUdevRule
                            ? 'A udev rule file already exists, so unplugging and replugging the receiver (or reloading udev rules below) should unlock access.'
                            : 'Install the DJI udev rule (/etc/udev/rules.d/60-dji-mic.rules) so your user session can control the receiver without root.',
                        style: TextStyle(fontSize: 13, color: colors.textDim),
                      ),
                    ],
                    if (isLinux) ...<Widget>[
                      const SizedBox(height: 14),
                      if (hasUdevRule && !permissionIssue)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.good.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.good.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.check_circle_outline, size: 16, color: colors.good),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Linux USB permissions (udev rule) are installed and ready.',
                                  style: TextStyle(fontSize: 12.5, color: colors.text),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.warn.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.warn.withValues(alpha: 0.35)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              if (!permissionIssue) ...<Widget>[
                                Row(
                                  children: <Widget>[
                                    Icon(Icons.info_outline, size: 16, color: colors.warn),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'First-time Linux setup recommended',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.text),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Linux blocks non-root USB control access until the DJI udev rule is installed. You can install it now before plugging in your receiver.',
                                  style: TextStyle(fontSize: 12.5, color: colors.textDim),
                                ),
                                const SizedBox(height: 10),
                              ],
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  if (controller.canInstallUdevInApp)
                                    FilledButton.icon(
                                      key: const Key('main-install-udev-btn'),
                                      onPressed: controller.installingUdev ? null : controller.installUdevRule,
                                      icon: controller.installingUdev
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.admin_panel_settings_outlined, size: 16),
                                      label: Text(
                                        controller.installingUdev
                                            ? 'Installing...'
                                            : (hasUdevRule ? 'Reload udev rules' : 'Install udev rule'),
                                      ),
                                    ),
                                  OutlinedButton(
                                    key: const Key('show-setup-cta'),
                                    onPressed: () => _openUsbSetup(context),
                                    child: const Text('Show setup instructions'),
                                  ),
                                ],
                              ),
                              if (installResult != null) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  installResult.message,
                                  key: const Key('udev-install-feedback'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: installResult.status == UdevInstallStatus.installed
                                        ? colors.good
                                        : colors.textDim,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (controller.hasCapabilityNeedingSetup) ...<Widget>[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _openCapabilities(context),
                  icon: Icon(Icons.tune_rounded, size: 15, color: colors.textDim),
                  label: Text(
                    'Optional desktop features (notifications, tray) have setup tips',
                    style: TextStyle(fontSize: 12.5, color: colors.textDim),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideStepRow extends StatelessWidget {
  const _GuideStepRow({
    required this.number,
    required this.text,
    required this.colors,
  });

  final String number;
  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accentSoft,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: colors.accent),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: colors.textDim)),
        ),
      ],
    );
  }
}
