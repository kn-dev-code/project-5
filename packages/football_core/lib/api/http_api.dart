import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/bet.dart';
import '../models/crowd_stats.dart';
import '../models/game.dart';
import '../models/game_notification.dart';
import 'betting_api.dart';

/// Thrown when the server can't be reached or answers with an unexpected
/// error. [message] is safe to show to the player.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// HTTP status, or null if the server couldn't be reached at all.
  final int? statusCode;

  @override
  String toString() => message;
}

/// Sends JSON requests to the football server at [baseUrl] and turns its error
/// replies back into the exceptions the in-process servers throw.
///
/// Error replies look like `{"error": {"kind": "bet", "message": "..."}}`,
/// where kind is `auth`, `bet`, `shop` or `other`.
class ApiConnection {
  ApiConnection(
    Uri baseUrl, {
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : baseUrl = baseUrl.path.endsWith('/')
           ? baseUrl
           : baseUrl.replace(path: '${baseUrl.path}/'),
       _client = client ?? http.Client();

  /// Always ends in '/', so request paths resolve under it.
  final Uri baseUrl;
  final Duration timeout;
  final http.Client _client;

  /// Sends one request and returns the decoded JSON reply, or null for an
  /// empty one.
  Future<Object?> send(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final request = http.Request(method, baseUrl.resolve(path))
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );
    } on TimeoutException {
      throw const ApiException('The server took too long to answer.');
    } on http.ClientException {
      throw const ApiException(
        "Can't reach the server. Check your connection.",
      );
    }

    final text = utf8.decode(response.bodyBytes);
    final Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      throw ApiException(
        'The server sent an unreadable reply.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 400) return json;

    final error = json is Map<String, dynamic>
        ? json['error'] as Map<String, dynamic>?
        : null;
    final message =
        error?['message'] as String? ??
        'The server answered with error ${response.statusCode}.';
    throw switch (error?['kind']) {
      'auth' => AuthException(message),
      'bet' => BetRejected(message),
      'shop' => ShopRejected(message),
      _ => ApiException(message, statusCode: response.statusCode),
    };
  }

  void close() => _client.close();
}

/// [AccountApi] backed by the football server.
class HttpAccountApi implements AccountApi {
  HttpAccountApi(this._api);

  final ApiConnection _api;

  @override
  Future<String> createAccount(String username, String password) async =>
      _token(
        await _api.send(
          'POST',
          'v1/accounts',
          body: {'username': username, 'password': password},
        ),
      );

  @override
  Future<String> logIn(String username, String password) async => _token(
    await _api.send(
      'POST',
      'v1/sessions',
      body: {'username': username, 'password': password},
    ),
  );

  @override
  Future<void> logOut(String token) =>
      _api.send('DELETE', 'v1/sessions', token: token);

  @override
  Future<Account> accountFor(String token) async => Account.fromJson(
    await _api.send('GET', 'v1/me', token: token) as Map<String, dynamic>,
  );

  static String _token(Object? json) =>
      (json as Map<String, dynamic>)['token'] as String;
}

/// [BettingApi] backed by the football server.
class HttpBettingApi implements BettingApi {
  HttpBettingApi(this._api);

  final ApiConnection _api;

  Future<Map<String, dynamic>> _object(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async =>
      await _api.send(method, path, token: token, body: body)
          as Map<String, dynamic>;

  Future<List<dynamic>> _list(String path, {String? token}) async =>
      await _api.send('GET', path, token: token) as List<dynamic>;

  static String _game(String id) => 'v1/games/${Uri.encodeComponent(id)}';

  @override
  Future<List<Game>> fetchGames() async => [
    for (final game in await _list('v1/games'))
      Game.fromJson(game as Map<String, dynamic>),
  ];

  @override
  Future<int> balance(String token) async =>
      (await _object('GET', 'v1/me/balance', token: token))['balance'] as int;

  @override
  Future<Set<String>> ownedShopItems(String token) async => {
    for (final id in await _list('v1/me/shop/owned', token: token))
      id as String,
  };

  @override
  Future<String> activeShopTheme(String token) async =>
      (await _object('GET', 'v1/me/shop/theme', token: token))['id'] as String;

  @override
  Future<void> setActiveShopTheme(String token, String themeId) =>
      _api.send('PUT', 'v1/me/shop/theme', token: token, body: {'id': themeId});

  @override
  Future<String?> activeShopBackground(String token) async =>
      (await _object('GET', 'v1/me/shop/background', token: token))['id']
          as String?;

  @override
  Future<void> setActiveShopBackground(String token, String? backgroundId) =>
      _api.send(
        'PUT',
        'v1/me/shop/background',
        token: token,
        body: {'id': backgroundId},
      );

  @override
  Future<int> purchaseShopItem(String token, String itemId) async =>
      (await _object(
            'POST',
            'v1/me/shop/purchases',
            token: token,
            body: {'itemId': itemId},
          ))['balance']
          as int;

  @override
  Future<bool> canClaimDailyReward(String token) async =>
      (await _object('GET', 'v1/me/daily-reward', token: token))['canClaim']
          as bool;

  @override
  Future<int> claimDailyReward(String token) async =>
      (await _object('POST', 'v1/me/daily-reward', token: token))['balance']
          as int;

  @override
  Future<int> claimBailoutIfBroke(String token) async =>
      (await _object('POST', 'v1/me/bailout', token: token))['coins'] as int;

  @override
  Future<List<GameNotification>> notifications(String token) async => [
    for (final n in await _list('v1/me/notifications', token: token))
      GameNotification.fromJson(n as Map<String, dynamic>),
  ];

  @override
  Future<void> markNotificationsRead(String token) =>
      _api.send('POST', 'v1/me/notifications/read', token: token);

  @override
  Future<Map<String, Bet>> bets(String token) async => {
    for (final MapEntry(:key, :value) in (await _object(
      'GET',
      'v1/me/bets',
      token: token,
    )).entries)
      key: Bet.fromJson(value as Map<String, dynamic>),
  };

  @override
  Future<CrowdStats> crowd(Game game, {String? token}) async =>
      CrowdStats.fromJson(
        await _object('GET', '${_game(game.id)}/crowd', token: token),
      );

  @override
  Future<void> placeBet(
    String token,
    String gameId,
    TeamSide side,
    int amount, {
    ScoreRange? scoreRange,
  }) => _api.send(
    'POST',
    '${_game(gameId)}/bets',
    token: token,
    body: {
      'side': side.name,
      'amount': amount,
      'scoreRange': scoreRange?.toJson(),
    },
  );

  @override
  Future<int> cashOutHalf(String token, String gameId) async =>
      (await _object(
            'POST',
            '${_game(gameId)}/cash-out',
            token: token,
          ))['refund']
          as int;

  @override
  Future<int> withdrawBet(String token, String gameId) async =>
      (await _object('DELETE', '${_game(gameId)}/bets', token: token))['refund']
          as int;

  @override
  Future<List<String>> takeResults(String token) async => [
    for (final id
        in (await _api.send('POST', 'v1/me/results/take', token: token))!
            as List)
      id as String,
  ];
}
