import 'package:flutter/material.dart';

import '../data/auth.dart';
import '../data/errors.dart';
import '../data/sound_effects.dart';
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
  late Future<Session?> _session = _auth.restore();

  @override
  void initState() {
    super.initState();
    // Wait for the saved mute setting, so a muted app opens quietly.
    sfx.loadSettings().then((_) => sfx.play(Sound.startup));
  }

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
        if (snapshot.error case final error? when userMessage(error) != null) {
          // Couldn't reach the server, so we don't know if the saved session
          // is still good. Don't log the player out over it.
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(userMessage(error)!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: sfx.withSound(
                        () => setState(() => _session = _auth.restore()),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
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
