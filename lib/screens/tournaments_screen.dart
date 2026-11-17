import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/models.dart';
import '../engine/pairing.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../state/player_session.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'about_screen.dart';
import 'account_sheet.dart';
import 'create_tournament_screen.dart';
import 'history_screen.dart';
import 'join_screen.dart';
import 'player_tournament_screen.dart';
import 'sign_in_screen.dart';
import 'tournament_screen.dart';

class TournamentsScreen extends StatelessWidget {
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final auth = authOf(context);
    if (auth != null && auth.user == null) {
      return Scaffold(
        appBar: AppBar(title: const BrandTitle(), actions: const [LangButton()]),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: S.t.signIn,
          body: S.t.signInNeeded,
          action: FilledButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignInScreen())),
            child: Text(S.t.signIn),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const BrandTitle(),
        actions: [
          const LangButton(),
          if (auth != null)
            IconButton(
              tooltip: S.t.account,
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => showAccountSheet(context),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => _menu(context, app, v),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'export', child: Text(S.t.copyBackup)),
              PopupMenuItem(value: 'import', child: Text(S.t.restoreBackup)),
              PopupMenuItem(value: 'look', child: Text(Looks.instance.light ? S.t.darkLook : S.t.lightLook)),
              PopupMenuItem(value: 'about', child: Text(S.t.about)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.add),
        label: Text(S.t.newTournament, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: !app.loaded
          ? const Center(child: CircularProgressIndicator())
          : auth != null
          ? _OnlineList(uid: auth.user!.uid, hosted: app.tournaments, onCreate: () => _create(context))
          : app.tournaments.isEmpty
          ? EmptyState(
              icon: Icons.emoji_events_outlined,
              title: S.t.noTournaments,
              body: S.t.noTournamentsBody,
              action: FilledButton.icon(
                onPressed: () => _create(context),
                icon: const Icon(Icons.add),
                label: Text(S.t.newTournament),
              ),
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
      context,
      MaterialPageRoute(builder: (_) => const CreateTournamentScreen()),
    );
    if (t == null || !context.mounted) return;
    context.read<AppState>().add(t);
    hostSyncOf(context, listen: false)?.ensureJoinCode(t);
    Navigator.push(context, MaterialPageRoute(builder: (_) => TournamentScreen(id: t.id)));
  }

  void _menu(BuildContext context, AppState app, String v) async {
    if (v == 'look') {
      Looks.instance.toggle();
    } else if (v == 'about') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
    } else if (v == 'export') {
      await copyText(context, app.exportAll(), S.t.backupWhat);
    } else if (v == 'import') {
      final data = await Clipboard.getData('text/plain');
      if (!context.mounted) return;
      try {
        final n = app.importAll(data?.text ?? '');
        toast(context, S.t.restored(n));
      } catch (_) {
        toast(context, S.t.badBackup);
      }
    }
  }
}

class _TournamentCard extends StatelessWidget {
  final Tournament t;

  /// Set for a tournament I play in (someone else hosts it): opens the player
  /// screen, or its history once finished, and can't be deleted from here.
  final String? joinedTid;
  const _TournamentCard(this.t, {this.joinedTid});

  @override
  Widget build(BuildContext context) {
    final (status, color) = statusOf(t);
    final d = t.created;
    final tid = joinedTid;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => tid == null
                ? TournamentScreen(id: t.id)
                : t.finished
                ? TournamentHistoryScreen(tid: tid)
                : PlayerTournamentScreen(tid: tid),
          ),
        ),
        onLongPress: tid != null
            ? null
            : () async {
                final ok = await confirm(
                  context,
                  S.t.deleteTitle(t.name),
                  S.t.deleteBody,
                  ok: S.t.delete,
                  danger: true,
                );
                if (ok && context.mounted) context.read<AppState>().remove(t);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 46,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      '${d.day}.${d.month}.${d.year}  ·  ${S.t.players(t.players.length)}  ·  ${t.format == TFormat.swiss ? S.t.swiss : S.t.roundRobin}${t.topCut > 0 ? ' + ${S.t.top(t.topCut)}' : ''}',
                      style: TextStyle(color: Z.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Pill(status, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Short status text + colour for a tournament.
(String, Color) statusOf(Tournament t) {
  if (t.finished) return (S.t.statusFinished, Z.win);
  if (!t.started) return (S.t.statusRegistration, Z.muted);
  final r = t.currentRound!;
  if (r.stage == Stage.top) return (S.t.topRoundName(topRoundSize(r)), Z.coral);
  return (S.t.roundOf(r.number, t.plannedSwissRounds), Z.blue);
}

/// Signed in: tournaments I play in (hosted by others, live) and ones I host.
class _OnlineList extends StatelessWidget {
  final String uid;
  final List<Tournament> hosted;
  final VoidCallback onCreate;
  const _OnlineList({required this.uid, required this.hosted, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: joinedTournaments(dbOf(context)!, uid),
      builder: (context, snap) {
        final playing = snap.data ?? const [];
        final live = [
          for (final p in playing)
            if (p.status != 'finished') p,
        ];
        final done = [
          for (final p in playing)
            if (p.status == 'finished') p,
        ];
        final hostingNow = [
          for (final t in hosted)
            if (!t.finished) t,
        ];
        final hostedDone = [
          for (final t in hosted)
            if (t.finished) t,
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            const JoinCard(),
            if (playing.isEmpty && hosted.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: EmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: S.t.noTournaments,
                  body: S.t.noTournamentsBody,
                  action: FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add),
                    label: Text(S.t.newTournament),
                  ),
                ),
              ),
            if (live.isNotEmpty) ...[
              SectionTitle(S.t.playingNow),
              for (final p in live) _joined(context, p.tid, p.name, p.t, finished: false),
              const SizedBox(height: 12),
            ],
            if (hostingNow.isNotEmpty) ...[
              SectionTitle(S.t.hosting),
              for (final t in hostingNow)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: _TournamentCard(t)),
              const SizedBox(height: 12),
            ],
            if (done.isNotEmpty || hostedDone.isNotEmpty) ...[
              SectionTitle(S.t.history),
              for (final t in hostedDone)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: _TournamentCard(t)),
              for (final p in done) _joined(context, p.tid, p.name, p.t, finished: true),
            ],
          ],
        );
      },
    );
  }
}

/// A tournament I play in: the full card when its data can be read, a plain row otherwise.
Widget _joined(BuildContext context, String tid, String name, Tournament? t, {required bool finished}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: t != null ? _TournamentCard(t, joinedTid: tid) : _joinedTile(context, tid, name, finished: finished),
);

Widget _joinedTile(BuildContext context, String tid, String name, {required bool finished}) => Card(
  child: ListTile(
    leading: Icon(finished ? Icons.history_rounded : Icons.sports_esports_outlined, color: finished ? Z.muted : Z.blue),
    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
    trailing: finished ? Pill(S.t.statusFinished) : const Icon(Icons.chevron_right),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => finished ? TournamentHistoryScreen(tid: tid) : PlayerTournamentScreen(tid: tid),
      ),
    ),
  ),
);
