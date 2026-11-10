import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../engine/models.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Where the round clock is: regular time, then overtime, then over.
enum ClockPhase { main, overtime, over }

class ClockState {
  final ClockPhase phase;
  final int shownMs; // what the big digits show
  final bool running;
  const ClockState(this.phase, this.shownMs, this.running);
}

ClockState clockOf(Tournament t) {
  final running = t.timerEndMs != null;
  final rem = running ? t.timerEndMs! - DateTime.now().millisecondsSinceEpoch : (t.timerPausedMs ?? t.roundMinutes * 60000);
  final ot = t.overtimeMinutes * 60000;
  if (rem > 0) return ClockState(ClockPhase.main, rem, running);
  if (ot > 0 && rem > -ot) return ClockState(ClockPhase.overtime, ot + rem, running);
  return ClockState(ClockPhase.over, 0, running);
}

String fmtClock(int ms) {
  final s = (ms / 1000).ceil();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Sound + vibration when the clock crosses into overtime and when overtime
/// ends. It rings on the *crossing* only: the last phase seen per tournament
/// is remembered, so two clocks on screen (the card and the full-screen view),
/// pausing/resuming or +1 minute inside overtime, and reopening the app on a
/// clock that is already past its time never ring again.
class RoundAlarm {
  static final _lastPhase = <String, ClockPhase>{};
  static final _player = AudioPlayer();

  /// Records the phase and says whether this is a crossing worth ringing for.
  static bool shouldRing(String id, ClockPhase phase, bool running) {
    final prev = _lastPhase[id];
    _lastPhase[id] = phase;
    if (!running || prev == null || prev == phase) return false;
    return phase.index > prev.index;
  }

  @visibleForTesting
  static void reset() => _lastPhase.clear();

  static void check(Tournament t, ClockState c) {
    if (shouldRing(t.id, c.phase, c.running)) ring(long: c.phase == ClockPhase.over);
  }

  static Future<void> ring({bool long = false}) async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/alarm.wav'), volume: 1);
    } catch (_) {}
    for (var i = 0; i < (long ? 6 : 3); i++) {
      HapticFeedback.vibrate();
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }
}

/// Keeps the screen on while anyone needs it. A counter, so the full-screen
/// clock closing does not switch it off under a still-running round clock.
class KeepAwake {
  static int _holders = 0;

  @visibleForTesting
  static void Function(bool on) apply = (on) => on ? WakelockPlus.enable() : WakelockPlus.disable();

  static void acquire() {
    if (_holders++ == 0) apply(true);
  }

  static void release() {
    if (_holders == 0) return;
    if (--_holders == 0) apply(false);
  }
}

/// Round clock. The end time is stored on the tournament, so it survives
/// leaving the screen or closing the app. The screen stays on while it runs.
class RoundTimer extends StatefulWidget {
  final Tournament t;
  const RoundTimer({super.key, required this.t});

  @override
  State<RoundTimer> createState() => _RoundTimerState();
}

class _RoundTimerState extends State<RoundTimer> {
  Timer? _tick;
  bool _awake = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final c = clockOf(widget.t);
      RoundAlarm.check(widget.t, c);
      _keepAwake(c.running && c.phase != ClockPhase.over);
      if (c.running) setState(() {});
    });
  }

  void _keepAwake(bool on) {
    if (on == _awake) return;
    _awake = on;
    on ? KeepAwake.acquire() : KeepAwake.release();
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_awake) KeepAwake.release();
    super.dispose();
  }

  void _openBig() =>
      Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => _BigTimer(t: widget.t)));

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final app = context.read<AppState>();
    final c = clockOf(t);
    final (label, color, bg) = switch (c.phase) {
      ClockPhase.main => (
          c.running ? 'זמן שנותר' : 'שעון סיבוב · ${t.roundMinutes}′ + ${t.overtimeMinutes}′',
          c.running && c.shownMs < 5 * 60000 ? Z.gold : Z.text,
          Z.surface
        ),
      ClockPhase.overtime => ('תוספת זמן (overtime)', Z.coral, const Color(0xFF3A2620)),
      ClockPhase.over => ('הזמן נגמר', Z.danger, const Color(0xFF3A1A1A)),
    };

    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _openBig,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 12.5, color: c.phase == ClockPhase.main ? Z.muted : color, fontWeight: FontWeight.w700)),
                Text(c.phase == ClockPhase.over ? '0:00' : fmtClock(c.shownMs),
                    style: TextStyle(fontSize: 38, height: 1.1, fontWeight: FontWeight.w800, color: color, fontFeatures: Z.tabular)),
              ]),
            ),
          ),
          IconButton(tooltip: 'מסך מלא', onPressed: _openBig, icon: const Icon(Icons.fullscreen)),
          IconButton(tooltip: 'דקה נוספת', onPressed: () => app.addTimerMinutes(t, 1), icon: const Icon(Icons.more_time)),
          IconButton(tooltip: 'איפוס', onPressed: () => app.resetTimer(t), icon: const Icon(Icons.replay)),
          const SizedBox(width: 4),
          IconButton.filled(
            iconSize: 30,
            style: IconButton.styleFrom(backgroundColor: Z.gold, foregroundColor: Z.ink, fixedSize: const Size(56, 56)),
            onPressed: () => c.running ? app.pauseTimer(t) : app.startTimer(t),
            icon: Icon(c.running ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
        ]),
      ),
    );
  }
}

/// Full-screen clock for showing the room.
class _BigTimer extends StatefulWidget {
  final Tournament t;
  const _BigTimer({required this.t});

  @override
  State<_BigTimer> createState() => _BigTimerState();
}

class _BigTimerState extends State<_BigTimer> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    KeepAwake.acquire();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      RoundAlarm.check(widget.t, clockOf(widget.t));
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    KeepAwake.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final app = context.watch<AppState>();
    final c = clockOf(t);
    final r = t.currentRound;
    final (bg, color, caption) = switch (c.phase) {
      ClockPhase.main => (Z.ink, Z.text, c.running ? 'הקישו כדי לעצור' : 'הקישו כדי להפעיל'),
      ClockPhase.overtime => (const Color(0xFF3A2620), Z.coral, 'OVERTIME — ${t.overtimeMinutes} דקות תוספת'),
      ClockPhase.over => (const Color(0xFF3A1414), Z.danger, 'הזמן נגמר — מסיימים את הפעולה הנוכחית'),
    };
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(t.name)),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => c.running ? app.pauseTimer(t) : app.startTimer(t),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (r != null)
              Text(r.stage == Stage.swiss ? 'סיבוב ${r.number}' : 'טופ קאט',
                  style: const TextStyle(fontSize: 26, color: Z.muted, fontWeight: FontWeight.w700)),
            FittedBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(c.phase == ClockPhase.over ? '0:00' : fmtClock(c.shownMs),
                    style: TextStyle(fontSize: 180, fontWeight: FontWeight.w800, color: color, fontFeatures: Z.tabular)),
              ),
            ),
            Text(caption, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: c.phase == ClockPhase.main ? Z.muted : color)),
          ]),
        ),
      ),
    );
  }
}
