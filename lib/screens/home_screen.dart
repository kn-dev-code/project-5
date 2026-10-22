import 'package:flutter/material.dart';

import '../data/auth.dart';
import '../data/app_theme.dart';
import '../data/backend.dart';
import '../models/shop_item.dart';
import '../server/betting_server.dart';
import '../widgets/shop_background.dart';
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

  int? _balance;
  bool _canClaimDailyReward = false;
  bool _loadingReward = true;
  bool _claimingReward = false;
  String? _rewardError;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _refreshRewards(awardOnLogin: true);
  }

  Future<void> _loadTheme() async {
    try {
      final (themeId, backgroundId) = await (
        _server.activeShopTheme(widget.session.token),
        _server.activeShopBackground(widget.session.token),
      ).wait;
      if (!mounted) return;
      activateBackground(backgroundId);
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
    } catch (_) {
      // The rest of the home screen remains usable if theme loading fails.
    }
  }

  Future<void> _refreshRewards({bool awardOnLogin = false}) async {
    if (!mounted) return;
    setState(() {
      _loadingReward = true;
      _rewardError = null;
    });
    try {
      final (balance, canClaim) = await (
        _server.balance(widget.session.token),
        _server.canClaimDailyReward(widget.session.token),
      ).wait;
      var currentBalance = balance;
      var rewardAvailable = canClaim;
      if (awardOnLogin && canClaim) {
        currentBalance = await _server.claimDailyReward(widget.session.token);
        rewardAvailable = false;
      }
      if (!mounted) return;
      setState(() {
        _balance = currentBalance;
        _canClaimDailyReward = rewardAvailable;
        _loadingReward = false;
      });
      if (awardOnLogin && canClaim) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Daily login reward: +${BettingServer.dailyRewardAmount} coins!',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingReward = false;
        _rewardError = 'Could not load your coins. Please try again.';
      });
    }
  }

  Future<void> _claimDailyReward() async {
    if (_claimingReward || _loadingReward || !_canClaimDailyReward) return;
    setState(() => _claimingReward = true);
    try {
      final newBalance = await _server.claimDailyReward(widget.session.token);
      if (!mounted) return;
      setState(() {
        _balance = newBalance;
        _canClaimDailyReward = false;
        _rewardError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You claimed 250 free coins!')),
      );
    } on BetRejected catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      await _refreshRewards();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not claim reward. Try again.')),
      );
      await _refreshRewards();
    } finally {
      if (mounted) setState(() => _claimingReward = false);
    }
  }

  Future<void> _openGames() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameSelectScreen(session: widget.session),
      ),
    );
    if (mounted) await _refreshRewards();
  }

  Future<void> _openShop() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopScreen(
          session: widget.session,
          server: _server,
        ),
      ),
    );
    if (mounted) {
      await _loadTheme();
      await _refreshRewards();
    }
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
      body: ShopBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: BackgroundPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.sports_football,
                      size: 96,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Football Winner',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Logged in as ${widget.session.account.username}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.monetization_on, color: colors.primary),
                                const SizedBox(width: 8),
                                Text(
                                  _balance == null ? 'Coins: —' : 'Coins: $_balance',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  tooltip: 'Refresh balance and reward',
                                  onPressed: _loadingReward || _claimingReward
                                      ? null
                                      : _refreshRewards,
                                  icon: const Icon(Icons.refresh),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Daily Reward: 250 Free Coins',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            if (_loadingReward)
                              const CircularProgressIndicator()
                            else ...[
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _canClaimDailyReward && !_claimingReward
                                      ? _claimDailyReward
                                      : null,
                                  icon: Icon(
                                    _canClaimDailyReward
                                        ? Icons.card_giftcard
                                        : Icons.check_circle_outline,
                                  ),
                                  label: Text(
                                    _claimingReward
                                        ? 'Claiming...'
                                        : _canClaimDailyReward
                                            ? 'Claim 250 Coins'
                                            : 'Reward Claimed Today',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _canClaimDailyReward
                                    ? 'Your free coins are ready!'
                                    : 'Next reward resets at midnight UTC.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (_rewardError != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _rewardError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.error),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _openGames,
                      icon: const Icon(Icons.sports_football),
                      label: const Text('Select Game'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _openShop,
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
          ),
        ),
      ),
    );
  }
}
