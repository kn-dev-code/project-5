import 'package:flutter/material.dart';

import '../data/auth.dart';
import '../data/app_theme.dart';
import '../data/backend.dart';
import '../models/shop_item.dart';
import '../server/betting_server.dart';
import 'game_select_screen.dart';
import 'login_screen.dart';
import 'shop_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session, this.auth, this.server});

  final Session session;

  /// Used to log out. Defaults to [Auth] with the shared accounts server.
  final Auth? auth;

  final BettingServer? server;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final BettingServer _server = widget.server ?? backend;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final themeId = await _server.activeShopTheme(widget.session.token);
    if (!mounted) return;
    ShopItem? theme;
    if (themeId == startingTheme.id) {
      theme = startingTheme;
    } else {
      for (final item in shopItems) {
        if (item.id == themeId && item.type == ShopItemType.theme) {
          theme = item;
          break;
        }
      }
    }
    appTheme.activate(theme ?? startingTheme);
  }

  Future<void> _logOut(BuildContext context) async {
    final auth = widget.auth ?? Auth();
    await auth.logOut(widget.session);
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(auth: auth)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Football Winner'),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        actions: [
          IconButton(
            onPressed: () => _logOut(context),
            icon: const Icon(Icons.logout),
            tooltip: 'Log Out',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.sports_football, size: 96, color: colors.primary),
              const SizedBox(height: 16),
              Text(
                'Football Winner',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Logged in as ${widget.session.account.username}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GameSelectScreen(session: widget.session),
                  ),
                ),
                icon: const Icon(Icons.sports_football),
                label: const Text('Select Game'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ShopScreen(
                      session: widget.session,
                      server: _server,
                    ),
                  ),
                ),
                icon: const Icon(Icons.storefront),
                label: const Text('Shop'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
