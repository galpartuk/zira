import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../engine/online.dart';
import '../l10n.dart';
import '../theme.dart';
import 'result_sheet.dart';

/// Where the signed-in player stands in the current round: their match, its
/// opponent and table, and the result state. Null pieces mean "nothing to show".
class MyMatchInfo {
  final Player me;
  final Round round;
  final Match match;
  const MyMatchInfo(this.me, this.round, this.match);

  bool get iAmP1 => match.p1 == me.id;
  String? get opponentId => iAmP1 ? match.p2 : match.p1;

  static MyMatchInfo? of(Tournament t, String uid) {
    final me = t.players.where((p) => p.uid == uid).firstOrNull;
    final r = t.currentRound;
    if (me == null || me.dropped || r == null || !r.published) return null;
    final m = r.matches.where((m) => m.involves(me.id)).firstOrNull;
    return m == null ? null : MyMatchInfo(me, r, m);
  }
}

/// "You won 2-1" / "You lost 1-2" / "Draw 1-1", always from the viewer's side.
String myResultText(MatchResult r, bool iAmP1) {
  final mine = iAmP1 ? r.g1 : r.g2;
  final theirs = iAmP1 ? r.g2 : r.g1;
  final won = (r.outcome == Outcome.p1 && iAmP1) || (r.outcome == Outcome.p2 && !iAmP1);
  final lost = (r.outcome == Outcome.p2 && iAmP1) || (r.outcome == Outcome.p1 && !iAmP1);
  if (won) return S.t.youWon(mine, theirs);
  if (lost) return S.t.youLost(mine, theirs);
  return S.t.myDraw(mine, theirs);
}

/// Who put the result in, from [viewerUid]'s point of view (null viewer =
/// neutral, for the host's list). Null when unknown (local events).
String? provenanceText(Tournament t, Match m, {required String? viewerUid}) {
  final by = m.by;
  if (by == null || m.result == null) return null;
  if (by == 'host') return S.t.byHost;
  if (by == 'dispute') return S.t.byDispute;
  final uid = by.substring(2);
  final reporter = t.players.where((p) => p.uid == uid).firstOrNull;
  if (reporter == null) return null;
  final otherId = m.p1 == reporter.id ? m.p2 : m.p1;
  final other = t.player(otherId);
  final you = viewerUid != null;
  if (by.startsWith('g:')) {
    return (you && reporter.uid == viewerUid) ? S.t.byYouVsGuest : S.t.byPlayer(reporter.name);
  }
  if (you && reporter.uid == viewerUid) return S.t.byYouAcceptedBy(other?.name ?? '?');
  if (you && other?.uid == viewerUid) return S.t.byThemAcceptedByYou(reporter.name);
  return S.t.byAccepted(reporter.name, other?.name ?? '?');
}

/// Opens the result sheet for [info]'s match and returns the chosen result.
Future<MatchResult?> pickResult(BuildContext context, Tournament t, MyMatchInfo info) async {
  final r = await showModalBottomSheet<MatchResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ResultSheet(
      p1: t.nameOf(info.match.p1),
      p2: t.nameOf(info.match.p2),
      bestOf: t.bestOfFor(info.round.stage),
      elimination: info.round.stage == Stage.top,
      current: info.match.result,
    ),
  );
  return (r == null || identical(r, ResultSheet.clear)) ? null : r;
}

/// The signed-in player's current match. Used by players and by a host who
/// also plays.
class MyMatchCard extends StatelessWidget {
  final Tournament t;
  final String uid;
  final ClaimState state;
  final Future<void> Function(MatchResult) onReport;

  const MyMatchCard({super.key, required this.t, required this.uid, required this.state, required this.onReport});

