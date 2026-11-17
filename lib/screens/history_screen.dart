import 'package:flutter/material.dart';

import '../cloud/history_repo.dart';
import '../engine/models.dart';
import '../engine/stats.dart';
import '../l10n.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/deck_field.dart';
import '../widgets/my_match_card.dart';
import 'player_tournament_screen.dart';

/// My record of one finished tournament: the deck I played and, per round,
/// the deck my opponent played.
class TournamentHistoryScreen extends StatelessWidget {
  final String tid;
  const TournamentHistoryScreen({super.key, required this.tid});

  @override
  Widget build(BuildContext context) {
    final db = dbOf(context)!;
    final uid = authOf(context, listen: false)!.user!.uid;
    final repo = HistoryRepo(db, uid);
    return StreamBuilder(
      stream: db.doc('tournaments/$tid').snapshots(),
      builder: (context, tsnap) {
        final d = tsnap.data?.data();
        if (d == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final t = Tournament.fromJson(Map<String, dynamic>.from(d['data'] as Map));
        return StreamBuilder(
          stream: repo.watch(),
          builder: (context, hsnap) {
            if (!hsnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            final all = hsnap.data!;
            return _HistoryBody(t: t, uid: uid, repo: repo, entry: all[tid], suggestions: HistoryRepo.suggestions(all));
          },
        );
      },
    );
  }
}

class _HistoryBody extends StatelessWidget {
  final Tournament t;
  final String uid;
  final HistoryRepo repo;
  final HistoryEntry? entry;
  final List<String> suggestions;
  const _HistoryBody({
    required this.t,
    required this.uid,
    required this.repo,
    required this.entry,
    required this.suggestions,
  });

  @override
  Widget build(BuildContext context) {
    final me = t.players.where((p) => p.uid == uid).firstOrNull;
    final rounds = [
      for (final r in t.rounds)
        for (final m in r.matches)
          if (me != null && m.involves(me.id)) (r, m),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: S.t.tabStandings,
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerTournamentScreen(tid: t.id))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            S.t.whichDeck,
            style: TextStyle(fontSize: 13, color: Z.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          DeckField(
            initial: entry?.myDeck,
            suggestions: suggestions,
            hint: S.t.myDeckHint,
            onSave: (v) => repo.setMyDeck(t.id, v),
          ),
          const SizedBox(height: 22),
          SectionTitle(S.t.myRounds),
          for (final (r, m) in rounds)
            _RoundRow(t: t, uid: uid, round: r, match: m, repo: repo, entry: entry, suggestions: suggestions),
        ],
      ),
    );
  }
}

class _RoundRow extends StatelessWidget {
  final Tournament t;
  final String uid;
  final Round round;
  final Match match;
  final HistoryRepo repo;
  final HistoryEntry? entry;
  final List<String> suggestions;
  const _RoundRow({
    required this.t,
    required this.uid,
    required this.round,
    required this.match,
    required this.repo,
    required this.entry,
    required this.suggestions,
  });

  @override
  Widget build(BuildContext context) {
    final me = t.players.firstWhere((p) => p.uid == uid);
    final info = MyMatchInfo(me, round, match);
    final o = outcomeFor(match, me.id);
    final color = o == null ? Z.muted : (o > 0 ? Z.win : (o < 0 ? Z.danger : Z.accent));
    final result = match.isBye
        ? S.t.byeAutoWin
        : (match.result == null ? '—' : myResultText(match.result!, info.iAmP1));
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  S.t.roundLabel(round),
                  style: TextStyle(color: Z.muted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    match.isBye ? '' : '${S.t.vs} ${t.nameOf(info.opponentId)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  result,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (!match.isBye) ...[
              const SizedBox(height: 10),
              DeckField(
                dense: true,
                initial: entry?.oppDecks[match.id],
                suggestions: suggestions,
                hint: S.t.oppDeckHint,
                onSave: (v) => repo.setOppDeck(t.id, match.id, v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
