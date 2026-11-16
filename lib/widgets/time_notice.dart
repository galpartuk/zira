import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../engine/online.dart';
import '../l10n.dart';
import '../theme.dart';
import 'my_match_card.dart';
import 'round_timer.dart';

/// For players (silent — only the host's phone rings): a strip on top of the
/// screen once the round clock reaches overtime or runs out, shown only while
/// my match has no result and I haven't reported it myself.
class TimeNotice extends StatefulWidget {
  final Tournament t;
  final String uid;
  final ClaimState state;
  const TimeNotice({super.key, required this.t, required this.uid, required this.state});

  /// Which notice applies right now, or null.
  static ClockPhase? phaseFor(Tournament t, String uid, ClaimState state) {
    final info = MyMatchInfo.of(t, uid);
    if (info == null || info.match.isBye || info.match.result != null || t.finished) return null;
    if (state is Pending && state.by.uid == uid) return null; // I already reported
    if (state is Disputed) return null;
    final c = clockOf(t);
    if (!c.running && c.phase == ClockPhase.main) return null;
    return c.phase == ClockPhase.main ? null : c.phase;
  }

  @override
  State<TimeNotice> createState() => _TimeNoticeState();
}

class _TimeNoticeState extends State<TimeNotice> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = TimeNotice.phaseFor(widget.t, widget.uid, widget.state);
    if (phase == null) return const SizedBox.shrink();
    final over = phase == ClockPhase.over;
    final color = over ? Z.danger : Z.coral;
    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(over ? Icons.timer_off_rounded : Icons.more_time_rounded, color: Z.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(over ? S.t.timeUpNotice : S.t.overtimeNotice,
                style: const TextStyle(color: Z.ink, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ]),
      ),
    );
  }
}
