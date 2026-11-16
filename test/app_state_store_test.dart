import 'package:flutter_test/flutter_test.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/state/app_state.dart';

class MemStore implements TournamentStore {
  List<Tournament> saved = [];
  final deleted = <String>[];
  int saves = 0;
  @override
  Future<List<Tournament>> load() async => saved;
  @override
  Future<void> saveAll(List<Tournament> ts) async {
    saves++;
    saved = [...ts];
  }
  @override
  Future<void> delete(Tournament t) async => deleted.add(t.id);
}

Tournament four() => Tournament(name: 'T', players: [
      for (var i = 0; i < 4; i++) Player(id: 'p$i', name: 'P$i', tieRand: i),
    ]);

void main() {
  test('local mode publishes rounds immediately (old behaviour)', () async {
    final app = AppState(store: MemStore());
    await app.load();
    final t = four();
    app.add(t);
    app.start(t);
    expect(t.rounds.single.published, isTrue);
  });

  test('draft mode: start makes a draft, publish sends it, results blocked on drafts', () async {
    final store = MemStore();
    final app = AppState(store: store, draftRounds: true);
    await app.load();
    final t = four();
    app.add(t);
    app.start(t);
    final r = t.rounds.single;
    expect(r.published, isFalse);
    app.setResult(t, r.matches.first, const MatchResult(Outcome.p1, 2, 0));
    expect(r.matches.first.result, isNull);
    app.publish(t);
    expect(r.published, isTrue);
    app.setResult(t, r.matches.first, const MatchResult(Outcome.p1, 2, 0));
    expect(r.matches.first.result, isNotNull);
  });

  test('advance does nothing while a draft is pending; repair keeps it a draft', () async {
    final app = AppState(store: MemStore(), draftRounds: true);
    await app.load();
    final t = four();
    app.add(t);
    app.start(t);
    app.advance(t);
    expect(t.rounds.length, 1);
    app.repair(t);
    expect(t.rounds.single.published, isFalse);
  });

  test('remove calls store.delete; attach reloads from the new store', () async {
    final a = MemStore();
    final app = AppState(store: a);
    await app.load();
    final t = four();
    app.add(t);
    app.remove(t);
    expect(a.deleted, [t.id]);
    final b = MemStore()..saved = [four()];
    await app.attach(b, draftRounds: true);
    expect(app.tournaments.length, 1);
    expect(app.draftRounds, isTrue);
    app.detach();
    expect(app.tournaments, isEmpty);
    expect(app.draftRounds, isFalse);
  });

  test('opened with no players: Swiss rounds follow the head count until the start', () async {
    final app = AppState(store: MemStore(), draftRounds: true);
    await app.load();
    final t = Tournament(name: 'T', swissRounds: recommendedSwissRounds(0), autoRounds: true);
    app.add(t);
    for (var i = 0; i < 12; i++) {
      t.players.add(Player(id: 'p$i', name: 'P$i', tieRand: i));
    }
    app.changed();
    expect(t.swissRounds, 4); // 9-16 players
    app.start(t);
    expect(t.swissRounds, 4);
    t.players.add(Player(id: 'late', name: 'Late', tieRand: 99)); // late entry: no change once started
    app.changed();
    expect(t.swissRounds, 4);
  });

  test('rounds the host picked by hand are kept', () async {
    final app = AppState(store: MemStore());
    await app.load();
    final t = Tournament(name: 'T', swissRounds: 6, autoRounds: false);
    app.add(t);
    for (var i = 0; i < 4; i++) {
      t.players.add(Player(id: 'p$i', name: 'P$i', tieRand: i));
    }
    app.changed();
    expect(t.swissRounds, 6);
  });

  test('autoRounds survives JSON, old saves load as manual', () {
    final t = Tournament(name: 'T', autoRounds: true);
    expect(Tournament.fromJson(t.toJson()).autoRounds, isTrue);
    expect(Tournament.fromJson(Tournament(name: 'T').toJson()).autoRounds, isFalse);
  });
}
