// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:flutter/material.dart';

import '../theme.dart';

/// 7-tier DJI Mic battery gauge (1=full .. 7=critical) with charging bolt and
/// 500ms hard-cut critical `!` blink matching upstream `BatteryIcon.svelte`.
class BatteryIcon extends StatefulWidget {
  const BatteryIcon({
    super.key,
    required this.value,
    this.charging = false,
    this.size = 20,
    this.tr,
  });

  final int? value;
  final bool charging;
  final double size;
  final String Function(String key, [Map<String, Object>? params])? tr;

  static String labelFor(int value) {
    if (value == 1) return 'Fully Charged';
    if (value >= 2 && value <= 4) return 'Good';
    if (value == 5) return 'Low';
    if (value == 6) return 'Very Low';
    return 'Critical';
  }

  static double fillFor(int value) {
    if (value <= 1) return 1.0;
    if (value <= 4) return 1.0 - (value - 1) * 0.25;
    if (value == 5) return 0.25;
    return 0.0;
  }

  @override
  State<BatteryIcon> createState() => _BatteryIconState();
}

class _BatteryIconState extends State<BatteryIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  bool get _shouldBlink => widget.value != null && widget.value! >= 7 && !widget.charging;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    if (_shouldBlink) _blink.repeat();
  }

  @override
  void didUpdateWidget(BatteryIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldBlink && !_blink.isAnimating) {
      _blink.repeat();
    } else if (!_shouldBlink && _blink.isAnimating) {
      _blink.stop();
      _blink.value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final val = widget.value;
    if (val == null || val <= 0) {
      return const SizedBox.shrink();
    }

    final colors = AppColors.of(context);
    final Color tierColor = val <= 4
        ? colors.good
        : val == 5
            ? colors.warn
            : colors.danger;
    final rawLabel = BatteryIcon.labelFor(val);
    final label = widget.tr != null ? widget.tr!(rawLabel) : rawLabel;
    final tooltipKey = widget.charging ? 'Battery: {label} (charging)' : 'Battery: {label}';
    final tooltip = widget.tr != null
        ? widget.tr!(tooltipKey, <String, Object>{'label': label})
        : 'Battery: $label${widget.charging ? ' (charging)' : ''}';
    final width = widget.size * 1.45;
    final height = widget.size * 0.78;

    return Tooltip(
      message: tooltip,
      child: AnimatedBuilder(
        animation: _blink,
        builder: (context, _) {
          final showBang = _shouldBlink && _blink.value < 0.5;
          return SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: _BatteryPainter(
                fillFraction: BatteryIcon.fillFor(val),
                color: tierColor,
                knockoutColor: colors.bgPanel,
                charging: widget.charging,
                showCriticalBang: showBang,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter({
    required this.fillFraction,
    required this.color,
    required this.knockoutColor,
    required this.charging,
    required this.showCriticalBang,
  });

  final double fillFraction;
  final Color color;
  final Color knockoutColor;
  final bool charging;
  final bool showCriticalBang;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = (size.height * 0.12).clamp(1.2, 2.0);
    final bodyW = size.width * 0.86;
    final bodyRect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      bodyW - stroke,
      size.height - stroke,
    );
    final radius = Radius.circular(size.height * 0.22);

    // Outline.
    final outlinePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, radius), outlinePaint);

    // Positive terminal nub.
    final nubPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final nubH = size.height * 0.44;
    final nubRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(bodyW + stroke * 0.4, (size.height - nubH) / 2, size.width - bodyW - stroke * 0.4, nubH),
      topRight: Radius.circular(stroke),
      bottomRight: Radius.circular(stroke),
    );
    canvas.drawRRect(nubRect, nubPaint);

    // Inner charge fill.
    if (fillFraction > 0) {
      final inset = stroke * 1.45;
      final maxFillW = (bodyRect.width - inset * 2).clamp(0.0, bodyRect.width);
      final fillRect = Rect.fromLTWH(
        bodyRect.left + inset,
        bodyRect.top + inset,
        maxFillW * fillFraction,
        bodyRect.height - inset * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, Radius.circular(stroke * 0.7)),
        nubPaint,
      );
    }

    final center = bodyRect.center;
    if (charging) {
      final h = bodyRect.height * 0.76;
      final w = h * 0.6;
      final path = Path()
        ..moveTo(center.dx + w * 0.1, center.dy - h * 0.5)
        ..lineTo(center.dx - w * 0.42, center.dy + h * 0.06)
        ..lineTo(center.dx + w * 0.04, center.dy + h * 0.06)
        ..lineTo(center.dx - w * 0.1, center.dy + h * 0.5)
        ..lineTo(center.dx + w * 0.42, center.dy - h * 0.06)
        ..lineTo(center.dx - w * 0.04, center.dy - h * 0.06)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = knockoutColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.5
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    } else if (showCriticalBang) {
      final bangPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final barH = bodyRect.height * 0.42;
      final barW = (stroke * 1.25).clamp(1.6, 2.4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(center.dx, center.dy - barH * 0.25), width: barW, height: barH),
          Radius.circular(barW / 2),
        ),
        bangPaint,
      );
      canvas.drawCircle(Offset(center.dx, center.dy + barH * 0.52), barW * 0.58, bangPaint);
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.fillFraction != fillFraction ||
      old.color != color ||
      old.knockoutColor != knockoutColor ||
      old.charging != charging ||
      old.showCriticalBang != showCriticalBang;
}
