// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../log/app_logger.dart';
import '../../platform/capabilities.dart';
import '../../platform/config_store.dart';
import '../../platform/udev_installer.dart';
import '../../protocol/settings.dart';
import '../../state/mic_controller.dart';
import '../theme.dart';
import 'setting_controls.dart';

/// Copyable USB permissions / udev / Zadig setup modal with one-click Linux installer.
class UsbSetupDialog extends StatefulWidget {
  const UsbSetupDialog({
    super.key,
    required this.controller,
    required this.usbReport,
  });

  final MicController controller;
  final CapabilityReport usbReport;

  @override
  State<UsbSetupDialog> createState() => _UsbSetupDialogState();
}

class _UsbSetupDialogState extends State<UsbSetupDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final usbReport = controller.capabilities?.usb ?? widget.usbReport;
        final installResult = controller.udevInstallResult;
        final isLinux = (controller.capabilities?.osName ?? 'linux') == 'linux';

        return Dialog(
          backgroundColor: colors.bgPanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              controller.t('Enable USB access'),
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colors.text),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, size: 18, color: colors.textDim),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(usbReport.summary, style: TextStyle(fontSize: 13.5, color: colors.textDim)),
                      if (isLinux && controller.canInstallUdevInApp) ...<Widget>[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.bgElev,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Text(
                                'Automatic install (recommended)',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.text),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Uses your desktop administrator prompt (pkexec) to write ${UdevHelper.rulePath} and reload udev rules.',
                                style: TextStyle(fontSize: 12.5, color: colors.textDim),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  key: const Key('modal-install-udev-btn'),
                                  onPressed: controller.installingUdev ? null : controller.installUdevRule,
                                  icon: controller.installingUdev
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.admin_panel_settings_outlined, size: 16),
                                  label: Text(
                                    controller.installingUdev ? 'Installing...' : 'Install udev rule',
                                  ),
                                ),
                              ),
                              if (installResult != null) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  installResult.message,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: installResult.status == UdevInstallStatus.installed
                                        ? colors.good
                                        : colors.warn,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (usbReport.steps.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14),
                        Text(
                          'Manual steps',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.text),
                        ),
                        const SizedBox(height: 6),
                        for (var i = 0; i < usbReport.steps.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text('${i + 1}. ', style: TextStyle(fontWeight: FontWeight.w600, color: colors.accent)),
                                Expanded(
                                  child: Text(usbReport.steps[i], style: TextStyle(fontSize: 13, color: colors.text)),
                                ),
                              ],
                            ),
                          ),
                      ],
                      if (usbReport.copyableSnippet != null) ...<Widget>[
                        const SizedBox(height: 14),
                        _CopyableCodeBlock(
                          header: usbReport.snippetHeader ?? 'Rule',
                          buttonLabel: 'Copy rule',
                          code: usbReport.copyableSnippet!,
                        ),
                      ],
                      if (usbReport.copyableCommand != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _CopyableCodeBlock(
                          header: 'Shell command',
                          buttonLabel: 'Copy command',
                          code: usbReport.copyableCommand!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// System & Capabilities dialog showing live OS probing, install suggestions,
/// and desktop preferences (theme, notifications, tray, autostart).
class CapabilitiesDialog extends StatefulWidget {
  const CapabilitiesDialog({
    super.key,
    required this.controller,
  });

  final MicController controller;

  @override
  State<CapabilitiesDialog> createState() => _CapabilitiesDialogState();
}

class _CapabilitiesDialogState extends State<CapabilitiesDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final caps = controller.capabilities;
        final cfg = controller.config;

        return Dialog(
          backgroundColor: colors.bgPanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                controller.t('System & Capabilities'),
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colors.text),
                              ),
                              Text(
                                'OS: ${caps?.osName ?? 'unknown'}${caps?.distroId != null ? ' (${caps!.distroId})' : ''}  |  Backend: ${controller.snapshot.backendName}',
                                style: TextStyle(fontSize: 12, color: colors.textDim),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: controller.recheckCapabilities,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Re-check'),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, size: 18, color: colors.textDim),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Scrollbar(
                      key: const Key('capabilities-scrollbar'),
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(right: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                          Text(
                            controller.t('PREFERENCES'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: colors.textFaint,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.bgElev,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: colors.border),
                            ),
                            child: Column(
                              children: <Widget>[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: <Widget>[
                                    Text(controller.t('Language'), style: TextStyle(fontSize: 13, color: colors.text)),
                                    MicSegmentedControl(
                                      key: const Key('locale-switcher'),
                                      compact: true,
                                      options: const <SettingOption>[
                                        SettingOption(value: 'en', label: 'English', wire: 0),
                                        SettingOption(value: 'zh-CN', label: '简体中文', wire: 1),
                                      ],
                                      value: cfg.locale,
                                      onSelected: controller.setLocale,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: <Widget>[
                                    Text(controller.t('Appearance'), style: TextStyle(fontSize: 13, color: colors.text)),
                                    MicSegmentedControl(
                                      compact: true,
                                      options: <SettingOption>[
                                        SettingOption(value: 'system', label: controller.t('System'), wire: 0),
                                        SettingOption(value: 'light', label: controller.t('Light'), wire: 1),
                                        SettingOption(value: 'dark', label: controller.t('Dark'), wire: 2),
                                      ],
                                      value: cfg.themeMode.slug,
                                      onSelected: (v) => controller.setThemePreference(AppThemePreference.fromSlug(v)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _PrefToggleRow(
                                  label: 'Close button hides to system tray',
                                  subtitle: controller.trayActive
                                      ? 'Tray host active'
                                      : 'Disabled automatically until a tray host is detected',
                                  value: cfg.closeToTray && controller.trayActive,
                                  disabled: !controller.trayActive,
                                  onChanged: () => controller.setCloseToTray(!cfg.closeToTray),
                                ),
                                const SizedBox(height: 10),
                                _PrefToggleRow(
                                  label: 'Start at login (hidden)',
                                  subtitle: 'Launches minimized to tray at desktop login',
                                  value: controller.autostartEnabled,
                                  onChanged: () => controller.setAutostart(!controller.autostartEnabled),
                                ),
                                const SizedBox(height: 10),
                                _PrefToggleRow(
                                  label: 'Notify on very low / critical TX battery',
                                  subtitle: 'Uses runtime OS notification support when installed',
                                  value: cfg.notifyCriticalBattery,
                                  onChanged: () => controller.setNotifyCriticalBattery(!cfg.notifyCriticalBattery),
                                ),
                                const SizedBox(height: 10),
                                _PrefToggleRow(
                                  label: 'Notify on unexpected receiver disconnect',
                                  subtitle: 'Suppressed during intentional Plug-Free reboots',
                                  value: cfg.notifyDisconnect,
                                  onChanged: () => controller.setNotifyDisconnect(!cfg.notifyDisconnect),
                                ),
                                const SizedBox(height: 10),
                                _PrefToggleRow(
                                  label: 'Show pending operations strip',
                                  subtitle: 'Displays active USB commands above the Diagnostics fold',
                                  value: cfg.showPendingStrip,
                                  onChanged: () => controller.setShowPendingStrip(!cfg.showPendingStrip),
                                ),
                                const SizedBox(height: 10),
                                _PrefToggleRow(
                                  label: 'Debug protocol logging',
                                  subtitle: 'Includes raw DUML hex frames in Diagnostics',
                                  value: cfg.debugLogging,
                                  onChanged: () => controller.setDebugLogging(!cfg.debugLogging),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'OS CAPABILITIES & OPTIONAL LIBRARIES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: colors.textFaint,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (caps != null)
                            for (final cap in caps.all) ...<Widget>[
                              _CapabilityCard(
                                report: cap,
                                showInstallUdevButton: cap.id == 'usb' &&
                                    caps.osName == 'linux' &&
                                    controller.canInstallUdevInApp &&
                                    (!caps.udevRuleInstalled || cap.status == CapabilityStatus.needsSetup),
                                installingUdev: controller.installingUdev,
                                udevInstallResult: cap.id == 'usb' ? controller.udevInstallResult : null,
                                onInstallUdev: controller.installUdevRule,
                              ),
                              const SizedBox(height: 10),
                            ],
                        ],
                      ),
                    ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PrefToggleRow extends StatelessWidget {
  const _PrefToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  final String label;
  final String subtitle;
  final bool value;
  final VoidCallback onChanged;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.text)),
              Text(subtitle, style: TextStyle(fontSize: 11.5, color: colors.textDim)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Opacity(
          opacity: disabled ? 0.45 : 1,
          child: MicSwitch(
            value: value,
            width: 36,
            height: 21,
            disabled: disabled,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.report,
    this.showInstallUdevButton = false,
    this.installingUdev = false,
    this.udevInstallResult,
    this.onInstallUdev,
  });

  final CapabilityReport report;
  final bool showInstallUdevButton;
  final bool installingUdev;
  final UdevInstallResult? udevInstallResult;
  final VoidCallback? onInstallUdev;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (badgeText, badgeColor) = switch (report.status) {
      CapabilityStatus.active => ('Active', colors.good),
      CapabilityStatus.available => ('Available', colors.accent),
      CapabilityStatus.needsSetup => ('Setup suggested', colors.warn),
      CapabilityStatus.unsupported => ('Unavailable', colors.textFaint),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  report.title,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colors.text),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(report.summary, style: TextStyle(fontSize: 12.5, color: colors.textDim)),
          const SizedBox(height: 4),
          Text(report.osHint, style: TextStyle(fontSize: 12, color: colors.textFaint)),
          if (showInstallUdevButton) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('caps-install-udev-btn'),
                onPressed: installingUdev ? null : onInstallUdev,
                icon: installingUdev
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.admin_panel_settings_outlined, size: 16),
                label: Text(installingUdev ? 'Installing...' : 'Install udev rule'),
              ),
            ),
            if (udevInstallResult != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                udevInstallResult!.message,
                style: TextStyle(
                  fontSize: 12,
                  color: udevInstallResult!.succeeded ? colors.good : colors.warn,
                ),
              ),
            ],
          ],
          if (report.copyableCommand != null &&
              (report.status == CapabilityStatus.needsSetup || showInstallUdevButton)) ...<Widget>[
            const SizedBox(height: 8),
            _CopyableCodeBlock(
              header: 'Suggested install / setup command',
              buttonLabel: 'Copy',
              code: report.copyableCommand!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Live Diagnostics ring-buffer log viewer (reusing Lumen's Diagnostics concept).
class DiagnosticsDialog extends StatefulWidget {
  const DiagnosticsDialog({
    super.key,
    required this.logger,
    required this.backendName,
  });

  final AppLogger logger;
  final String backendName;

  @override
  State<DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<DiagnosticsDialog> {
  final ScrollController _scrollController = ScrollController();
  LogLevel? _filter;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final entries = widget.logger.entries.where((e) => _filter == null || e.level == _filter).toList();

    return Dialog(
      backgroundColor: colors.bgPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 580),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Diagnostics', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colors.text)),
                        Text('Transport: ${widget.backendName}  |  ${entries.length} entries', style: TextStyle(fontSize: 12, color: colors.textDim)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.logger.dumpText()));
                    },
                    child: const Text('Copy all'),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(widget.logger.clear);
                    },
                    child: const Text('Clear'),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: colors.textDim),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final level in LogLevel.values)
                    ChoiceChip(
                      label: Text(level.tag),
                      selected: _filter == level,
                      onSelected: (_) => setState(() => _filter = level),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: entries.isEmpty
                      ? Center(child: Text('No log entries yet.', style: TextStyle(color: colors.textFaint)))
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(right: 14),
                            itemCount: entries.length,
                            itemBuilder: (context, idx) {
                              return SelectableText(
                                entries[idx].format(),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: entries[idx].level == LogLevel.error
                                      ? colors.danger
                                      : entries[idx].level == LogLevel.warn
                                          ? colors.warn
                                          : colors.text,
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyableCodeBlock extends StatefulWidget {
  const _CopyableCodeBlock({
    required this.header,
    required this.buttonLabel,
    required this.code,
  });

  final String header;
  final String buttonLabel;
  final String code;

  @override
  State<_CopyableCodeBlock> createState() => _CopyableCodeBlockState();
}

class _CopyableCodeBlockState extends State<_CopyableCodeBlock> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.header,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: colors.textDim),
                  ),
                ),
                TextButton(
                  onPressed: _copy,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(_copied ? 'Copied' : widget.buttonLabel, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              widget.code.trimRight(),
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}
