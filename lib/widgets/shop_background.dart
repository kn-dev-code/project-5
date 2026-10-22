import 'package:flutter/material.dart';

import '../data/app_theme.dart';
import '../models/shop_item.dart';

/// Paints the player's active shop background behind [child].
class ShopBackground extends StatelessWidget {
  const ShopBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ShopItem?>(
      valueListenable: appBackground,
      builder: (context, item, _) {
        if (item == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _painterFor(item)),
            child,
          ],
        );
      },
    );
  }

  static CustomPainter _painterFor(ShopItem item) => switch (item.id) {
    'stadium_lights' => _StadiumLightsPainter(item.color),
    'gridiron' => _GridironPainter(item.color),
    _ => _GradientPainter(item.color),
  };
}

/// Puts [child] on a translucent card while a background is showing, so text
/// drawn straight on the screen stays readable.
class BackgroundPanel extends StatelessWidget {
  const BackgroundPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ShopItem?>(
      valueListenable: appBackground,
      builder: (context, item, _) {
        if (item == null) return child;
        return Card(
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
          child: Padding(padding: padding, child: child),
        );
      },
    );
  }
}

class _GradientPainter extends CustomPainter {
  _GradientPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, Color.lerp(color, Colors.black, 0.5)!],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GradientPainter old) => old.color != color;
}

/// Night sky with floodlight glows over a strip of field.
class _StadiumLightsPainter extends _GradientPainter {
  _StadiumLightsPainter(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    super.paint(canvas, size);
    for (final x in [0.15, 0.85]) {
      final center = Offset(size.width * x, size.height * 0.08);
      final radius = size.shortestSide * 0.6;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.55),
              Colors.amber.withValues(alpha: 0.15),
              Colors.transparent,
            ],
            stops: const [0, 0.35, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.82, size.width, size.height * 0.18),
      Paint()..color = const Color(0xFF2E6B3A),
    );
  }
}

/// Mowed field stripes with white yard lines.
class _GridironPainter extends CustomPainter {
  _GridironPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stripes = 10;
    final stripeHeight = size.height / stripes;
    final light = Color.lerp(color, Colors.white, 0.08)!;
    for (var i = 0; i < stripes; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * stripeHeight, size.width, stripeHeight),
        Paint()..color = i.isEven ? color : light,
      );
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    for (var i = 1; i < stripes; i++) {
      final y = i * stripeHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      for (final x in [0.3, 0.7]) {
        final hashX = size.width * x;
        canvas.drawLine(
          Offset(hashX, y - stripeHeight / 2 - 6),
          Offset(hashX, y - stripeHeight / 2 + 6),
          line,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridironPainter old) => old.color != color;
}
