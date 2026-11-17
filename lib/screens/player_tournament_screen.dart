import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/models.dart';
import '../engine/online.dart';
import '../engine/pairing.dart';
import '../engine/prizes.dart';
import '../l10n.dart';
import '../state/player_session.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/lobby_card.dart';
import '../widgets/my_match_card.dart';
import '../widgets/round_timer.dart';
import '../widgets/time_notice.dart';
import 'history_screen.dart';
import 'tabs/bracket_tab.dart';
import 'tabs/standings_tab.dart';

/// A tournament someone else hosts, as the signed-in player sees it (live).
class PlayerTournamentScreen extends StatelessWidget {
  final String tid;
  const PlayerTournamentScreen({super.key, required this.tid});

  @override
  Widget build(BuildContext context) {
    final db = dbOf(context)!;
    final uid = authOf(context, listen: false)!.user!.uid;
    return ChangeNotifierProvider(
      create: (_) => PlayerSession(db, tid, uid),
      child: const _PlayerView(),
    );
  }
}

class _PlayerView extends StatelessWidget {
  const _PlayerView();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PlayerSession>();
    final t = s.t;
    if (s.gone) {
      return Scaffold(
          appBar: AppBar(),
          body: EmptyState(icon: Icons.event_busy, title: S.t.tournamentGone, body: ''));
    }
    if (t == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final r = t.currentRound;
    final canDrop = s.me != null && !s.me!.dropped && !t.finished;
    final tabs = <(String, Widget)>[
      if (t.finished && t.resultsPublished) (S.t.finalResults, _Results(t: t, myId: s.me?.id)),
      (S.t.myMatch, _MyMatchTab(s: s, t: t)),
      (S.t.tabRounds, _Pairings(t: t, myId: s.me?.id)),
      (S.t.tabStandings, t.started ? StandingsTab(t: t) : const SizedBox()),
      if (t.topCut > 0) (S.t.tabBracket, BracketTab(t: t, readOnly: true)),
    ];
    return DefaultTabController(
      length: tabs.length,
      initialIndex: 0, // finished + sent: the results tab is first
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (r != null)
              Text(S.t.roundLabel(r), style: const TextStyle(fontSize: 12.5, color: Z.muted)),
          ]),
          actions: [
            if (t.finished && s.me != null)
              IconButton(
                tooltip: S.t.myRecord,
                icon: const Icon(Icons.style_outlined),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => TournamentHistoryScreen(tid: s.tid))),
              ),
            if (canDrop)
              PopupMenuButton<String>(
                onSelected: (_) async {
                  final ok = await confirm(context, S.t.dropFromEvent, S.t.dropFromEventBody, ok: S.t.drop, danger: true);
                  if (!ok) return;
                  try {
                    await s.drop();
                  } catch (_) {
                    if (context.mounted) toast(context, S.t.authError('network-request-failed'));
                  }
                },
                itemBuilder: (_) => [PopupMenuItem(value: 'drop', child: Text(S.t.dropFromEvent))],
              ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(t.finished ? 82 : 46),
            child: Column(children: [
              if (t.finished)
                Container(
                  width: double.infinity,
                  color: Z.win.withValues(alpha: .15),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Text(t.resultsPublished ? S.t.tournamentOverFinal : S.t.waitingFinalResults,
                      style: const TextStyle(color: Z.win, fontWeight: FontWeight.w800)),
                ),
              TabBar(isScrollable: true, tabs: [for (final x in tabs) Tab(text: x.$1)]),
            ]),
          ),
        ),
        body: ClaimPrompt(
          t: t,
          uid: s.uid,
          state: s.myState,
          onReport: s.report,
          child: Column(children: [
            TimeNotice(t: t, uid: s.uid, state: s.myState),
            Expanded(child: TabBarView(children: [for (final x in tabs) x.$2])),
          ]),
        ),
      ),
    );
  }
}

