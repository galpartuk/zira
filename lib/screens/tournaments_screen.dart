import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/models.dart';
import '../engine/pairing.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'create_tournament_screen.dart';
import 'tournament_screen.dart';

class TournamentsScreen extends StatelessWidget {
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('זירה'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => _menu(context, app, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('העתקת גיבוי של כל הטורנירים')),
              PopupMenuItem(value: 'import', child: Text('שחזור גיבוי מהלוח')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('טורניר חדש', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: !app.loaded
          ? const Center(child: CircularProgressIndicator())
          : app.tournaments.isEmpty
              ? EmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: 'עוד אין טורנירים',
                  body: 'פתחו טורניר, הוסיפו שחקנים, והאפליקציה תזווג, תדרג ותחשב פרסים.',
                  action: FilledButton.icon(
                      onPressed: () => _create(context), icon: const Icon(Icons.add), label: const Text('טורניר חדש')),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: app.tournaments.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (c, i) => _TournamentCard(app.tournaments[i]),
                ),
    );
  }

  void _create(BuildContext context) async {
    final t = await Navigator.push<Tournament>(
        context, MaterialPageRoute(builder: (_) => const CreateTournamentScreen()));
    if (t == null || !context.mounted) return;
    context.read<AppState>().add(t);
    Navigator.push(context, MaterialPageRoute(builder: (_) => TournamentScreen(id: t.id)));
  }

  void _menu(BuildContext context, AppState app, String v) async {
    if (v == 'export') {
      await copyText(context, app.exportAll(), 'הגיבוי');
    } else if (v == 'import') {
      final data = await Clipboard.getData('text/plain');
      if (!context.mounted) return;
      try {
        final n = app.importAll(data?.text ?? '');
        toast(context, 'שוחזרו $n טורנירים');
      } catch (_) {
        toast(context, 'בלוח אין גיבוי תקין. העתיקו קודם גיבוי מהאפליקציה.');
      }
    }
  }
}

class _TournamentCard extends StatelessWidget {
  final Tournament t;
  const _TournamentCard(this.t);

  @override
  Widget build(BuildContext context) {
    final (status, color) = statusOf(t);
    final d = t.created;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TournamentScreen(id: t.id))),
        onLongPress: () async {
          final ok = await confirm(context, 'למחוק את "${t.name}"?', 'כל הסיבובים והתוצאות יימחקו. אי אפשר לבטל.',
              ok: 'מחיקה', danger: true);
          if (ok && context.mounted) context.read<AppState>().remove(t);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            Container(
              width: 4,
              height: 46,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${d.day}.${d.month}.${d.year}  ·  ${t.players.length} שחקנים  ·  ${t.format == TFormat.swiss ? 'סוויס' : 'ראונד רובין'}${t.topCut > 0 ? ' + טופ ${t.topCut}' : ''}',
                  style: const TextStyle(color: Z.muted, fontSize: 13),
                ),
              ]),
            ),
            Pill(status, color: color),
          ]),
        ),
      ),
    );
  }
}

/// Short status text + colour for a tournament.
(String, Color) statusOf(Tournament t) {
  if (t.finished) return ('הסתיים', Z.win);
  if (!t.started) return ('הרשמה', Z.muted);
  final r = t.currentRound!;
  if (r.stage == Stage.top) return (topRoundName(r), Z.coral);
  return ('סיבוב ${r.number}/${t.plannedSwissRounds}', Z.gold);
}
