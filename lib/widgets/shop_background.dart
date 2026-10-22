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
    'sunset_drive' => _SunsetPainter(item.color),
    'snow_game' => _SnowPainter(item.color),
    'championship' => _ChampionshipPainter(item.color),
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

class _SunsetPainter extends _GradientPainter {
  _SunsetPainter(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    super.paint(canvas, size);
    final sunCenter = Offset(size.width * 0.5, size.height * 0.62);
    canvas.drawCircle(
      sunCenter,
      size.shortestSide * 0.16,
      Paint()..color = const Color(0xFFFFD180).withValues(alpha: 0.85),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.72, size.width, size.height * 0.28),
      Paint()..color = const Color(0xFF263C36).withValues(alpha: 0.85),
    );
  }
}

class _SnowPainter extends _GradientPainter {
  _SnowPainter(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    super.paint(canvas, size);
    final snow = Paint()..color = Colors.white.withValues(alpha: 0.72);
    for (var row = 0; row < 9; row++) {
      for (var column = 0; column < 7; column++) {
        final x = size.width * ((column * 37 + row * 19) % 100) / 100;
        final y = size.height * ((row * 23 + column * 11) % 100) / 100;
        canvas.drawCircle(Offset(x, y), 1.5 + (row % 3) * 0.6, snow);
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.84, size.width, size.height * 0.16),
      Paint()..color = const Color(0xFFDCEAF0).withValues(alpha: 0.8),
    );
  }
}

class _ChampionshipPainter extends _StadiumLightsPainter {
  _ChampionshipPainter(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    super.paint(canvas, size);
    final paint = Paint()
      ..color = const Color(0xFFFFD54F).withValues(alpha: 0.65);
    for (var i = 0; i < 24; i++) {
      final x = size.width * ((i * 41) % 100) / 100;
      final y = size.height * (0.12 + ((i * 29) % 58) / 100);
      canvas.drawCircle(Offset(x, y), 1.6 + (i % 3) * 0.6, paint);
    }
  }
}
