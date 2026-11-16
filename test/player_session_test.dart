import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/l10n.dart';
import 'package:zira/widgets/my_match_card.dart';
import 'package:zira/widgets/round_timer.dart';
import 'package:zira/cloud/claims.dart';
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

  test('a deleted tournament is reported as gone', () async {
    final db = await hosted();
    final s = PlayerSession(db, 't1', 'alice');
    await pumpEventQueue();
    expect(s.gone, isFalse);
    await db.doc('tournaments/t1').delete();
    await pumpEventQueue();
    expect(s.gone, isTrue);
    s.dispose();
  });

  test('claims are only listened to once I am a member (the rules refuse it before)', () async {
    final db = await hosted();
    // Eve just joined: she is in no player list and not a member yet.
    await db.doc('tournaments/t1').update({'memberUids': ['host', 'alice', 'bob']});
    final s = PlayerSession(db, 't1', 'eve');
    await pumpEventQueue();
    expect(s.listeningToClaims, isFalse);
    await db.doc('tournaments/t1').update({'memberUids': ['host', 'alice', 'bob', 'eve']});
    await pumpEventQueue();
    expect(s.listeningToClaims, isTrue);
    s.dispose();
  });

  test('drop writes a dropped entry', () async {
    final db = await hosted();
    await writeEntry(db, 't1', const Entry(uid: 'alice', displayName: 'Alice', status: EntryStatus.joined));
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
    expect(find.text('Alice reported a result'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    expect(sent, same(theirs));
  });

  testWidgets('pop-up appears once when the opponent reports, and Confirm sends their result', (tester) async {
    Lang.instance.code = 'en';
    final t = Tournament(name: 'T', players: [
      Player(id: 'a', name: 'Alice', uid: 'alice', tieRand: 1),
      Player(id: 'b', name: 'Bob', uid: 'bob', tieRand: 2),
    ]);
    t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [Match(id: 'm1', table: 3, p1: 'a', p2: 'b')]));
    const theirs = MatchResult(Outcome.p1, 2, 1);
    final sent = <MatchResult>[];
    Widget app(ClaimState st) => MaterialApp(
          home: Scaffold(
            body: ClaimPrompt(
              t: t,
              uid: 'bob',
              state: st,
              onReport: (r) async => sent.add(r),
              child: const SizedBox.expand(),
            ),
          ),
        );
    await tester.pumpWidget(app(const NoClaims()));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    const pending = Pending(Claim(matchId: 'm1', uid: 'alice', result: theirs, atMs: 1));
    await tester.pumpWidget(app(pending));
    await tester.pumpAndSettle();
    expect(find.text('Alice reported a result'), findsOneWidget);
    expect(find.text(S.t.youLost(1, 2)), findsOneWidget); // from Bob's side
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(sent.single, same(theirs));

    await tester.pumpWidget(app(pending)); // same report again: no second pop-up
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('players get the clock without start/pause/reset buttons', (tester) async {
    Lang.instance.code = 'en';
    final t = Tournament(name: 'T');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RoundTimer(t: t, readOnly: true))));
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    expect(find.byIcon(Icons.replay), findsNothing);
    expect(find.byIcon(Icons.more_time), findsNothing);
    await tester.pumpWidget(const SizedBox()); // stops the clock's ticker
  });

  testWidgets('the pop-up closes by itself when the host moves on', (tester) async {
    Lang.instance.code = 'en';
    final t = Tournament(name: 'T', players: [
      Player(id: 'a', name: 'Alice', uid: 'alice', tieRand: 1),
      Player(id: 'b', name: 'Bob', uid: 'bob', tieRand: 2),
    ]);
    t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [Match(id: 'm1', table: 3, p1: 'a', p2: 'b')]));
    const theirs = MatchResult(Outcome.p1, 2, 1);
    final sent = <MatchResult>[];
    Widget app(ClaimState st) => MaterialApp(
          home: Scaffold(
            body: ClaimPrompt(t: t, uid: 'bob', state: st, onReport: (r) async => sent.add(r), child: const SizedBox.expand()),
          ),
        );
    await tester.pumpWidget(app(const Pending(Claim(matchId: 'm1', uid: 'alice', result: theirs, atMs: 1))));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    // The host accepted Alice's report and moved on.
    t.rounds.single.matches.single
      ..result = theirs
      ..by = 'p:alice';
    await tester.pumpWidget(app(const NoClaims()));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(sent, isEmpty);
  });
}
