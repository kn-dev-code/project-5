import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:football_core/models/game.dart';

enum ScoreEffectKind {
  /// The team the user backed scored.
  fanfare,

  /// The other team scored.
  moneyAway,
}

class ScoreEvent {
  const ScoreEvent({
    required this.kind,
    required this.team,
    required this.points,
  });

  final ScoreEffectKind kind;
  final String team;
  final int points;

  String get headline => switch (kind) {
    ScoreEffectKind.fanfare => '${_play(points)}! $team +$points',
    ScoreEffectKind.moneyAway =>
      '$team scored $points. Your coins are slipping away...',
  };

  static String _play(int points) => switch (points) {
    >= 6 => 'TOUCHDOWN',
    3 => 'FIELD GOAL',
    _ => 'SCORE',
  };
}

/// Scores that changed between [previous] and [current] in games where the
/// user backed a side, keyed in [backed] by game id.
List<ScoreEvent> scoreEvents(
  List<Game> previous,
  List<Game> current,
  Map<String, TeamSide> backed,
) {
  final before = {for (final game in previous) game.id: game};
  int points(Game game, TeamSide side) =>
      side == TeamSide.home ? game.homeScore : game.awayScore;

  return [
    for (final game in current)
      if (before[game.id] case final old? when backed.containsKey(game.id))
        for (final side in TeamSide.values)
          if (points(game, side) - points(old, side) case final scored
              when scored > 0)
            ScoreEvent(
              kind: side == backed[game.id]
                  ? ScoreEffectKind.fanfare
                  : ScoreEffectKind.moneyAway,
              team: game.teamName(side),
              points: scored,
            ),
  ];
}

/// Plays one [ScoreEvent] over the screen, then calls [onDone].
class ScoreEffect extends StatefulWidget {
  const ScoreEffect({super.key, required this.event, required this.onDone});

  static const duration = Duration(milliseconds: 2600);

  final ScoreEvent event;
  final VoidCallback onDone;

  @override
  State<ScoreEffect> createState() => _ScoreEffectState();
}

class _ScoreEffectState extends State<ScoreEffect>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: ScoreEffect.duration,
  );
  final _seed = Random().nextInt(1 << 31);

  bool get _fanfare => widget.event.kind == ScoreEffectKind.fanfare;

  @override
  void initState() {
    super.initState();
    _fanfare ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) widget.onDone();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (!reduceMotion)
                _fanfare
                    ? CustomPaint(painter: _ConfettiPainter(t, _seed))
                    : _FloatingCoins(t: t, seed: _seed),
              Align(
                alignment: const Alignment(0, -0.6),
                child: _Banner(event: widget.event, t: t),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.event, required this.t});

  final ScoreEvent event;

  /// Animation progress from 0 to 1.
  final double t;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fanfare = event.kind == ScoreEffectKind.fanfare;
    final scale = fanfare
        ? Curves.elasticOut.transform((t / 0.35).clamp(0, 1))
        : Curves.easeOut.transform((t / 0.2).clamp(0, 1));
    final opacity = t < 0.8 ? 1.0 : (1 - t) / 0.2;
    final background = fanfare
        ? colors.primaryContainer
        : colors.errorContainer;
    final foreground = fanfare
        ? colors.onPrimaryContainer
        : colors.onErrorContainer;

    return Opacity(
      opacity: opacity.clamp(0, 1),
      child: Transform.scale(
        scale: scale,
        child: Material(
          color: background,
          elevation: 6,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  fanfare ? Icons.celebration : Icons.money_off,
                  color: foreground,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    event.headline,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Confetti bursting from the top of the screen and falling.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.seed);

  static const _count = 70;
  static const _colors = [
    Colors.amber,
    Colors.redAccent,
    Colors.lightBlueAccent,
    Colors.greenAccent,
    Colors.purpleAccent,
    Colors.white,
  ];

  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    final opacity = t < 0.7 ? 1.0 : (1 - t) / 0.3;
    for (var i = 0; i < _count; i++) {
      final angle = -pi / 2 + (random.nextDouble() - 0.5) * pi * 0.9;
      final speed = 0.5 + random.nextDouble() * 0.7;
      final x = size.width / 2 + cos(angle) * speed * t * size.width * 0.8;
      final y =
          size.height * 0.2 +
          sin(angle) * speed * t * size.height * 0.5 +
          t * t * size.height * 0.9;
      final color = _colors[random.nextInt(_colors.length)];
      final spin = random.nextDouble() * 10;
      final w = 6 + random.nextDouble() * 6;

      canvas
        ..save()
        ..translate(x, y)
        ..rotate(spin * t * 2 * pi);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.5),
        Paint()..color = color.withValues(alpha: opacity.clamp(0, 1)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t || old.seed != seed;
}

/// Coins drifting up and off the screen as they fade.
class _FloatingCoins extends StatelessWidget {
  const _FloatingCoins({required this.t, required this.seed});

  static const _count = 14;

  final double t;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final random = Random(seed);
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final coins = <Widget>[];
        for (var i = 0; i < _count; i++) {
          final startX = width * (0.15 + random.nextDouble() * 0.7);
          final delay = random.nextDouble() * 0.3;
          final speed = 0.5 + random.nextDouble() * 0.5;
          final phase = random.nextDouble() * 2 * pi;
          final local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
          coins.add(
            Positioned(
              left: startX + sin(local * 6 + phase) * 24,
              top: height * 0.8 - local * height * speed,
              child: Opacity(
                opacity: 1 - local,
                child: Transform.rotate(
                  angle: local * 3 + phase,
                  child: const Icon(
                    Icons.monetization_on,
                    size: 32,
                    color: Colors.amber,
                  ),
                ),
              ),
            ),
          );
        }
        return Stack(children: coins);
      },
    );
  }
}
