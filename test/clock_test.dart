import 'package:flutter_test/flutter_test.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/prizes.dart';
import 'package:zira/widgets/round_timer.dart';

void main() {
  int now() => DateTime.now().millisecondsSinceEpoch;

  test('defaults: no top cut, BO3, 45 + 5 minutes, packs one each', () {
    final t = Tournament(name: 'x');
    expect(t.topCut, 0);
    expect(t.swissBestOf, 3);
    expect(t.roundMinutes, 45);
    expect(t.overtimeMinutes, 5);
    expect(t.prizes.unit, PrizeConfig.packs);
    expect(t.prizes.entryFee, 1);
    // 12 players → 12 packs to hand out.
    expect(computePrizes(t.prizes, 12).net, 12);
  });

  test('clock runs main time, then overtime, then over', () {
    final t = Tournament(name: 'x', roundMinutes: 45, overtimeMinutes: 5);
    expect(clockOf(t).phase, ClockPhase.main);
    expect(clockOf(t).shownMs, 45 * 60000);
    expect(clockOf(t).running, isFalse);

    t.timerEndMs = now() + 60000;
    expect(clockOf(t).phase, ClockPhase.main);

    t.timerEndMs = now() - 60000; // 1 minute past regular time
    final ot = clockOf(t);
    expect(ot.phase, ClockPhase.overtime);
    expect(ot.shownMs, closeTo(4 * 60000, 1000));

    t.timerEndMs = now() - 6 * 60000;
    expect(clockOf(t).phase, ClockPhase.over);
  });

  test('pausing in overtime keeps the overtime position', () {
    final t = Tournament(name: 'x', overtimeMinutes: 5)..timerPausedMs = -2 * 60000;
    final c = clockOf(t);
    expect(c.phase, ClockPhase.overtime);
    expect(c.shownMs, 3 * 60000);
  });

  test('no overtime configured goes straight to over', () {
    final t = Tournament(name: 'x', overtimeMinutes: 0)..timerEndMs = now() - 1000;
    expect(clockOf(t).phase, ClockPhase.over);
  });
}
