import 'package:flutter/material.dart';
import 'package:football_core/api/betting_api.dart';
import 'package:football_core/models/game_notification.dart';

import '../data/auth.dart';
import '../data/errors.dart';
import '../data/sound_effects.dart';

/// App bar button that opens the notifications list, with a badge counting
/// unread ones.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.unread,
    required this.onPressed,
  });

  final int unread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: sfx.withSound(onPressed),
    tooltip: 'Notifications',
    icon: Badge(
      isLabelVisible: unread > 0,
      label: Text('$unread'),
      child: Icon(
        unread > 0 ? Icons.notifications_active : Icons.notifications,
      ),
    ),
  );
}

/// One line per notification for a snack bar, e.g. 'Halftime: ... Your bet'.
String notificationSummary(Iterable<GameNotification> notifications) =>
    notifications.map((n) => '${n.title}. ${n.body}').join('\n');

/// Lists the player's notifications, newest first, and marks them all read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.session,
    required this.server,
  });

  final Session session;
  final BettingApi server;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<GameNotification>? _notifications;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    try {
      // Read before marking, so unread ones still stand out on this visit.
      final notifications = await widget.server.notifications(token);
      await widget.server.markNotificationsRead(token);
      if (mounted) setState(() => _notifications = notifications);
    } catch (e) {
      final message = userMessage(e);
      if (message == null) rethrow;
      if (mounted) setState(() => _error = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final notifications = _notifications;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ),
      body: SafeArea(
        child: notifications == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
              )
            : notifications.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Bet on a game and you'll get its halftime score and "
                    'result here.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: notifications.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) =>
                    _NotificationTile(notification: notifications[i]),
              ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final GameNotification notification;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = !notification.read;
    final sent = TimeOfDay.fromDateTime(notification.sentAt.toLocal());

    return ListTile(
      tileColor: unread ? colors.primaryContainer : null,
      leading: Icon(
        notification.kind == GameNotificationKind.halftime
            ? Icons.timer_outlined
            : Icons.emoji_events_outlined,
        color: colors.primary,
      ),
      title: Text(
        notification.title,
        style: unread ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      subtitle: Text(notification.body),
      trailing: Text(
        MaterialLocalizations.of(context).formatTimeOfDay(sent),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
