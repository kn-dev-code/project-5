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
