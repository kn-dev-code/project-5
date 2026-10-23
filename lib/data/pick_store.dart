import 'dart:convert';

import 'package:football_core/models/game.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saves the user's winner picks on the device, keyed by game id.
class PickStore {
  static const _key = 'winner_picks';

  Future<Map<String, TeamSide>> loadPicks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        key: ?TeamSide.values.asNameMap()[value],
    };
  }

  Future<void> savePick(String gameId, TeamSide side) async {
    final picks = await loadPicks();
    picks[gameId] = side;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({for (final e in picks.entries) e.key: e.value.name}),
    );
  }
}
