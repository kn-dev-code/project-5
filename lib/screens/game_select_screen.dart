import 'dart:async';

import 'package:flutter/material.dart';
import 'package:football_core/api/betting_api.dart';
import 'package:football_core/models/bet.dart';
import 'package:football_core/models/crowd_stats.dart';
import 'package:football_core/models/game.dart';
import 'package:football_core/models/game_notification.dart';
import 'package:football_core/models/team_record.dart';
import 'package:football_core/server/payouts.dart';

import '../data/auth.dart';
import '../data/backend.dart';
import '../data/errors.dart';
import '../data/pick_store.dart';
import '../data/sound_effects.dart';
import '../widgets/game_time.dart';
import '../widgets/score_effects.dart';
import '../widgets/shop_background.dart';
import 'notifications_screen.dart';
import 'pick_winner_screen.dart';

class GameSelectScreen extends StatefulWidget {
  const GameSelectScreen({
    super.key,
    required this.session,
    this.server,
    this.pickStore,
    this.refreshInterval = const Duration(seconds: 30),
  });

  /// The logged-in player whose coins and bets are shown.
  final Session session;

  /// Where games, coins and bets come from. Defaults to the shared [backend].
  final BettingApi? server;
  final PickStore? pickStore;

  /// How often scores are re-fetched while the screen is open.
  final Duration refreshInterval;

  @override
  State<GameSelectScreen> createState() => _GameSelectScreenState();
}

class _GameSelectScreenState extends State<GameSelectScreen> {
  late final BettingApi _server = widget.server ?? backend;
  late final PickStore _pickStore = widget.pickStore ?? PickStore();
  late final String _token = widget.session.token;
  late final Timer _refreshTimer;

  List<Game>? _games;

  /// Why the games couldn't be loaded, shown until a retry works.
  String? _loadError;
  Map<String, TeamSide> _picks = {};
  Map<String, Bet> _bets = {};

  /// Other players' votes and bets per game, not counting this user.
  Map<String, CrowdStats> _crowds = {};

  /// Null until the first load, so the app bar never shows a made-up 0.
  int? _balance;
  int _unreadNotifications = 0;

  /// Newest notification id already accounted for, so only notifications that
  /// arrive while the screen is open pop up. Null before the first load.
  int? _lastNotificationId;

  /// Scoring effects currently playing, keyed by a unique id.
  final Map<int, ScoreEvent> _effects = {};
  var _nextEffectId = 0;

