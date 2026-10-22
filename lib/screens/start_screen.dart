import 'package:flutter/material.dart';

import '../data/auth.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Opens the homepage if a session was saved on this device, or the login
/// screen if not.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key, this.auth});

  /// Defaults to [Auth] with the shared accounts server.
  final Auth? auth;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  late final Auth _auth = widget.auth ?? Auth();
  late final Future<Session?> _session = _auth.restore();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data case final session?) {
          return HomeScreen(session: session, auth: _auth);
        }
        return LoginScreen(auth: _auth);
      },
    );
  }
}
