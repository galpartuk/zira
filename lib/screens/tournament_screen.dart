import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/models.dart';
import '../engine/pairing.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'tabs/bracket_tab.dart';
import 'tabs/players_tab.dart';
import 'tabs/prizes_tab.dart';
import 'tabs/rounds_tab.dart';
import 'tabs/standings_tab.dart';
import 'tournament_settings_sheet.dart';
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
    var initial = keys.indexOf(prevKey ?? (t.started ? 'rounds' : 'players'));
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
    final t = app.byId(widget.id);
    if (t == null) return const Scaffold(body: SizedBox());
    _ensureTabs(t);
    final (status, color) = statusOf(t);

    const labels = {
      'players': 'שחקנים',
      'rounds': 'סיבובים',
      'standings': 'דירוג',
      'bracket': 'טופ קאט',
      'prizes': 'פרסים',
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
            Text('${t.activePlayers.length} פעילים', style: const TextStyle(fontSize: 12.5, color: Z.muted)),
          ]),
        ]),
        toolbarHeight: 68,
        actions: [
          IconButton(
            tooltip: 'הגדרות',
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
      body: TabBarView(controller: _tabs, children: [
        for (final k in _keys)
          switch (k) {
            'players' => PlayersTab(t: t),
            'rounds' => RoundsTab(t: t),
            'standings' => StandingsTab(t: t),
            'bracket' => BracketTab(t: t),
            _ => PrizesTab(t: t),
          }
      ]),
      bottomNavigationBar: _NextStepBar(t: t, goTo: _goTo),
    );
  }
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
    if (t.finished) {
      final winner = finalPlacements(t).firstOrNull;
      label = 'הטורניר הסתיים';
      hint = winner == null ? null : 'אלוף: ${t.nameOf(winner.playerId)}';
      icon = Icons.emoji_events;
      action = () => goTo('prizes');
    } else if (!t.started) {
      final n = t.activePlayers.length;
      label = n < 2 ? 'צריך לפחות 2 שחקנים' : 'התחלת הטורניר · סיבוב 1';
      if (n >= 2) {
        action = () {
          app.start(t);
          goTo('rounds');
        };
      }
    } else if (open != null) {
      label = open.pending == 1 ? 'חסרה תוצאה אחת' : 'חסרות ${open.pending} תוצאות';
      hint = open.stage == Stage.top ? topRoundName(open) : 'סיבוב ${open.number} מתוך ${t.plannedSwissRounds}';
      icon = Icons.hourglass_top_rounded;
      action = () => goTo('rounds');
    } else if (!t.swissDone) {
      label = 'זיווג סיבוב ${t.swissRoundsList.length + 1}';
      icon = Icons.shuffle_rounded;
      action = () {
        app.advance(t);
        goTo('rounds');
      };
    } else if (effectiveTopCut(t) > 0 && !topCutFinished(t)) {
      final next = nextTopRound(t);
      label = t.topRoundsList.isEmpty ? 'התחלת טופ ${effectiveTopCut(t)}' : 'יצירת ${next == null ? '' : topRoundName(next)}';
      icon = Icons.account_tree_rounded;
      action = () {
        app.advance(t);
        goTo('bracket');
      };
    } else {
      label = 'סיום הטורניר ודירוג סופי';
      icon = Icons.flag_rounded;
      action = () {
        app.advance(t);
        goTo('prizes');
      };
    }

    final waiting = t.started && !t.finished && open != null;
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
