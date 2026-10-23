import 'game.dart';

/// Inclusive range of points the winning team is expected to finish with.
class ScoreRange {
  const ScoreRange(this.low, this.high);

  factory ScoreRange.fromJson(Map<String, dynamic> json) =>
      ScoreRange(json['low'] as int, json['high'] as int);

  final int low;
  final int high;

  /// Points between the two ends; 0 means one exact score.
  int get width => high - low;

  bool contains(int score) => score >= low && score <= high;

  Map<String, Object?> toJson() => {'low': low, 'high': high};

  @override
  String toString() => low == high ? '$low' : '$low-$high';
}

class Bet {
  const Bet({
    required this.side,
    required this.amount,
    this.payout,
    this.cashOutAmount = 0,
    this.multiplier = 1.0,
    this.scoreRange,
  });

  factory Bet.fromJson(Map<String, dynamic> json) => Bet(
    side: TeamSide.values.byName(json['side'] as String),
    amount: json['amount'] as int,
    payout: json['payout'] as int?,
    cashOutAmount: json['cashOutAmount'] as int? ?? 0,
    multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
    scoreRange: switch (json['scoreRange']) {
      final Map<String, dynamic> range => ScoreRange.fromJson(range),
      _ => null,
    },
  );

  final TeamSide side;

  /// Coins staked.
  final int amount;

  /// Coins paid back after the game ended (0 if the bet lost). Null until the
  /// bet is settled.
  final int? payout;

  /// Coins returned by a pre-halftime cash-out.
  final int cashOutAmount;

  /// Bonus applied to a winning payout, locked in when the bet was placed.
  /// Bets on teams with worse records get bigger multipliers.
  final double multiplier;

  /// Optional guess at the winning team's final score. If set, the bet only
  /// wins when [side] wins and finishes inside this range, and a winning
  /// payout gets an extra bonus for narrower ranges.
  final ScoreRange? scoreRange;

  bool get isSettled => payout != null;

  /// Whether this bet wins a game that [winner] won with [winningScore]
  /// points. Nothing wins a tie.
  bool wins(TeamSide? winner, int? winningScore) =>
      winner != null &&
      side == winner &&
      (scoreRange == null ||
          (winningScore != null && scoreRange!.contains(winningScore)));

  Map<String, Object?> toJson() => {
    'side': side.name,
    'amount': amount,
    'payout': payout,
    'cashOutAmount': cashOutAmount,
    'multiplier': multiplier,
    'scoreRange': scoreRange?.toJson(),
  };
}
