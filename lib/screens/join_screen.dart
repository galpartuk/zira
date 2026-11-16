import 'package:flutter/material.dart';

import '../l10n.dart';
import '../state/player_session.dart';
import '../state/session.dart';
import '../theme.dart';
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
    setState(() => _busy = true);
    await joinAndOpen(context, _code.text, replace: true);
    if (mounted) setState(() => _busy = false);
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

/// Joins with [code] and opens the tournament; explains any refusal.
Future<void> joinAndOpen(BuildContext context, String code, {bool replace = false}) async {
  final auth = authOf(context, listen: false)!;
  final db = dbOf(context)!;
  try {
    final (res, tid) = await joinWithCode(db, uid: auth.user!.uid, name: auth.displayName, code: code);
    if (!context.mounted) return;
    switch (res) {
      case JoinResult.ok || JoinResult.requested:
        final route = MaterialPageRoute(builder: (_) => PlayerTournamentScreen(tid: tid!));
        replace ? Navigator.pushReplacement(context, route) : Navigator.push(context, route);
      case JoinResult.badCode:
        toast(context, S.t.badCode);
      case JoinResult.closed:
        toast(context, S.t.joinClosed);
      case JoinResult.removed:
        toast(context, S.t.joinRemoved);
    }
  } catch (_) {
    if (context.mounted) toast(context, S.t.authError('network-request-failed'));
  }
}

/// The big "join a tournament" card on top of the tournaments list.
class JoinCard extends StatefulWidget {
  const JoinCard({super.key});

  @override
  State<JoinCard> createState() => _JoinCardState();
}

class _JoinCardState extends State<JoinCard> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_code.text.trim().length != 6) {
      toast(context, S.t.codeHint);
      return;
    }
    setState(() => _busy = true);
    FocusScope.of(context).unfocus();
    await joinAndOpen(context, _code.text);
    if (mounted) {
      _code.clear();
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Z.gold.withValues(alpha: .6), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.login_rounded, color: Z.gold),
            const SizedBox(width: 10),
            Text(S.t.joinTournament, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text(S.t.joinTournamentBody, style: const TextStyle(color: Z.muted, fontSize: 13.5)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _code,
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4),
                decoration: const InputDecoration(hintText: 'ABC234', counterText: ''),
                onSubmitted: (_) => _join(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: FilledButton(onPressed: _busy ? null : _join, child: Text(S.t.join)),
            ),
          ]),
        ]),
      ),
    );
  }
}
