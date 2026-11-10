import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart';
import '../../engine/standings.dart';
import '../../l10n.dart';
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

  String roundLabel(Round r) => S.t.roundLabel(r);

  @override
  Widget build(BuildContext context) {
    if (!t.started) {
      return EmptyState(
        icon: Icons.shuffle_rounded,
        title: S.t.notStarted,
        body: S.t.notStartedBody,
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
              round.complete ? Pill(S.t.complete, color: Z.win) : Pill(S.t.openMatches(round.pending), color: Z.gold),
              const Spacer(),
              IconButton(
                tooltip: S.t.copyPairings,
                icon: const Icon(Icons.copy_rounded),
                onPressed: () => copyText(context, _pairingsText(round, standings), S.t.pairingsWhat),
              ),
              if (isCurrent && !round.anyResult && !t.finished)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    final app = context.read<AppState>();
                    if (v == 'repair') {
                      app.repair(t);
                      if (context.mounted) toast(context, S.t.repaired);
                    } else if (v == 'undo') {
                      final ok = await confirm(context, S.t.undoTitle(roundLabel(round)), S.t.undoBody);
                      if (ok) app.undoRound(t);
                    }
                  },
                  itemBuilder: (_) => [
                    if (round.stage == Stage.swiss && t.format == TFormat.swiss)
                      PopupMenuItem(value: 'repair', child: Text(S.t.repair)),
                    PopupMenuItem(value: 'undo', child: Text(S.t.undoRound)),
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
                // Drops apply from the next pairing, so only offer them while
                // more Swiss rounds can still follow.
                onDrop: (isCurrent && !t.finished && round.stage == Stage.swiss) ? () => _drop(m) : null,
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

  Future<void> _drop(Match m) async {
    final ids = [m.p1, if (m.p2 != null) m.p2!];
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(S.t.dropTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(S.t.dropBody, style: const TextStyle(color: Z.muted, fontSize: 13)),
              const SizedBox(height: 10),
              for (final id in ids)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.nameOf(id), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(t.player(id)!.dropped ? S.t.droppedNotPaired : S.t.stillPlaying),
                  value: t.player(id)!.dropped,
                  activeThumbColor: Z.ink,
                  activeTrackColor: Z.danger,
                  onChanged: (v) {
                    t.player(id)!.dropped = v;
                    context.read<AppState>().changed();
                    setSheet(() {});
                  },
                ),
            ]),
          ),
        ),
      ),
    );
  }

  String _pairingsText(Round round, Map<String, Standing> st) {
    final b = StringBuffer('${t.name} — ${roundLabel(round)}\n');
    for (final m in round.matches) {
      if (m.isBye) {
        b.writeln('BYE: ${t.nameOf(m.p1)}');
      } else {
        final tag = m.thirdPlace ? S.t.thirdPlaceTag : S.t.table(m.table);
        b.writeln('$tag: ${t.nameOf(m.p1)} (${st[m.p1]?.points ?? 0}) ${S.t.vs} ${t.nameOf(m.p2)} (${st[m.p2]?.points ?? 0})'
            '${m.result != null ? '  ✓ ${S.t.scoreText(m.result!, bestOf: t.bestOfFor(round.stage))}' : ''}');
      }
    }
    return b.toString();
  }
}

/// Score with each number on its own player's side (a Row follows the text
/// direction, so player 1 — on the start side: left in English, right in
/// Hebrew — gets the first number).
class _Score extends StatelessWidget {
  final MatchResult res;
  final int bo;
  const _Score({required this.res, required this.bo});

  @override
  Widget build(BuildContext context) {
    if (res.outcome == Outcome.doubleLoss) {
      return Text(S.t.doubleLossShort,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, height: 1.15, color: Z.danger));
    }
    if (res.outcome == Outcome.draw && bo == 1) {
      return Text(S.t.draw, style: const TextStyle(fontWeight: FontWeight.w800, color: Z.muted));
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
  final VoidCallback? onDrop;

  const _MatchCard(
      {required this.t, required this.m, required this.round, required this.standings, this.onTap, this.onDrop});

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
              Text('${S.t.pts(st.points)} · ${st.record}',
                  style: const TextStyle(fontSize: 12, color: Z.muted, fontFeatures: Z.tabular)),
            if (t.player(id)?.dropped ?? false)
              Padding(padding: const EdgeInsets.only(top: 3), child: Pill(S.t.dropped, color: Z.danger)),
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
            padding: EdgeInsetsDirectional.fromSTEB(12, 12, onDrop != null ? 4 : 12, 12),
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
                Text(S.t.autoWin, style: const TextStyle(color: Z.muted, fontSize: 13)),
              ] else ...[
                side(m.p1, Z.blue, TextAlign.start),
                SizedBox(
                  width: 74,
                  child: Center(
                    child: res == null
                        ? Text(S.t.vs, style: const TextStyle(color: Z.muted, fontWeight: FontWeight.w600))
                        : _Score(res: res, bo: bo),
                  ),
                ),
                side(m.p2, Z.coral, TextAlign.end),
              ],
              if (onDrop != null)
                SizedBox(
                  width: 34,
                  child: IconButton(
                    tooltip: S.t.drop,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    color: Z.muted,
                    onPressed: onDrop,
                    icon: const Icon(Icons.person_remove_outlined),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
