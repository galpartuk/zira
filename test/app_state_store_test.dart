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
}
