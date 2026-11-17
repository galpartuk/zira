import 'package:flutter/material.dart';

import '../cloud/history_repo.dart';
import '../engine/models.dart';
import '../engine/stats.dart';
import '../l10n.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// How each of my decks did, and how they did against each opponent deck.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String? _deck; // null = all my decks

  @override
  Widget build(BuildContext context) {
    final auth = authOf(context);
    final db = dbOf(context);
    final uid = auth?.user?.uid;
    if (db == null || uid == null) {
      return Scaffold(
        appBar: AppBar(title: Text(S.t.stats)),
        body: EmptyState(icon: Icons.lock_outline, title: S.t.signIn, body: S.t.signInNeeded),
      );
    }
    final repo = HistoryRepo(db, uid);
    return Scaffold(
      appBar: AppBar(title: Text(S.t.stats)),
      body: StreamBuilder<List<Tournament>>(
        stream: repo.playedFinished(),
        builder: (context, tsnap) => StreamBuilder<Map<String, HistoryEntry>>(
          stream: repo.watch(),
          builder: (context, hsnap) {
            if (!tsnap.hasData || !hsnap.hasData) return Center(child: CircularProgressIndicator());
            final played = HistoryRepo.join(tsnap.data!, hsnap.data!, uid);
            if (played.isEmpty) {
              return EmptyState(icon: Icons.insights_outlined, title: S.t.noStatsYet, body: S.t.noStatsBody);
            }
            final s = computeDeckStats(played);
            String name(String key) => key.isEmpty ? S.t.unmarked : (s.label[key] ?? key);
            final decks = s.byDeck.keys.toList()..sort((a, b) => s.byDeck[b]!.matches.compareTo(s.byDeck[a]!.matches));
            final deck = (_deck != null && s.matchups.containsKey(_deck)) ? _deck : null;
            final mu = deck == null ? s.allMatchups() : s.matchups[deck]!;
            final opps = mu.keys.toList()..sort((a, b) => mu[b]!.matches.compareTo(mu[a]!.matches));
            return ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                SectionTitle(S.t.myDecks),
                _Table(
                  firstColumn: S.t.deck,
                  rows: [for (final k in decks) (name(k), s.byDeck[k]!, s.byDeck[k]!.tournaments.length)],
                  showTournaments: true,
                ),
                SizedBox(height: 24),
                SectionTitle(S.t.matchups),
                DropdownButton<String?>(
                  isExpanded: true,
                  value: deck,
                  onChanged: (v) => setState(() => _deck = v),
                  items: [
                    DropdownMenuItem(value: null, child: Text(S.t.allMyDecks)),
                    for (final k in decks) DropdownMenuItem(value: k, child: Text(name(k))),
                  ],
                ),
                SizedBox(height: 8),
                _Table(firstColumn: S.t.opponentDeck, rows: [for (final k in opps) (name(k), mu[k]!, 0)]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  final String firstColumn;
  final List<(String, Record, int)> rows;
  final bool showTournaments;
  const _Table({required this.firstColumn, required this.rows, this.showTournaments = false});

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(fontSize: 12, color: Z.muted, fontWeight: FontWeight.w600);
    const num = TextStyle(fontFeatures: Z.tabular, fontWeight: FontWeight.w600);
    Widget cell(String s, {TextStyle style = num, double w = 56}) => SizedBox(
      width: w,
      child: Text(s, textAlign: TextAlign.center, style: style),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(firstColumn, style: head)),
                if (showTournaments) cell(S.t.tournamentsShort, style: head, w: 44),
                cell(S.t.wld, style: head, w: 74),
                cell(S.t.winRate, style: head),
              ],
            ),
            const Divider(height: 16),
            for (final (name, r, tn) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (showTournaments) cell('$tn', w: 44),
                    cell('${r.wins}-${r.losses}-${r.draws}', w: 74),
                    cell(
                      '${(r.winRate * 100).round()}%',
                      style: num.copyWith(color: r.winRate >= .5 ? Z.win : Z.coral, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
