import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/pairing.dart';
import 'package:zira/state/app_state.dart';
import 'package:zira/widgets/round_timer.dart';

import 'engine_test.dart' show makeT, playOut;

/// Regression tests for the bugs found in the November 2026 review. Each one
/// failed before its fix.
void main() {
  Tournament swissDone(int n, int rounds, int top, int seed) {
    final t = makeT(n, rounds: rounds, top: top);
    final rng = Random(seed);
    for (var r = 0; r < rounds; r++) {
      final round = pairSwissRound(t, rng: rng);
      t.rounds.add(round);
      playOut(round, rng: rng);
    }
    return t;
  }

  group('placements during an unfinished top cut', () {
    test('quarterfinal losers are not placed above the players still in the bracket', () {
      final t = swissDone(16, 4, 8, 5);
      final qf = nextTopRound(t)!;
      t.rounds.add(qf);
      playOut(qf, rng: Random(3));
      final alive = qf.matches.map((m) => m.winner!).toSet();
      final out = qf.matches.map((m) => m.loser!).toSet();
      final pl = finalPlacements(t);
      expect(pl.take(4).map((p) => p.playerId).toSet(), alive);
      expect(pl.skip(4).take(4).map((p) => p.playerId).toSet(), out);
      expect(pl[4].label, '5-8');
    });

    test('a decided 3rd-place match does not put its winner above the finalists', () {
      final t = swissDone(8, 3, 4, 2)..thirdPlace = true;
      final semis = nextTopRound(t)!;
      t.rounds.add(semis);
      playOut(semis, rng: Random(1));
      final fin = nextTopRound(t)!;
      t.rounds.add(fin);
      final third = fin.matches.firstWhere((m) => m.thirdPlace);
      third.result = const MatchResult(Outcome.p1, 2, 0); // final still pending
      final finalists = semis.matches.map((m) => m.winner!).toSet();
      final pl = finalPlacements(t);
      expect(pl.take(2).map((p) => p.playerId).toSet(), finalists);
      expect(pl[2].playerId, third.p1);
      expect(pl[3].playerId, third.p2);
    });
  });

  test('top cut size is fixed once the cut has started, even if a player in it drops', () {
    final t = swissDone(8, 3, 8, 4);
    t.rounds.add(nextTopRound(t)!);
    expect(effectiveTopCut(t), 8);
    t.player(t.topRoundsList.first.matches.first.p2)!.dropped = true;
    expect(effectiveTopCut(t), 8);
  });

  test('no late entries once no more Swiss rounds will be paired', () {
    final t = makeT(6, rounds: 2);
    expect(t.acceptsNewPlayers, isTrue);
    t.rounds.add(pairSwissRound(t, rng: Random(1)));
    expect(t.acceptsNewPlayers, isTrue); // round 2 still to come
    playOut(t.rounds.last);
    t.rounds.add(pairSwissRound(t, rng: Random(1)));
    expect(t.acceptsNewPlayers, isFalse); // last round: a newcomer would never play
    final rr = makeT(4, format: TFormat.roundRobin);
    expect(rr.acceptsNewPlayers, isTrue);
    rr.rounds.add(roundRobinRound(rr));
    expect(rr.acceptsNewPlayers, isFalse);
  });

  test('cannot pair the next round while an earlier round is missing a result', () {
    final app = AppState();
    final t = makeT(6, rounds: 3);
    app.tournaments.add(t);
    app.start(t);
    playOut(t.rounds.last);
    app.advance(t);
    playOut(t.rounds.last);
    // Clear a result in round 1 after round 2 was played.
    t.rounds.first.matches.firstWhere((m) => !m.isBye).result = null;
    expect(t.firstIncompleteRound, t.rounds.first);
    app.advance(t);
    expect(t.rounds.length, 2);
  });

  test('a bad backup leaves the existing tournaments untouched', () {
    final app = AppState();
    final keep = makeT(4)..name = 'keep';
    app.tournaments.add(keep);
    final good = jsonEncode(keep.toJson()..['name'] = 'replaced');
    expect(() => app.importAll('[$good, {"id": 1}]'), throwsA(anything));
    expect(app.tournaments.single.name, 'keep');
  });

  group('round alarm', () {
    setUp(RoundAlarm.reset);

    test('rings once when crossing into overtime, not again on pause/resume or +1 minute', () {
      expect(RoundAlarm.shouldRing('t', ClockPhase.main, true), isFalse);
      expect(RoundAlarm.shouldRing('t', ClockPhase.overtime, true), isTrue);
      expect(RoundAlarm.shouldRing('t', ClockPhase.overtime, true), isFalse);
      // Pause, resume (new end time) and +1 minute still inside overtime.
      expect(RoundAlarm.shouldRing('t', ClockPhase.overtime, false), isFalse);
      expect(RoundAlarm.shouldRing('t', ClockPhase.overtime, true), isFalse);
      expect(RoundAlarm.shouldRing('t', ClockPhase.over, true), isTrue);
      expect(RoundAlarm.shouldRing('t', ClockPhase.over, true), isFalse);
    });

    test('does not ring for a clock that was already past its time when the app opened', () {
      expect(RoundAlarm.shouldRing('t', ClockPhase.over, true), isFalse);
      expect(RoundAlarm.shouldRing('u', ClockPhase.overtime, true), isFalse);
      expect(RoundAlarm.shouldRing('u', ClockPhase.over, true), isTrue);
    });

    test('rings again after a reset or after +1 minute took it back to main time', () {
      RoundAlarm.shouldRing('t', ClockPhase.main, true);
      expect(RoundAlarm.shouldRing('t', ClockPhase.overtime, true), isTrue);
      expect(RoundAlarm.shouldRing('t', ClockPhase.main, false), isFalse);
      expect(RoundAlarm.shouldRing('t', ClockPhase.overtime, true), isTrue);
    });

    test('a paused clock never rings', () {
      RoundAlarm.shouldRing('t', ClockPhase.main, false);
      expect(RoundAlarm.shouldRing('t', ClockPhase.overtime, false), isFalse);
    });
  });

  test('closing the full-screen clock keeps the screen awake while the round clock still needs it', () {
    final calls = <bool>[];
    KeepAwake.apply = calls.add;
    KeepAwake.acquire(); // round clock running
    KeepAwake.acquire(); // full-screen view opened
    KeepAwake.release(); // full-screen view closed
    expect(calls, [true]);
    KeepAwake.release();
    expect(calls, [true, false]);
  });
}
