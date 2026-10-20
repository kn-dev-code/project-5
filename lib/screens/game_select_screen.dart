import 'dart:async';

import 'package:flutter/material.dart';

import '../data/fake_crowd.dart';
import '../data/game_feed.dart';
import '../data/pick_store.dart';
import '../data/wallet_store.dart';
import '../models/bet.dart';
import '../models/crowd_stats.dart';
import '../models/game.dart';
import 'pick_winner_screen.dart';

class GameSelectScreen extends StatefulWidget {
  const GameSelectScreen({
    super.key,
    this.feed,
    this.pickStore,
    this.wallet,
    this.refreshInterval = const Duration(seconds: 30),
  });

  /// Where games come from. Defaults to the shared [gameFeed].
  final GameFeed? feed;
  final PickStore? pickStore;
  final WalletStore? wallet;

  /// How often scores are re-fetched while the screen is open.
  final Duration refreshInterval;

  @override
  State<GameSelectScreen> createState() => _GameSelectScreenState();
}

class _GameSelectScreenState extends State<GameSelectScreen> {
  late final GameFeed _feed = widget.feed ?? gameFeed;
  late final PickStore _pickStore = widget.pickStore ?? PickStore();
  late final WalletStore _wallet = widget.wallet ?? WalletStore();
  late final Timer _refreshTimer;

  List<Game>? _games;
  Map<String, TeamSide> _picks = {};
  Map<String, Bet> _bets = {};
  int _balance = 0;

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
    final games = await _feed.fetchGames();
    await _update(games, previous: null);
  }

  Future<void> _refresh() async {
    final games = await _feed.fetchGames();
    await _update(games, previous: _games);
  }

  /// Shows [games], pays out bets on finished games, and tells the user how
  /// their picks did. [previous] is null on first load.
  Future<void> _update(
    List<Game> games, {
    required List<Game>? previous,
  }) async {
    final settled = <String, Bet>{
      for (final game in games) game.id: ?await _wallet.settle(game),
    };
    final (picks, bets, balance) = await (
      _pickStore.loadPicks(),
      _wallet.loadBets(),
      _wallet.loadBalance(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _games = games;
      _picks = picks;
      _bets = bets;
      _balance = balance;
    });

    final wasFinished = {
      for (final g in previous ?? games)
        if (g.isFinished) g.id,
    };
    final messages = [
      for (final game in games)
        if (settled.containsKey(game.id) ||
            (game.isFinished &&
                !wasFinished.contains(game.id) &&
                picks.containsKey(game.id)))
          _resultMessage(game, picks[game.id], settled[game.id]),
    ];
    if (messages.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(messages.join('\n'))));
  }

  static String _resultMessage(Game game, TeamSide? pick, Bet? bet) {
    final winner = game.winner;
    final String result;
    if (winner == null) {
      result = '${game.homeTeam} vs ${game.awayTeam} ended in a tie.';
    } else {
      final outcome = winner == (bet?.side ?? pick)
          ? 'Your pick was right!'
          : 'Your pick missed.';
      result = '${game.teamName(winner)} won! $outcome';
    }
    if (bet == null) return result;
    return '$result ${_betOutcome(game, bet)}';
  }

  static String _betOutcome(Game game, Bet bet) {
    if (game.winner == null) return '${bet.amount} coins refunded.';
    final payout = bet.payout ?? 0;
    return payout > 0
        ? 'You won $payout coins.'
        : 'You lost ${bet.amount} coins.';
  }

  CrowdStats _crowd(Game game) =>
      fakeCrowdFor(game).withUser(pick: _picks[game.id], bet: _bets[game.id]);

  Future<void> _openPick(Game game) async {
    final result = await Navigator.of(context).push<PickResult>(
      MaterialPageRoute(
        builder: (_) => PickWinnerScreen(
          game: game,
          initialPick: _picks[game.id],
          balance: _balance,
          existingBet: _bets[game.id],
        ),
      ),
    );
    if (result == null) return;
    await _pickStore.savePick(game.id, result.side);
    if (result.bet > 0) {
      await _wallet.placeBet(game.id, result.side, result.bet);
    }
    final (bets, balance) = await (
      _wallet.loadBets(),
      _wallet.loadBalance(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _picks = {..._picks, game.id: result.side};
      _bets = bets;
      _balance = balance;
    });
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.monetization_on),
                const SizedBox(width: 4),
                Text('$_balance coins'),
              ],
            ),
          ),
        ],
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
        for (final game in live) _card(game, onTap: () => _openPick(game)),
        if (upcoming.isNotEmpty) ...[
          const _SectionHeader('Upcoming'),
          for (final game in upcoming) _card(game),
        ],
        if (finished.isNotEmpty) ...[
          const _SectionHeader('Finished'),
          for (final game in finished) _card(game),
        ],
      ],
    );
  }

  Widget _card(Game game, {VoidCallback? onTap}) => _GameCard(
    game: game,
    crowd: _crowd(game),
    pick: _picks[game.id],
    bet: _bets[game.id],
    onTap: onTap,
  );
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
  const _GameCard({
    required this.game,
    required this.crowd,
    this.pick,
    this.bet,
    this.onTap,
  });

  final Game game;

  /// Votes and bets from all users, including this one.
  final CrowdStats crowd;

  /// The side the user picked to win, if they made a pick.
  final TeamSide? pick;

  final Bet? bet;

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
                const SizedBox(height: 12),
                _VoteSplit(crowd: crowd),
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
                if (bet != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _betLabel(bet!),
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
    if (onTap == null) return picked;
    return bet == null ? '$picked (tap to change)' : picked;
  }

  String _betLabel(Bet bet) {
    final staked = 'Bet: ${bet.amount} coins on ${game.teamName(bet.side)}';
    final payout = bet.payout;
    if (payout == null) {
      final ifWon = crowd.winningPayout(bet.side, bet.amount);
      return '$staked (pays $ifWon if it wins)';
    }
    if (game.winner == null) return '$staked - refunded';
    return payout > 0 ? '$staked - won $payout' : '$staked - lost';
  }
}

/// Bar showing what share of users voted for each team.
class _VoteSplit extends StatelessWidget {
  const _VoteSplit({required this.crowd});

  final CrowdStats crowd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.onSurfaceVariant);
    final home = crowd.votePercent(TeamSide.home);
    final away = crowd.votePercent(TeamSide.away);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('$home%', style: style),
            Expanded(
              child: Text(
                '${crowd.totalVotes} votes',
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
            Text('$away%', style: style),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: home / 100,
          color: colors.primary,
          backgroundColor: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
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
