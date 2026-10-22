import 'package:flutter/material.dart';

import '../data/auth.dart';
import '../data/app_theme.dart';
import '../data/backend.dart';
import '../models/shop_item.dart';
import '../server/betting_server.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.session, this.server});

  final Session session;
  final BettingServer? server;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late final BettingServer _server = widget.server ?? backend;
  int _balance = 0;
  Set<String> _owned = {};
  String _activeThemeId = startingTheme.id;
  String? _activeBackgroundId;
  bool _loading = true;
  String? _busyItem;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final (balance, owned, activeThemeId, activeBackgroundId) = await (
      _server.balance(widget.session.token),
      _server.ownedShopItems(widget.session.token),
      _server.activeShopTheme(widget.session.token),
      _server.activeShopBackground(widget.session.token),
    ).wait;
    if (!mounted) return;
    final activeTheme = _themeById(activeThemeId);
    if (activeTheme != null) appTheme.activate(activeTheme);
    activateBackground(activeBackgroundId);
    setState(() {
      _balance = balance;
      _owned = owned;
      _activeThemeId = activeThemeId;
      _activeBackgroundId = activeBackgroundId;
      _loading = false;
    });
  }

  ShopItem? _themeById(String id) {
    if (id == startingTheme.id) return startingTheme;
    for (final item in shopItems) {
      if (item.id == id && item.type == ShopItemType.theme) return item;
    }
    return null;
  }

  Future<void> _purchase(ShopItem item) async {
    setState(() => _busyItem = item.id);
    try {
      final balance = await _server.purchaseShopItem(
        widget.session.token,
        item.id,
      );
      final owned = await _server.ownedShopItems(widget.session.token);
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _owned = owned;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} added to your inventory.')),
      );
    } on ShopRejected catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _busyItem = null);
    }
  }

  Future<void> _activateTheme(ShopItem item) async {
    setState(() => _busyItem = item.id);
    try {
      await _server.setActiveShopTheme(widget.session.token, item.id);
      if (!mounted) return;
      appTheme.activate(item);
      setState(() => _activeThemeId = item.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} is now active.')),
      );
    } on ShopRejected catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _busyItem = null);
    }
  }

  /// Shows [item] as the background, or removes the background if [item] is
  /// already the active one.
  Future<void> _toggleBackground(ShopItem item) async {
    final newId = _activeBackgroundId == item.id ? null : item.id;
    setState(() => _busyItem = item.id);
    try {
      await _server.setActiveShopBackground(widget.session.token, newId);
      if (!mounted) return;
      activateBackground(newId);
      setState(() => _activeBackgroundId = newId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newId == null
                ? '${item.name} removed.'
                : '${item.name} is now your background.',
          ),
        ),
      );
    } on ShopRejected catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _busyItem = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Shop'),
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('$_balance coins',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.storefront), text: 'Shop'),
              Tab(icon: Icon(Icons.inventory_2), text: 'Inventory'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildShop(colors),
                  _buildInventory(colors),
                ],
              ),
      ),
    );
  }

  Widget _buildShop(ColorScheme colors) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Personalize your game day',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Spend your coins on backgrounds and themes.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          for (final item in shopItems) _itemCard(item, inInventory: false),
        ],
      );

  Widget _buildInventory(ColorScheme colors) {
    final items = [
      startingTheme,
      ...shopItems.where((item) => _owned.contains(item.id)),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${items.length} ${items.length == 1 ? 'item' : 'items'} owned',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final item in items) _itemCard(item, inInventory: true),
      ],
    );
  }

  Widget _itemCard(ShopItem item, {required bool inInventory}) {
    final owned = _owned.contains(item.id);
    final isTheme = item.type == ShopItemType.theme;
    final active = isTheme && _activeThemeId == item.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 96,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [item.color, item.color.withValues(alpha: 0.55)],
              ),
            ),
            child: Icon(item.icon, size: 48, color: Colors.white),
          ),
          ListTile(
            title: Text(item.name),
            subtitle: Text('${item.typeLabel} · ${item.description}'),
            trailing: inInventory && !isTheme
                ? OutlinedButton(
                    onPressed: _busyItem == null
                        ? () => _toggleBackground(item)
                        : null,
                    child: Text(
                      _activeBackgroundId == item.id
                          ? 'Remove'
                          : 'Use background',
                    ),
                  )
                : inInventory && isTheme
                ? active
                    ? const Chip(label: Text('Active'))
                    : OutlinedButton(
                        onPressed: _busyItem == null
                            ? () => _activateTheme(item)
                            : null,
                        child: _busyItem == item.id
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Use theme'),
                      )
                : inInventory || owned
                    ? const Chip(label: Text('Owned'))
                : FilledButton.tonal(
                    onPressed: _busyItem == null ? () => _purchase(item) : null,
                    child: _busyItem == item.id
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('${item.price} coins'),
                  ),
          ),
        ],
      ),
    );
  }
}
