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

  /// Whether a football game is still before halftime according to its feed.
  bool get isBeforeHalftime {
    if (!isLive) return false;
    if (quarter == 1) return true;
    if (quarter != 2 || clock == null) return false;
    final parts = clock!.split(':');
    if (parts.length != 2) return false;
    final minutes = int.tryParse(parts[0]);
    final seconds = int.tryParse(parts[1]);
    return minutes != null && seconds != null && minutes * 60 + seconds > 0;
  }

  bool get isFinished => status == GameStatus.finished;

  /// The side that won, or null if the game isn't over or ended in a tie.
  TeamSide? get winner {
    if (!isFinished || homeScore == awayScore) return null;
    return homeScore > awayScore ? TeamSide.home : TeamSide.away;
  }

  /// Quarter and clock for display, e.g. 'Q2 8:42' or 'OT 3:10'.
  String? get gameClock {
    if (quarter == null) return null;
    final period = quarter! > 4 ? 'OT' : 'Q$quarter';
    return clock == null ? period : '$period $clock';
  }

  String teamName(TeamSide side) => side == TeamSide.home ? homeTeam : awayTeam;
}
