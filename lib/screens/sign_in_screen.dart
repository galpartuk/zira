import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cloud/auth_service.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _register = false;
  bool _busy = false;
  AuthService? _auth;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthService?>();
    _auth?.addListener(_signedIn);
  }

  void _signedIn() {
    if (_auth?.user != null && mounted) Navigator.maybePop(context);
  }

  @override
  void dispose() {
    _auth?.removeListener(_signedIn);
    _name.dispose();
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on FirebaseAuthException catch (e) {
      if (mounted && !e.code.contains('cancel')) toast(context, S.t.authError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth!;
    return Scaffold(
      appBar: AppBar(title: Text(S.t.signIn), actions: const [LangButton()]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(S.t.signInNeeded, style: const TextStyle(color: Z.muted)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(auth.signInGoogle),
          icon: const Icon(Icons.login),
          label: Text(S.t.signInGoogle),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),
        if (_register) TextField(controller: _name, decoration: InputDecoration(labelText: S.t.displayNameLabel)),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: S.t.email)),
        TextField(controller: _pw, obscureText: true, decoration: InputDecoration(labelText: S.t.password)),
        const SizedBox(height: 16),
        FilledButton.tonal(
          onPressed: _busy
              ? null
              : () => _run(() => _register
                  ? auth.register(_name.text, _email.text, _pw.text)
                  : auth.signInEmail(_email.text, _pw.text)),
          child: Text(_register ? S.t.register : S.t.signIn),
        ),
        TextButton(
            onPressed: () => setState(() => _register = !_register),
            child: Text(_register ? S.t.haveAccount : S.t.noAccount)),
        if (!_register)
          TextButton(
            onPressed: () => _run(() async {
              await auth.resetPassword(_email.text);
              if (context.mounted) toast(context, S.t.resetSent);
            }),
            child: Text(S.t.forgotPassword),
          ),
      ]),
    );
  }
}
