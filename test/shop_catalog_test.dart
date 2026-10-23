import 'package:flutter_test/flutter_test.dart';
import 'package:football_core/models/shop_catalog.dart';
import 'package:footballapp/models/shop_item.dart';

void main() {
  test('the app shows the same items, types and prices the server sells', () {
    String describe(String id, ShopItemType type, int price) =>
        '$id ${type.name} $price';

    expect(
      [for (final item in shopItems) describe(item.id, item.type, item.price)],
      [
        for (final listing in shopListings)
          describe(listing.id, listing.type, listing.price),
      ],
    );
    expect(
      describe(startingTheme.id, startingTheme.type, startingTheme.price),
      describe(
        startingThemeListing.id,
        startingThemeListing.type,
        startingThemeListing.price,
      ),
    );
  });
}
