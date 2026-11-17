import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/cloud/claims.dart';
import 'package:zira/cloud/join_codes.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';

Tournament t2() {
  final t = Tournament(id: 't1', name: 'T', players: [
    Player(id: 'a', name: 'A', uid: 'host', tieRand: 1),
    Player(id: 'b', name: 'B', uid: 'bob', tieRand: 2),
    Player(id: 'c', name: 'Guest', tieRand: 3),
  ]);
  t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [Match(id: 'm1', table: 1, p1: 'a', p2: 'b')]));
  return t;
}

void main() {
  test('save writes the published shape and a host-only draft', () async {
    final db = FakeFirebaseFirestore();
    final store = CloudStore(db, 'host');
    final t = t2()..joinCode = 'ABC234';
    t.rounds.add(Round(number: 2, stage: Stage.swiss, matches: [Match(id: 'm2', table: 1, p1: 'a', p2: 'c')], published: false));
    await store.saveAll([t]);
    final doc = (await db.doc('tournaments/t1').get()).data()!;
    expect(doc['hostUid'], 'host');
    expect(doc['status'], 'running');
    expect(doc['joinCode'], 'ABC234');
    expect(doc['joinMode'], 'open');
    expect(List<String>.from(doc['memberUids']), unorderedEquals(['host', 'bob']));
    expect(doc['matchUids'], isEmpty); // last round is a draft
    expect((doc['data']['rounds'] as List).length, 1);
    final priv = (await db.doc('tournaments/t1/private/host').get()).data()!;
    expect(priv['draftRound']['n'], 2);
  });

  test('load merges the draft back and only returns hosted tournaments', () async {
    final db = FakeFirebaseFirestore();
    final t = t2();
    t.rounds.add(Round(number: 2, stage: Stage.swiss, matches: [], published: false));
    await CloudStore(db, 'host').saveAll([t]);
    await db.doc('tournaments/other').set({'hostUid': 'zed', 'memberUids': ['zed', 'host'], 'data': t2().toJson()});
    final loaded = await CloudStore(db, 'host').load();
    expect(loaded.single.id, 't1');
    expect(loaded.single.rounds.length, 2);
    expect(loaded.single.rounds.last.published, isFalse);
  });

  test('unchanged tournaments are not rewritten', () async {
    final db = FakeFirebaseFirestore();
    final store = CloudStore(db, 'host');
    final t = t2();
    await store.saveAll([t]);
    await db.doc('tournaments/t1').update({'name': 'tampered'});
    await store.saveAll([t]);
    expect((await db.doc('tournaments/t1').get()).data()!['name'], 'tampered');
    t.name = 'New';
    await store.saveAll([t]);
    expect((await db.doc('tournaments/t1').get()).data()!['name'], 'New');
  });

  test('delete removes doc, private and join code', () async {
    final db = FakeFirebaseFirestore();
    final store = CloudStore(db, 'host');
    final t = t2()..joinCode = 'ABC234';
    await store.saveAll([t]);
    await db.doc('joinCodes/ABC234').set({'tid': 't1', 'hostUid': 'host'});
    await store.delete(t);
    expect((await db.doc('tournaments/t1').get()).exists, isFalse);
    expect((await db.doc('joinCodes/ABC234').get()).exists, isFalse);
  });

  test('join codes: alphabet, reserve, lookup', () async {
    final code = randomJoinCode();
    expect(code, matches(RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$')));
    final db = FakeFirebaseFirestore();
    final c = await reserveJoinCode(db, tid: 't1', hostUid: 'host');
    expect(await lookupJoinCode(db, ' ${c.toLowerCase()} '), 't1');
    expect(await lookupJoinCode(db, 'ZZZZZZ'), isNull);
  });

  test('writeClaim and writeEntry doc ids', () async {
    final db = FakeFirebaseFirestore();
    await writeClaim(db, 't1', const Claim(matchId: 'm1', uid: 'bob', result: MatchResult(Outcome.p2, 1, 2), atMs: 5));
    expect((await db.doc('tournaments/t1/claims/m1_bob').get()).data()!['uid'], 'bob');
    await writeEntry(db, 't1', const Entry(uid: 'bob', displayName: 'Bob', status: EntryStatus.joined));
    expect((await db.doc('tournaments/t1/entries/bob').get()).data()!['status'], 'joined');
  });
}
