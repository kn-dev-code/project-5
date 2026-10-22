import 'game.dart';

class Bet {
  const Bet({
    required this.side,
    required this.amount,
    this.payout,
    this.cashOutAmount = 0,
  });

  factory Bet.fromJson(Map<String, dynamic> json) => Bet(
    side: TeamSide.values.byName(json['side'] as String),
    amount: json['amount'] as int,
    payout: json['payout'] as int?,
    cashOutAmount: json['cashOutAmount'] as int? ?? 0,
  );

  final TeamSide side;

  /// Coins staked.
  final int amount;

  /// Coins paid back after the game ended (0 if the bet lost). Null until the
  /// bet is settled.
  final int? payout;

  /// Coins returned by a pre-halftime cash-out.
  final int cashOutAmount;

  bool get isSettled => payout != null;

  Map<String, Object?> toJson() => {
    'side': side.name,
    'amount': amount,
    'payout': payout,
    'cashOutAmount': cashOutAmount,
  };
}
