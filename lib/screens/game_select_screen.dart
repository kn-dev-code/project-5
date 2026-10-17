import 'dart:async';

import 'package:flutter/material.dart';

import '../data/game_feed.dart';
import '../data/pick_store.dart';
import '../models/game.dart';
import 'pick_winner_screen.dart';

class GameSelectScreen extends StatefulWidget {
  const GameSelectScreen({
    super.key,
    this.feed,
    this.pickStore,
    this.refreshInterval = const Duration(seconds: 30),
  });

  /// Where games come from. Defaults to the shared [gameFeed].
  final GameFeed? feed;
  final PickStore? pickStore;

  /// How often scores are re-fetched while the screen is open.
  final Duration refreshInterval;

  @override
  State<GameSelectScreen> createState() => _GameSelectScreenState();
}

class _GameSelectScreenState extends State<GameSelectScreen> {
  late final GameFeed _feed = widget.feed ?? gameFeed;
  late final PickStore _pickStore = widget.pickStore ?? PickStore();
  late final Timer _refreshTimer;

  List<Game>? _games;
  Map<String, TeamSide> _picks = {};

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final (games, picks) = await (
      _feed.fetchGames(),
      _pickStore.loadPicks(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _games = games;
      _picks = picks;
    });
  }

  Future<void> _refresh() async {
    final previous = _games;
    final games = await _feed.fetchGames();
    if (!mounted) return;
    setState(() => _games = games);
    if (previous != null) _announceResults(previous, games);
  }

  /// Tells the user how their picks did for games that just ended.
  void _announceResults(List<Game> previous, List<Game> current) {
    final wasFinished = {
      for (final g in previous)
        if (g.isFinished) g.id,
    };
    final messages = [
      for (final game in current)
        if (game.isFinished &&
            !wasFinished.contains(game.id) &&
            _picks.containsKey(game.id))
          _resultMessage(game, _picks[game.id]!),
    ];
    if (messages.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(messages.join('\n'))));
  }

  static String _resultMessage(Game game, TeamSide pick) {
    final winner = game.winner;
    if (winner == null) {
      return '${game.homeTeam} vs ${game.awayTeam} ended in a tie.';
    }
    final outcome = winner == pick
        ? 'Your pick was right!'
        : 'Your pick missed.';
    return '${game.teamName(winner)} won! $outcome';
  }

  Future<void> _openPick(Game game) async {
    final pick = await Navigator.of(context).push<TeamSide>(
      MaterialPageRoute(
        builder: (_) =>
            PickWinnerScreen(game: game, initialPick: _picks[game.id]),
      ),
    );
    if (pick == null) return;
    await _pickStore.savePick(game.id, pick);
    if (!mounted) return;
    setState(() => _picks = {..._picks, game.id: pick});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final allGames = _games;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Game'),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ),
      body: SafeArea(
        child: allGames == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refresh,
                child: _buildList(allGames),
              ),
      ),
    );
  }

  Widget _buildList(List<Game> allGames) {
    final live = allGames.where((g) => g.status == GameStatus.live).toList();
    final upcoming = allGames
        .where((g) => g.status == GameStatus.upcoming)
        .toList();
    final finished = allGames
        .where((g) => g.status == GameStatus.finished)
        .toList();

    return ListView(
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
            pick: _picks[game.id],
            onTap: () => _openPick(game),
          ),
        if (upcoming.isNotEmpty) ...[
          const _SectionHeader('Upcoming'),
          for (final game in upcoming)
            _GameCard(game: game, pick: _picks[game.id]),
        ],
        if (finished.isNotEmpty) ...[
          const _SectionHeader('Finished'),
          for (final game in finished)
            _GameCard(game: game, pick: _picks[game.id]),
        ],
      ],
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
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, this.pick, this.onTap});

  final Game game;

  /// The side the user picked to win, if they made a pick.
  final TeamSide? pick;

  /// Only live games can be bet on, so only they get a tap handler.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final showScore = game.status != GameStatus.upcoming;

    return Opacity(
      opacity: enabled || game.isFinished ? 1 : 0.6,
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
                  isWinner: game.winner == TeamSide.home,
                ),
                const SizedBox(height: 6),
                _TeamRow(
                  name: game.awayTeam,
                  score: showScore ? game.awayScore : null,
                  isWinner: game.winner == TeamSide.away,
                ),
                if (game.isFinished) ...[
                  const SizedBox(height: 12),
                  Text(
                    game.winner == null
                        ? 'Ended in a tie'
                        : 'Winner: ${game.teamName(game.winner!)}',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                if (pick != null || enabled) ...[
                  const SizedBox(height: 12),
                  Text(
                    _pickLabel(),
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

  String _pickLabel() {
    final pick = this.pick;
    if (pick == null) return 'Tap to pick a winner';
    final picked = 'Your pick: ${game.teamName(pick)}';
    if (game.isFinished) {
      return game.winner == pick ? '$picked - correct!' : '$picked - missed';
    }
    return onTap != null ? '$picked (tap to change)' : picked;
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.name, this.score, this.isWinner = false});

  final String name;
  final int? score;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(child: Text(name, style: textTheme.titleMedium)),
        if (isWinner)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.emoji_events,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        if (score != null)
          Text(
            '$score',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.bold),
      ),
    );
  }

  static String _formatKickoff(BuildContext context, DateTime? kickoff) {
    if (kickoff == null) return 'Upcoming';
    return MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(kickoff));
  }
}
