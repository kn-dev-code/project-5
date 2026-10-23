/// A player's account, as the app sees it. Passwords never leave the server.
class Account {
  const Account({required this.id, required this.username});

  factory Account.fromJson(Map<String, dynamic> json) =>
      Account(id: json['id'] as String, username: json['username'] as String);

  final String id;
  final String username;

  Map<String, Object?> toJson() => {'id': id, 'username': username};
}
