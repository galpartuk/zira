import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart';
import '../../engine/pairing.dart';
import '../../engine/standings.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/result_sheet.dart';
import '../../widgets/round_timer.dart';

class RoundsTab extends StatefulWidget {
  final Tournament t;
  const RoundsTab({super.key, required this.t});

  @override
  State<RoundsTab> createState() => _RoundsTabState();
}

class _RoundsTabState extends State<RoundsTab> {
  int? _selected; // index into t.rounds; null = latest
  int _lastCount = 0;

  Tournament get t => widget.t;

  String roundLabel(Round r) => r.stage == Stage.swiss ? 'סיבוב ${r.number}' : topRoundName(r);

  @override
  Widget build(BuildContext context) {
    if (!t.started) {
      return const EmptyState(
        icon: Icons.shuffle_rounded,
        title: 'הטורניר עוד לא התחיל',
        body: 'כשכל השחקנים רשומים, לחצו על "התחלת הטורניר" למטה והזיווג של סיבוב 1 יופיע כאן.',
      );
    }
    // Jump to the newest round whenever one is added.
    if (t.rounds.length != _lastCount) {
      _lastCount = t.rounds.length;
      _selected = null;
    }
    final idx = (_selected ?? t.rounds.length - 1).clamp(0, t.rounds.length - 1);
    final round = t.rounds[idx];
    final isCurrent = idx == t.rounds.length - 1;
    // Points as they stood when this round was paired, not live totals.
    final standings = {for (final s in computeStandings(t, beforeRound: idx)) s.player.id: s};
    final editable = !t.finished && (round.stage == Stage.top ? isCurrent : t.topRoundsList.isEmpty);

    final matches = [...round.matches]..sort((a, b) {
        if (a.isBye != b.isBye) return a.isBye ? 1 : -1;
        if (a.thirdPlace != b.thirdPlace) return a.thirdPlace ? 1 : -1;
        return a.table.compareTo(b.table);
      });

    return Column(children: [
      SizedBox(
        height: 54,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          itemCount: t.rounds.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (c, i) {
            final r = t.rounds[i];
            final sel = i == idx;
            return ChoiceChip(
              label: Text(roundLabel(r)),
              selected: sel,
              showCheckmark: false,
              selectedColor: Z.gold,
              labelStyle: TextStyle(color: sel ? Z.ink : Z.text, fontWeight: FontWeight.w700),
              avatar: r.complete ? Icon(Icons.check_circle, size: 16, color: sel ? Z.ink : Z.win) : null,
              onSelected: (_) => setState(() => _selected = i),
            );
          },
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
          children: [
            if (isCurrent && !t.finished) ...[RoundTimer(t: t), const SizedBox(height: 12)],
            Row(children: [
              Text(roundLabel(round), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              round.complete ? const Pill('הושלם', color: Z.win) : Pill('${round.pending} פתוחים', color: Z.gold),
              const Spacer(),
              IconButton(
                tooltip: 'העתקת זיווגים',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () => copyText(context, _pairingsText(round, standings), 'הזיווג'),
              ),
              if (isCurrent && !round.anyResult && !t.finished)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    final app = context.read<AppState>();
                    if (v == 'repair') {
                      app.repair(t);
                      if (context.mounted) toast(context, 'הסיבוב זווג מחדש');
                    } else if (v == 'undo') {
                      final ok = await confirm(context, 'לבטל את ${roundLabel(round)}?', 'הזיווג יימחק ותוכלו ליצור אותו שוב.');
                      if (ok) app.undoRound(t);
                    }
                  },
                  itemBuilder: (_) => [
                    if (round.stage == Stage.swiss && t.format == TFormat.swiss)
                      const PopupMenuItem(value: 'repair', child: Text('זיווג מחדש')),
                    const PopupMenuItem(value: 'undo', child: Text('ביטול הסיבוב')),
                  ],
                ),
            ]),
            const SizedBox(height: 6),
            for (final m in matches)
              _MatchCard(
                t: t,
                m: m,
                round: round,
                standings: standings,
                onTap: (!editable || m.isBye) ? null : () => _report(round, m),
              ),
          ],
        ),
      ),
    ]);
  }

  Future<void> _report(Round round, Match m) async {
    final r = await showModalBottomSheet<MatchResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ResultSheet(
        p1: t.nameOf(m.p1),
        p2: t.nameOf(m.p2),
        bestOf: t.bestOfFor(round.stage),
        elimination: round.stage == Stage.top,
        current: m.result,
      ),
    );
    if (r == null || !mounted) return;
    context.read<AppState>().setResult(t, m, identical(r, ResultSheet.clear) ? null : r);
  }

  String _pairingsText(Round round, Map<String, Standing> st) {
    final b = StringBuffer('${t.name} — ${roundLabel(round)}\n');
    for (final m in round.matches) {
      if (m.isBye) {
        b.writeln('BYE: ${t.nameOf(m.p1)}');
      } else {
        final tag = m.thirdPlace ? 'מקום 3' : 'שולחן ${m.table}';
        b.writeln('$tag: ${t.nameOf(m.p1)} (${st[m.p1]?.points ?? 0}) נגד ${t.nameOf(m.p2)} (${st[m.p2]?.points ?? 0})'
            '${m.result != null ? '  ✓ ${m.result!.scoreText(bestOf: t.bestOfFor(round.stage))}' : ''}');
      }
    }
    return b.toString();
  }
}

