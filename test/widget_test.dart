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

  testWidgets('Select Game lists games and lets the user pick a live winner',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FootballWinnerApp());

    await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select Game'));
    await tester.pumpAndSettle();

    expect(find.text('Live Now'), findsOneWidget);
    expect(find.text('Riverside Raptors'), findsOneWidget);

    await tester.tap(find.text('Riverside Raptors'));
    await tester.pumpAndSettle();

    expect(find.text('Who will win?'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Confirm Pick');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.widgetWithText(ListTile, 'Northgate Knights'));
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.text('You picked Northgate Knights to win!'), findsOneWidget);
    expect(find.text('Live Now'), findsOneWidget);
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
