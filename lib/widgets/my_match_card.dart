import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../engine/online.dart';
import '../l10n.dart';
import '../theme.dart';
import 'result_sheet.dart';

/// The signed-in player's current match: table, opponent, report / confirm /
/// dispute. Used by players and by a host who also plays.
class MyMatchCard extends StatelessWidget {
  final Tournament t;
  final String uid;
  final ClaimState state;
  final Future<void> Function(MatchResult) onReport;

  const MyMatchCard({super.key, required this.t, required this.uid, required this.state, required this.onReport});

  @override
  Widget build(BuildContext context) {
    final me = t.players.where((p) => p.uid == uid).firstOrNull;
    final r = t.currentRound;
    final m = (me == null || r == null) ? null : r.matches.where((m) => m.involves(me.id)).firstOrNull;
    if (me == null) return _shell(Text(S.t.notInEventYet));
    if (me.dropped) return _shell(Text(S.t.youDropped));
    if (m == null || r == null) return _shell(Text(S.t.waitingNextRound));
    final oppId = m.p1 == me.id ? m.p2 : m.p1;
    final bo = t.bestOfFor(r.stage);

    Future<void> openSheet() async {
      final res = await showModalBottomSheet<MatchResult>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ResultSheet(
            p1: t.nameOf(m.p1), p2: t.nameOf(m.p2), bestOf: bo, elimination: r.stage == Stage.top, current: m.result),
      );
      if (res != null && !identical(res, ResultSheet.clear)) await onReport(res);
    }

    final Widget action = switch (state) {
      _ when m.isBye => Text(S.t.autoWin),
      _ when m.result != null => Text(S.t.scoreText(m.result!, bestOf: bo)),
      Pending(by: final c) when c.uid == uid => Text(S.t.youReported, style: const TextStyle(color: Z.muted)),
      Pending(by: final c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(S.t.opponentReported(t.nameOf(oppId), S.t.scoreText(c.result, bestOf: bo)),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: FilledButton(onPressed: () => onReport(c.result), child: Text(S.t.confirmResult))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: openSheet, child: Text(S.t.disputeResult))),
          ]),
        ]),
      Disputed() => Text(S.t.disputeSent, style: const TextStyle(color: Z.danger)),
      _ => FilledButton.icon(onPressed: openSheet, icon: const Icon(Icons.edit_note), label: Text(S.t.reportResult)),
    };

    return _shell(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${S.t.roundLabel(r)} · ${m.isBye ? 'BYE' : S.t.table(m.table)}', style: const TextStyle(color: Z.muted)),
      const SizedBox(height: 4),
      Text(m.isBye ? 'BYE' : '${S.t.vs} ${t.nameOf(oppId)}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      action,
    ]));
  }

  Widget _shell(Widget child) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(S.t.myMatch, style: const TextStyle(fontSize: 12.5, color: Z.gold, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            child,
          ]),
        ),
      );
}
