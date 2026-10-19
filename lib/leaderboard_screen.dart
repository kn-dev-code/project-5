import 'package:flutter/material.dart';

class LeaderboardUser {
  final String username;
  final int correctGuesses;
  final int totalPoints;
  final String avatarUrl;

  LeaderboardUser({
    required this.username,
    required this.correctGuesses,
    required this.totalPoints,
    required this.avatarUrl,
  });
}

class LeaderboardScreen extends StatelessWidget {
  LeaderboardScreen({super.key});

  final List<LeaderboardUser> _topUsers = [
    LeaderboardUser(username: 'Alex_Picks', correctGuesses: 28, totalPoints: 1420, avatarUrl: ''),
    LeaderboardUser(username: 'GridironGuru', correctGuesses: 25, totalPoints: 1250, avatarUrl: ''),
    LeaderboardUser(username: 'TouchdownTim', correctGuesses: 22, totalPoints: 1100, avatarUrl: ''),
    LeaderboardUser(username: 'Sarah_Stats', correctGuesses: 19, totalPoints: 950, avatarUrl: ''),
    LeaderboardUser(username: 'FootballFanatic', correctGuesses: 15, totalPoints: 750, avatarUrl: ''),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Top Predictors Leaderboard'),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12.0),
        itemCount: _topUsers.length,
        itemBuilder: (context, index) {
          final user = _topUsers[index];
          final rank = index + 1;

          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getRankColor(rank),
                child: Text(
                  '#$rank',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                user.username,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${user.correctGuesses} correct team guesses'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${user.totalPoints} pts',
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber.shade700; // Gold
      case 2:
        return Colors.grey.shade500;  // Silver
      case 3:
        return Colors.brown.shade400; // Bronze
      default:
        return Colors.blueGrey;
    }
  }
}
