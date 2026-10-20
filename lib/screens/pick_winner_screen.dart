import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fake_crowd.dart';
import '../models/bet.dart';
import '../models/crowd_stats.dart';
import '../models/game.dart';

/// What the user chose: the side they picked and how many coins they bet on
/// it (0 for no new bet).
typedef PickResult = ({TeamSide side, int bet});

class PickWinnerScreen extends StatefulWidget {
  const PickWinnerScreen({
    super.key,
    required this.game,
    this.initialPick,
    this.crowd,
    this.balance = 0,
    this.existingBet,
  });

  final Game game;

  /// The user's previously saved pick for this game, if any.
  final TeamSide? initialPick;

  /// Other users' votes and bets, not counting this user. Defaults to
  /// [fakeCrowdFor].
  final CrowdStats? crowd;

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
  late final CrowdStats _crowd = widget.crowd ?? fakeCrowdFor(widget.game);
  final _betController = TextEditingController();

  bool get _locked => widget.existingBet != null;

  int get _betAmount => int.tryParse(_betController.text) ?? 0;

  String? get _betError => _betAmount > widget.balance
      ? 'You only have ${widget.balance} coins'
      : null;

  /// The user's bet as it would stand if they confirmed now.
  Bet? get _bet {
    if (widget.existingBet case final bet?) return bet;
    final pick = _pick;
    if (pick == null || _betAmount <= 0) return null;
    return Bet(side: pick, amount: _betAmount);
  }

  @override
  void dispose() {
    _betController.dispose();
    super.dispose();
  }

  /// Pops with the [PickResult]; the caller is responsible for saving it.
  void _confirm() {
    final pick = _pick;
    if (pick == null || _betError != null) return;
    final bet = _locked ? 0 : _betAmount;

    final team = widget.game.teamName(pick);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop<PickResult>((side: pick, bet: bet));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          bet > 0
              ? 'You picked $team to win and bet $bet coins!'
              : 'You picked $team to win!',
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
    final crowd = _crowd.withUser(pick: _pick, bet: bet);

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
                    '${crowd.totalVotes} votes',
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
                      '${game.teamName(existing.side)}. Bets are final.',
                    )
                  else
                    TextField(
                      controller: _betController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Amount (optional)',
                        helperText: 'Balance: ${widget.balance} coins',
                        errorText: _betError,
                        prefixIcon: const Icon(Icons.monetization_on),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  if (bet != null && _betError == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'If ${game.teamName(bet.side)} wins you get '
                      '${crowd.winningPayout(bet.side, bet.amount)} coins. '
                      'Pool: ${crowd.totalPool} coins.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton(
                onPressed: _pick == null || _betError != null ? null : _confirm,
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

class _TeamOption extends StatelessWidget {
  const _TeamOption({
    required this.name,
    required this.label,
    required this.votePercent,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String label;
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
            Text('$label · $votePercent% of votes'),
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
