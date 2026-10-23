import 'package:flutter/material.dart';
import 'package:football_core/models/shop_catalog.dart';

export 'package:football_core/models/shop_catalog.dart' show ShopItemType;

// Prices and types must match the server's [shopListings]; a test checks this.

const startingTheme = ShopItem(
  id: 'basic_theme',
  name: 'Basic Theme',
  description: 'The original Football Winner green theme.',
  price: 0,
  type: ShopItemType.theme,
  color: Color(0xFF1B5E20),
  icon: Icons.sports_football,
);

class ShopItem {
  const ShopItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.type,
    required this.color,
    required this.icon,
  });

  final String id;
  final String name;
  final String description;
  final int price;
  final ShopItemType type;
  final Color color;
  final IconData icon;

  String get typeLabel => switch (type) {
    ShopItemType.background => 'Background',
    ShopItemType.theme => 'Theme',
  };
}

const shopItems = <ShopItem>[
  ShopItem(
    id: 'stadium_lights',
    name: 'Stadium Lights',
    description: 'A bright Friday night stadium look.',
    price: 250,
    type: ShopItemType.background,
    color: Color(0xFF163A35),
    icon: Icons.stadium,
  ),
  ShopItem(
    id: 'gridiron',
    name: 'Gridiron',
    description: 'Bring the field stripes to your home screen.',
    price: 400,
    type: ShopItemType.background,
    color: Color(0xFF285D38),
    icon: Icons.sports_football,
  ),
  ShopItem(
    id: 'sunset_drive',
    name: 'Sunset Drive',
    description: 'A warm sunset over the field. Greatness starts here.',
    price: 350,
    type: ShopItemType.background,
    color: Color(0xFF9C3D4A),
    icon: Icons.wb_twilight,
  ),
  ShopItem(
    id: 'snow_game',
    name: 'Snow Game',
    description: 'A crisp winter field under falling snow.',
    price: 450,
    type: ShopItemType.background,
    color: Color(0xFF527B9D),
    icon: Icons.ac_unit,
  ),
  ShopItem(
    id: 'championship',
    name: 'Championship Night',
    description: 'A packed championship field beneath the lights.',
    price: 600,
    type: ShopItemType.background,
    color: Color(0xFF512B72),
    icon: Icons.emoji_events,
  ),
  ShopItem(
    id: 'midnight_theme',
    name: 'Midnight Theme',
    description: 'A deep navy look for late games.',
    price: 500,
    type: ShopItemType.theme,
    color: Color(0xFF18243B),
    icon: Icons.dark_mode,
  ),
  ShopItem(
    id: 'gold_theme',
    name: 'Gold Rush Theme',
    description: 'Warm gold accents for your collection.',
    price: 750,
    type: ShopItemType.theme,
    color: Color(0xFF9B7626),
    icon: Icons.auto_awesome,
  ),
  ShopItem(
    id: 'red_zone_theme',
    name: 'Red Zone Theme',
    description: 'Bold crimson colors for every game day.',
    price: 650,
    type: ShopItemType.theme,
    color: Color(0xFFB32635),
    icon: Icons.flag,
  ),
  ShopItem(
    id: 'arctic_theme',
    name: 'Arctic Theme',
    description: 'Cool blue colors with a clean, icy feel.',
    price: 650,
    type: ShopItemType.theme,
    color: Color(0xFF2878A5),
    icon: Icons.ac_unit,
  ),
  ShopItem(
    id: 'purple_reign_theme',
    name: 'Purple Reign Theme',
    description: 'A bold purple palette for your home team.',
    price: 800,
    type: ShopItemType.theme,
    color: Color(0xFF673AB7),
    icon: Icons.bolt,
  ),
];
