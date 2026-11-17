import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zira/engine/memory.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/pairing.dart';
import 'package:zira/engine/prizes.dart';
import 'package:zira/engine/standings.dart';

Tournament makeT(int n, {TFormat format = TFormat.swiss, int rounds = 0, int top = 0}) {
  final t = Tournament(name: 'T', format: format, topCut: top);
  for (var i = 0; i < n; i++) {
    t.players.add(Player(id: 'p$i', name: 'P$i', tieRand: i));
  }
  t.swissRounds = rounds == 0 ? recommendedSwissRounds(n) : rounds;
  if (format == TFormat.roundRobin) {
    t.rrSchedule = buildRoundRobinSchedule(t.players.map((p) => p.id).toList(), rng: Random(1));
  }
  return t;
}

/// Reports every pending match: the lower id wins (deterministic).
void playOut(Round r, {Random? rng}) {
  for (final m in r.matches) {
    if (m.isBye || m.result != null) continue;
    final p1Wins = rng != null ? rng.nextBool() : m.p1.compareTo(m.p2!) < 0;
    m.result = MatchResult(p1Wins ? Outcome.p1 : Outcome.p2, p1Wins ? 1 : 0, p1Wins ? 0 : 1);
  }
}

void main() {
  group('standings', () {
    test('points, OMW and OOMW with a hand-checked example', () {
      final t = makeT(4, rounds: 2);
      // R1: p0 beats p1, p2 beats p3. R2: p0 beats p2, p1 beats p3.
      t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [
        Match(table: 1, p1: 'p0', p2: 'p1', result: const MatchResult(Outcome.p1, 1, 0)),
        Match(table: 2, p1: 'p2', p2: 'p3', result: const MatchResult(Outcome.p1, 1, 0)),
      ]));
      t.rounds.add(Round(number: 2, stage: Stage.swiss, matches: [
        Match(table: 1, p1: 'p0', p2: 'p2', result: const MatchResult(Outcome.p1, 1, 0)),
        Match(table: 2, p1: 'p1', p2: 'p3', result: const MatchResult(Outcome.p1, 1, 0)),
      ]));
      final s = {for (final x in computeStandings(t)) x.player.id: x};
      expect(s['p0']!.points, 6);
      expect(s['p1']!.points, 3);
      expect(s['p2']!.points, 3);
      expect(s['p3']!.points, 0);
      // p1 opps: p0 (1.0), p3 (0 → floor .33)  => .665
      expect(s['p1']!.omw, closeTo((1.0 + 0.33) / 2, 1e-9));
      // p2 opps: p3 (.33), p0 (1.0) => same OMW as p1 -> OOMW decides
      expect(s['p2']!.omw, closeTo((1.0 + 0.33) / 2, 1e-9));
      final ranks = computeStandings(t).map((x) => x.player.id).toList();
      expect(ranks.first, 'p0');
      expect(ranks.last, 'p3');
    });

    test('standings before a round ignore that round and later ones', () {
      final t = makeT(3, rounds: 2);
      t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [
        Match(table: 1, p1: 'p0', p2: 'p1', result: const MatchResult(Outcome.p1, 1, 0)),
        Match(table: 0, p1: 'p2'),
      ]));
      t.rounds.add(Round(number: 2, stage: Stage.swiss, matches: [
        Match(table: 1, p1: 'p0', p2: 'p2'),
        Match(table: 0, p1: 'p1'), // the round-1 loser gets the bye
      ]));
      final before2 = {for (final s in computeStandings(t, beforeRound: 1)) s.player.id: s};
      expect(before2['p1']!.points, 0);
      expect(before2['p1']!.record, '0-1');
      final before1 = {for (final s in computeStandings(t, beforeRound: 0)) s.player.id: s};
      expect(before1.values.every((s) => s.points == 0), isTrue);
      // Current standings still count the bye.
      expect({for (final s in computeStandings(t)) s.player.id: s}['p1']!.points, 3);
    });

    test('double loss gives no points to either player', () {
      final t = makeT(2, rounds: 1);
      t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [
        Match(table: 1, p1: 'p0', p2: 'p1', result: const MatchResult(Outcome.doubleLoss)),
      ]));
      final s = computeStandings(t);
      expect(s.every((x) => x.points == 0 && x.losses == 1), isTrue);
    });

    test('draw is 1 point each', () {
      final t = makeT(2, rounds: 1);
      t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [
        Match(table: 1, p1: 'p0', p2: 'p1', result: const MatchResult(Outcome.draw, 1, 1)),
      ]));
      expect(computeStandings(t).every((x) => x.points == 1 && x.draws == 1), isTrue);
    });

    test('bye is a win worth 3 and not counted as an opponent', () {
      final t = makeT(3, rounds: 1);
      t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [
        Match(table: 1, p1: 'p0', p2: 'p1', result: const MatchResult(Outcome.p1, 1, 0)),
        Match(table: 0, p1: 'p2'),
      ]));
      final s = {for (final x in computeStandings(t)) x.player.id: x};
      expect(s['p2']!.points, 3);
      expect(s['p2']!.opponents, isEmpty);
      expect(s['p2']!.omw, 0);
    });
  });

  group('swiss pairing', () {
    for (final n in [4, 5, 7, 8, 9, 13, 16, 17, 32, 33, 64]) {
      test('$n players: no rematches, at most one bye each, everyone plays every round', () {
        final rng = Random(n);
        final t = makeT(n);
        for (var r = 0; r < t.swissRounds; r++) {
          final round = pairSwissRound(t, rng: rng);
          final seen = <String>{};
          for (final m in round.matches) {
            expect(seen.add(m.p1), isTrue);
            if (m.p2 != null) expect(seen.add(m.p2!), isTrue);
          }
          expect(seen.length, n);
          expect(round.matches.where((m) => m.isBye).length, n.isOdd ? 1 : 0);
          t.rounds.add(round);
          playOut(round, rng: rng);
        }
        // No rematch.
        final pairs = <String>{};
        for (final r in t.rounds) {
          for (final m in r.matches.where((m) => !m.isBye)) {
            final k = ([m.p1, m.p2!]..sort()).join();
            expect(pairs.add(k), isTrue, reason: 'rematch $k');
          }
        }
        // Byes go to different players.
        final byes = t.rounds.expand((r) => r.matches.where((m) => m.isBye).map((m) => m.p1)).toList();
        expect(byes.toSet().length, byes.length);
      });
    }

    test('players are paired within their point group when possible', () {
      final t = makeT(8, rounds: 3);
      final rng = Random(3);
      final r1 = pairSwissRound(t, rng: rng);
      t.rounds.add(r1);
      playOut(r1);
      final r2 = pairSwissRound(t, rng: rng);
      final pts = {for (final s in computeStandings(t)) s.player.id: s.points};
      for (final m in r2.matches) {
        expect(pts[m.p1], pts[m.p2]);
      }
    });

    test('dropped players are not paired', () {
      final t = makeT(6, rounds: 3);
      t.players[0].dropped = true;
      final r = pairSwissRound(t, rng: Random(1));
      expect(r.matches.any((m) => m.involves('p0')), isFalse);
      expect(r.matches.where((m) => m.isBye).length, 1);
    });

    test('bye goes to the lowest ranked player without a bye', () {
      final t = makeT(5, rounds: 3);
      final rng = Random(9);
      final r1 = pairSwissRound(t, rng: rng);
      t.rounds.add(r1);
      playOut(r1);
      final standings = computeStandings(t);
      final r2 = pairSwissRound(t, rng: rng);
      final bye = r2.matches.firstWhere((m) => m.isBye).p1;
      final hadBye = r1.matches.firstWhere((m) => m.isBye).p1;
      final expected = standings.reversed.firstWhere((s) => s.player.id != hadBye).player.id;
      expect(bye, expected);
    });

    test('falls back to a rematch only when there is no legal pairing', () {
      final t = makeT(2, rounds: 3);
      for (var i = 0; i < 3; i++) {
        final r = pairSwissRound(t, rng: Random(i));
        expect(r.matches.length, 1);
        t.rounds.add(r);
        playOut(r);
      }
    });
  });

  group('round robin', () {
    for (final n in [3, 4, 5, 6, 7, 10]) {
      test('$n players meet each other exactly once', () {
        final t = makeT(n, format: TFormat.roundRobin);
        expect(t.rrSchedule!.length, rrRoundCount(n));
        final pairs = <String>{};
        for (var r = 0; r < t.rrSchedule!.length; r++) {
          final round = roundRobinRound(t);
          t.rounds.add(round);
          playOut(round);
          for (final m in round.matches.where((m) => !m.isBye)) {
            expect(pairs.add(([m.p1, m.p2!]..sort()).join('|')), isTrue);
          }
        }
        expect(pairs.length, n * (n - 1) ~/ 2);
      });
    }

    test('match against a dropped player becomes a bye', () {
      final t = makeT(4, format: TFormat.roundRobin);
      t.players[1].dropped = true;
      final r = roundRobinRound(t);
      expect(r.matches.any((m) => m.involves('p1')), isFalse);
      expect(r.matches.where((m) => m.isBye).length, 1);
    });
  });

  group('top cut', () {
    test('bracket order', () {
      expect(bracketOrder(2), [1, 2]);
      expect(bracketOrder(4), [1, 4, 2, 3]);
      expect(bracketOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
    });

    test('top 8 with third place runs to a full final order', () {
      final t = makeT(16, rounds: 4, top: 8)..thirdPlace = true;
      final rng = Random(5);
      for (var r = 0; r < 4; r++) {
        final round = pairSwissRound(t, rng: rng);
        t.rounds.add(round);
        playOut(round, rng: rng);
      }
      final seeds = topCutQualifiers(t);
      expect(seeds.length, 8);
      final q = firstTopRound(t);
      expect(q.matches.first.p1, seeds[0]);
      expect(q.matches.first.p2, seeds[7]);
      t.rounds.add(q);
      playOut(q, rng: rng);
      final semis = nextTopRound(t)!;
      expect(semis.matches.length, 2);
      t.rounds.add(semis);
      playOut(semis, rng: rng);
      final fin = nextTopRound(t)!;
      expect(fin.matches.length, 2); // final + 3rd place
      expect(fin.matches.where((m) => m.thirdPlace).length, 1);
      t.rounds.add(fin);
      expect(topCutFinished(t), isFalse);
      playOut(fin, rng: rng);
      expect(topCutFinished(t), isTrue);
      expect(nextTopRound(t), isNull);

      final pl = finalPlacements(t);
      expect(pl.length, 16);
      expect(pl.map((p) => p.playerId).toSet().length, 16);
      expect(pl[0].playerId, fin.matches.first.winner);
      expect(pl[1].playerId, fin.matches.first.loser);
      expect(pl[2].playerId, fin.matches.last.winner);
      expect(pl[2].label, '3');
      expect(pl[4].label, '5-8');
      expect(pl[7].label, '5-8');
      expect(pl[8].label, '9');
      expect(pl.take(8).map((p) => p.playerId).toSet(), seeds.toSet());
    });

    test('without third place the semifinal losers share 3-4', () {
      final t = makeT(8, rounds: 3, top: 4);
      final rng = Random(2);
      for (var r = 0; r < 3; r++) {
        final round = pairSwissRound(t, rng: rng);
        t.rounds.add(round);
        playOut(round, rng: rng);
      }
      Round? r;
      while ((r = nextTopRound(t)) != null) {
        t.rounds.add(r!);
        playOut(r, rng: rng);
      }
      final pl = finalPlacements(t);
      expect(pl[2].label, '3-4');
      expect(pl[3].label, '3-4');
    });

    test('before the cut, a dropped leader is placed after the qualifiers', () {
      final t = makeT(8, rounds: 3, top: 4);
      final rng = Random(11);
      for (var r = 0; r < 3; r++) {
        final round = pairSwissRound(t, rng: rng);
        t.rounds.add(round);
        playOut(round, rng: rng);
      }
      final leader = computeStandings(t).first.player;
      leader.dropped = true;
      final pl = finalPlacements(t);
      expect(pl.take(4).any((p) => p.playerId == leader.id), isFalse);
      expect(pl[4].playerId, leader.id);
      expect(pl.length, 8);
    });

    test('top cut shrinks when too few active players', () {
      final t = makeT(6, top: 8);
      expect(effectiveTopCut(t), 4);
      t.players[0].dropped = true;
      t.players[1].dropped = true;
      t.players[2].dropped = true;
      expect(effectiveTopCut(t), 2);
    });
  });

  group('prizes', () {
    test('pool, house cut and percent split', () {
      final c = PrizeConfig(entryFee: 40, extra: 0, houseCut: 10, step: 1, percents: [50, 30, 20]);
      final r = computePrizes(c, 20);
      expect(r.gross, 800);
      expect(r.houseAmount, 80);
      expect(r.net, 720);
      expect(r.lines.map((l) => l.amount).toList(), [360, 216, 144]);
      expect(r.leftover, 0);
    });

    test('rounding to 10 never exceeds the pool', () {
      final c = PrizeConfig(entryFee: 35, step: 10, percents: [50, 30, 20]);
      final r = computePrizes(c, 13); // 455
      expect(r.distributed <= r.net, isTrue);
      expect(r.lines.every((l) => l.amount % 10 == 0), isTrue);
      expect(r.leftover, r.net - r.distributed);
    });

    test('packs: whole numbers that add up exactly', () {
      final c = PrizeConfig(unit: PrizeConfig.packs, entryFee: 0, extra: 24, step: 1, splitTies: false, percents: [40, 25, 17.5, 17.5]);
      final r = computePrizes(c, 10);
      expect(r.lines.every((l) => l.amount == l.amount.roundToDouble()), isTrue);
      expect(r.distributed, 24);
    });

    test('tie groups are paid equally', () {
      final t = makeT(8, rounds: 3, top: 4);
      final rng = Random(4);
      for (var i = 0; i < 3; i++) {
        final round = pairSwissRound(t, rng: rng);
        t.rounds.add(round);
        playOut(round, rng: rng);
      }
      Round? r;
      while ((r = nextTopRound(t)) != null) {
        t.rounds.add(r!);
        playOut(r, rng: rng);
      }
      final c = PrizeConfig(entryFee: 30, step: 1, percents: [50, 30, 20]);
      final res = computePrizes(c, 8, placements: finalPlacements(t));
      // 3rd's 20% is split between the two semifinal losers.
      expect(res.lines.length, 4);
      expect(res.lines[2].amount, res.lines[3].amount);
      expect(res.lines[2].percent, 10);
      expect(res.distributed <= res.net, isTrue);
    });

    test('helpers', () {
      expect(flatPercents(4), [25, 25, 25, 25]);
      expect(steppedPercents(3).fold<double>(0, (a, b) => a + b), closeTo(100, 0.05));
      expect(normalisePercents([1, 1]), [50, 50]);
    });
  });

  group('memory gauge', () {
    test('paying past zero moves the memory but never passes the turn by itself', () {
      var m = const MemoryState(); // bottom's turn at 0
      m = m.adjust(Side.bottom, 3); // gains 3 -> +3
      expect(m.value, 3);
      m = m.adjust(Side.bottom, -5); // pays 5 -> 2 on top's side
      expect(m.value, -2);
      expect(m.memoryFor(Side.top), 2);
      expect(m.turn, Side.bottom); // still bottom's turn until they end it
      expect(m.turnNumber, 1);
      expect(m.setTo(-7).turn, Side.bottom);
    });

    test('ending the turn hands it over and leaves the memory alone', () {
      final m = const MemoryState(value: -2).endTurn();
      expect(m.value, -2);
      expect(m.turn, Side.top);
      expect(m.turnNumber, 2);
      final m2 = m.endTurn();
      expect(m2.value, -2);
      expect(m2.turn, Side.bottom);
      expect(m2.turnNumber, 3);
    });

    test('a cost past the opponent\'s 10 cannot be paid', () {
      const m = MemoryState(value: 3); // bottom has 3
      expect(m.canPay(Side.bottom, 13), isTrue); // lands exactly on the opponent's 10
      expect(m.adjust(Side.bottom, -13).value, -10);
      expect(m.canPay(Side.bottom, 14), isFalse);
      expect(m.adjust(Side.bottom, -14).value, 3); // illegal: nothing moves
      // From the top player's seat the same 3 is "3 on the opponent's side": they can pay up to 7.
      expect(m.canPay(Side.top, 7), isTrue);
      expect(m.canPay(Side.top, 8), isFalse);
    });

    test('gauge is capped at 10', () {
      final m = const MemoryState(value: 9).adjust(Side.bottom, 5);
      expect(m.value, 10);
      expect(const MemoryState(turn: Side.top).setTo(-15).value, -10);
    });
  });

  test('tournament json round trip', () {
    final t = makeT(6, rounds: 3, top: 4);
    final r = pairSwissRound(t, rng: Random(1));
    t.rounds.add(r);
    playOut(r);
    t.prizes.percents = [60, 40];
    final back = Tournament.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), jsonEncode(t.toJson()));
  });

  test('prize unit: old Hebrew / symbol values load as language-neutral codes', () {
    PrizeConfig load(Object? unit) => PrizeConfig.fromJson({if (unit != null) 'unit': unit, 'fee': 1});
    expect(load('חבילות').unit, PrizeConfig.packs);
    expect(load('בוסטרים').unit, PrizeConfig.packs);
    expect(load('₪').unit, PrizeConfig.ils);
    expect(load(null).unit, PrizeConfig.ils); // the very first saves had money only
    expect(load('packs').unit, PrizeConfig.packs);
    expect(load('ILS').unit, PrizeConfig.ils);
    expect(load('₪').isMoney, isTrue);
    // Saved back as the code.
    expect(load('חבילות').toJson()['unit'], 'packs');
  });

  test('old double-loss results still load and give no points', () {
    final r = MatchResult.fromJson({'o': 3, 'g1': 0, 'g2': 0});
    expect(r.outcome, Outcome.doubleLoss);
  });
}
