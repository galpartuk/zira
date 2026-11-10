import 'package:flutter/material.dart';

import '../../engine/models.dart';
import '../../engine/pairing.dart';
import '../../engine/standings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class StandingsTab extends StatelessWidget {
  final Tournament t;
  const StandingsTab({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    if (t.players.isEmpty) {
      return const EmptyState(icon: Icons.leaderboard_outlined, title: 'אין דירוג עדיין', body: 'הוסיפו שחקנים והתחילו סיבוב.');
    }
    final list = computeStandings(t);
    final cut = t.topRoundsList.isEmpty ? effectiveTopCut(t) : 0;
    final qualifiers = cut > 0 ? topCutQualifiers(t).toSet() : <String>{};
    final rounds = t.swissRoundsList.length;

    const head = TextStyle(fontSize: 12, color: Z.muted, fontWeight: FontWeight.w700);
    const num = TextStyle(fontSize: 14, fontFeatures: Z.tabular, fontWeight: FontWeight.w600);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              rounds == 0 ? 'לפני סיבוב 1' : 'אחרי ${list.isEmpty ? 0 : rounds} סיבובים${t.swissDone ? ' (סופי)' : ''}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'העתקת דירוג',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => copyText(context, _text(list), 'הדירוג'),
          ),
        ]),
        if (cut > 0 && rounds > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('מסומנים בצהוב: עולים לטופ $cut אם הטורניר היה נגמר עכשיו',
                style: const TextStyle(fontSize: 12.5, color: Z.muted)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: const Row(children: [
            SizedBox(width: 30, child: Text('#', style: head)),
            Expanded(child: Text('שחקן', style: head)),
            SizedBox(width: 38, child: Text('נק׳', style: head, textAlign: TextAlign.center)),
            SizedBox(width: 52, child: Text('מאזן', style: head, textAlign: TextAlign.center)),
            SizedBox(width: 56, child: Text('OMW', style: head, textAlign: TextAlign.center)),
            SizedBox(width: 56, child: Text('OOMW', style: head, textAlign: TextAlign.center)),
          ]),
        ),
        for (final s in list)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            decoration: BoxDecoration(
              color: Z.surface,
              borderRadius: BorderRadius.circular(10),
              border: qualifiers.contains(s.player.id)
                  ? const BorderDirectional(start: BorderSide(color: Z.gold, width: 3))
                  : null,
            ),
            child: Row(children: [
              SizedBox(
                  width: 30,
                  child: Text('${s.rank}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFeatures: Z.tabular,
                          color: s.rank <= 3 ? Z.gold : Z.muted))),
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(
                      s.player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700, color: s.player.dropped ? Z.muted : Z.text),
                    ),
                  ),
                  if (s.player.dropped) ...[const SizedBox(width: 6), const Pill('פרש', color: Z.danger)],
                ]),
              ),
              SizedBox(
                  width: 38,
                  child: Text('${s.points}',
                      textAlign: TextAlign.center,
                      style: num.copyWith(fontWeight: FontWeight.w800, fontSize: 15.5))),
              SizedBox(width: 52, child: Text(s.record, textAlign: TextAlign.center, style: num)),
              SizedBox(
                  width: 56,
                  child: Text(s.opponents.isEmpty ? '–' : pct(s.omw),
                      textAlign: TextAlign.center, style: num.copyWith(fontSize: 12.5, color: Z.muted))),
              SizedBox(
                  width: 56,
                  child: Text(s.opponents.isEmpty ? '–' : pct(s.oomw),
                      textAlign: TextAlign.center, style: num.copyWith(fontSize: 12.5, color: Z.muted))),
            ]),
          ),
        const SizedBox(height: 12),
        const Text(
          'סדר הדירוג: נקודות ← OMW% ← OOMW% ← הגרלה קבועה. נצחון 3 · תיקו 1 · הפסד 0 · BYE = נצחון.',
          style: TextStyle(color: Z.muted, fontSize: 12.5, height: 1.5),
        ),
      ],
    );
  }

  String _text(List<Standing> list) {
    final b = StringBuffer('${t.name} — דירוג\n');
    for (final s in list) {
      b.writeln('${s.rank}. ${s.player.name} — ${s.points} נק׳ (${s.record})${s.player.dropped ? ' [פרש]' : ''}');
    }
    return b.toString();
  }
}