class _MyMatchTab extends StatelessWidget {
  final PlayerSession s;
  final Tournament t;
  const _MyMatchTab({required this.s, required this.t});

  @override
  Widget build(BuildContext context) {
    final r = t.currentRound;
    final me = s.me;
    // Nothing to do yet: show that the screen is alive and who is in so far.
    Widget? lobby;
    if (me == null && s.myStatus == EntryStatus.requested) {
      lobby = LobbyCard(
          t: t,
          uid: s.uid,
          icon: Icons.hourglass_top_rounded,
          color: Z.gold,
          title: S.t.requestSentTitle,
          subtitle: S.t.requestSentBody);
    } else if (me == null && !t.finished && t.acceptsNewPlayers && s.myStatus == EntryStatus.joined) {
      lobby = LobbyCard(
          t: t,
          uid: s.uid,
          icon: Icons.sync_rounded,
          color: Z.blue,
          title: S.t.joiningTitle,
          subtitle: S.t.notInEventYet);
    } else if (me != null && !me.dropped && !t.finished && MyMatchInfo.of(t, s.uid) == null) {
      lobby = LobbyCard(
          t: t,
          uid: s.uid,
          icon: Icons.check_rounded,
          color: Z.win,
          title: S.t.youAreIn,
          subtitle: t.underway ? S.t.waitingNextRound : S.t.waitingHostStart,
          showPlayers: !t.underway);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (r != null && !t.finished) ...[RoundTimer(t: t, readOnly: true), const SizedBox(height: 12)],
      lobby ?? MyMatchCard(t: t, uid: s.uid, state: s.myState, onReport: s.report),
    ]);
  }
}

class _Pairings extends StatelessWidget {
  final Tournament t;
  final String? myId;
  const _Pairings({required this.t, required this.myId});

  @override
  Widget build(BuildContext context) {
    final r = t.currentRound;
    if (r == null) return EmptyState(icon: Icons.shuffle_rounded, title: S.t.waitingNextRound, body: '');
    final matches = [...r.matches]..sort((a, b) => a.isBye == b.isBye ? a.table.compareTo(b.table) : (a.isBye ? 1 : -1));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      for (final m in matches)
        Card(
          color: myId != null && m.involves(myId!) ? Z.gold.withValues(alpha: .18) : null,
          child: ListTile(
            leading: Text(m.isBye ? 'BYE' : '${m.table}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, fontFeatures: Z.tabular)),
            title: Text(m.isBye ? t.nameOf(m.p1) : '${t.nameOf(m.p1)}  ${S.t.vs}  ${t.nameOf(m.p2)}'),
            trailing: m.result == null ? null : Text(S.t.scoreText(m.result!, bestOf: t.bestOfFor(r.stage))),
          ),
        ),
    ]);
  }
}

/// Final placements and prizes, once the host sent them.
class _Results extends StatelessWidget {
  final Tournament t;
  final String? myId;
  const _Results({required this.t, required this.myId});

  @override
  Widget build(BuildContext context) {
    final placements = finalPlacements(t);
    final prizes = computePrizes(t.prizes, t.players.length, placements: placements);
    final prizeOf = {
      for (final l in prizes.lines)
        if (l.playerId != null && l.amount > 0) l.playerId!: S.t.amount(t.prizes.unit, l.amount),
    };
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      for (final p in placements)
        Card(
          color: p.playerId == myId ? Z.gold.withValues(alpha: .18) : null,
          child: ListTile(
            leading: SizedBox(
              width: 44,
              child: Text(p.groupFrom == p.groupTo ? '${p.groupFrom}' : '${p.groupFrom}-${p.groupTo}',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: p.place == 1 ? Z.gold : Z.text,
                      fontFeatures: Z.tabular)),
            ),
            title: Text(t.nameOf(p.playerId), style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: prizeOf[p.playerId] == null
                ? null
                : Text(prizeOf[p.playerId]!, style: const TextStyle(color: Z.win, fontWeight: FontWeight.w800)),
          ),
        ),
    ]);
  }
}
