import 'package:flutter/material.dart';

import '../models/game.dart';

class PickWinnerScreen extends StatefulWidget {
  const PickWinnerScreen({super.key, required this.game, this.initialPick});

  final Game game;

  /// The user's previously saved pick for this game, if any.
  final TeamSide? initialPick;

  @override
  State<PickWinnerScreen> createState() => _PickWinnerScreenState();
}

class _PickWinnerScreenState extends State<PickWinnerScreen> {
  late TeamSide? _pick = widget.initialPick;

  /// Pops with the chosen side; the caller is responsible for saving it.
  void _confirm() {
    final pick = _pick;
    if (pick == null) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(pick);
    messenger.showSnackBar(
      SnackBar(
        content: Text('You picked ${widget.game.teamName(pick)} to win!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final game = widget.game;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick a Winner'),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  style: textTheme.titleMedium?.copyWith(color: colors.error),
                ),
              const SizedBox(height: 32),
              Text(
                'Who will win?',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              for (final side in TeamSide.values) ...[
                _TeamOption(
                  name: game.teamName(side),
                  label: side == TeamSide.home ? 'Home' : 'Away',
                  selected: _pick == side,
                  onTap: () => setState(() => _pick = side),
                ),
                const SizedBox(height: 12),
              ],
              const Spacer(),
              FilledButton(
                onPressed: _pick == null ? null : _confirm,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Confirm Pick'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamOption extends StatelessWidget {
  const _TeamOption({
    required this.name,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String label;
  final bool selected;
  final VoidCallback onTap;

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
        subtitle: Text(label),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected ? colors.primary : colors.outline,
        ),
      ),
    );
  }
}