/// Score with each number on its own player's side (a Row follows the text
/// direction, so player 1 — on the right in Hebrew — gets the first number).
class _Score extends StatelessWidget {
  final MatchResult res;
  final int bo;
  const _Score({required this.res, required this.bo});

  @override
  Widget build(BuildContext context) {
    if (res.outcome == Outcome.doubleLoss) {
      return const Text('הפסד\nכפול',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, height: 1.15, color: Z.danger));
    }
    if (res.outcome == Outcome.draw && bo == 1) {
      return const Text('תיקו', style: TextStyle(fontWeight: FontWeight.w800, color: Z.muted));
    }
    final a = bo > 1 ? res.g1 : (res.outcome == Outcome.p1 ? 1 : 0);
    final b = bo > 1 ? res.g2 : (res.outcome == Outcome.p2 ? 1 : 0);
    TextStyle st(bool win) => TextStyle(
        fontSize: 20, fontWeight: FontWeight.w800, color: win ? Z.gold : Z.muted, fontFeatures: Z.tabular);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('$a', style: st(res.outcome == Outcome.p1)),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text(':', style: TextStyle(color: Z.muted, fontWeight: FontWeight.w800)),
      ),
      Text('$b', style: st(res.outcome == Outcome.p2)),
    ]);
  }
}

class _MatchCard extends StatelessWidget {
  final Tournament t;
  final Match m;
  final Round round;
  final Map<String, Standing> standings;
  final VoidCallback? onTap;

  const _MatchCard({required this.t, required this.m, required this.round, required this.standings, this.onTap});

  @override
  Widget build(BuildContext context) {
    final res = m.result;
    final w = m.winner;
    final bo = t.bestOfFor(round.stage);

    Widget side(String? id, Color color, TextAlign align) {
      final isWinner = w != null && w == id;
      final isLoser = res != null && !m.isBye && w != id;
      final st = id == null ? null : standings[id];
      return Expanded(
        child: Column(
          crossAxisAlignment: align == TextAlign.start ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(
              t.nameOf(id),
              textAlign: align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: isWinner ? FontWeight.w800 : FontWeight.w600,
                color: id == null ? Z.muted : (isLoser ? Z.muted : (isWinner ? color : Z.text)),
              ),
            ),
            if (st != null && round.stage == Stage.swiss)
              Text('${st.points} נק׳ · ${st.record}',
                  style: const TextStyle(fontSize: 12, color: Z.muted, fontFeatures: Z.tabular)),
          ],
        ),
      );
    }

    final label = m.isBye ? 'BYE' : (m.thirdPlace ? '3' : '${m.table}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Z.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: m.done ? Z.win.withValues(alpha: .14) : Z.raised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: m.isBye ? 11 : 16,
                        color: m.done ? Z.win : Z.text,
                        fontFeatures: Z.tabular)),
              ),
              const SizedBox(width: 12),
              if (m.isBye) ...[
                side(m.p1, Z.blue, TextAlign.start),
                const Text('נצחון אוטומטי', style: TextStyle(color: Z.muted, fontSize: 13)),
              ] else ...[
                side(m.p1, Z.blue, TextAlign.start),
                SizedBox(
                  width: 74,
                  child: Center(
                    child: res == null
                        ? const Text('נגד', style: TextStyle(color: Z.muted, fontWeight: FontWeight.w600))
                        : _Score(res: res, bo: bo),
                  ),
                ),
                side(m.p2, Z.coral, TextAlign.end),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
