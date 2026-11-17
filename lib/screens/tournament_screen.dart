import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/models.dart';
import '../engine/pairing.dart';
import '../l10n.dart';
import '../engine/online.dart';
import '../state/app_state.dart';
import '../state/session.dart';
import '../theme.dart';
import '../tools/memory_screen.dart';
import '../widgets/common.dart';
import '../cloud/claims.dart';
import '../widgets/host_strip.dart';
import '../widgets/my_match_card.dart';
import 'tabs/bracket_tab.dart';
import 'tabs/players_tab.dart';
import 'tabs/prizes_tab.dart';
import 'tabs/rounds_tab.dart';
import 'tabs/standings_tab.dart';
import 'tournament_settings_sheet.dart';
import 'history_screen.dart';
import 'tournaments_screen.dart';

class TournamentScreen extends StatefulWidget {
  final String id;
  const TournamentScreen({super.key, required this.id});

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> with TickerProviderStateMixin {
  TabController? _tabs;
  List<String> _keys = [];

  void _ensureTabs(Tournament t) {
    final keys = ['players', 'rounds', 'standings', if (t.topCut > 0) 'bracket', 'prizes'];
    if (_tabs != null && keys.join() == _keys.join()) return;
    final prevKey = _tabs == null ? null : _keys[_tabs!.index];
    _tabs?.dispose();
    var initial = keys.indexOf(prevKey ?? (t.finished ? 'prizes' : (t.started ? 'rounds' : 'players')));
    if (initial < 0) initial = 0;
    _keys = keys;
    _tabs = TabController(length: keys.length, vsync: this, initialIndex: initial);
  }

  void _goTo(String key) {
    final i = _keys.indexOf(key);
    if (i >= 0) _tabs?.animateTo(i);
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sync = hostSyncOf(context);
    final t = app.byId(widget.id);
    if (t == null) return const Scaffold(body: SizedBox());
    _ensureTabs(t);
    final (status, color) = statusOf(t);

    final labels = {
      'players': S.t.tabPlayers,
      'rounds': S.t.tabRounds,
      'standings': S.t.tabStandings,
      'bracket': S.t.tabBracket,
      'prizes': S.t.tabPrizes,
    };

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            Pill(status, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(S.t.active(t.activePlayers.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Z.muted)),
            ),
          ]),
        ]),
        toolbarHeight: 68,
        actions: [
          if (!t.finished)
            IconButton(
              key: const ValueKey('open-memory'),
              tooltip: S.t.memoryGauge,
              icon: const Icon(Icons.linear_scale_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryScreen())),
            ),
          if (t.finished && sync != null && t.players.any((p) => p.uid == sync.uid))
            IconButton(
              tooltip: S.t.myRecord,
              icon: const Icon(Icons.style_outlined),
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => TournamentHistoryScreen(tid: t.id))),
            ),
          IconButton(
            tooltip: S.t.settings,
            icon: const Icon(Icons.tune),
            onPressed: () => showModalBottomSheet(
                context: context, isScrollControlled: true, builder: (_) => TournamentSettingsSheet(t: t)),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [for (final k in _keys) Tab(text: labels[k])],
        ),
      ),
      body: _withHostPrompt(context, t, Column(children: [
        if (sync != null && !t.finished) HostStrip(t: t, sync: sync),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
        for (final k in _keys)
          switch (k) {
            'players' => PlayersTab(t: t),
            'rounds' => RoundsTab(t: t, header: _hostMatch(context, t)),
            'standings' => StandingsTab(t: t),
            'bracket' => BracketTab(t: t),
            _ => PrizesTab(t: t),
          }
          ]),
        ),
      ])),
      bottomNavigationBar: _NextStepBar(t: t, goTo: _goTo),
    );
  }
}

/// A host who also plays gets the same pop-up as players when the opponent reports.
Widget _withHostPrompt(BuildContext context, Tournament t, Widget child) {
  final sync = hostSyncOf(context);
  final uid = authOf(context)?.user?.uid;
  final db = dbOf(context);
  if (sync == null || uid == null || db == null) return child;
  final info = MyMatchInfo.of(t, uid);
  return ClaimPrompt(
    t: t,
    uid: uid,
    state: info == null ? const NoClaims() : sync.stateOf(t, info.match),
    onReport: (res) => info == null
        ? Future.value()
        : writeClaim(db, t.id,
            Claim(matchId: info.match.id, uid: uid, result: res, atMs: DateTime.now().millisecondsSinceEpoch)),
    child: child,
  );
}

