import 'package:flutter/material.dart';

import '../models/shop_item.dart';

class AppThemeController extends ValueNotifier<ThemeData> {
  AppThemeController() : super(_themeFor(startingTheme));

  void activate(ShopItem item) {
    if (item.type != ShopItemType.theme) return;
    value = _themeFor(item);
  }

  static ThemeData _themeFor(ShopItem item) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: item.color),
      );
}

final appTheme = AppThemeController();

/// The shop background shown behind the main screens, or null for none.
final appBackground = ValueNotifier<ShopItem?>(null);

/// Shows the background with [id], or none if [id] isn't a background.
void activateBackground(String? id) {
  appBackground.value = shopItems
      .where((item) => item.id == id && item.type == ShopItemType.background)
      .firstOrNull;
}
