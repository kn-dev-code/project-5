import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footballapp/widgets/game_time.dart';

Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    ),
  );
  return context;
}

void main() {
  testWidgets('names nearby days and dates the rest', (tester) async {
    final context = await _context(tester);
    final now = DateTime(2026, 10, 23, 9);

    String day(DateTime time) => formatGameDay(context, time, now: now);

    expect(day(DateTime(2026, 10, 23, 20)), 'Today');
    expect(day(DateTime(2026, 10, 24, 0, 30)), 'Tomorrow');
    expect(day(DateTime(2026, 10, 22, 23)), 'Yesterday');
    expect(day(DateTime(2026, 10, 25, 13)), 'Sun, Oct 25');
    expect(day(DateTime(2026, 10, 19, 20)), 'Mon, Oct 19');
  });

  testWidgets('shows feed times, which come in UTC, in local time', (
    tester,
  ) async {
    final context = await _context(tester);
    final kickoff = DateTime.utc(2026, 10, 25, 17);
    final local = kickoff.toLocal();

    expect(
      formatGameTime(context, kickoff),
      MaterialLocalizations.of(context)
          .formatTimeOfDay(TimeOfDay(hour: local.hour, minute: local.minute)),
    );
    expect(
      formatGameDay(context, kickoff, now: DateTime(2026, 10, 23)),
      MaterialLocalizations.of(context).formatMediumDate(local),
    );
  });
}
