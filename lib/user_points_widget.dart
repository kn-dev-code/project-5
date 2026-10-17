import 'package:flutter/material.dart';

class UserPointsWidget extends StatefulWidget {
  const UserPointsWidget({super.key});

  @override
  State<UserPointsWidget> createState() => _UserPointsWidgetState();
}

class _UserPointsWidgetState extends State<UserPointsWidget> {
  int _points = 120; // Starting points for correct team guesses
  int _correctStreak = 3;

  void _addPoints(int amount) {
    setState(() {
      _points += amount;
      _correctStreak++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Prediction Scoreboard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Total Points: $_points', style: const TextStyle(fontSize: 16)),
            Text('Correct Pick Streak: $_correctStreak games', style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _addPoints(10),
              icon: const Icon(Icons.add),
              label: const Text('Simulate Correct Guess (+10 pts)'),
            ),
          ],
        ),
      ),
    );
  }
}
