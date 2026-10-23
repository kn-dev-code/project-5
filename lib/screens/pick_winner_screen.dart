import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:football_core/models/bet.dart';
import 'package:football_core/models/crowd_stats.dart';
import 'package:football_core/models/game.dart';
import 'package:football_core/models/team_record.dart';
import 'package:football_core/server/payouts.dart';

/// What the user chose: the side they picked, how many coins they bet on it
/// (0 only when they already had a bet), and the winner's score range they bet on, if any.
typedef PickResult = ({TeamSide side, int bet, ScoreRange? scoreRange});

class PickWinnerScreen extends StatefulWidget {
  const PickWinnerScreen({
    super.key,
    required this.game,
    this.initialPick,
    required this.crowd,
    this.balance = 0,
    this.existingBet,
  });

  final Game game;

  /// The user's previously saved pick for this game, if any.
  final TeamSide? initialPick;

  /// Other users' votes and bets, not counting this user.
  final CrowdStats crowd;

  /// Coins the user can bet.
  final int balance;

  /// A bet the user already placed; bets can't be changed, so this locks the
  /// pick to the bet's side.
  final Bet? existingBet;

  @override
  State<PickWinnerScreen> createState() => _PickWinnerScreenState();
}

class _PickWinnerScreenState extends State<PickWinnerScreen> {
  late TeamSide? _pick = widget.existingBet?.side ?? widget.initialPick;
  final _betController = TextEditingController();
  final _lowController = TextEditingController();
  final _highController = TextEditingController();

  /// Whether the user wants to also bet on the winner's score range.
  bool _useScoreRange = false;

  bool get _locked => widget.existingBet != null;

  int get _betAmount => int.tryParse(_betController.text) ?? 0;

  String? get _betError => _betAmount > widget.balance
      ? 'You only have ${widget.balance} coins'
      : null;

  bool get _rangeActive => !_locked && _betAmount > 0 && _useScoreRange;

  /// The score range as entered, or null if it is off or invalid.
  ScoreRange? get _scoreRange {
    if (!_rangeActive) return null;
    final low = int.tryParse(_lowController.text);
    final high = int.tryParse(_highController.text);
    if (low == null || high == null) return null;
    final range = ScoreRange(low, high);
    return isValidScoreRange(range) ? range : null;
  }

  String? get _rangeError {
    if (!_rangeActive) return null;
    final low = int.tryParse(_lowController.text);
    final high = int.tryParse(_highController.text);
    if (low == null || high == null) return 'Enter both ends of the range';
    if (high < low) return 'The high score must be at least the low score';
    if (high - low > maxScoreRangeWidth) {
      return 'The range can be at most $maxScoreRangeWidth points wide';
    }
    return null;
  }

  /// Every new pick needs a bet; with an existing bet the pick is locked.
  bool get _canConfirm =>
      _pick != null &&
      (_locked || _betAmount > 0) &&
      _betError == null &&
      _rangeError == null;

  /// The user's bet as it would stand if they confirmed now.
  Bet? get _bet {
    if (widget.existingBet case final bet?) return bet;
    final pick = _pick;
    if (pick == null || _betAmount <= 0) return null;
    return Bet(
      side: pick,
      amount: _betAmount,
      multiplier: underdogMultiplier(widget.game.record(pick)),
      scoreRange: _scoreRange,
    );
  }

  static int _payoutIfWon(CrowdStats crowd, Bet bet) => applyMultiplier(
    crowd.winningPayout(bet.side, bet.amount),
    totalMultiplier(bet),
  );

  /// The bonuses a winning [bet] gets, e.g. ' with a 1.5x underdog bonus'.
  static String _bonusText(Bet bet) {
    final range = scoreRangeMultiplier(bet.scoreRange);
    final bonuses = [
      if (bet.multiplier > 1) '${bet.multiplier}x underdog bonus',
      if (range > 1) '${range}x score range bonus',
    ];
    return bonuses.isEmpty ? '' : ' with a ${bonuses.join(' and a ')}';
  }

  /// Coins back per coin bet on [side], underdog bonus included.
  double? _oddsFor(CrowdStats crowd, TeamSide side) {
    final odds = crowd.odds(side);
    if (odds == null) return null;
    return odds * underdogMultiplier(widget.game.record(side));
  }

  static TeamSide _other(TeamSide side) =>
      side == TeamSide.home ? TeamSide.away : TeamSide.home;

  @override
  void dispose() {
    _betController.dispose();
    _lowController.dispose();
    _highController.dispose();
    super.dispose();
  }

