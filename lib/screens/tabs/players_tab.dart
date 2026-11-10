import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart';
import '../../engine/standings.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class PlayersTab extends StatefulWidget {
  final Tournament t;
  const PlayersTab({super.key, required this.t});

  @override
  State<PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<PlayersTab> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  Tournament get t => widget.t;

  /// Late entries are fine in Swiss (they start on 0 points); a round robin
  /// schedule is fixed once it starts.
  bool get canAdd => !t.finished && t.topRoundsList.isEmpty && !(t.format == TFormat.roundRobin && t.started);

  void _add() {
    final names = _ctrl.text.split(RegExp(r'[\n,]')).map((s) => s.trim()).where((s) => s.isNotEmpty);
    if (names.isEmpty) return;
    final existing = t.players.map((p) => p.name).toSet();
    for (final n in names) {
      var name = n;
      var k = 2;
      while (existing.contains(name)) {
        name = '$n ${k++}';
      }
      existing.add(name);
      t.players.add(Player(id: newId(), name: name));
    }
    _ctrl.clear();
    context.read<AppState>().changed();
    _focus.requestFocus();
    if (t.started) toast(context, 'נוסף באיחור — ישתתף מהסיבוב הבא עם 0 נקודות');
  }

  @override
  Widget build(BuildContext context) {
    final standings = {for (final s in computeStandings(t)) s.player.id: s};
    final players = [...t.players]..sort((a, b) {
        if (a.dropped != b.dropped) return a.dropped ? 1 : -1;
        return t.started ? standings[a.id]!.rank.compareTo(standings[b.id]!.rank) : 0;
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (canAdd)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: const InputDecoration(hintText: 'שם שחקן', prefixIcon: Icon(Icons.person_add_alt_1)),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(onPressed: _add, child: const Text('הוספה')),
          ]),
        if (t.players.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(
                icon: Icons.groups_outlined,
                title: 'אין עדיין שחקנים',
                body: 'הקלידו שם ולחצו הוספה. אפשר גם להדביק רשימה, שם בכל שורה.'),
          ),
        const SizedBox(height: 8),
        for (var i = 0; i < players.length; i++) _row(players[i], i + 1, standings[players[i].id]!),
      ],
    );
  }

  Widget _row(Player p, int n, Standing s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Z.surface,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: SizedBox(
            width: 28,
            child: Text('$n',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Z.muted, fontWeight: FontWeight.w700, fontFeatures: Z.tabular)),
          ),
          title: Text(p.name,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: p.dropped ? Z.muted : Z.text,
                decoration: p.dropped ? TextDecoration.lineThrough : null,
              )),
          subtitle: t.started
              ? Text('${s.points} נק׳  ·  ${s.record}', style: const TextStyle(color: Z.muted, fontFeatures: Z.tabular))
              : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (p.dropped) const Pill('פרש', color: Z.danger),
            PopupMenuButton<String>(
              onSelected: (v) => _action(p, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('שינוי שם')),
                if (t.started && !t.finished)
                  PopupMenuItem(value: 'drop', child: Text(p.dropped ? 'החזרה לטורניר' : 'פרישה מהטורניר')),
                if (!t.started) const PopupMenuItem(value: 'delete', child: Text('הסרה')),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  void _action(Player p, String v) async {
    final app = context.read<AppState>();
    switch (v) {
      case 'rename':
        final name = await promptText(context, 'שינוי שם', initial: p.name);
        if (name != null && name.isNotEmpty) {
          p.name = name;
          app.changed();
        }
      case 'drop':
        if (!p.dropped) {
          final ok = await confirm(context, 'פרישה של ${p.name}',
              'השחקן לא יזווג בסיבובים הבאים. התוצאות שכבר נרשמו נשארות ונספרות לשוברי השוויון של היריבים.',
              ok: 'פרישה');
          if (!ok) return;
        }
        p.dropped = !p.dropped;
        app.changed();
      case 'delete':
        t.players.remove(p);
        app.changed();
    }
  }
}
