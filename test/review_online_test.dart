// Regression tests for the pre-release review (2026-11-16).
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/cloud/claims.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';
import 'package:zira/state/app_state.dart';
import 'package:zira/state/host_sync.dart';
import 'package:zira/state/player_session.dart';

Future<(FakeFirebaseFirestore, AppState, HostSync, Tournament)> host({TFormat format = TFormat.swiss}) async {
  final db = FakeFirebaseFirestore();
  final app = AppState(store: CloudStore(db, 'host'), draftRounds: true);
  await app.load();
  final t = Tournament(
    id: 't1',
    name: 'T',
    joinCode: 'ABC234',
    format: format,
    swissRounds: 3,
    players: [
      Player(id: 'g', name: 'Gal', tieRand: 0), // a guest already called Gal
      Player(id: 'b', name: 'Bob', uid: 'bob', tieRand: 1),
      Player(id: 'c', name: 'Cid', uid: 'cid', tieRand: 2),
    ],
  );
  app.add(t);
  await db.doc('joinCodes/ABC234').set({'tid': 't1', 'hostUid': 'host'});
  final sync = HostSync(db, app, 'host');
  await pumpEventQueue();
  return (db, app, sync, t);
}

void main() {
  test('#1 a renamed player ("Gal 2") drops: only the status changes, the stored name stays', () async {
    final (db, app, sync, t) = await host();
    await writeEntry(db, 't1', const Entry(uid: 'gal2', displayName: 'Gal', status: EntryStatus.joined));
    await pumpEventQueue();
    expect(t.players.firstWhere((p) => p.uid == 'gal2').name, 'Gal 2');
    app.start(t);
    app.publish(t);
    await pumpEventQueue();
    final s = PlayerSession(db, 't1', 'gal2');
    await pumpEventQueue();
    await s.drop();
    await pumpEventQueue();
    final entry = (await db.doc('tournaments/t1/entries/gal2').get()).data()!;
    expect(entry['displayName'], 'Gal'); // unchanged, so the rules accept it
    expect(entry['status'], 'dropped');
    expect(t.players.firstWhere((p) => p.uid == 'gal2').dropped, isTrue);
    s.dispose();
    sync.dispose();
  });

  test('#2 round robin: no joins once round 1 exists, even as a draft', () {
    final t = Tournament(
      name: 'RR',
      format: TFormat.roundRobin,
      players: [for (var i = 0; i < 4; i++) Player(id: 'p$i', name: 'P$i', tieRand: i)],
    );
    expect(t.acceptsNewPlayers, isTrue);
    final app = AppState(draftRounds: true)..add(t);
    app.start(t);
    expect(t.currentRound!.published, isFalse);
    expect(t.acceptsNewPlayers, isFalse);
  });

  test('#3 after a host restart old entries are not applied again (a manual un-drop sticks)', () async {
    final (db, app, sync, t) = await host();
    app.start(t);
    app.publish(t);
    await writeEntry(db, 't1', const Entry(uid: 'bob', displayName: 'Bob', status: EntryStatus.dropped));
    await pumpEventQueue();
    expect(t.player('b')!.dropped, isTrue);
    t.player('b')!.dropped = false; // host un-drops him
    app.changed();
    sync.dispose();
    await pumpEventQueue();
    // The host's app restarts: reload from the cloud and listen again.
    final app2 = AppState(store: CloudStore(db, 'host'), draftRounds: true);
    await app2.load();
    final sync2 = HostSync(db, app2, 'host');
    await pumpEventQueue();
    expect(app2.byId('t1')!.player('b')!.dropped, isFalse);
    sync2.dispose();
  });

  test('#4 re-entering the code while waiting for approval just opens it; after dropping says so', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('joinCodes/ABC234').set({'tid': 't1', 'hostUid': 'host'});
    await db.doc('tournaments/t1').set({
      'hostUid': 'host',
      'status': 'registration',
      'joinMode': 'approval',
      'data': {},
    });
    await writeEntry(db, 't1', const Entry(uid: 'eve', displayName: 'Eve', status: EntryStatus.requested));
    expect((await joinWithCode(db, uid: 'eve', name: 'Eve', code: 'ABC234')).$1, JoinResult.requested);
    await db.doc('tournaments/t1/entries/eve').update({'status': 'dropped'});
    expect((await joinWithCode(db, uid: 'eve', name: 'Eve', code: 'ABC234')).$1, JoinResult.dropped);
  });

  test('#5 the host removing himself writes no entry', () async {
    final (db, app, sync, t) = await host();
    final me = Player(id: 'h', name: 'Host', uid: 'host', tieRand: 9);
    t.players.add(me);
    app.changed();
    await sync.removePlayer(t, me);
    expect((await db.doc('tournaments/t1/entries/host').get()).exists, isFalse);
    expect(t.player('h'), isNull);
    sync.dispose();
  });

  test('#6 a confirmed result the host cleared is not refilled by the old reports', () async {
    final (db, app, sync, t) = await host();
    // Four players: whatever the random pairing, one match has two app players.
    t.players.add(Player(id: 'd', name: 'Dan', uid: 'dan', tieRand: 3));
    app.start(t);
    app.publish(t);
    final m = t.currentRound!.matches.firstWhere(
      (m) => !m.isBye && t.player(m.p1)!.uid != null && t.player(m.p2)?.uid != null,
    );
    for (final u in [t.player(m.p1)!.uid!, t.player(m.p2)!.uid!]) {
      await writeClaim(db, 't1', Claim(matchId: m.id, uid: u, result: const MatchResult(Outcome.p1, 2, 0), atMs: 1));
    }
    await pumpEventQueue();
    expect(m.result, isNotNull);
    app.setResult(t, m, null); // host clears it on purpose
    expect(m.by, 'x');
    sync.dispose();
    final app2 = AppState(store: CloudStore(db, 'host'), draftRounds: true);
    await app2.load();
    final sync2 = HostSync(db, app2, 'host');
    await pumpEventQueue();
    final m2 = app2.byId('t1')!.currentRound!.matches.firstWhere((x) => x.id == m.id);
    expect(m2.result, isNull);
    sync2.dispose();
  });
}
