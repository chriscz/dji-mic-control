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
    if (assetKey == 'mobile-rx') {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: const _MobileRxPainter()),
      );
    }
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

/// Vector pictogram for DJI Mic Series Mobile Receiver, matching upstream PR #4 `mobile-rx.svg`.
class _MobileRxPainter extends CustomPainter {
  const _MobileRxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 64.0;
    final sy = size.height / 64.0;
    canvas.save();
    canvas.scale(sx, sy);

    // Top USB-C plug.
    final plugRect = RRect.fromRectAndRadius(const Rect.fromLTWH(25, 3, 14, 16), const Radius.circular(3));
    canvas.drawRRect(plugRect, Paint()..color = const Color(0xFFB2B9C1));
    canvas.drawRRect(
      plugRect,
      Paint()
        ..color = const Color(0xFF647182)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Main rounded receiver body.
    final bodyRect = RRect.fromRectAndRadius(const Rect.fromLTWH(7, 18, 50, 30), const Radius.circular(9));
    canvas.drawRRect(bodyRect, Paint()..color = const Color(0xFFF0F2F4));
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..color = const Color(0xFF8C98A7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Bottom clip / base.
    final baseRect = RRect.fromRectAndRadius(const Rect.fromLTWH(23, 47, 18, 7), const Radius.circular(3));
    canvas.drawRRect(baseRect, Paint()..color = const Color(0xFF344150));

    // Two green status LEDs.
    final ledPaint = Paint()..color = const Color(0xFF37A16C);
    canvas.drawCircle(const Offset(17, 28), 2, ledPaint);
    canvas.drawCircle(const Offset(47, 28), 2, ledPaint);

    // Center slot / O-L-H bar.
    canvas.drawLine(
      const Offset(26, 36),
      const Offset(38, 36),
      Paint()
        ..color = const Color(0xFF8090A2)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MobileRxPainter oldDelegate) => false;
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
