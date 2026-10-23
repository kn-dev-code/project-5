/// What a [GameNotification] is about.
enum GameNotificationKind { halftime, result }

/// A message the server sends a player about a game they bet on.
class GameNotification {
  const GameNotification({
    required this.id,
    required this.gameId,
    required this.kind,
    required this.title,
    required this.body,
    required this.sentAt,
    this.read = false,
  });

  factory GameNotification.fromJson(Map<String, dynamic> json) =>
      GameNotification(
        id: json['id'] as int,
        gameId: json['gameId'] as String,
        kind: GameNotificationKind.values.byName(json['kind'] as String),
        title: json['title'] as String,
        body: json['body'] as String,
        sentAt: DateTime.parse(json['sentAt'] as String),
        read: json['read'] as bool? ?? false,
      );

  /// Increases with every notification the server sends, so newer
  /// notifications have bigger ids.
  final int id;
  final String gameId;
  final GameNotificationKind kind;
  final String title;
  final String body;
  final DateTime sentAt;
  final bool read;

  GameNotification markedRead() => GameNotification(
    id: id,
    gameId: gameId,
    kind: kind,
    title: title,
    body: body,
    sentAt: sentAt,
    read: true,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'gameId': gameId,
    'kind': kind.name,
    'title': title,
    'body': body,
    'sentAt': sentAt.toIso8601String(),
    'read': read,
  };
}