/// The host's own match when they also play (online only).
Widget? _hostMatch(BuildContext context, Tournament t) {
  final sync = hostSyncOf(context);
  final uid = authOf(context)?.user?.uid;
  final db = dbOf(context);
  if (sync == null || uid == null || db == null || t.finished) return null;
  final me = t.players.where((p) => p.uid == uid).firstOrNull;
  final r = t.currentRound;
  if (me == null || r == null || !r.published) return null;
  final m = r.matches.where((m) => m.involves(me.id)).firstOrNull;
  if (m == null) return null;
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: MyMatchCard(
      t: t,
      uid: uid,
      state: sync.stateOf(t, m),
      onReport: (res) => writeClaim(
          db, t.id, Claim(matchId: m.id, uid: uid, result: res, atMs: DateTime.now().millisecondsSinceEpoch)),
    ),
  );
}

/// The one primary action of the moment: start, next round, top cut, finish.
class _NextStepBar extends StatelessWidget {
  final Tournament t;
  final void Function(String) goTo;
  const _NextStepBar({required this.t, required this.goTo});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    String label;
    String? hint;
    VoidCallback? action;
    IconData icon = Icons.play_arrow_rounded;

    final open = t.firstIncompleteRound;
    final sync = hostSyncOf(context);
    // Only unconfirmed reports left in the current round: they can be accepted.
    final pending = (sync != null && open != null && identical(open, t.currentRound))
        ? sync.pendingOnly(t, open)
        : const <(Match, Claim)>[];
    final onlyPendingLeft = pending.isNotEmpty && pending.length == open!.pending;
    if (draftRound(t) != null) {
      label = S.t.sendToPlayers;
      hint = S.t.draftBanner;
      icon = Icons.send_rounded;
      action = () {
        app.publish(t);
        goTo('rounds');
      };
    } else if (t.finished && sync != null && !t.resultsPublished) {
      label = S.t.sendResults;
      hint = S.t.sendResultsHint;
      icon = Icons.send_rounded;
      action = () {
        t.resultsPublished = true;
        app.changed();
        goTo('prizes');
      };
    } else if (onlyPendingLeft) {
      label = S.t.nextAcceptingPending(pending.length);
      hint = S.t.acceptPendingHint;
      icon = Icons.done_all_rounded;
      action = () async {
        final ok = await confirm(context, S.t.acceptPendingTitle(pending.length), S.t.acceptPendingBody);
        if (!ok) return;
        sync!.acceptPending(t, open);
        if (!context.mounted) return;
        if (t.firstIncompleteRound == null) {
          app.advance(t);
          goTo(t.finished ? 'prizes' : (t.topRoundsList.isNotEmpty ? 'bracket' : 'rounds'));
        }
      };
    } else if (t.finished) {
      final winner = finalPlacements(t).firstOrNull;
      label = S.t.tournamentOver;
      hint = winner == null ? null : S.t.champion(t.nameOf(winner.playerId));
      icon = Icons.emoji_events;
      action = () => goTo('prizes');
    } else if (!t.started) {
      final n = t.activePlayers.length;
      label = n < 2 ? S.t.needTwoPlayers : S.t.startTournament;
      if (n >= 2) {
        action = () {
          app.start(t);
          goTo('rounds');
        };
      }
    } else if (open != null) {
      label = S.t.missingResults(open.pending);
      hint = open.stage == Stage.top
          ? S.t.topRoundName(topRoundSize(open))
          : S.t.roundOutOf(open.number, t.plannedSwissRounds);
      icon = Icons.hourglass_top_rounded;
      action = () => goTo('rounds');
    } else if (!t.swissDone) {
      label = S.t.pairRound(t.swissRoundsList.length + 1);
      icon = Icons.shuffle_rounded;
      action = () {
        app.advance(t);
        goTo('rounds');
      };
    } else if (effectiveTopCut(t) > 0 && !topCutFinished(t)) {
      final next = nextTopRound(t);
      label = t.topRoundsList.isEmpty
          ? S.t.startTop(effectiveTopCut(t))
          : S.t.create(next == null ? '' : S.t.topRoundName(topRoundSize(next)));
      icon = Icons.account_tree_rounded;
      action = () {
        app.advance(t);
        goTo('bracket');
      };
    } else {
      label = S.t.finishTournament;
      icon = Icons.flag_rounded;
      action = () {
        app.advance(t);
        goTo('prizes');
      };
    }

    final waiting = t.started && !t.finished && open != null && draftRound(t) == null && !onlyPendingLeft;
    return Material(
      color: Z.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: waiting
                  ? OutlinedButton.icon(
                      onPressed: action,
                      icon: Icon(icon, size: 20),
                      label: Text(label),
                    )
                  : FilledButton.icon(
                      onPressed: action,
                      icon: Icon(icon),
                      label: Text(label),
                    ),
            ),
            if (hint != null) ...[
              const SizedBox(width: 12),
              Flexible(
                flex: 2,
                child: Text(hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Z.muted, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
