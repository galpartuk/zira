import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/models.dart';
import '../engine/pairing.dart';

/// All tournaments, persisted to SharedPreferences as JSON after every change.
class AppState extends ChangeNotifier {
  static const _key = 'zira.tournaments.v1';

  final List<Tournament> tournaments = [];
  bool loaded = false;
  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        tournaments
          ..clear()
          ..addAll(list.map((e) => Tournament.fromJson(e as Map<String, dynamic>)));
      } catch (e) {
        debugPrint('load failed: $e');
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs?.setString(_key, jsonEncode(tournaments.map((t) => t.toJson()).toList()));
  }

  /// Call after mutating a tournament in place.
  void changed() {
    notifyListeners();
    _save();
  }

  Tournament? byId(String id) {
    for (final t in tournaments) {
      if (t.id == id) return t;
    }
    return null;
  }

  void add(Tournament t) {
    tournaments.insert(0, t);
    changed();
  }

  void remove(Tournament t) {
    tournaments.remove(t);
    changed();
  }

  String exportAll() => const JsonEncoder.withIndent(' ').convert(tournaments.map((t) => t.toJson()).toList());

  /// Imports tournaments from a backup; ones that already exist are replaced.
  int importAll(String raw) {
    final decoded = jsonDecode(raw);
    final list = decoded is List ? decoded : [decoded];
    var n = 0;
    for (final e in list) {
      final t = Tournament.fromJson(e as Map<String, dynamic>);
      tournaments.removeWhere((x) => x.id == t.id);
      tournaments.insert(0, t);
      n++;
    }
    changed();
    return n;
  }

  // ------------------------------------------------------------ flow

  void start(Tournament t) {
    if (t.format == TFormat.roundRobin) {
      t.rrSchedule = buildRoundRobinSchedule(t.activePlayers.map((p) => p.id).toList());
      t.swissRounds = t.rrSchedule!.length;
      t.rounds.add(roundRobinRound(t));
    } else {
      t.rounds.add(pairSwissRound(t));
    }
    resetTimer(t, notify: false);
    changed();
  }

  /// Generates whatever comes next: a Swiss round, the first / next bracket
  /// round, or marks the tournament finished.
  void advance(Tournament t) {
    if (!t.swissDone) {
      t.rounds.add(t.format == TFormat.roundRobin ? roundRobinRound(t) : pairSwissRound(t));
    } else if (effectiveTopCut(t) > 0 && !topCutFinished(t)) {
      final r = nextTopRound(t);
      if (r != null) t.rounds.add(r);
    } else {
      t.finished = true;
    }
    resetTimer(t, notify: false);
    changed();
  }

  /// Throws away the current round (only allowed before any result) and pairs
  /// it again.
  void repair(Tournament t) {
    final r = t.currentRound;
    if (r == null || r.anyResult) return;
    t.rounds.removeLast();
    if (r.stage == Stage.swiss) {
      t.rounds.add(t.format == TFormat.roundRobin ? roundRobinRound(t) : pairSwissRound(t));
    } else {
      final n = nextTopRound(t);
      if (n != null) t.rounds.add(n);
    }
    changed();
  }

  /// Removes the current round entirely (only before any result).
  void undoRound(Tournament t) {
    final r = t.currentRound;
    if (r == null || r.anyResult) return;
    t.rounds.removeLast();
    if (t.rounds.isEmpty) t.rrSchedule = null;
    t.finished = false;
    changed();
  }

  void setResult(Tournament t, Match m, MatchResult? r) {
    m.result = r;
    changed();
  }

  // ------------------------------------------------------------ timer

  void startTimer(Tournament t) {
    final remaining = t.timerPausedMs ?? t.roundMinutes * 60000;
    t.timerEndMs = DateTime.now().millisecondsSinceEpoch + remaining;
    t.timerPausedMs = null;
    changed();
  }

  void pauseTimer(Tournament t) {
    if (t.timerEndMs == null) return;
    t.timerPausedMs = (t.timerEndMs! - DateTime.now().millisecondsSinceEpoch).clamp(0, 1 << 31);
    t.timerEndMs = null;
    changed();
  }

  void resetTimer(Tournament t, {bool notify = true}) {
    t.timerEndMs = null;
    t.timerPausedMs = null;
    if (notify) changed();
  }

  void addTimerMinutes(Tournament t, int minutes) {
    final d = minutes * 60000;
    if (t.timerEndMs != null) {
      t.timerEndMs = t.timerEndMs! + d;
    } else {
      t.timerPausedMs = ((t.timerPausedMs ?? t.roundMinutes * 60000) + d).clamp(0, 1 << 31);
    }
    changed();
  }
}
