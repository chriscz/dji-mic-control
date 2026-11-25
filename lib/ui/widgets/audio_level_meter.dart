// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:flutter/material.dart';

import '../theme.dart';

/// 5-stop gradient audio level VU meter matching upstream `DevicePanel.svelte`.
class AudioLevelMeter extends StatelessWidget {
  const AudioLevelMeter({
    super.key,
    required this.rawLevel,
  });

  final int? rawLevel;

  static double fractionFor(int? level) {
    if (level == null || level <= 0) return 0.0;
    return (level / 80.0).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pct = fractionFor(rawLevel);
    final unfilled = (1.0 - pct).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Color(0xFF2EA043),
                    Color(0xFF57B846),
                    Color(0xFFE0B400),
                    Color(0xFFE8863A),
                    Color(0xFFE5484D),
                  ],
                  stops: <double>[0.0, 0.35, 0.68, 0.85, 1.0],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 90),
                curve: Curves.linear,
                widthFactor: unfilled,
                heightFactor: 1.0,
                child: ColoredBox(color: colors.bg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