  Future<void> _report(BuildContext context, MyMatchInfo info, MatchResult r) async {
    await onReport(r);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(S.t.resultSent(t.nameOf(info.opponentId)))));
  }

  @override
  Widget build(BuildContext context) {
    final me = t.players.where((p) => p.uid == uid).firstOrNull;
    if (me == null) {
      return (t.finished || !t.acceptsNewPlayers)
          ? _Message(icon: Icons.block_rounded, text: S.t.joinClosedLate)
          : _Message(icon: Icons.hourglass_top_rounded, text: S.t.notInEventYet);
    }
    if (me.dropped) return _Message(icon: Icons.logout_rounded, text: S.t.youDropped);
    final info = MyMatchInfo.of(t, uid);
    if (info == null) return _Message(icon: Icons.schedule_rounded, text: S.t.waitingNextRound);

    final m = info.match;
    final opp = t.nameOf(info.opponentId);
    Future<void> pickAndReport() async {
      final r = await pickResult(context, t, info);
      if (r != null && context.mounted) await _report(context, info, r);
    }

    final Widget status = switch (state) {
      _ when m.isBye => _Status(color: Z.win, icon: Icons.check_circle_rounded, title: S.t.byeAutoWin),
      _ when m.result != null => _Status(
          color: Z.win,
          icon: Icons.check_circle_rounded,
          title: myResultText(m.result!, info.iAmP1),
          subtitle: provenanceText(t, m, viewerUid: uid) ?? S.t.resultFinal,
        ),
      Pending(by: final c) when c.uid == uid => _Status(
          color: Z.gold,
          icon: Icons.hourglass_top_rounded,
          title: S.t.waitingFor(opp),
          subtitle: S.t.youReportedScore(myResultText(c.result, info.iAmP1)),
          action: TextButton(onPressed: pickAndReport, child: Text(S.t.change)),
        ),
      Pending(by: final c) => _Status(
          color: Z.blue,
          icon: Icons.notifications_active_rounded,
          title: S.t.opponentReportedTitle(opp),
          subtitle: myResultText(c.result, info.iAmP1),
          buttons: [
            OutlinedButton(onPressed: pickAndReport, child: Text(S.t.disputeResult)),
            FilledButton(onPressed: () => _report(context, info, c.result), child: Text(S.t.confirmResult)),
          ],
        ),
      Disputed() => _Status(
          color: Z.danger,
          icon: Icons.gavel_rounded,
          title: S.t.disputeSent,
          subtitle: S.t.disputeBody,
        ),
      _ => SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: pickAndReport,
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(S.t.reportResult, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(S.t.myMatch.toUpperCase(),
                style: const TextStyle(fontSize: 12, letterSpacing: 1.2, color: Z.gold, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${S.t.roundLabel(info.round)} · ${m.isBye ? 'BYE' : S.t.table(m.table)}',
                style: const TextStyle(fontSize: 13, color: Z.muted, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          if (!m.isBye) ...[
            Text(S.t.vs, style: const TextStyle(fontSize: 13, color: Z.muted)),
            Text(opp,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 16),
          ],
          status,
        ]),
      ),
    );
  }
}

/// A coloured status block: icon, title, optional subtitle and actions.
class _Status extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final List<Widget> buttons;

  const _Status({
    required this.color,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.buttons = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .55)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: color)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: const TextStyle(fontSize: 14, color: Z.text)),
              ],
            ]),
          ),
          ?action,
        ]),
        if (buttons.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: SizedBox(height: 46, child: buttons[i])),
            ],
          ]),
        ],
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          child: Row(children: [
            Icon(icon, color: Z.muted),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600))),
          ]),
        ),
      );
}

/// Pops up a dialog the moment the opponent reports a result for my match,
/// wherever I am in the tournament screen. Wrap the screen body with it.
class ClaimPrompt extends StatefulWidget {
  final Tournament? t;
  final String uid;
  final ClaimState state;
  final Future<void> Function(MatchResult) onReport;
  final Widget child;

  const ClaimPrompt({
    super.key,
    required this.t,
    required this.uid,
    required this.state,
    required this.onReport,
    required this.child,
  });

  @override
  State<ClaimPrompt> createState() => _ClaimPromptState();
}

class _ClaimPromptState extends State<ClaimPrompt> {
  /// Claims already shown, so each report pops up once.
  final _shown = <String>{};
  bool _open = false;

  @override
  void didUpdateWidget(ClaimPrompt old) {
    super.didUpdateWidget(old);
    _maybePrompt();
  }

  @override
  void initState() {
    super.initState();
    _maybePrompt();
  }

  void _maybePrompt() {
    final t = widget.t;
    final s = widget.state;
    if (t == null || s is! Pending || s.by.uid == widget.uid || _open) return;
    final info = MyMatchInfo.of(t, widget.uid);
    if (info == null || info.match.result != null || s.by.matchId != info.match.id) return;
    final key = '${s.by.matchId}|${s.by.result.toJson()}';
    if (!_shown.add(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _show(t, info, s.by));
  }

  Future<void> _show(Tournament t, MyMatchInfo info, Claim c) async {
    if (!mounted) return;
    _open = true;
    final opp = t.nameOf(info.opponentId);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_rounded, color: Z.blue, size: 34),
        title: Text(S.t.opponentReportedTitle(opp), textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${S.t.roundLabel(info.round)} · ${S.t.table(info.match.table)}',
              style: const TextStyle(color: Z.muted)),
          const SizedBox(height: 12),
          Text(myResultText(c.result, info.iAmP1),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(S.t.confirmQuestion, textAlign: TextAlign.center, style: const TextStyle(color: Z.muted)),
        ]),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'later'), child: Text(S.t.later)),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, 'dispute'), child: Text(S.t.disputeResult)),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'confirm'), child: Text(S.t.confirmResult)),
        ],
      ),
    );
    _open = false;
    if (!mounted) return;
    if (choice == 'confirm') {
      await widget.onReport(c.result);
    } else if (choice == 'dispute') {
      final r = await pickResult(context, t, info);
      if (r != null) await widget.onReport(r);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
