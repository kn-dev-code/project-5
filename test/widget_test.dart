import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footballapp/main.dart';

void main() {
  testWidgets('Login screen leads to homepage with Select Game and Shop',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FootballWinnerApp());

    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Select Game'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
  });

  testWidgets('Create account screen asks for username and password twice',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FootballWinnerApp());

    await tester.tap(find.text("Don't have an account? Create one"));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Confirm Password'), findsOneWidget);
  });
}
