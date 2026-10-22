import 'package:flutter/material.dart';

enum ShopItemType { background, theme }

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
];
