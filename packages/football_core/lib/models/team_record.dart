/// A team's season win-loss record.
class TeamRecord {
  const TeamRecord(this.wins, this.losses);

  factory TeamRecord.fromJson(Map<String, dynamic> json) =>
      TeamRecord(json['wins'] as int, json['losses'] as int);

  final int wins;
  final int losses;

  int get gamesPlayed => wins + losses;

  /// Share of games won, from 0 to 1, or null before the first game.
  double? get winRate => gamesPlayed == 0 ? null : wins / gamesPlayed;

  Map<String, Object?> toJson() => {'wins': wins, 'losses': losses};

  @override
  String toString() => '$wins-$losses';
}
