import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/game.dart';
import '../models/team_record.dart';
import 'game_feed.dart';

/// A league on ESPN's scoreboard.
class EspnLeague {
  const EspnLeague({
    required this.key,
    required this.name,
    required this.path,
    this.query = const {},
  });

  /// Prefix for game ids, so a game can be looked up again by id.
  final String key;

  /// League name shown in the app.
  final String name;

  /// Sport and league in ESPN's URLs, e.g. 'football/nfl'.
  final String path;

  /// Extra scoreboard query parameters.
  final Map<String, String> query;
}

const nfl = EspnLeague(key: 'nfl', name: 'NFL', path: 'football/nfl');

/// Every FBS game (group 80), not just the ranked ones ESPN shows by default.
const collegeFootball = EspnLeague(
  key: 'cfb',
  name: 'College Football',
  path: 'football/college-football',
  query: {'groups': '80', 'limit': '300'},
);

/// Thrown when ESPN can't be reached or sends something unexpected.
class GameFeedException implements Exception {
  const GameFeedException(this.message);

  final String message;

  @override
  String toString() => 'GameFeedException: $message';
}

/// Live games and scores from ESPN's public scoreboard.
///
/// ESPN doesn't document or license this API for commercial use, and can
/// change or block it without notice. Everything that depends on its format is
/// in this file, so moving to a paid provider only means replacing this class.
class EspnGameFeed implements GameFeed {
  EspnGameFeed({
    http.Client? client,
    this.leagues = const [nfl, collegeFootball],
    this.finishedWindow = const Duration(hours: 18),
    this.upcomingWindow = const Duration(days: 7),
    this.timeout = const Duration(seconds: 10),
    Uri? baseUrl,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? defaultBaseUrl,
       _clock = clock ?? DateTime.now;

  static final defaultBaseUrl = Uri.parse(
    'https://site.api.espn.com/apis/site/v2/sports/',
  );

  final List<EspnLeague> leagues;

  /// Finished games stay listed until this long after kickoff.
  final Duration finishedWindow;

  /// Upcoming games are listed from this long before kickoff.
  final Duration upcomingWindow;

  /// How long to wait for each ESPN request.
  final Duration timeout;

  final http.Client _client;
  final Uri _baseUrl;
  final DateTime Function() _clock;

  /// Every league's scoreboard. Throws [GameFeedException] if any of them
  /// can't be loaded, so a caller never mistakes a failed request for games
  /// that have dropped off the schedule.
  @override
  Future<List<Game>> fetchGames() async {
    final boards = await Future.wait([
      for (final league in leagues)
        _get(_url(league, 'scoreboard', league.query)),
    ]);
    final now = _clock();
    return List.unmodifiable([
      for (final (i, board) in boards.indexed)
        for (final event in board['events'] as List? ?? const [])
          if (parseEspnEvent(event as Map<String, dynamic>, leagues[i])
              case final game? when _isListed(game, now))
            game,
    ]);
  }

  /// Looks each game up on its own. Ids from other feeds are left out, and so
  /// are games ESPN can't be reached for right now, to be tried again later.
  @override
  Future<List<Game>> fetchGamesById(Iterable<String> ids) async {
    final lookups = <Future<Game?>>[];
    for (final id in ids) {
      final dash = id.indexOf('-');
      if (dash < 0) continue;
      final key = id.substring(0, dash);
      final eventId = id.substring(dash + 1);
      for (final league in leagues) {
        if (league.key == key) lookups.add(_fetchOne(league, eventId));
      }
    }
    return [for (final game in await Future.wait(lookups)) ?game];
  }

  Future<Game?> _fetchOne(EspnLeague league, String eventId) async {
    try {
      final summary = await _get(_url(league, 'summary', {'event': eventId}));
      final header = summary['header'] as Map<String, dynamic>;
      final competition =
          (header['competitions'] as List).first as Map<String, dynamic>;
      return parseEspnCompetition(eventId, competition, league);
    } on GameFeedException {
      return null;
    }
  }

  bool _isListed(Game game, DateTime now) {
    final kickoff = game.kickoff;
    if (kickoff == null) return true;
    return switch (game.status) {
      GameStatus.upcoming => kickoff.isBefore(now.add(upcomingWindow)),
      GameStatus.finished => kickoff.isAfter(now.subtract(finishedWindow)),
      GameStatus.live => true,
    };
  }

  Uri _url(EspnLeague league, String endpoint, Map<String, String> query) =>
      _baseUrl
          .resolve('${league.path}/$endpoint')
          .replace(queryParameters: query.isEmpty ? null : query);

  Future<Map<String, dynamic>> _get(Uri url) async {
    final http.Response response;
    try {
      response = await _client.get(url).timeout(timeout);
    } on TimeoutException {
      throw GameFeedException('$url timed out');
    } on http.ClientException catch (e) {
      throw GameFeedException('$url failed: ${e.message}');
    }
    if (response.statusCode != 200) {
      throw GameFeedException('$url returned ${response.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on FormatException {
      throw GameFeedException('$url returned something other than JSON');
    }
  }
}

/// A scoreboard event as a [Game], or null if it was postponed, canceled or
/// is missing its teams.
Game? parseEspnEvent(Map<String, dynamic> event, EspnLeague league) {
  final competitions = event['competitions'] as List? ?? const [];
  if (competitions.isEmpty) return null;
  final first = competitions.first as Map<String, dynamic>;
  // Scoreboard events also carry the date and status at the top level.
  final competition = {
    ...first,
    'date': first['date'] ?? event['date'],
    'status': first['status'] ?? event['status'],
  };
  return parseEspnCompetition(event['id'] as String, competition, league);
}

/// One ESPN competition, from a scoreboard event or a game summary's header,
/// as a [Game].
Game? parseEspnCompetition(
  String eventId,
  Map<String, dynamic> competition,
  EspnLeague league,
) {
  final status = competition['status'] as Map<String, dynamic>? ?? const {};
  final type = status['type'] as Map<String, dynamic>? ?? const {};
  final gameStatus = switch (type['state']) {
    'pre' => GameStatus.upcoming,
    'in' => GameStatus.live,
    // Postponed and canceled games are also 'post', but never completed.
    'post' when type['completed'] == true => GameStatus.finished,
    _ => null,
  };
  if (gameStatus == null) return null;

  Map<String, dynamic>? side(String homeAway) {
    for (final c in competition['competitors'] as List? ?? const []) {
      if ((c as Map<String, dynamic>)['homeAway'] == homeAway) return c;
    }
    return null;
  }

  final home = side('home');
  final away = side('away');
  if (home == null || away == null) return null;
  final live = gameStatus == GameStatus.live;

  return Game(
    id: '${league.key}-$eventId',
    league: league.name,
    homeTeam: _teamName(home),
    awayTeam: _teamName(away),
    status: gameStatus,
    homeScore: _score(home),
    awayScore: _score(away),
    quarter: live ? status['period'] as int? : null,
    clock: live ? status['displayClock'] as String? : null,
    kickoff: switch (competition['date']) {
      final String date => DateTime.tryParse(date),
      _ => null,
    },
    homeRecord: _record(home),
    awayRecord: _record(away),
  );
}

String _teamName(Map<String, dynamic> competitor) {
  final team = competitor['team'] as Map<String, dynamic>? ?? const {};
  return (team['displayName'] ?? team['name'] ?? 'TBD') as String;
}

int _score(Map<String, dynamic> competitor) => switch (competitor['score']) {
  final int score => score,
  final String score => int.tryParse(score) ?? 0,
  // Some endpoints wrap it, e.g. {'value': 21.0, 'displayValue': '21'}.
  {'value': final num value} => value.toInt(),
  _ => 0,
};

/// The team's overall record, e.g. '5-2' or '5-2-1'. Ties are left out.
TeamRecord? _record(Map<String, dynamic> competitor) {
  // Scoreboards call the list 'records'; game summaries call it 'record'.
  final records = competitor['records'] ?? competitor['record'];
  if (records is! List) return null;
  for (final r in records.cast<Map<String, dynamic>>()) {
    if (r['type'] != 'total' && r['name'] != 'overall') continue;
    final parts = (r['summary'] as String? ?? '').split('-');
    if (parts.length < 2) return null;
    final wins = int.tryParse(parts[0]);
    final losses = int.tryParse(parts[1]);
    if (wins == null || losses == null) return null;
    return TeamRecord(wins, losses);
  }
  return null;
}
