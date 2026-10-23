import 'dart:convert';

import 'package:football_core/feeds/espn_game_feed.dart';
import 'package:football_core/models/game.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A competitor shaped like ESPN's scoreboard (records under 'records') or
/// game summary (records under 'record').
Map<String, Object?> _team(
  String homeAway,
  String name,
  Object score, {
  String record = '5-2',
  String recordsKey = 'records',
}) => {
  'homeAway': homeAway,
  'team': {'displayName': name},
  'score': score,
  recordsKey: [
    {'name': 'overall', 'type': 'total', 'summary': record},
    {'name': 'Home', 'type': 'home', 'summary': '3-1'},
  ],
};

Map<String, Object?> _event(
  String id, {
  required String state,
  bool completed = false,
  int period = 0,
  String clock = '0:00',
  String date = '2026-10-23T00:15Z',
  Object homeScore = '0',
  Object awayScore = '0',
}) {
  final status = {
    'displayClock': clock,
    'period': period,
    'type': {'state': state, 'completed': completed},
  };
  return {
    'id': id,
    'date': date,
    'status': status,
    'competitions': [
      {
        'id': id,
        'date': date,
        'status': status,
        'competitors': [
          _team('home', 'Chicago Bears', homeScore),
          _team('away', 'New England Patriots', awayScore, record: '3-4-1'),
        ],
      },
    ],
  };
}

void main() {
  group('parseEspnEvent', () {
    test('reads a live game', () {
      final game = parseEspnEvent(
        _event(
          '401',
          state: 'in',
          period: 2,
          clock: '8:42',
          homeScore: '14',
          awayScore: '10',
        ),
        nfl,
      )!;
      expect(game.id, 'nfl-401');
      expect(game.league, 'NFL');
      expect(game.homeTeam, 'Chicago Bears');
      expect(game.awayTeam, 'New England Patriots');
      expect(game.status, GameStatus.live);
      expect((game.homeScore, game.awayScore), (14, 10));
      expect(game.gameClock, 'Q2 8:42');
      expect(game.kickoff, DateTime.utc(2026, 10, 23, 0, 15));
      expect(game.homeRecord.toString(), '5-2');
      // Ties are left out of the record.
      expect(game.awayRecord.toString(), '3-4');
      expect(game.isBeforeHalftime, isTrue);
    });

    test('treats the end of the second quarter as halftime', () {
      final game = parseEspnEvent(
        _event('401', state: 'in', period: 2, clock: '0:00'),
        nfl,
      )!;
      expect(game.isHalftimeOrLater, isTrue);
      expect(game.isBeforeHalftime, isFalse);
    });

    test('reads upcoming and finished games without a clock', () {
      final upcoming = parseEspnEvent(_event('1', state: 'pre'), nfl)!;
      expect(upcoming.status, GameStatus.upcoming);
      expect(upcoming.quarter, isNull);

      final finished = parseEspnEvent(
        _event(
          '2',
          state: 'post',
          completed: true,
          period: 4,
          homeScore: '30',
          awayScore: '20',
        ),
        collegeFootball,
      )!;
      expect(finished.id, 'cfb-2');
      expect(finished.status, GameStatus.finished);
      expect(finished.winner, TeamSide.home);
      expect(finished.gameClock, isNull);
    });

    test('leaves out postponed and canceled games', () {
      expect(parseEspnEvent(_event('3', state: 'post'), nfl), isNull);
    });
  });

  group('EspnGameFeed', () {
    test('lists every league and drops games outside the windows', () async {
      final now = DateTime.utc(2026, 10, 23, 12);
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        final events = request.url.path.contains('college')
            ? [_event('10', state: 'in', period: 1, clock: '12:00')]
            : [
                _event('1', state: 'post', completed: true),
                _event(
                  '2',
                  state: 'post',
                  completed: true,
                  date: '2026-10-20T00:15Z',
                ),
                _event('3', state: 'pre', date: '2026-10-26T17:00Z'),
                _event('4', state: 'pre', date: '2026-11-20T17:00Z'),
              ];
        return http.Response(jsonEncode({'events': events}), 200);
      });
      final feed = EspnGameFeed(client: client, clock: () => now);

      final games = await feed.fetchGames();
      expect(games.map((g) => g.id), ['nfl-1', 'nfl-3', 'cfb-10']);
      expect(
        requested.map((u) => u.toString()),
        containsAll([
          'https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard',
          'https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard?groups=80&limit=300',
        ]),
      );
    });

    test('fails as a whole if any league fails', () async {
      final feed = EspnGameFeed(
        client: MockClient(
          (request) async => request.url.path.contains('college')
              ? http.Response('busy', 503)
              : http.Response(jsonEncode({'events': []}), 200),
        ),
      );
      await expectLater(feed.fetchGames(), throwsA(isA<GameFeedException>()));
    });

    test('looks games up by id from their summaries', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/football/nfl/summary'));
        if (request.url.queryParameters['event'] != '401') {
          return http.Response('not found', 404);
        }
        return http.Response(
          jsonEncode({
            'header': {
              'competitions': [
                {
                  'date': '2026-10-23T00:15Z',
                  'status': {
                    'type': {'state': 'post', 'completed': true},
                  },
                  'competitors': [
                    _team('home', 'Chicago Bears', '30', recordsKey: 'record'),
                    _team('away', 'New England Patriots', '20'),
                  ],
                },
              ],
            },
          }),
          200,
        );
      });
      final feed = EspnGameFeed(client: client);

      final games = await feed.fetchGamesById([
        'nfl-401',
        'nfl-999',
        'fake-12',
      ]);
      expect(games, hasLength(1));
      expect(games.single.id, 'nfl-401');
      expect(games.single.winner, TeamSide.home);
      expect(games.single.homeRecord.toString(), '5-2');
    });
  });
}
