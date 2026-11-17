import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';
import 'package:zira/l10n.dart';
import 'package:zira/widgets/round_timer.dart';
import 'package:zira/widgets/time_notice.dart';

Tournament withClock(int msLeft) {
  final t = Tournament(
    name: 'T',
    roundMinutes: 45,
    overtimeMinutes: 5,
    players: [
      Player(id: 'a', name: 'Alice', uid: 'alice', tieRand: 1),
      Player(id: 'b', name: 'Bob', uid: 'bob', tieRand: 2),
    ],
  );
  t.rounds.add(
    Round(
      number: 1,
      stage: Stage.swiss,
      matches: [Match(id: 'm1', table: 1, p1: 'a', p2: 'b')],
    ),
  );
  t.timerEndMs = DateTime.now().millisecondsSinceEpoch + msLeft;
  return t;
}

void main() {
  setUp(() => Lang.instance.code = 'en');

  test('no notice while the round clock still runs', () {
    expect(TimeNotice.phaseFor(withClock(60000), 'alice', const NoClaims()), isNull);
  });

  test('overtime and time-up for a player who has not reported', () {
    expect(TimeNotice.phaseFor(withClock(-60000), 'alice', const NoClaims()), ClockPhase.overtime);
    expect(TimeNotice.phaseFor(withClock(-10 * 60000), 'alice', const NoClaims()), ClockPhase.over);
    // The opponent reported but I didn't confirm yet: still my cue.
    const theirs = Pending(Claim(matchId: 'm1', uid: 'bob', result: MatchResult(Outcome.p1, 2, 0), atMs: 1));
    expect(TimeNotice.phaseFor(withClock(-60000), 'alice', theirs), ClockPhase.overtime);
  });

  test('no notice once I reported or the result is in', () {
    const mine = Pending(Claim(matchId: 'm1', uid: 'alice', result: MatchResult(Outcome.p1, 2, 0), atMs: 1));
    expect(TimeNotice.phaseFor(withClock(-60000), 'alice', mine), isNull);
    final t = withClock(-60000)..rounds.single.matches.single.result = const MatchResult(Outcome.p1, 2, 0);
    expect(TimeNotice.phaseFor(t, 'alice', const NoClaims()), isNull);
  });

  testWidgets('the strip shows the time-up text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimeNotice(t: withClock(-10 * 60000), uid: 'alice', state: const NoClaims()),
        ),
      ),
    );
    expect(find.text('Time is up — report your result now'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stop the ticker
  });
}
