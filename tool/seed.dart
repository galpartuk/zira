// ignore_for_file: avoid_print
// Generates demo tournaments (JSON) for screenshots / manual testing.
//   dart run tool/seed.dart > seed.json
import 'dart:convert';
import 'dart:math';

import 'package:zira/engine/models.dart';
import 'package:zira/engine/pairing.dart';

const names = [
  'נועם', 'איתי', 'דניאל', 'יואב', 'עומר', 'אורי', 'שירה', 'מאיה', 'רון', 'עידו', 'תמר', 'אלון',
  'גיא', 'ליאור', 'נגה', 'עמית', 'הדר', 'יונתן', 'אביב', 'רותם',
];

void play(Round r, Random rng, {int bo = 1, bool allowOdd = true}) {
  for (final m in r.matches) {
    if (m.isBye || m.result != null) continue;
    final x = rng.nextDouble();
    if (allowOdd && x < .06) {
      m.result = const MatchResult(Outcome.doubleLoss);
    } else if (allowOdd && x < .1) {
      m.result = MatchResult(Outcome.draw, bo > 1 ? 1 : 0, bo > 1 ? 1 : 0);
    } else {
      final p1 = rng.nextBool();
      final close = rng.nextBool();
      m.result = bo > 1
          ? MatchResult(p1 ? Outcome.p1 : Outcome.p2, p1 ? 2 : (close ? 1 : 0), p1 ? (close ? 1 : 0) : 2)
          : MatchResult(p1 ? Outcome.p1 : Outcome.p2, p1 ? 1 : 0, p1 ? 0 : 1);
    }
  }
}

Tournament base(String name, int n, {int top = 0, TFormat f = TFormat.swiss}) {
  final t = Tournament(name: name, format: f, topCut: top, created: DateTime(2026, 11, 8));
  for (var i = 0; i < n; i++) {
    t.players.add(Player(id: newId(), name: names[i]));
  }
  t.swissRounds = recommendedSwissRounds(n);
  return t;
}

void main() {
  final rng = Random(7);

  // 1) Live: 13 players, round 3 of 4 half reported, timer running.
  final live = base('לוקאל דיג׳ימון — שלישי', 13, top: 4);
  live.prizes = PrizeConfig(entryFee: 40, houseCut: 10, step: 5, percents: [40, 25, 17.5, 17.5]);
  for (var r = 0; r < 3; r++) {
    final round = pairSwissRound(live, rng: rng);
    live.rounds.add(round);
    if (r < 2) {
      play(round, rng);
    } else {
      final ms = round.matches.where((m) => !m.isBye).toList();
      play(Round(number: 0, stage: Stage.swiss, matches: ms.take(3).toList()), rng);
    }
  }
  live.players[11].dropped = true;
  live.timerEndMs = DateTime.now().millisecondsSinceEpoch + 17 * 60000 + 42000;

  // 2) Finished: 16 players, top 8 with 3rd place, BO3 top.
  final done = base('גביע החורף 2026', 16, top: 8);
  done.thirdPlace = true;
  done.prizes = PrizeConfig(entryFee: 50, extra: 200, step: 10, percents: [30, 20, 12.5, 12.5, 6.25, 6.25, 6.25, 6.25]);
  for (var r = 0; r < done.swissRounds; r++) {
    final round = pairSwissRound(done, rng: rng);
    done.rounds.add(round);
    play(round, rng);
  }
  Round? nr;
  while ((nr = nextTopRound(done)) != null) {
    done.rounds.add(nr!);
    play(nr, rng, bo: 3, allowOdd: false);
  }
  done.finished = true;

  // 3) Round robin, 6 players, round 2 just paired.
  final rr = base('ליגת חברים', 6, f: TFormat.roundRobin);
  rr.rrSchedule = buildRoundRobinSchedule(rr.players.map((p) => p.id).toList(), rng: rng);
  rr.swissRounds = rr.rrSchedule!.length;
  rr.rounds.add(roundRobinRound(rr));
  play(rr.rounds.last, rng);
  rr.rounds.add(roundRobinRound(rr));

  print(jsonEncode([live.toJson(), done.toJson(), rr.toJson()]));
}