  /// Pops with the [PickResult]; the caller is responsible for saving it.
  void _confirm() {
    final pick = _pick;
    if (pick == null || !_canConfirm) return;
    final bet = _locked ? 0 : _betAmount;
    final scoreRange = _scoreRange;

    final team = widget.game.teamName(pick);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context)
        .pop<PickResult>((side: pick, bet: bet, scoreRange: scoreRange));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          bet <= 0
              ? 'You picked $team to win!'
              : scoreRange != null
              ? 'You bet $bet coins on $team winning with $scoreRange points!'
              : 'You picked $team to win and bet $bet coins!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final game = widget.game;
    final bet = _bet;
    final crowd = widget.crowd.withUser(pick: _pick, bet: bet);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick a Winner'),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    game.league,
                    textAlign: TextAlign.center,
                    style: textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${game.homeTeam}  ${game.homeScore} - ${game.awayScore}  '
                    '${game.awayTeam}',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (game.gameClock != null)
                    Text(
                      game.gameClock!,
                      textAlign: TextAlign.center,
                      style: textTheme.titleMedium?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  const SizedBox(height: 32),
                  Text(
                    'Who will win?',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${crowd.totalVotes} votes · '
                    '${crowd.totalBettors} players have bet',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final side in TeamSide.values) ...[
                    _TeamOption(
                      name: game.teamName(side),
                      label: side == TeamSide.home ? 'Home' : 'Away',
                      record: game.record(side),
                      multiplier: underdogMultiplier(game.record(side)),
                      odds: _oddsFor(crowd, side),
                      bettors: crowd.bettors(side),
                      pool: crowd.pool(side),
                      votePercent: crowd.votePercent(side),
                      selected: _pick == side,
                      onTap: _locked
                          ? null
                          : () => setState(() => _pick = side),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 20),
                  Text('Bet coins', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (widget.existingBet case final existing?)
                    Text(
                      'You bet ${existing.amount} coins on '
                      '${game.teamName(existing.side)}'
                      '${existing.scoreRange == null ? '' : ' scoring ${existing.scoreRange} points'}'
                      '. Bets are final.',
                    )
                  else
                    TextField(
                      controller: _betController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        helperText: widget.balance > 0
                            ? 'Balance: ${widget.balance} coins · '
                                  'every pick needs a bet'
                            : 'No coins left. Wait for your bets to settle, '
                                  'or come back tomorrow.',
                        errorText: _betError,
                        prefixIcon: const Icon(Icons.monetization_on),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  if (bet != null && _betError == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Your odds: ${formatOdds(_payoutIfWon(crowd, bet) / bet.amount)} '
                      'if you bet ${bet.amount} coins.',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${crowd.bettors(bet.side)} '
                      '${crowd.bettors(bet.side) == 1 ? 'player has' : 'players have'} '
                      'bet on ${game.teamName(bet.side)}, '
                      '${crowd.bettors(_other(bet.side))} on '
                      '${game.teamName(_other(bet.side))}.',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'If ${game.teamName(bet.side)} wins'
                      '${bet.scoreRange == null ? '' : ' with ${bet.scoreRange} points'} '
                      'you get ${_payoutIfWon(crowd, bet)} coins'
                      '${_bonusText(bet)}. '
                      'Pool: ${crowd.totalPool} coins.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ],
                  if (!_locked && _betAmount > 0 && _betError == null) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Bet on the winner's score"),
                      subtitle: Text(
                        'Up to $maxScoreRangeWidth points wide. Each point '
                        'narrower adds ${scoreRangeStep}x, but you lose if '
                        'the score lands outside it.',
                      ),
                      value: _useScoreRange,
                      onChanged: (value) =>
                          setState(() => _useScoreRange = value),
                    ),
                    if (_useScoreRange) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _ScoreField(
                              controller: _lowController,
                              label: 'Low score',
                              onChanged: () => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ScoreField(
                              controller: _highController,
                              label: 'High score',
                              onChanged: () => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _rangeError ??
                            '${scoreRangeMultiplier(_scoreRange)}x score '
                                'range bonus if the winner scores '
                                '$_scoreRange points.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: _rangeError == null
                              ? colors.tertiary
                              : colors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton(
                onPressed: _canConfirm ? _confirm : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Confirm Pick'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreField extends StatelessWidget {
  const _ScoreField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onChanged: (_) => onChanged(),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}

class _TeamOption extends StatelessWidget {
  const _TeamOption({
    required this.name,
    required this.label,
    required this.record,
    required this.multiplier,
    required this.odds,
    required this.bettors,
    required this.pool,
    required this.votePercent,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String label;
  final TeamRecord? record;

  /// Underdog bonus for a winning bet on this team.
  final double multiplier;

  /// Coins back per coin bet on this team, or null before anyone has bet.
  final double? odds;
  final int bettors;

  /// Coins bet on this team.
  final int pool;
  final int votePercent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: selected ? colors.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                label,
                ?record?.toString(),
                '$votePercent% of votes',
              ].join(' · '),
            ),
            Text(
              odds == null
                  ? 'No bets yet'
                  : 'Odds ${formatOdds(odds!)} · '
                        '$bettors ${bettors == 1 ? 'bettor' : 'bettors'} · '
                        '$pool coins',
            ),
            if (multiplier > 1)
              Text(
                '${multiplier}x underdog bonus if they win',
                style: TextStyle(
                  color: colors.tertiary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: votePercent / 100,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected ? colors.primary : colors.outline,
        ),
      ),
    );
  }
}
