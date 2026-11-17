import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/cloud/claims.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';
import 'package:zira/state/app_state.dart';
import 'package:zira/state/host_sync.dart';

Future<(FakeFirebaseFirestore, AppState, HostSync, Tournament)> setup() async {
  final db = FakeFirebaseFirestore();
  final app = AppState(store: CloudStore(db, 'host'), draftRounds: true);
  await app.load();
  final t = Tournament(
    id: 't1',
    name: 'T',
    players: [
      Player(id: 'a', name: 'A', uid: 'alice', tieRand: 1),
      Player(id: 'b', name: 'B', uid: 'bob', tieRand: 2),
      Player(id: 'c', name: 'C', tieRand: 3),
      Player(id: 'd', name: 'D', uid: 'dan', tieRand: 4),
    ],
  );
  app.add(t);
  final sync = HostSync(db, app, 'host');
  await pumpEventQueue();
  return (db, app, sync, t);
}

Claim c(String matchId, String uid, Outcome o) => Claim(
  matchId: matchId,
  uid: uid,
  result: MatchResult(o, o == Outcome.p1 ? 2 : 0, o == Outcome.p1 ? 0 : 2),
  atMs: 0,
);

void main() {
  test('a joined entry adds the player', () async {
    final (db, app, sync, t) = await setup();
    await writeEntry(db, 't1', const Entry(uid: 'eve', displayName: 'Eve', status: EntryStatus.joined));
    await pumpEventQueue();
    expect(t.players.any((p) => p.uid == 'eve'), isTrue);
    sync.dispose();
  });

  test('requests are listed and approve joins them', () async {
    final (db, app, sync, t) = await setup();
    await writeEntry(db, 't1', const Entry(uid: 'eve', displayName: 'Eve', status: EntryStatus.requested));
    await pumpEventQueue();
    expect(sync.requests(t).single.uid, 'eve');
    await sync.approve(t, 'eve');
    await pumpEventQueue();
    expect(t.players.any((p) => p.uid == 'eve'), isTrue);
    sync.dispose();
  });

  test('confirmed claims set the result; disputes and pending do not', () async {
    final (db, app, sync, t) = await setup();
    app.start(t);
    app.publish(t);
    final r = t.currentRound!;
    final m = r.matches.firstWhere((m) => !m.isBye && t.player(m.p1)!.uid != null && t.player(m.p2)!.uid != null);
    final u1 = t.player(m.p1)!.uid!, u2 = t.player(m.p2)!.uid!;
    await writeClaim(db, 't1', c(m.id, u1, Outcome.p1));
    await pumpEventQueue();
    expect(m.result, isNull);
    expect(sync.stateOf(t, m), isA<Pending>());
    await writeClaim(db, 't1', c(m.id, u2, Outcome.p2));
    await pumpEventQueue();
    expect(m.result, isNull);
    expect(sync.stateOf(t, m), isA<Disputed>());
    await writeClaim(db, 't1', c(m.id, u2, Outcome.p1));
    await pumpEventQueue();
    expect(m.result!.outcome, Outcome.p1);
    // host clears it on purpose → not re-applied this session
    app.setResult(t, m, null);
    await writeClaim(db, 't1', c(m.id, u2, Outcome.p1));
    await pumpEventQueue();
    expect(m.result, isNull);
    sync.dispose();
  });

  test('a claim vs a guest is applied at once', () async {
    final (db, app, sync, t) = await setup();
    app.start(t);
    app.publish(t);
    final m = t.currentRound!.matches.firstWhere(
      (m) => !m.isBye && (t.player(m.p1)!.uid == null || t.player(m.p2)?.uid == null),
    );
    final reporter = t.player(m.p1)!.uid ?? t.player(m.p2)!.uid!;
    await writeClaim(db, 't1', c(m.id, reporter, Outcome.p2));
    await pumpEventQueue();
    expect(m.result!.outcome, Outcome.p2);
    sync.dispose();
  });

  test('finishing releases the join code', () async {
    final (db, app, sync, t) = await setup();
    await db.doc('joinCodes/ABC234').set({'tid': 't1', 'hostUid': 'host'});
    t
      ..joinCode = 'ABC234'
      ..finished = true;
    app.changed();
    await pumpEventQueue();
    expect(t.joinCode, isNull);
    expect((await db.doc('joinCodes/ABC234').get()).exists, isFalse);
    sync.dispose();
  });

  test('removePlayer before start removes and blocks rejoin', () async {
    final (db, app, sync, t) = await setup();
    // Bob joined by code, so he has an entry.
    await writeEntry(db, 't1', const Entry(uid: 'bob', displayName: 'B', status: EntryStatus.joined));
    await pumpEventQueue();
    await sync.removePlayer(t, t.player('b')!);
    expect(t.player('b'), isNull);
    expect((await db.doc('tournaments/t1/entries/bob').get()).data()!['status'], 'removed');
    sync.dispose();
  });

  test('a host undoing a self-drop is not overridden by unrelated entry changes', () async {
    final (db, app, sync, t) = await setup();
    app.start(t);
    app.publish(t);
    await writeEntry(db, 't1', const Entry(uid: 'alice', displayName: 'A', status: EntryStatus.dropped));
    await pumpEventQueue();
    expect(t.player('a')!.dropped, isTrue);
    t.player('a')!.dropped = false; // host undoes it
    app.changed();
    await writeEntry(db, 't1', const Entry(uid: 'eve', displayName: 'Eve', status: EntryStatus.requested));
    await pumpEventQueue();
    expect(t.player('a')!.dropped, isFalse);
    sync.dispose();
  });

  test('roundCounts', () async {
    final (db, app, sync, t) = await setup();
    app.start(t);
    app.publish(t);
    expect(sync.roundCounts(t).total, t.currentRound!.matches.where((m) => !m.isBye).length);
    sync.dispose();
  });
}
