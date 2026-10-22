import 'package:flutter/material.dart';

import 'screens/start_screen.dart';

void main() {
  runApp(const FootballWinnerApp());
}

class FootballWinnerApp extends StatelessWidget {
  const FootballWinnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Football Winner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green.shade800),
      ),
      home: const StartScreen(),
    );
  }
}
