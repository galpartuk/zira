import 'package:flutter_test/flutter_test.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';

void main() {
  group('model fields', () {
    test('Player.uid round-trips and old JSON loads as guest', () {
      final p = Player(id: 'a', name: 'Gal', uid: 'u1', tieRand: 1);
      expect(Player.fromJson(p.toJson()).uid, 'u1');
      expect(Player.fromJson({'id': 'b', 'name': 'B', 'dropped': false, 'tieRand': 2}).uid, isNull);
      expect(Player(id: 'c', name: 'C', tieRand: 3).toJson().containsKey('uid'), isFalse);
    });

    test('Round.published defaults true, false survives JSON', () {
      final r = Round(number: 1, stage: Stage.swiss, matches: []);
      expect(r.published, isTrue);
      expect(r.toJson().containsKey('pub'), isFalse);
      r.published = false;
      expect(Round.fromJson(r.toJson()).published, isFalse);
    });

    test('Tournament joinCode / joinMode round-trip with defaults', () {
      final t = Tournament(name: 'T');
      expect(t.joinMode, 'open');
      expect(t.joinCode, isNull);
      t
        ..joinCode = 'K7Q2XM'
        ..joinMode = 'approval';
      final back = Tournament.fromJson(t.toJson());
      expect(back.joinCode, 'K7Q2XM');
      expect(back.joinMode, 'approval');
    });
  });
  onlineGroups();
}

Tournament online2({String? u1 = 'u1', String? u2 = 'u2'}) {
  final t = Tournament(
    name: 'T',
    players: [
      Player(id: 'a', name: 'A', uid: u1, tieRand: 1),
      Player(id: 'b', name: 'B', uid: u2, tieRand: 2),
    ],
  );
  t.rounds.add(
    Round(
      number: 1,
      stage: Stage.swiss,
      matches: [Match(id: 'm1', table: 1, p1: 'a', p2: 'b')],
    ),
  );
  return t;
}

Claim claim(String uid, Outcome o, [int g1 = 2, int g2 = 1]) =>
    Claim(matchId: 'm1', uid: uid, result: MatchResult(o, g1, g2), atMs: 0);

