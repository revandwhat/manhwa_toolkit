import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'game_page.dart';

// ==== YOUR SUPABASE PROJECT (Dashboard -> Project Settings -> API) ====
// Paste your values between the quotes and rebuild. Then EVERY user gets
// login/signup with zero setup. The anon/publishable key is safe to embed.
const String kSupabaseUrl = 'https://cbadhjkgcnxiclmrimlf.supabase.co';
const String kSupabasePublishableKey = 'sb_publishable_KQGQCv1ioKofoGrDrt7Few_l-PKwqms';

class SbReady {
  static bool initialized = false;
}

Future<void> initSupabaseFromPrefs() async {
  if (kSupabaseUrl.isNotEmpty && kSupabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(
        url: kSupabaseUrl, publishableKey: kSupabasePublishableKey);
    SbReady.initialized = true;
    return;
  }
  final p = await SharedPreferences.getInstance();
  final url = p.getString('sb_url');
  final key = p.getString('sb_key');
  if (url != null && key != null && url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: key);
    SbReady.initialized = true;
  }
}

class GameGate extends StatefulWidget {
  const GameGate({super.key});

  @override
  State<GameGate> createState() => _GameGateState();
}

class _GameGateState extends State<GameGate> {
  @override
  Widget build(BuildContext context) {
    if (!SbReady.initialized) return const _SbConfigForm();
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snap) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return const LoginPage();
        return const GamePage();
      },
    );
  }
}

class _SbConfigForm extends StatefulWidget {
  const _SbConfigForm();

  @override
  State<_SbConfigForm> createState() => _SbConfigFormState();
}

class _SbConfigFormState extends State<_SbConfigForm> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Supabase.initialize(
        url: _url.text.trim(),
        publishableKey: _key.text.trim(),
      );
      SbReady.initialized = true;
      final p = await SharedPreferences.getInstance();
      await p.setString('sb_url', _url.text.trim());
      await p.setString('sb_key', _key.text.trim());
      if (mounted) setState(() {});
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect online backend')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'One-time setup. Create a free project at supabase.com, run the '
            'schema SQL (from the build guide), then paste:\n\n'
            '1. Project URL  (Settings -> API -> Project URL)\n'
            '2. anon public key  (Settings -> API -> Project API keys)\n\n'
            'Use the ANON key only - never the service_role key.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
                labelText: 'Project URL', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            decoration: const InputDecoration(
                labelText: 'anon public key', border: OutlineInputBorder()),
          ),
          if (_err != null) ...[
            const SizedBox(height: 12),
            Text(_err!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Connecting...' : 'Connect'),
          ),
        ],
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _user = TextEditingController();
  bool _mode = false; // false = login, true = signup
  bool _busy = false;
  String? _err;

  SupabaseClient get _sb => Supabase.instance.client;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (_mode) {
        if (_user.text.trim().length < 3) {
          throw Exception('Username needs at least 3 characters');
        }
        await _sb.auth.signUp(
          email: _email.text.trim(),
          password: _pass.text,
          data: {'username': _user.text.trim()},
        );
      } else {
        await _sb.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _pass.text,
        );
      }
    } on AuthException catch (e) {
      setState(() => _err = e.message);
    } catch (e) {
      setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _forgotFlow() async {
    final emailC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password - step 1'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('We will email you a 6-digit code.'),
            const SizedBox(height: 12),
            TextField(
              controller: emailC,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send code')),
        ],
      ),
    );
    if (ok != true || emailC.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await _sb.auth.resetPasswordForEmail(emailC.text.trim());
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;

    final codeC = TextEditingController();
    final passC = TextEditingController();
    final ok2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password - step 2'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Type the 6-digit code from the email and your new password.'),
            const SizedBox(height: 12),
            TextField(
              controller: codeC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Code', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passC,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'New password', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Change password')),
        ],
      ),
    );
    if (ok2 != true) return;
    setState(() => _busy = true);
    try {
      await _sb.auth.verifyOTP(
        email: emailC.text.trim(),
        token: codeC.text.trim(),
        type: OtpType.recovery,
      );
      await _sb.auth.updateUser(UserAttributes(password: passC.text));
      await _sb.auth.signOut();
      _toast('Password changed - log in with the new one');
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_mode ? 'Sign up' : 'Log in')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_mode) ...[
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                  labelText: 'Username', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
                labelText: 'Email', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Password', border: OutlineInputBorder()),
          ),
          if (_err != null) ...[
            const SizedBox(height: 12),
            Text(_err!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _go,
            child: Text(_busy ? '...' : (_mode ? 'Create account' : 'Log in')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _forgotFlow,
            child: const Text('Forgot password?'),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _mode = !_mode),
            child: Text(_mode
                ? 'Have an account? Log in'
                : 'No account? Sign up (pick a username, get 500 coins)'),
          ),
        ],
      ),
    );
  }
}
