import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../engine/models.dart';
import '../state/app_state.dart';
import '../theme.dart';

int _remaining(Tournament t) {
  if (t.timerEndMs != null) return t.timerEndMs! - DateTime.now().millisecondsSinceEpoch;
  return t.timerPausedMs ?? t.roundMinutes * 60000;
}

String fmtClock(int ms) {
  final neg = ms < 0;
  final s = (ms.abs() / 1000).ceil();
  final m = s ~/ 60, r = s % 60;
  return '${neg ? '+' : ''}$m:${r.toString().padLeft(2, '0')}';
}

/// Round clock. The end time is stored on the tournament, so it survives
/// leaving the screen or closing the app.
class RoundTimer extends StatefulWidget {
  final Tournament t;
  const RoundTimer({super.key, required this.t});

  @override
  State<RoundTimer> createState() => _RoundTimerState();
}

class _RoundTimerState extends State<RoundTimer> {
  Timer? _tick;
  bool _buzzed = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final t = widget.t;
      if (t.timerEndMs != null) {
        final rem = _remaining(t);
        if (rem <= 0 && !_buzzed) {
          _buzzed = true;
          HapticFeedback.heavyImpact();
          SystemSound.play(SystemSoundType.alert);
        }
        if (rem > 0) _buzzed = false;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final app = context.read<AppState>();
    final running = t.timerEndMs != null;
    final rem = _remaining(t);
    final over = rem <= 0;
    final low = rem < 5 * 60000;
    final color = over ? Z.danger : (low && running ? Z.coral : Z.text);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => _BigTimer(t: t))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(over ? 'הזמן נגמר' : (running ? 'זמן שנותר' : 'שעון סיבוב'),
                    style: TextStyle(fontSize: 12.5, color: over ? Z.danger : Z.muted, fontWeight: FontWeight.w700)),
                Text(fmtClock(rem),
                    style: TextStyle(fontSize: 38, height: 1.1, fontWeight: FontWeight.w800, color: color, fontFeatures: Z.tabular)),
              ]),
            ),
          ),
          IconButton(tooltip: 'מסך מלא', onPressed: () => Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => _BigTimer(t: t))), icon: const Icon(Icons.fullscreen)),
          IconButton(tooltip: 'דקה נוספת', onPressed: () => app.addTimerMinutes(t, 1), icon: const Icon(Icons.more_time)),
          IconButton(tooltip: 'איפוס', onPressed: () => app.resetTimer(t), icon: const Icon(Icons.replay)),
          const SizedBox(width: 4),
          IconButton.filled(
            iconSize: 30,
            style: IconButton.styleFrom(backgroundColor: Z.gold, foregroundColor: Z.ink, fixedSize: const Size(56, 56)),
            onPressed: () => running ? app.pauseTimer(t) : app.startTimer(t),
            icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
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
    WakelockPlus.enable();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final app = context.watch<AppState>();
    final rem = _remaining(t);
    final running = t.timerEndMs != null;
    final over = rem <= 0;
    final r = t.currentRound;
    return Scaffold(
      backgroundColor: over ? const Color(0xFF3A1414) : Z.ink,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(t.name)),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => running ? app.pauseTimer(t) : app.startTimer(t),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (r != null)
              Text(r.stage == Stage.swiss ? 'סיבוב ${r.number}' : 'טופ קאט',
                  style: const TextStyle(fontSize: 26, color: Z.muted, fontWeight: FontWeight.w700)),
            FittedBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(fmtClock(rem),
                    style: TextStyle(
                        fontSize: 180,
                        fontWeight: FontWeight.w800,
                        color: over ? Z.danger : Z.text,
                        fontFeatures: Z.tabular)),
              ),
            ),
            Text(over ? 'הזמן נגמר — מסיימים את הפעולה הנוכחית' : (running ? 'הקישו כדי לעצור' : 'הקישו כדי להפעיל'),
                style: const TextStyle(fontSize: 18, color: Z.muted)),
          ]),
        ),
      ),
    );
  }
}
