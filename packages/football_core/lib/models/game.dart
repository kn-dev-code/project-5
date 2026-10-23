import 'team_record.dart';

enum GameStatus { live, upcoming, finished }

/// Which side of a game a user picks to win.
enum TeamSide { home, away }

class Game {
  const Game({
    required this.id,
    required this.league,
    required this.homeTeam,
    required this.awayTeam,
    required this.status,
    this.homeScore = 0,
    this.awayScore = 0,
    this.quarter,
    this.clock,
    this.kickoff,
    this.endsAt,
    this.homeRecord,
    this.awayRecord,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) => switch (json[key]) {
      final String value => DateTime.parse(value),
      _ => null,
    };
    TeamRecord? record(String key) => switch (json[key]) {
      final Map<String, dynamic> value => TeamRecord.fromJson(value),
      _ => null,
    };
    return Game(
      id: json['id'] as String,
      league: json['league'] as String,
      homeTeam: json['homeTeam'] as String,
      awayTeam: json['awayTeam'] as String,
      status: GameStatus.values.byName(json['status'] as String),
      homeScore: json['homeScore'] as int? ?? 0,
      awayScore: json['awayScore'] as int? ?? 0,
      quarter: json['quarter'] as int?,
      clock: json['clock'] as String?,
      kickoff: time('kickoff'),
      endsAt: time('endsAt'),
      homeRecord: record('homeRecord'),
      awayRecord: record('awayRecord'),
    );
  }

  final String id;
  final String league;
  final String homeTeam;
  final String awayTeam;
  final GameStatus status;
  final int homeScore;
  final int awayScore;

  /// Current quarter (1-4, 5 for overtime), only set while the game is live.
  final int? quarter;

  /// Time left in the quarter, e.g. '8:42', only set while the game is live.
  final String? clock;

  /// Kickoff time, if the feed knows it.
  final DateTime? kickoff;

  /// When the game is scheduled to be over, if the feed knows it. Bets are
  /// settled once the feed reports the game finished.
  final DateTime? endsAt;

  /// Each team's season record going into this game, if the feed has it.
  final TeamRecord? homeRecord;
  final TeamRecord? awayRecord;

  TeamRecord? record(TeamSide side) =>
      side == TeamSide.home ? homeRecord : awayRecord;

  bool get isLive => status == GameStatus.live;

  /// Seconds left in the quarter, or null if [clock] isn't set or readable.
  int? get _secondsLeft {
    final parts = clock?.split(':');
    if (parts == null || parts.length != 2) return null;
    final minutes = int.tryParse(parts[0]);
    final seconds = int.tryParse(parts[1]);
    if (minutes == null || seconds == null) return null;
    return minutes * 60 + seconds;
  }

  /// Whether bets are taken: from when the game is listed until the end of
  /// the first quarter.
  bool get isBettingOpen {
    if (status == GameStatus.upcoming) return true;
    if (!isLive || quarter != 1) return false;
    // Feeds without a clock keep betting open for the whole first quarter.
    return (_secondsLeft ?? 1) > 0;
  }

  /// Whether a football game is still before halftime according to its feed.
  bool get isBeforeHalftime {
    if (!isLive) return false;
    if (quarter == 1) return true;
    if (quarter != 2) return false;
    return (_secondsLeft ?? 0) > 0;
  }

  /// Whether a live game has reached halftime or gone past it.
  bool get isHalftimeOrLater {
    if (!isLive || quarter == null) return false;
    return quarter! >= 3 || (quarter == 2 && !isBeforeHalftime);
  }

  bool get isFinished => status == GameStatus.finished;

  /// The side that won, or null if the game isn't over or ended in a tie.
  TeamSide? get winner {
    if (!isFinished || homeScore == awayScore) return null;
    return homeScore > awayScore ? TeamSide.home : TeamSide.away;
  }

  int score(TeamSide side) => side == TeamSide.home ? homeScore : awayScore;

  /// The winner's final score, or null if there is no winner yet.
  int? get winningScore => switch (winner) {
    final side? => score(side),
    null => null,
  };

  /// Quarter and clock for display, e.g. 'Q2 8:42' or 'OT 3:10'.
  String? get gameClock {
    if (quarter == null) return null;
    final period = quarter! > 4 ? 'OT' : 'Q$quarter';
    return clock == null ? period : '$period $clock';
  }

  String teamName(TeamSide side) => side == TeamSide.home ? homeTeam : awayTeam;

  Map<String, Object?> toJson() => {
    'id': id,
    'league': league,
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'status': status.name,
    'homeScore': homeScore,
    'awayScore': awayScore,
    'quarter': quarter,
    'clock': clock,
    'kickoff': kickoff?.toUtc().toIso8601String(),
    'endsAt': endsAt?.toUtc().toIso8601String(),
    'homeRecord': homeRecord?.toJson(),
    'awayRecord': awayRecord?.toJson(),
  };
}
