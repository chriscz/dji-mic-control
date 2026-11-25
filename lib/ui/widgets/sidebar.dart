// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:flutter/material.dart';

import '../../transport/device_manager.dart';
import '../theme.dart';
import 'battery_icon.dart';
import 'device_picto.dart';

/// Collapsible 260px left device sidebar with click-empty-space-to-deselect.
class DeviceSidebar extends StatelessWidget {
  const DeviceSidebar({
    super.key,
    required this.open,
    required this.devices,
    required this.selectedId,
    required this.onSelect,
  });

  final bool open;
  final List<DeviceSummary> devices;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  static const double sidebarWidth = 260;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.ease,
      width: open ? sidebarWidth : 0,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: sidebarWidth,
          maxWidth: sidebarWidth,
          child: Container(
            width: sidebarWidth,
            decoration: BoxDecoration(
              color: colors.bgPanel,
              border: Border(right: BorderSide(color: colors.border)),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => onSelect(null),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Text(
                      'DEVICES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.7,
                        color: colors.textFaint,
                      ),
                    ),
                  ),
                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'No devices',
                        style: TextStyle(fontSize: 13, color: colors.textDim),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                        itemCount: devices.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final dev = devices[index];
                          final active = dev.id == selectedId;
                          return _SidebarDeviceTile(
                            device: dev,
                            active: active,
                            onTap: () => onSelect(dev.id),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarDeviceTile extends StatelessWidget {
  const _SidebarDeviceTile({
    required this.device,
    required this.active,
    required this.onTap,
  });

  final DeviceSummary device;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final hasAnyTx = device.tx.any((t) => t != null);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          key: Key('sidebar-device-${device.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: active ? colors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? colors.accent.withValues(alpha: 0.4) : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              DevicePicto(assetKey: '${device.pictogramKey}-rx', size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      device.modelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.rxSerial ?? device.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textDim,
                        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                      ),
                    ),
                    if (hasAnyTx) ...<Widget>[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: <Widget>[
                          for (var i = 0; i < device.tx.length; i++)
                            if (device.tx[i] != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    'TX${i + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textDim,
                                    ),
                                  ),
                                  if (device.tx[i]!.battery != null && device.tx[i]!.battery! > 0) ...<Widget>[
                                    const SizedBox(width: 4),
                                    BatteryIcon(
                                      value: device.tx[i]!.battery,
                                      charging: device.tx[i]!.charging ?? false,
                                      size: 14,
                                    ),
                                  ],
                                ],
                              ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: device.connected ? 'Connected' : 'Connecting...',
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: device.connected ? colors.good : colors.textFaint,
                    boxShadow: device.connected
                        ? <BoxShadow>[
                            BoxShadow(
                              color: colors.good.withValues(alpha: 0.3),
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
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
