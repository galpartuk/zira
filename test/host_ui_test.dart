import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zira/cloud/claims.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';
import 'package:zira/l10n.dart';
import 'package:zira/screens/tournament_screen.dart';
import 'package:zira/state/app_state.dart';
import 'package:zira/state/host_sync.dart';
import 'package:zira/theme.dart';
import 'package:zira/widgets/round_timer.dart';

import 'l10n_test.dart' show loadHeebo;

Future<(FakeFirebaseFirestore, AppState, HostSync, Tournament)> pumpHost(WidgetTester tester, String lang) async {
  Lang.instance.code = lang;
  await tester.binding.setSurfaceSize(const Size(400, 860));
  final db = FakeFirebaseFirestore();
  final app = AppState(store: CloudStore(db, 'host'), draftRounds: true);
  await app.load();
  final t = Tournament(id: 't1', name: 'Friday', joinCode: 'ABC234', players: [
    Player(id: 'a', name: 'Alice', uid: 'alice', tieRand: 1),
    Player(id: 'b', name: 'Bob', uid: 'bob', tieRand: 2),
    Player(id: 'c', name: 'Carmel', uid: 'carmel', tieRand: 3),
    Player(id: 'd', name: 'Dana', uid: 'dana', tieRand: 4),
  ]);
  app.add(t);
  final sync = HostSync(db, app, 'host');
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider<HostSync?>.value(value: sync),
    ],
    child: MaterialApp(theme: buildTheme(), home: const TournamentScreen(id: 't1')),
  ));
  await tester.pumpAndSettle();
  return (db, app, sync, t);
}

void main() {
  setUpAll(loadHeebo);

  testWidgets('draft round: send to players, then claims show as waiting', (tester) async {
    final (db, app, sync, t) = await pumpHost(tester, 'en');
    expect(find.text('ABC234'), findsOneWidget);
    app.start(t);
    await tester.pumpAndSettle();
    expect(find.text('Send to players'), findsWidgets);
    expect(find.byType(RoundTimer), findsNothing);

    await tester.tap(find.text('Send to players').first);
    await tester.pumpAndSettle();
    expect(t.currentRound!.published, isTrue);
    expect(find.byType(RoundTimer), findsOneWidget);

    final m = t.currentRound!.matches.first;
    final uid = t.player(m.p1)!.uid!;
    await writeClaim(db, 't1', Claim(matchId: m.id, uid: uid, result: const MatchResult(Outcome.p1, 2, 0), atMs: 1));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for confirmation'), findsOneWidget);
    sync.dispose();
  });

  testWidgets('Hebrew host screen has no overflow', (tester) async {
    final (_, app, sync, t) = await pumpHost(tester, 'he');
    app.start(t);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    sync.dispose();
    Lang.instance.code = 'en';
  });

  testWidgets('host who plays: tapping their own match sends a player report, not a final result', (tester) async {
    final (db, app, sync, t) = await pumpHost(tester, 'en');
    // The host plays too, as 'Alice' would: give the host's uid to a player.
    final hostPlayer = Player(id: 'h', name: 'Host', uid: 'host', tieRand: 9);
    t.players
      ..removeWhere((p) => p.id == 'd')
      ..add(hostPlayer);
    app.start(t);
    app.publish(t);
    await tester.pumpAndSettle();
    final mine = t.currentRound!.matches.firstWhere((m) => m.involves('h'));
    await tester.tap(find.text('Rounds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Host').last); // the match in the round list
    await tester.pumpAndSettle();
    await tester.tap(find.text('2-0'));
    await tester.pumpAndSettle();
    expect(mine.result, isNull, reason: 'the opponent still has to confirm');
    final claims = await db.collection('tournaments/t1/claims').get();
    expect(claims.docs.map((d) => d.id), contains('${mine.id}_host'));
    sync.dispose();
  });
}
