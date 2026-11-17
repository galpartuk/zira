import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart';
import '../../engine/standings.dart';
import '../../l10n.dart';
import '../../engine/online.dart';
import '../../state/app_state.dart';
import '../../state/session.dart';
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

  bool get canAdd => t.acceptsNewPlayers;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

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
    if (t.started) toast(context, S.t.lateEntry);
  }

  @override
  Widget build(BuildContext context) {
    final standings = {for (final s in computeStandings(t)) s.player.id: s};
    final players = [...t.players]..sort((a, b) {
        if (a.dropped != b.dropped) return a.dropped ? 1 : -1;
        return t.started ? standings[a.id]!.rank.compareTo(standings[b.id]!.rank) : 0;
      });

    final sync = hostSyncOf(context);
    final auth = authOf(context);
    final myUid = auth?.user?.uid;
    final requests = sync?.requests(t) ?? const <Entry>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (sync != null && !t.started)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(S.t.setupGuideTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (final line in [S.t.setupGuide1, S.t.setupGuide2, S.t.setupGuide3])
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('•  $line', style: const TextStyle(color: Z.muted, fontSize: 13.5)),
                  ),
              ]),
            ),
          ),
        if (requests.isNotEmpty) ...[
          SectionTitle(S.t.joinRequests),
          for (final e in requests)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(e.displayName),
              trailing: FilledButton.tonal(onPressed: () => sync!.approve(t, e.uid), child: Text(S.t.approve)),
            ),
          const SizedBox(height: 8),
        ],
        if (sync != null && myUid != null && canAdd && !t.players.any((p) => p.uid == myUid))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.person_add_alt),
              label: Text(S.t.addMe),
              onPressed: () {
                t.players.add(Player(id: newId(), name: uniquePlayerName(t, auth!.displayName), uid: myUid));
                context.read<AppState>().changed();
              },
            ),
          ),
        if (canAdd)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(hintText: S.t.playerName, prefixIcon: const Icon(Icons.person_add_alt_1)),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(onPressed: _add, child: Text(S.t.add)),
          ]),
        if (t.players.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyState(icon: Icons.groups_outlined, title: S.t.noPlayers, body: S.t.noPlayersBody),
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
              ? Text('${S.t.pts(s.points)}  ·  ${s.record}', style: const TextStyle(color: Z.muted, fontFeatures: Z.tabular))
              : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (p.dropped) Pill(S.t.dropped, color: Z.danger),
            if (hostSyncOf(context) != null && !p.dropped) Pill(p.uid != null ? S.t.online : S.t.guest),
            PopupMenuButton<String>(
              onSelected: (v) => _action(p, v),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'rename', child: Text(S.t.rename)),
                if (t.started && !t.finished)
                  PopupMenuItem(value: 'drop', child: Text(p.dropped ? S.t.undrop : S.t.dropFromTournament)),
                if (!t.started) PopupMenuItem(value: 'delete', child: Text(S.t.remove)),
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
        final name = await promptText(context, S.t.rename, initial: p.name);
        if (name != null && name.isNotEmpty) {
          p.name = name;
          app.changed();
        }
      case 'drop':
        if (!p.dropped) {
          final ok = await confirm(context, S.t.dropPlayerTitle(p.name), S.t.dropPlayerBody, ok: S.t.drop);
          if (!ok) return;
        }
        p.dropped = !p.dropped;
        app.changed();
      case 'delete':
        final sync = hostSyncOf(context, listen: false);
        if (sync != null && p.uid != null) {
          await sync.removePlayer(t, p);
        } else {
          t.players.remove(p);
          app.changed();
        }
    }
  }
}