void onlineGroups() {
  group('manual pairing', () {
    Round r() => Round(
      number: 1,
      stage: Stage.swiss,
      matches: [
        Match(id: 'm1', table: 1, p1: 'a', p2: 'b'),
        Match(id: 'm2', table: 2, p1: 'c', p2: 'd'),
        Match(id: 'bye', table: 0, p1: 'e'),
      ],
    );
    String pairs(Round x) => x.matches.map((m) => '${m.p1}-${m.p2}').join(',');
    test('across tables', () {
      final x = r();
      swapPlayers(x, 'b', 'c');
      expect(pairs(x), 'a-c,b-d,e-null');
    });
    test('with the bye', () {
      final x = r();
      swapPlayers(x, 'a', 'e');
      expect(pairs(x), 'e-b,c-d,a-null');
    });
    test('within a match, or the same player twice', () {
      final x = r();
      swapPlayers(x, 'a', 'b');
      swapPlayers(x, 'c', 'c');
      expect(pairs(x), 'b-a,c-d,e-null');
    });
  });

  group('resolveClaims', () {
    test('no claims', () {
      final t = online2();
      expect(resolveClaims(t, t.rounds[0].matches[0], []), isA<NoClaims>());
    });
    test('one claim vs account holder is pending', () {
      final t = online2();
      final s = resolveClaims(t, t.rounds[0].matches[0], [claim('u1', Outcome.p1)]);
      expect(s, isA<Pending>());
      expect((s as Pending).by.uid, 'u1');
    });
    test('one claim vs guest is confirmed', () {
      final t = online2(u2: null);
      final s = resolveClaims(t, t.rounds[0].matches[0], [claim('u1', Outcome.p1)]);
      expect((s as Confirmed).result.outcome, Outcome.p1);
    });
    test('two equal claims confirm', () {
      final t = online2();
      final s = resolveClaims(t, t.rounds[0].matches[0], [claim('u1', Outcome.p1), claim('u2', Outcome.p1)]);
      expect(s, isA<Confirmed>());
    });
    test('two different claims dispute, p1 claim first', () {
      final t = online2();
      final s = resolveClaims(t, t.rounds[0].matches[0], [claim('u2', Outcome.p2, 1, 2), claim('u1', Outcome.p1)]);
      expect(s, isA<Disputed>());
      expect((s as Disputed).a.uid, 'u1');
      expect(s.b.uid, 'u2');
    });
    test('claims from outsiders or other matches are ignored', () {
      final t = online2();
      final other = Claim(matchId: 'zzz', uid: 'u1', result: const MatchResult(Outcome.p1, 2, 0), atMs: 0);
      expect(resolveClaims(t, t.rounds[0].matches[0], [claim('u9', Outcome.p1), other]), isA<NoClaims>());
    });
    test('guest vs guest never resolves', () {
      final t = online2(u1: null, u2: null);
      expect(resolveClaims(t, t.rounds[0].matches[0], [claim('u1', Outcome.p1)]), isA<NoClaims>());
    });
  });

  group('applyEntries', () {
    test('joined adds a player once, with a unique name', () {
      final t = Tournament(
        name: 'T',
        players: [Player(id: 'x', name: 'Gal', tieRand: 1)],
      );
      final e = Entry(uid: 'u1', displayName: 'Gal', status: EntryStatus.joined);
      expect(applyEntries(t, [e]), isTrue);
      expect(applyEntries(t, [e]), isFalse);
      expect(t.players.where((p) => p.uid == 'u1').single.name, 'Gal 2');
    });
    test('requested adds nothing', () {
      final t = Tournament(name: 'T');
      expect(applyEntries(t, [Entry(uid: 'u1', displayName: 'A', status: EntryStatus.requested)]), isFalse);
      expect(t.players, isEmpty);
    });
    test('dropped before start removes, after start marks dropped', () {
      final t = Tournament(
        name: 'T',
        players: [Player(id: 'a', name: 'A', uid: 'u1', tieRand: 1)],
      );
      applyEntries(t, [Entry(uid: 'u1', displayName: 'A', status: EntryStatus.dropped)]);
      expect(t.players, isEmpty);
      final s = online2();
      applyEntries(s, [Entry(uid: 'u1', displayName: 'A', status: EntryStatus.dropped)]);
      expect(s.player('a')!.dropped, isTrue);
    });
    test('joined is ignored when the event no longer accepts players', () {
      final t = online2()..finished = true;
      expect(applyEntries(t, [Entry(uid: 'u3', displayName: 'C', status: EntryStatus.joined)]), isFalse);
    });
  });

  group('cloud shape', () {
    test('matchUidsFor uses the last published round and skips guests and byes', () {
      final t = online2(u2: null);
      t.rounds[0].matches.add(Match(id: 'bye', table: 2, p1: 'b'));
      expect(matchUidsFor(t), {
        'm1': ['u1'],
      });
      t.rounds[0].published = false;
      expect(matchUidsFor(t), isEmpty);
    });
    test('publishedJson drops the draft; draftRound returns it', () {
      final t = online2();
      t.rounds.add(Round(number: 2, stage: Stage.swiss, matches: [], published: false));
      expect((publishedJson(t)['rounds'] as List).length, 1);
      expect(draftRound(t)!.number, 2);
      t.rounds.last.published = true;
      expect(draftRound(t), isNull);
    });
    test('onlineStatus', () {
      expect(onlineStatus(Tournament(name: 'T')), 'registration');
      final t = online2();
      expect(onlineStatus(t), 'running');
      t.finished = true;
      expect(onlineStatus(t), 'finished');
    });
  });
}
