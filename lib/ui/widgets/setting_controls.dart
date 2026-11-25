// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:flutter/material.dart';

import '../../protocol/settings.dart';
import '../theme.dart';

/// Custom pill toggle switch matching upstream proportions and 160ms motion.
class MicSwitch extends StatelessWidget {
  const MicSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 42,
    this.height = 25,
    this.disabled = false,
  });

  final bool value;
  final VoidCallback onChanged;
  final double width;
  final double height;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final knobSize = height - 6;

    return Semantics(
      toggled: value,
      enabled: !disabled,
      child: GestureDetector(
        onTap: disabled ? null : onChanged,
        child: MouseRegion(
          cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: width,
            height: height,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? colors.accent : colors.borderStrong,
              borderRadius: BorderRadius.circular(999),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: knobSize,
                height: knobSize,
                decoration: BoxDecoration(
                  color: value ? colors.accentContrast : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x28000000), blurRadius: 3, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom pill segmented selector matching upstream `SettingControl.svelte`.
class MicSegmentedControl extends StatelessWidget {
  const MicSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onSelected,
    this.compact = false,
    this.disabled = false,
  });

  final List<SettingOption> options;
  final String? value;
  final ValueChanged<String> onSelected;
  final bool compact;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final active = opt.value == value;
          return GestureDetector(
            onTap: (disabled || active) ? null : () => onSelected(opt.value),
            child: MouseRegion(
              cursor: (disabled || active) ? SystemMouseCursors.basic : SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 12,
                  vertical: compact ? 4 : 5,
                ),
                decoration: BoxDecoration(
                  color: active ? colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  opt.label,
                  style: TextStyle(
                    fontSize: compact ? 12 : 12.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? colors.accentContrast : colors.textDim,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Renders one [SettingDefinition] row with lock, note, pending, and unknown handling.
class SettingControlRow extends StatelessWidget {
  const SettingControlRow({
    super.key,
    required this.setting,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.subRow = false,
    this.pending = false,
    this.lockReason,
    this.overrideLabel,
  });

  final SettingDefinition setting;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool compact;
  final bool subRow;
  final bool pending;
  final String? lockReason;
  final String? overrideLabel;

  bool get _locked => lockReason != null;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final label = overrideLabel ?? setting.label;

    final Widget control;
    if (value == null) {
      control = Text(
        '--',
        style: TextStyle(
          color: colors.textFaint,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      );
    } else if (setting.kind == SettingKind.toggle && setting.options.length == 2) {
      final isOn = value == setting.options[1].value;
      final swWidth = subRow ? (compact ? 28.0 : 32.0) : (compact ? 36.0 : 42.0);
      final swHeight = subRow ? (compact ? 17.0 : 19.0) : (compact ? 21.0 : 25.0);
      control = MicSwitch(
        key: Key('setting-switch-${setting.id}'),
        value: isOn,
        width: swWidth,
        height: swHeight,
        disabled: _locked || pending,
        onChanged: () {
          final next = isOn ? setting.options[0].value : setting.options[1].value;
          onChanged(next);
        },
      );
    } else {
      control = MicSegmentedControl(
        key: Key('setting-seg-${setting.id}'),
        options: setting.options,
        value: value,
        compact: compact || subRow,
        disabled: _locked || pending,
        onSelected: onChanged,
      );
    }

    final Widget labelBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: subRow ? 12.5 : (compact ? 13 : 13.5),
                  fontWeight: subRow ? FontWeight.w400 : FontWeight.w500,
                  color: subRow ? colors.textDim : colors.text,
                ),
              ),
            ),
            if (_locked) ...<Widget>[
              const SizedBox(width: 6),
              Tooltip(
                message: lockReason!,
                child: Icon(Icons.lock_outline, size: 14, color: colors.textFaint),
              ),
            ],
            if (compact && setting.note != null) ...<Widget>[
              const SizedBox(width: 6),
              Tooltip(
                message: setting.note!,
                child: Icon(Icons.warning_amber_rounded, size: 15, color: colors.warn),
              ),
            ],
          ],
        ),
        if (!compact && setting.note != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            setting.note!,
            style: TextStyle(fontSize: 12, color: colors.warn),
          ),
        ],
      ],
    );

    final Widget wrappedControl = IgnorePointer(
      ignoring: _locked || pending,
      child: Opacity(
        opacity: _locked ? 0.4 : 1.0,
        child: control,
      ),
    );

    final bool stackVertically = compact && setting.options.length >= 3;
    final Widget rowContent = stackVertically
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              labelBlock,
              const SizedBox(height: 6),
              wrappedControl,
            ],
          )
        : Row(
            children: <Widget>[
              Expanded(child: labelBlock),
              const SizedBox(width: 12),
              wrappedControl,
            ],
          );

    return MouseRegion(
      cursor: pending ? SystemMouseCursors.progress : SystemMouseCursors.basic,
      child: rowContent,
    );
  }
}

/// Composite 3-setting Noise Cancelling block matching upstream `NoiseCancelControl.svelte`.
class NoiseCancelControl extends StatelessWidget {
  const NoiseCancelControl({
    super.key,
    required this.powerSetting,
    required this.modeSetting,
    required this.buttonSetting,
    required this.values,
    required this.isPending,
    required this.lockReasonFor,
    required this.onChanged,
    this.compact = false,
  });

  final SettingDefinition? powerSetting;
  final SettingDefinition? modeSetting;
  final SettingDefinition? buttonSetting;
  final Map<String, String> values;
  final bool Function(String id) isPending;
  final String? Function(SettingDefinition setting) lockReasonFor;
  final void Function(String id, String value) onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (powerSetting != null)
          SettingControlRow(
            setting: powerSetting!,
            value: values[powerSetting!.id],
            compact: compact,
            pending: isPending(powerSetting!.id),
            lockReason: lockReasonFor(powerSetting!),
            onChanged: (v) => onChanged(powerSetting!.id, v),
          ),
        if (modeSetting != null || buttonSetting != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: Container(
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: colors.border, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (modeSetting != null)
                    SettingControlRow(
                      setting: modeSetting!,
                      overrideLabel: 'Mode',
                      value: values[modeSetting!.id],
                      compact: compact,
                      subRow: true,
                      pending: isPending(modeSetting!.id),
                      lockReason: lockReasonFor(modeSetting!),
                      onChanged: (v) => onChanged(modeSetting!.id, v),
                    ),
                  if (modeSetting != null && buttonSetting != null) const SizedBox(height: 8),
                  if (buttonSetting != null)
                    SettingControlRow(
                      setting: buttonSetting!,
                      value: values[buttonSetting!.id],
                      compact: compact,
                      subRow: true,
                      pending: isPending(buttonSetting!.id),
                      lockReason: lockReasonFor(buttonSetting!),
                      onChanged: (v) => onChanged(buttonSetting!.id, v),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
