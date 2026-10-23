import 'dart:async';
import 'dart:convert';

import 'package:football_core/api/betting_api.dart';
import 'package:football_core/feeds/espn_game_feed.dart';
import 'package:football_core/models/bet.dart';
import 'package:football_core/models/game.dart';
import 'package:football_core/server/account_server.dart';
import 'package:football_core/server/betting_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// The HTTP API the app's `HttpAccountApi` and `HttpBettingApi` talk to.
///
/// Requests and replies are JSON. Players send their session token as
/// `Authorization: Bearer <token>`. Errors come back as
/// `{"error": {"kind": "auth" | "bet" | "shop" | "other", "message": "..."}}`.
class FootballApi {
  FootballApi({
    required this._accounts,
    required this._betting,
    this.gamesMaxAge = const Duration(seconds: 20),
    this.allowedOrigin = '*',
    void Function(String message)? log,
  }) : _log = log ?? print;

  /// Games are fetched from the feed again once they're this old.
  final Duration gamesMaxAge;

  /// Value for `Access-Control-Allow-Origin`, so the web app can call the API.
  final String allowedOrigin;

  final AccountServer _accounts;
  final BettingServer _betting;
  final void Function(String message) _log;

  List<Game>? _games;
  DateTime? _gamesFetchedAt;
  Future<List<Game>>? _gamesFetch;

  /// Fetches games from the feed now, which also settles finished games and
  /// sends notifications. Concurrent calls share one fetch.
  Future<List<Game>> refreshGames() => _gamesFetch ??= () async {
    try {
      final games = await _betting.fetchGames();
      _games = games;
      _gamesFetchedAt = DateTime.now();
      return games;
    } finally {
      _gamesFetch = null;
    }
  }();

  /// The latest games, fetching again if they're older than [gamesMaxAge].
  /// If the feed is down, the last games fetched are served instead.
  Future<List<Game>> _latestGames() async {
    final games = _games;
    final fetchedAt = _gamesFetchedAt;
    if (games != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < gamesMaxAge) {
      return games;
    }
    try {
      return await refreshGames();
    } on GameFeedException catch (e) {
      if (games == null) rethrow;
      _log('Serving old games, feed failed: $e');
      return games;
    }
  }

  Handler get handler => const Pipeline()
      .addMiddleware(_cors)
      .addMiddleware(_errors)
      .addHandler(_router().call);

