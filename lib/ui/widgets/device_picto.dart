// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:flutter/material.dart';

import '../theme.dart';

/// Displays bundled DJI device artwork with an inline stroke microphone fallback.
class DevicePicto extends StatelessWidget {
  const DevicePicto({
    super.key,
    required this.assetKey,
    this.size = 40,
  });

  final String assetKey;
  final double size;

  static const Map<String, String> _knownAssets = <String, String>{
    'mic-mini-rx': 'assets/devices/mic-mini-rx.png',
    'mic-mini-tx': 'assets/devices/mic-mini-tx.png',
    'mic-mini-2-tx': 'assets/devices/mic-mini-2-tx.png',
  };

  @override
  Widget build(BuildContext context) {
    final path = _knownAssets[assetKey];
    if (path != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          path,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _FallbackMicIcon(size: size),
        ),
      );
    }
    return _FallbackMicIcon(size: size);
  }
}

class _FallbackMicIcon extends StatelessWidget {
  const _FallbackMicIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FallbackMicPainter(colors.textDim),
      ),
    );
  }
}

class _FallbackMicPainter extends CustomPainter {
  const _FallbackMicPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final capsule = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.37), width: w * 0.28, height: h * 0.42),
      Radius.circular(w * 0.14),
    );
    canvas.drawRRect(capsule, paint);

    final arcRect = Rect.fromCenter(center: Offset(w * 0.5, h * 0.44), width: w * 0.52, height: h * 0.42);
    canvas.drawArc(arcRect, 0, 3.14159, false, paint);
    canvas.drawLine(Offset(w * 0.5, h * 0.65), Offset(w * 0.5, h * 0.84), paint);
    canvas.drawLine(Offset(w * 0.34, h * 0.84), Offset(w * 0.66, h * 0.84), paint);
  }

  @override
  bool shouldRepaint(_FallbackMicPainter oldDelegate) => oldDelegate.color != color;
}
