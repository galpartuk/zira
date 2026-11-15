import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/l10n.dart';
import 'package:zira/widgets/my_match_card.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';
import 'package:zira/state/player_session.dart';

Future<FakeFirebaseFirestore> hosted({String joinMode = 'open', bool started = true, String? bobUid = 'bob'}) async {
  final db = FakeFirebaseFirestore();
  final t = Tournament(id: 't1', name: 'T', joinMode: joinMode, joinCode: 'ABC234', players: [
    Player(id: 'a', name: 'Alice', uid: 'alice', tieRand: 1),
    Player(id: 'b', name: 'Bob', uid: bobUid, tieRand: 2),
  ]);
  if (started) t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [Match(id: 'm1', table: 3, p1: 'a', p2: 'b')]));
  await CloudStore(db, 'host').saveAll([t]);
  await db.doc('joinCodes/ABC234').set({'tid': 't1', 'hostUid': 'host'});
  return db;
}

void main() {
  test('join with code: open → joined entry', () async {
    final db = await hosted(started: false);
    final (res, tid) = await joinWithCode(db, uid: 'eve', name: 'Eve', code: 'abc234');
    expect(res, JoinResult.ok);
    expect(tid, 't1');
    expect((await db.doc('tournaments/t1/entries/eve').get()).data()!['status'], 'joined');
  });

  test('join: approval → requested; bad code; closedOnStart after start', () async {
    expect((await joinWithCode(await hosted(joinMode: 'approval', started: false), uid: 'eve', name: 'E', code: 'ABC234')).$1,
        JoinResult.requested);
    expect((await joinWithCode(await hosted(), uid: 'eve', name: 'E', code: 'ZZZZZZ')).$1, JoinResult.badCode);
    expect((await joinWithCode(await hosted(joinMode: 'closedOnStart'), uid: 'eve', name: 'E', code: 'ABC234')).$1,
        JoinResult.closed);
  });

  test('session shows my match and reports a claim', () async {
    final db = await hosted();
    final s = PlayerSession(db, 't1', 'alice');
    await pumpEventQueue();
    expect(s.me!.name, 'Alice');
    expect(s.myMatch!.table, 3);
    await s.report(const MatchResult(Outcome.p1, 2, 1));
    await pumpEventQueue();
    expect((await db.doc('tournaments/t1/claims/m1_alice').get()).exists, isTrue);
    expect(s.myState, isA<Pending>());
    s.dispose();
  });

  test('confirm copies the opponent claim', () async {
    final db = await hosted();
    await db.doc('tournaments/t1/claims/m1_alice').set(
        const Claim(matchId: 'm1', uid: 'alice', result: MatchResult(Outcome.p1, 2, 0), atMs: 1).toJson());
    final s = PlayerSession(db, 't1', 'bob');
    await pumpEventQueue();
    expect(s.myState, isA<Pending>());
    await s.confirm();
    await pumpEventQueue();
    expect(s.myState, isA<Confirmed>());
    s.dispose();
  });

  test('drop writes a dropped entry', () async {
    final db = await hosted();
    final s = PlayerSession(db, 't1', 'alice');
    await pumpEventQueue();
    await s.drop();
    expect((await db.doc('tournaments/t1/entries/alice').get()).data()!['status'], 'dropped');
    s.dispose();
  });

  testWidgets('MyMatchCard: confirming reports the opponent result', (tester) async {
    Lang.instance.code = 'en';
    final t = Tournament(name: 'T', players: [
      Player(id: 'a', name: 'Alice', uid: 'alice', tieRand: 1),
      Player(id: 'b', name: 'Bob', uid: 'bob', tieRand: 2),
    ]);
    t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [Match(id: 'm1', table: 3, p1: 'a', p2: 'b')]));
    const theirs = MatchResult(Outcome.p1, 2, 1);
    MatchResult? sent;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MyMatchCard(
          t: t,
          uid: 'bob',
          state: const Pending(Claim(matchId: 'm1', uid: 'alice', result: theirs, atMs: 1)),
          onReport: (r) async => sent = r,
        ),
      ),
    ));
    expect(find.textContaining('Alice reported'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    expect(sent, same(theirs));
  });
}