  Router _router() => Router()
    // Accounts
    ..post('/v1/accounts', (Request request) async {
      final body = await _body(request);
      return _json({
        'token': await _accounts.createAccount(
          body['username'] as String,
          body['password'] as String,
        ),
      });
    })
    ..post('/v1/sessions', (Request request) async {
      final body = await _body(request);
      return _json({
        'token': await _accounts.logIn(
          body['username'] as String,
          body['password'] as String,
        ),
      });
    })
    ..delete('/v1/sessions', (Request request) async {
      await _accounts.logOut(_token(request));
      return _json(null);
    })
    ..get(
      '/v1/me',
      (Request request) async =>
          _json((await _accounts.accountFor(_token(request))).toJson()),
    )
    // Games
    ..get(
      '/v1/games',
      (Request request) async =>
          _json([for (final game in await _latestGames()) game.toJson()]),
    )
    ..get('/v1/games/<id>/crowd', (Request request, String id) async {
      var game = _betting.gameById(id);
      if (game == null) {
        await _latestGames();
        game = _betting.gameById(id);
      }
      if (game == null) return _error(404, 'other', 'No game with id $id.');
      final token = _optionalToken(request);
      return _json((await _betting.crowd(game, token: token)).toJson());
    })
    ..post('/v1/games/<id>/bets', (Request request, String id) async {
      final token = _token(request);
      final body = await _body(request);
      // Make sure the server knows the game is live before taking the bet.
      await _latestGames();
      await _betting.placeBet(
        token,
        id,
        TeamSide.values.byName(body['side'] as String),
        body['amount'] as int,
        scoreRange: switch (body['scoreRange']) {
          final Map<String, dynamic> range => ScoreRange.fromJson(range),
          _ => null,
        },
      );
      return _json(null);
    })
    ..post('/v1/games/<id>/cash-out', (Request request, String id) async {
      final token = _token(request);
      await _latestGames();
      return _json({'refund': await _betting.cashOutHalf(token, id)});
    })
    // The player's coins and bets
    ..get(
      '/v1/me/balance',
      (Request request) async =>
          _json({'balance': await _betting.balance(_token(request))}),
    )
    ..get('/v1/me/bets', (Request request) async {
      final bets = await _betting.bets(_token(request));
      return _json({for (final e in bets.entries) e.key: e.value.toJson()});
    })
    ..post(
      '/v1/me/results/take',
      (Request request) async =>
          _json(await _betting.takeResults(_token(request))),
    )
    ..get(
      '/v1/me/daily-reward',
      (Request request) async => _json({
        'canClaim': await _betting.canClaimDailyReward(_token(request)),
      }),
    )
    ..post(
      '/v1/me/daily-reward',
      (Request request) async =>
          _json({'balance': await _betting.claimDailyReward(_token(request))}),
    )
    ..post(
      '/v1/me/bailout',
      (Request request) async =>
          _json({'coins': await _betting.claimBailoutIfBroke(_token(request))}),
    )
    // Notifications
    ..get('/v1/me/notifications', (Request request) async {
      final notifications = await _betting.notifications(_token(request));
      return _json([for (final n in notifications) n.toJson()]);
    })
    ..post('/v1/me/notifications/read', (Request request) async {
      await _betting.markNotificationsRead(_token(request));
      return _json(null);
    })
    // Shop
    ..get(
      '/v1/me/shop/owned',
      (Request request) async =>
          _json((await _betting.ownedShopItems(_token(request))).toList()),
    )
    ..get(
      '/v1/me/shop/theme',
      (Request request) async =>
          _json({'id': await _betting.activeShopTheme(_token(request))}),
    )
    ..put('/v1/me/shop/theme', (Request request) async {
      final token = _token(request);
      final body = await _body(request);
      await _betting.setActiveShopTheme(token, body['id'] as String);
      return _json(null);
    })
    ..get(
      '/v1/me/shop/background',
      (Request request) async =>
          _json({'id': await _betting.activeShopBackground(_token(request))}),
    )
    ..put('/v1/me/shop/background', (Request request) async {
      final token = _token(request);
      final body = await _body(request);
      await _betting.setActiveShopBackground(token, body['id'] as String?);
      return _json(null);
    })
    ..post('/v1/me/shop/purchases', (Request request) async {
      final token = _token(request);
      final body = await _body(request);
      return _json({
        'balance': await _betting.purchaseShopItem(
          token,
          body['itemId'] as String,
        ),
      });
    })
    ..get('/healthz', (Request request) => Response.ok('ok'))
    ..all('/<ignored|.*>', (Request request) {
      return _error(404, 'other', 'Not found.');
    });

  /// Turns the servers' exceptions into error replies.
  Handler _errors(Handler inner) => (request) async {
    try {
      return await inner(request);
    } on AuthException catch (e) {
      return _error(401, 'auth', e.message);
    } on BetRejected catch (e) {
      return _error(400, 'bet', e.message);
    } on ShopRejected catch (e) {
      return _error(400, 'shop', e.message);
    } on _BadRequest catch (e) {
      return _error(400, 'other', e.message);
    } on GameFeedException catch (e) {
      _log('Game feed failed: $e');
      return _error(503, 'other', "Can't load games right now. Try again.");
    } on Object catch (e, stack) {
      // Missing or wrongly typed fields in a request body end up here as
      // TypeErrors, as do real bugs, so log them all.
      _log('${request.method} ${request.url} failed: $e\n$stack');
      return e is TypeError || e is ArgumentError
          ? _error(400, 'other', 'Bad request.')
          : _error(500, 'other', 'Something went wrong on the server.');
    }
  };

  Handler _cors(Handler inner) {
    final headers = {
      'Access-Control-Allow-Origin': allowedOrigin,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Max-Age': '86400',
    };
    return (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok(null, headers: headers);
      }
      return (await inner(request)).change(headers: headers);
    };
  }

  static String _token(Request request) =>
      _optionalToken(request) ?? (throw const AuthException('Please log in.'));

  static String? _optionalToken(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring('Bearer '.length);
  }

  static Future<Map<String, dynamic>> _body(Request request) async {
    try {
      return jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      throw const _BadRequest('The request body must be JSON.');
    } on TypeError {
      throw const _BadRequest('The request body must be a JSON object.');
    }
  }

  static Response _json(Object? body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {'Content-Type': 'application/json'},
  );

  static Response _error(int status, String kind, String message) => _json({
    'error': {'kind': kind, 'message': message},
  }, status: status);
}

class _BadRequest implements Exception {
  const _BadRequest(this.message);

  final String message;
}
