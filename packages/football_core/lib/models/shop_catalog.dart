enum ShopItemType { background, theme }

/// What the server needs to know about an item it sells. The app keeps the
/// names, colors and icons in its own list, keyed by the same [id].
class ShopListing {
  const ShopListing(this.id, this.type, this.price);

  final String id;
  final ShopItemType type;
  final int price;
}

/// The free theme every player starts with.
const startingThemeListing = ShopListing('basic_theme', ShopItemType.theme, 0);

/// Everything for sale.
const shopListings = <ShopListing>[
  ShopListing('stadium_lights', ShopItemType.background, 250),
  ShopListing('gridiron', ShopItemType.background, 400),
  ShopListing('sunset_drive', ShopItemType.background, 350),
  ShopListing('snow_game', ShopItemType.background, 450),
  ShopListing('championship', ShopItemType.background, 600),
  ShopListing('midnight_theme', ShopItemType.theme, 500),
  ShopListing('gold_theme', ShopItemType.theme, 750),
  ShopListing('red_zone_theme', ShopItemType.theme, 650),
  ShopListing('arctic_theme', ShopItemType.theme, 650),
  ShopListing('purple_reign_theme', ShopItemType.theme, 800),
];

ShopListing? shopListingById(String id) {
  for (final listing in shopListings) {
    if (listing.id == id) return listing;
  }
  return null;
}
