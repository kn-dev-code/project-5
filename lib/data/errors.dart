import 'dart:async';

import 'package:football_core/api/betting_api.dart';
import 'package:football_core/api/http_api.dart';

/// What to tell the player about [error], or null if it's a bug rather than
/// something they can act on.
String? userMessage(Object error) => switch (error) {
  AuthException(:final message) ||
  BetRejected(:final message) ||
  ShopRejected(:final message) ||
  ApiException(:final message) => message,
  // Several requests at once, at least one failed; most likely the network.
  ParallelWaitError() =>
    "Couldn't load everything from the server. "
        'Try again.',
  _ => null,
};
