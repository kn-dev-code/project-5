import 'package:flutter/material.dart';

import '../data/fake_games.dart';
import '../models/game.dart';
import 'pick_winner_screen.dart';

class GameSelectScreen extends StatelessWidget {
  const GameSelectScreen({super.key, this.games});

  /// Games to show. Defaults to [fakeGames] until a real feed exists.
  final List<Game>? games;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final allGames = games ?? fakeGames;
    final live = allGames.where((g) => g.status == GameStatus.live).toList();
    final upcoming =
        allGames.where((g) => g.status == GameStatus.upcoming).toList();
    final finished =
        allGames.where((g) => g.status == GameStatus.finished).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Game'),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionHeader('Live Now'),
            if (live.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No live games right now.'),
              ),
            for (final game in live)
              _GameCard(
                game: game,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PickWinnerScreen(game: game),
                  ),
                ),
              ),
            if (upcoming.isNotEmpty) ...[
              const _SectionHeader('Upcoming'),
              for (final game in upcoming) _GameCard(game: game),
            ],
            if (finished.isNotEmpty) ...[
              const _SectionHeader('Finished'),
              for (final game in finished) _GameCard(game: game),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, this.onTap});

  final Game game;

  /// Only live games can be bet on, so only they get a tap handler.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final showScore = game.status != GameStatus.upcoming;

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        game.league,
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    _StatusChip(game: game),
                  ],
                ),
                const SizedBox(height: 12),
                _TeamRow(
                  name: game.homeTeam,
                  score: showScore ? game.homeScore : null,
                ),
                const SizedBox(height: 6),
                _TeamRow(
                  name: game.awayTeam,
                  score: showScore ? game.awayScore : null,
                ),
                if (enabled) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Tap to pick a winner',
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.name, this.score});

  final String name;
  final int? score;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(child: Text(name, style: textTheme.titleMedium)),
        if (score != null)
          Text(
            '$score',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final (label, background, foreground) = switch (game.status) {
      GameStatus.live => (
          'LIVE ${game.gameClock ?? ''}'.trim(),
          colors.error,
          colors.onError,
        ),
      GameStatus.upcoming => (
          _formatKickoff(context, game.kickoff),
          colors.secondaryContainer,
          colors.onSecondaryContainer,
        ),
      GameStatus.finished => (
          'FINAL',
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  static String _formatKickoff(BuildContext context, DateTime? kickoff) {
    if (kickoff == null) return 'Upcoming';
    return MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(kickoff));
  }
}
