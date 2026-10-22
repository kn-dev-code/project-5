/// A player's account, as the app sees it. Passwords never leave the server.
class Account {
  const Account({required this.id, required this.username});

  final String id;
  final String username;
}
