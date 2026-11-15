import 'package:flutter/material.dart';

import '../l10n.dart';
import '../state/player_session.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import 'player_tournament_screen.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final auth = authOf(context, listen: false)!;
    final db = dbOf(context)!;
    setState(() => _busy = true);
    try {
      final (res, tid) = await joinWithCode(db, uid: auth.user!.uid, name: auth.displayName, code: _code.text);
      if (!mounted) return;
      switch (res) {
        case JoinResult.ok || JoinResult.requested:
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PlayerTournamentScreen(tid: tid!)));
        case JoinResult.badCode:
          toast(context, S.t.badCode);
        case JoinResult.closed:
          toast(context, S.t.joinClosed);
        case JoinResult.removed:
          toast(context, S.t.joinRemoved);
      }
    } catch (_) {
      if (mounted) toast(context, S.t.authError('network-request-failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t.joinWithCode)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
          controller: _code,
          autofocus: true,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 6),
          decoration: InputDecoration(hintText: 'ABC234', helperText: S.t.codeHint),
          onSubmitted: (_) => _join(),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _join, child: Text(S.t.join)),
      ]),
    );
  }
}
