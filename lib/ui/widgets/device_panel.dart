// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../platform/config_store.dart';
import '../../protocol/settings.dart';
import '../../protocol/state.dart';
import '../../state/mic_controller.dart';
import '../../transport/device_manager.dart';
import '../theme.dart';
import 'audio_level_meter.dart';
import 'battery_icon.dart';
import 'device_picto.dart';
import 'setting_controls.dart';

const Set<String> _ncGroupIds = <String>{
  'noise-cancel',
  'noise-cancel-power',
  'noise-cancel-button',
};

const Set<String> _txTargetedIds = <String>{'voice-tone'};

/// Main scrollable device detail view: header, RX/TX status cards, and settings.
class DevicePanel extends StatelessWidget {
  const DevicePanel({
    super.key,
    required this.controller,
    required this.device,
    required this.status,
    required this.settings,
  });

  final MicController controller;
  final DeviceSummary device;
  final DeviceStatus status;
  final List<SettingDefinition> settings;

  String? _lockReasonFor(SettingDefinition setting, Map<String, String> values) {
    if (status.protocolVersion == 1 && setting.v1Command == null) {
      return 'Requires protocol v2, please update your firmware';
    }
    if (setting.id == 'noise-cancel' && !controller.effectiveNcEnabled) {
      return 'Turn on "Noise Cancelling" first';
    }
    for (final otherId in setting.exclusiveWith) {
      final otherVal = values[otherId];
      if (otherVal != null && otherVal != 'off' && otherVal != 'mono') {
        final otherDef = settings.where((s) => s.id == otherId).firstOrNull;
        final otherLabel = otherDef?.label ?? otherId;
        return 'Turn off "$otherLabel" first';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final values = controller.effectiveSettings;
    final byId = <String, SettingDefinition>{for (final s in settings) s.id: s};
    final viewMode = controller.config.viewMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(colors),
          const SizedBox(height: 18),
          _buildStatusGrid(context, colors, byId),
          const SizedBox(height: 24),
          _buildSettingsHeader(colors, viewMode),
          const SizedBox(height: 12),
          if (viewMode == ViewMode.compact)
            _buildCompactMasonry(colors, values, byId)
          else
            _buildListView(colors, values, byId),
        ],
      ),
    );
  }

  Widget _buildHeader(AppColors colors) {
    final connected = status.connected;
    final pillColor = connected ? colors.good : colors.textDim;

    return Row(
      children: <Widget>[
        DevicePicto(assetKey: '${device.pictogramKey}-rx', size: 54),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                device.modelName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                status.rx?.serial ?? device.id,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textDim,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        Container(
          key: const Key('connection-status-pill'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: pillColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: pillColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: pillColor),
              ),
              const SizedBox(width: 7),
              Text(
                connected ? 'Connected' : 'No signal',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: pillColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusGrid(
    BuildContext context,
    AppColors colors,
    Map<String, SettingDefinition> byId,
  ) {
    final cards = <Widget>[
      _buildRxCard(colors),
      _buildTxCard(colors, 0, byId['voice-tone']),
      _buildTxCard(colors, 1, byId['voice-tone']),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        final cols = max(1, min(3, ((constraints.maxWidth + gap) / (210 + gap)).floor()));
        if (cols == 3) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: cards[0]),
                const SizedBox(width: gap),
                Expanded(child: cards[1]),
                const SizedBox(width: gap),
                Expanded(child: cards[2]),
              ],
            ),
          );
        }
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards.map((card) {
            final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return SizedBox(width: width, child: card);
          }).toList(),
        );
      },
    );
  }

  Widget _buildRxCard(AppColors colors) {
    final rx = status.rx;
    final proto = status.protocolVersion;
    final gain = status.gainDial;
    final gainText = gain == null
        ? null
        : gain > 0
            ? '+$gain dB'
            : '$gain dB';

    return _StatusCardShell(
      colors: colors,
      title: 'RECEIVER',
      trailing: DevicePicto(assetKey: '${device.pictogramKey}-rx', size: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (rx != null) ...<Widget>[
            _KvRow(label: 'Serial', value: rx.serial ?? 'Unknown'),
            const SizedBox(height: 6),
            _KvRow(label: 'Firmware', value: rx.firmware?.toString() ?? 'Unknown'),
          ] else
            Text('No data', style: TextStyle(fontSize: 13, color: colors.textFaint)),
          if (proto != null) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('Protocol', style: TextStyle(fontSize: 12.5, color: colors.textDim)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (proto == 2 ? colors.v2Purple : colors.accent).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'v$proto',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: proto == 2 ? colors.v2Purple : colors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (gainText != null) ...<Widget>[
            const SizedBox(height: 6),
            _KvRow(
              label: 'Gain',
              value: gainText,
              valueColor: gain == 0 ? colors.warn : colors.text,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTxCard(AppColors colors, int index, SettingDefinition? voiceToneSetting) {
    final tx = status.tx[index];
    final label = tx?.productName != null ? '${tx!.productName} (TX${index + 1})' : 'TX${index + 1}';

    // Avoid icon flicker on v2 before the first identity push reveals Mic Mini vs Mic Mini 2.
    Widget? picto;
    if (tx != null) {
      if (tx.productName == 'DJI Mic Mini 2') {
        picto = const DevicePicto(assetKey: 'mic-mini-2-tx', size: 38);
      } else if (status.protocolVersion != 2 || tx.productName != null) {
        picto = DevicePicto(assetKey: '${device.pictogramKey}-tx', size: 38);
      }
    }

    final showVoiceTone = tx != null &&
        tx.productName == 'DJI Mic Mini 2' &&
        status.protocolVersion == 2 &&
        voiceToneSetting != null;

    return _StatusCardShell(
      key: Key('tx-card-${index + 1}'),
      colors: colors,
      title: label,
      titleInline: tx != null
          ? BatteryIcon(
              value: tx.battery,
              charging: tx.charging ?? false,
              size: 18,
            )
          : null,
      trailing: picto,
      child: tx == null
          ? Text('Disconnected', style: TextStyle(fontSize: 13, color: colors.textFaint))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _KvRow(label: 'Serial', value: tx.serial ?? 'Unknown'),
                const SizedBox(height: 6),
                _KvRow(label: 'Firmware', value: tx.firmware?.toString() ?? 'Unknown'),
                const SizedBox(height: 10),
                AudioLevelMeter(rawLevel: tx.level),
                if (showVoiceTone) ...<Widget>[
                  const SizedBox(height: 12),
                  SettingControlRow(
                    setting: voiceToneSetting,
                    value: controller.effectiveVoiceTone(index),
                    compact: true,
                    pending: controller.isTxPending(index),
                    onChanged: (val) => controller.setTxSetting(index, voiceToneSetting.id, val),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildSettingsHeader(AppColors colors, ViewMode mode) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          'SETTINGS',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
            color: colors.textFaint,
          ),
        ),
        MicSegmentedControl(
          key: const Key('view-mode-switcher'),
          compact: true,
          options: const <SettingOption>[
            SettingOption(value: 'compact', label: 'Compact', wire: 0),
            SettingOption(value: 'list', label: 'List', wire: 1),
          ],
          value: mode.slug,
          onSelected: (slug) => controller.setViewMode(ViewMode.fromSlug(slug)),
        ),
      ],
    );
  }

  List<_SettingGroupBucket> _buildGroups() {
    final buckets = <String, List<_SettingItem>>{};
    var addedNc = false;

    for (final s in settings) {
      if (_txTargetedIds.contains(s.id)) continue;
      if (_ncGroupIds.contains(s.id)) {
        if (!addedNc) {
          addedNc = true;
          buckets.putIfAbsent(s.group, () => <_SettingItem>[]).add(const _NcCompositeItem());
        }
        continue;
      }
      buckets.putIfAbsent(s.group, () => <_SettingItem>[]).add(_SingleSettingItem(s));
    }

    return buckets.entries
        .map((e) => _SettingGroupBucket(name: e.key, items: e.value))
        .toList();
  }

  Widget _buildCompactMasonry(
    AppColors colors,
    Map<String, String> values,
    Map<String, SettingDefinition> byId,
  ) {
    final groups = _buildGroups();
    return LayoutBuilder(
      builder: (context, constraints) {
        const minCol = 260.0;
        const gap = 18.0;
        final colCount = max(1, min(groups.length, ((constraints.maxWidth + gap) / (minCol + gap)).floor()));
        final cols = List<List<_SettingGroupBucket>>.generate(colCount, (_) => <_SettingGroupBucket>[]);
        final heights = List<double>.filled(colCount, 0.0);

        for (final g in groups) {
          var shortest = 0;
          for (var c = 1; c < colCount; c++) {
            if (heights[c] < heights[shortest]) shortest = c;
          }
          cols[shortest].add(g);
          heights[shortest] += g.items.length + 1.5;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var c = 0; c < colCount; c++) ...<Widget>[
              if (c > 0) const SizedBox(width: gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (var i = 0; i < cols[c].length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(height: gap),
                      _buildCompactGroupCard(colors, cols[c][i], values, byId),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCompactGroupCard(
    AppColors colors,
    _SettingGroupBucket group,
    Map<String, String> values,
    Map<String, SettingDefinition> byId,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x0E000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            group.name.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: colors.textFaint,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < group.items.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.bgElev,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: _buildItemWidget(group.items[i], values, byId, compact: true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildListView(
    AppColors colors,
    Map<String, String> values,
    Map<String, SettingDefinition> byId,
  ) {
    final groups = _buildGroups();
    final flat = <_SettingItem>[
      for (final g in groups) ...g.items,
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < flat.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, thickness: 1, color: colors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _buildItemWidget(flat[i], values, byId, compact: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemWidget(
    _SettingItem item,
    Map<String, String> values,
    Map<String, SettingDefinition> byId, {
    required bool compact,
  }) {
    return switch (item) {
      _NcCompositeItem() => NoiseCancelControl(
          powerSetting: byId['noise-cancel-power'],
          modeSetting: byId['noise-cancel'],
          buttonSetting: byId['noise-cancel-button'],
          values: values,
          compact: compact,
          isPending: controller.isPending,
          lockReasonFor: (s) => _lockReasonFor(s, values),
          onChanged: controller.setSetting,
        ),
      _SingleSettingItem(:final setting) => SettingControlRow(
          setting: setting,
          value: values[setting.id],
          compact: compact,
          pending: controller.isPending(setting.id),
          lockReason: _lockReasonFor(setting, values),
          onChanged: (v) => controller.setSetting(setting.id, v),
        ),
    };
  }
}

class _StatusCardShell extends StatelessWidget {
  const _StatusCardShell({
    super.key,
    required this.colors,
    required this.title,
    this.titleInline,
    this.trailing,
    required this.child,
  });

  final AppColors colors;
  final String title;
  final Widget? titleInline;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: colors.textDim,
                        ),
                      ),
                    ),
                    if (titleInline != null) ...<Widget>[
                      const SizedBox(width: 8),
                      titleInline!,
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: TextStyle(fontSize: 12.5, color: colors.textDim)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: valueColor ?? colors.text,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

sealed class _SettingItem {
  const _SettingItem();
}

final class _NcCompositeItem extends _SettingItem {
  const _NcCompositeItem();
}

final class _SingleSettingItem extends _SettingItem {
  const _SingleSettingItem(this.setting);
  final SettingDefinition setting;
}

class _SettingGroupBucket {
  const _SettingGroupBucket({required this.name, required this.items});
  final String name;
  final List<_SettingItem> items;
}