  /// At most this many effects play at once; older ones are dropped.
  static const _maxEffects = 3;

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
    try {
      final games = await _server.fetchGames();
      await _update(games, previous: null);
    } catch (e) {
      final message = userMessage(e);
      if (message == null) rethrow;
      if (mounted) setState(() => _loadError = message);
    }
  }

  /// Fetches games again. Failed automatic refreshes are skipped quietly,
  /// since the next one may work; when the player pulls to refresh, they're
  /// told why nothing changed.
  Future<void> _refresh({bool userAsked = false}) async {
    if (_games == null) return _load();
    try {
      final games = await _server.fetchGames();
      await _update(games, previous: _games);
    } catch (e) {
      final message = userMessage(e);
      if (message == null) rethrow;
      if (userAsked && mounted) _showMessage(message);
    }
  }

  /// Shows a refusal or failure, with the error sound.
  void _showMessage(String message) {
    sfx.play(Sound.error);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Shows [games] and tells the user how their picks did and what the server
  /// paid out for their bets. [previous] is null on first load.
  Future<void> _update(
    List<Game> games, {
    required List<Game>? previous,
  }) async {
    // Settles first (the caller already fetched games), so a bailout only
    // happens once the player's last bet is decided.
    final bailout = await _server.claimBailoutIfBroke(_token);
    final (picks, bets, balance, crowds, settled, notifications) = await (
      _pickStore.loadPicks(),
      _server.bets(_token),
      _server.balance(_token),
      _loadCrowds(games),
      _server.takeResults(_token),
      _server.notifications(_token),
    ).wait;
    if (!mounted) return;
    // Results already get their own message below, so only halftime updates
    // pop up here.
    final lastSeen = _lastNotificationId;
    final halftimes = lastSeen == null
        ? const <GameNotification>[]
        : notifications.reversed.where(
            (n) => n.id > lastSeen && n.kind == GameNotificationKind.halftime,
          );
    final scored = previous == null
        ? const <ScoreEvent>[]
        : scoreEvents(previous, games, {
            ...picks,
            for (final MapEntry(:key, :value) in bets.entries) key: value.side,
          });
    setState(() {
      _games = games;
      _loadError = null;
      _picks = picks;
      _bets = bets;
      _crowds = crowds;
      _balance = balance;
      _unreadNotifications = notifications.where((n) => !n.read).length;
      _lastNotificationId = notifications.isEmpty
          ? lastSeen ?? -1
          : notifications.first.id;
      for (final event in scored) {
        _effects[_nextEffectId++] = event;
      }
      while (_effects.length > _maxEffects) {
        _effects.remove(_effects.keys.first);
      }
    });

    final wasFinished = {
      for (final g in previous ?? games)
        if (g.isFinished) g.id,
    };
    final messages = [
      for (final game in games)
        if (settled.contains(game.id) ||
            (game.isFinished &&
                !wasFinished.contains(game.id) &&
                picks.containsKey(game.id)))
          _resultMessage(
            game,
            picks[game.id],
            settled.contains(game.id) ? bets[game.id] : null,
          ),
      if (halftimes.isNotEmpty) notificationSummary(halftimes),
      if (bailout > 0)
        "You're out of coins, so here are $bailout to keep playing. "
            'This bailout comes once a day.',
    ];
    if (messages.isEmpty) return;
    sfx.play(_updateSound(settled, bets, bailout));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(messages.join('\n'))));
  }

  /// One sound for everything an update reports, the best news winning:
  /// coins for a win or a bailout, a sad slide for a loss, otherwise a ding.
  static Sound _updateSound(
    List<String> settled,
    Map<String, Bet> bets,
    int bailout,
  ) {
    final payouts = [for (final id in settled) ?bets[id]?.payout];
    if (bailout > 0 || payouts.any((p) => p > 0)) return Sound.coins;
    if (payouts.isNotEmpty) return Sound.lose;
    return Sound.notify;
  }

  static String _resultMessage(Game game, TeamSide? pick, Bet? bet) {
    final winner = game.winner;
    final String result;
    if (winner == null) {
      result = '${game.homeTeam} vs ${game.awayTeam} ended in a tie.';
    } else {
      final range = bet?.scoreRange;
      final outcome = winner != (bet?.side ?? pick)
          ? 'Your pick missed.'
          : range != null && !range.contains(game.score(winner))
          ? 'Your pick was right, but the score missed your $range range.'
          : 'Your pick was right!';
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

  /// Every game's crowd stats, requested all at once; one at a time takes
  /// seconds with a full slate of live games.
  Future<Map<String, CrowdStats>> _loadCrowds(List<Game> games) async {
    final crowds = await Future.wait([
      for (final game in games) _server.crowd(game, token: _token),
    ]);
    return {for (final (i, game) in games.indexed) game.id: crowds[i]};
  }

  CrowdStats _crowd(Game game) =>
      _crowds[game.id]!.withUser(pick: _picks[game.id], bet: _bets[game.id]);

  Future<void> _openPick(Game game) async {
    final result = await Navigator.of(context).push<PickResult>(
      MaterialPageRoute(
        builder: (_) => PickWinnerScreen(
          game: game,
          initialPick: _picks[game.id],
          crowd: _crowds[game.id]!,
          balance: _balance ?? 0,
          existingBet: _bets[game.id],
        ),
      ),
    );
    if (result == null) return;
    // A pick always comes with a bet, so it only counts if the bet goes
    // through. With an existing bet [result.bet] is 0 and the pick is unchanged.
    if (result.bet > 0) {
      try {
        await _server.placeBet(
          _token,
          game.id,
          result.side,
          result.bet,
          scoreRange: result.scoreRange,
        );
        sfx.play(Sound.bet);
      } catch (e) {
        final message = userMessage(e);
        if (message == null) rethrow;
        if (mounted) _showMessage(message);
        return;
      }
    }
    await _pickStore.savePick(game.id, result.side);
    final Map<String, Bet> bets;
    final int balance;
    final CrowdStats crowd;
    try {
      (bets, balance, crowd) = await (
        _server.bets(_token),
        _server.balance(_token),
        _server.crowd(game, token: _token),
      ).wait;
    } on ParallelWaitError {
      // The bet went through; the next refresh will show it.
      return;
    }
    if (!mounted) return;
    setState(() {
      _picks = {..._picks, game.id: result.side};
      _bets = bets;
      _crowds = {..._crowds, game.id: crowd};
      _balance = balance;
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            NotificationsScreen(session: widget.session, server: _server),
      ),
    );
    try {
      final notifications = await _server.notifications(_token);
      if (!mounted) return;
      setState(
        () => _unreadNotifications = notifications.where((n) => !n.read).length,
      );
    } catch (e) {
      // The next refresh updates the count.
      if (userMessage(e) == null) rethrow;
    }
  }

  Future<void> _cashOutHalf(Game game) async {
    try {
      final refund = await _server.cashOutHalf(_token, game.id);
      final (bets, balance, crowd) = await (
        _server.bets(_token),
        _server.balance(_token),
        _server.crowd(game, token: _token),
      ).wait;
      if (!mounted) return;
      setState(() {
        _bets = bets;
        _balance = balance;
        _crowds = {..._crowds, game.id: crowd};
      });
      sfx.play(Sound.coins);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$refund coins returned to your balance.')),
      );
    } catch (e) {
      final message = userMessage(e);
      if (message == null) rethrow;
      if (mounted) _showMessage(message);
    }
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
          NotificationBell(
            unread: _unreadNotifications,
            onPressed: _openNotifications,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.monetization_on),
                const SizedBox(width: 4),
                Text(_balance == null ? '… coins' : '$_balance coins'),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ShopBackground(
            child: SafeArea(
              child: allGames == null
                  ? Center(
                      child: _loadError == null
                          ? const CircularProgressIndicator()
                          : _LoadError(message: _loadError!, onRetry: _load),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _refresh(userAsked: true),
                      child: _buildList(allGames),
                    ),
            ),
          ),
          for (final MapEntry(key: id, value: event) in _effects.entries)
            ScoreEffect(
              key: ValueKey(id),
              event: event,
              onDone: () => setState(() => _effects.remove(id)),
            ),
        ],
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
            child: BackgroundPanel(
              padding: EdgeInsets.all(12),
              child: Text('No live games right now.'),
            ),
          ),
        for (final game in live) _card(game),
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

  Widget _card(Game game) => _GameCard(
    game: game,
    crowd: _crowd(game),
    pick: _picks[game.id],
    bet: _bets[game.id],
    onTap: game.isBettingOpen ? sfx.withSound(() => _openPick(game)) : null,
    onCashOut: _canCashOut(game, _bets[game.id])
        ? () => _cashOutHalf(game)
        : null,
  );

  static bool _canCashOut(Game game, Bet? bet) =>
      game.isBeforeHalftime &&
      bet != null &&
      !bet.isSettled &&
      bet.cashOutAmount == 0 &&
      bet.amount >= 2;
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: BackgroundPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: sfx.withSound(onRetry),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: BackgroundPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
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
    this.onCashOut,
  });

  final Game game;

  /// Votes and bets from all users, including this one.
  final CrowdStats crowd;

  /// The side the user picked to win, if they made a pick.
  final TeamSide? pick;

  final Bet? bet;

  /// Only games still taking bets get a tap handler.
  final VoidCallback? onTap;

  final VoidCallback? onCashOut;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final showScore = game.status != GameStatus.upcoming;

    return Opacity(
      opacity: enabled || game.isLive || game.isFinished ? 1 : 0.6,
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
                        [
                          game.league,
                          if (game.kickoff case final kickoff?)
                            formatGameDay(context, kickoff),
                          if (game.endsAt case final endsAt?
                              when !game.isFinished)
                            'ends ${formatGameTime(context, endsAt)}',
                        ].join(' · '),
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
                  record: game.homeRecord,
                  score: showScore ? game.homeScore : null,
                  isWinner: game.winner == TeamSide.home,
                ),
                const SizedBox(height: 6),
                _TeamRow(
                  name: game.awayTeam,
                  record: game.awayRecord,
                  score: showScore ? game.awayScore : null,
                  isWinner: game.winner == TeamSide.away,
                ),
                const SizedBox(height: 12),
                _VoteSplit(game: game, crowd: crowd),
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
                if (pick != null || enabled || game.isLive) ...[
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
                  if (onCashOut != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: onCashOut,
                        icon: const Icon(Icons.savings_outlined),
                        label: Text(
                          'Cash out half (${bet!.amount ~/ 2} coins)',
                        ),
                      ),
                    ),
                  ],
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
    if (pick == null) {
      return onTap != null
          ? 'Tap to pick a winner'
          : 'Betting closed after the first quarter';
    }
    final picked = 'Your pick: ${game.teamName(pick)}';
    if (game.isFinished) {
      return game.winner == pick ? '$picked - correct!' : '$picked - missed';
    }
    if (onTap == null) return picked;
    return bet == null ? '$picked (tap to change)' : picked;
  }

  String _betLabel(Bet bet) {
    final range = bet.scoreRange == null ? '' : ' scoring ${bet.scoreRange}';
    final staked =
        'Bet: ${bet.amount} coins on ${game.teamName(bet.side)}$range';
    final returned = bet.cashOutAmount > 0
        ? ' (${bet.cashOutAmount} coins returned before halftime)'
        : '';
    final payout = bet.payout;
    if (payout == null) {
      final ifWon = applyMultiplier(
        crowd.winningPayout(bet.side, bet.amount),
        totalMultiplier(bet),
      );
      final multiplier = totalMultiplier(bet);
      final bonus = multiplier > 1 ? ' with ${multiplier}x bonus' : '';
      return '$staked$returned (pays $ifWon$bonus if it wins)';
    }
    if (game.winner == null) return '$staked$returned - refunded';
    return payout > 0
        ? '$staked$returned - won $payout'
        : '$staked$returned - lost';
  }
}

/// Bar showing what share of users voted for each team, and the odds and
/// bettor count on each side.
class _VoteSplit extends StatelessWidget {
  const _VoteSplit({required this.game, required this.crowd});

  final Game game;
  final CrowdStats crowd;

  String _betSummary(TeamSide side) {
    final bettors = crowd.bettors(side);
    final people = '$bettors ${bettors == 1 ? 'bettor' : 'bettors'}';
    final odds = crowd.odds(side);
    if (odds == null) return people;
    final shown = odds * underdogMultiplier(game.record(side));
    return '${formatOdds(shown)} · $people';
  }

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
        const SizedBox(height: 4),
        Row(
          children: [
            Text(_betSummary(TeamSide.home), style: style),
            const Spacer(),
            Text(_betSummary(TeamSide.away), style: style),
          ],
        ),
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.name,
    this.record,
    this.score,
    this.isWinner = false,
  });

  final String name;
  final TeamRecord? record;
  final int? score;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(child: Text(name, style: textTheme.titleMedium)),
              if (record != null) ...[
                const SizedBox(width: 8),
                Text(
                  '$record',
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
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
        game.kickoff == null
            ? 'Upcoming'
            : formatGameTime(context, game.kickoff!),
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
}
