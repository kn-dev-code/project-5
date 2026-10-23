import 'package:flutter/material.dart';

/// The day of [time] in the phone's time zone: 'Today', 'Tomorrow',
/// 'Yesterday', or the weekday and date, e.g. 'Sun, Oct 25'.
String formatGameDay(BuildContext context, DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  return switch (DateUtils.dateOnly(local).difference(today).inDays) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => MaterialLocalizations.of(context).formatMediumDate(local),
  };
}

/// The clock time of [time] in the phone's time zone, e.g. '1:30 PM'.
///
/// Live feeds send times in UTC, so they must be converted before showing.
String formatGameTime(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(time.toLocal()));
