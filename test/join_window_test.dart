import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/cloud/claims.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';
import 'package:zira/l10n.dart';
import 'package:zira/state/app_state.dart';
import 'package:zira/state/host_sync.dart';
import 'package:zira/state/player_session.dart';
import 'package:zira/widgets/my_match_card.dart';

Tournament swiss(int rounds) => Tournament(id: 't1', name: 'T', joinCode: 'ABC234', swissRounds: rounds, players: [
      for (var i = 0; i < 4; i++) Player(id: 'p$i', name: 'P$i', uid: 'u$i', tieRand: i),
    ]);

void main() {
  setUp(() => Lang.instance.code = 'en');

  test('the tournament doc says whether players can still join', () async {
    final db = FakeFirebaseFirestore();
    final app = AppState(store: CloudStore(db, 'host'));
    await app.load();
    final t = swiss(2);
    app.add(t);
    await pumpEventQueue();
    Future<Object?> accepts() async => (await db.doc('tournaments/t1').get()).data()!['acceptsPlayers'];
    expect(await accepts(), isTrue); // not started
    app.start(t);
    await pumpEventQueue();
    expect(await accepts(), isTrue); // round 1 of 2: a late entry can still play round 2
    for (final m in t.currentRound!.matches) {
      m.result ??= const MatchResult(Outcome.p1, 2, 0);
    }
    app.advance(t); // round 2 = the last one
    await pumpEventQueue();
    expect(await accepts(), isFalse);
  });

  test('joining is refused with "closed" when the host no longer accepts players', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('joinCodes/ABC234').set({'tid': 't1', 'hostUid': 'host'});
    await db.doc('tournaments/t1').set({
      'hostUid': 'host',
      'status': 'running',
      'joinMode': 'open',
      'acceptsPlayers': false,
      'memberUids': ['host'],
      'data': swiss(2).toJson(),
    });
    final (res, _) = await joinWithCode(db, uid: 'eve', name: 'Eve', code: 'ABC234');
    expect(res, JoinResult.closed);
    expect((await db.doc('tournaments/t1/entries/eve').get()).exists, isFalse);
  });

  test('the host is told when a player joins', () async {
    final db = FakeFirebaseFirestore();
    final app = AppState(store: CloudStore(db, 'host'), draftRounds: true);
    await app.load();
    app.add(swiss(3));
    final notices = <String>[];
    final sync = HostSync(db, app, 'host')..onNotice = notices.add;
    await pumpEventQueue();
    await writeEntry(db, 't1', const Entry(uid: 'eve', displayName: 'Eve', status: EntryStatus.joined));
    await pumpEventQueue();
    expect(notices, ['Eve joined']);
    sync.dispose();
  });

  testWidgets('a player who could not be added sees that registration closed', (tester) async {
    final t = swiss(1);
    t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [Match(id: 'm1', table: 1, p1: 'p0', p2: 'p1')]));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MyMatchCard(t: t, uid: 'late-eve', state: const NoClaims(), onReport: (_) async {}),
      ),
    ));
    expect(find.textContaining('Registration is closed'), findsOneWidget);
  });
}
