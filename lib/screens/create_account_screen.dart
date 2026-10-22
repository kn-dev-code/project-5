import 'package:flutter/material.dart';

import '../data/auth.dart';
import '../server/account_server.dart';
import 'home_screen.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key, this.auth});

  /// Defaults to [Auth] with the shared accounts server.
  final Auth? auth;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  late final Auth _auth = widget.auth ?? Auth();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _confirmError;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Creates the account and logs straight in. The server checks the
  /// username and password rules; only the confirmation is checked here.
  Future<void> _create() async {
    if (_passwordController.text != _confirmController.text) {
      setState(() {
        _error = null;
        _confirmError = "Passwords don't match.";
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _confirmError = null;
    });
    try {
      final session = await _auth.createAccount(
        _usernameController.text,
        _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => HomeScreen(session: session, auth: _auth),
        ),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    helperText: '3 to 20 letters, numbers or underscores',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  autocorrect: false,
                  autofillHints: const [AutofillHints.newUsername],
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    helperText:
                        'At least ${AccountServer.minPasswordLength} '
                        'characters',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmController,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    errorText: _confirmError,
                  ),
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _create(),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 16),
                  Text(error, style: TextStyle(color: colors.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Create Account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
