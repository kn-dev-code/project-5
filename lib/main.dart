import 'package:flutter/material.dart';

import 'data/app_theme.dart';
import 'screens/start_screen.dart';

void main() {
  runApp(const FootballWinnerApp());
}

class FootballWinnerApp extends StatelessWidget {
  const FootballWinnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
      valueListenable: appTheme,
      builder: (context, theme, _) => MaterialApp(
        title: 'Football Winner',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const StartScreen(),
      ),
    );
  }
}
