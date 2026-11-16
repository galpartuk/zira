import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/models.dart';
import '../engine/online.dart';
import '../engine/pairing.dart';

/// Where tournaments are kept. [PrefsStore] = the phone (old behaviour, used
/// by tests and before sign-in); the cloud store lives in lib/cloud/.
abstract class TournamentStore {
  Future<List<Tournament>> load();
  Future<void> saveAll(List<Tournament> ts);
  Future<void> delete(Tournament t);
}

class PrefsStore implements TournamentStore {
  static const key = 'zira.tournaments.v1';

  /// Set by [load]; saving before that is a no-op (as before the store split).
  SharedPreferences? _prefs;

  @override
  Future<List<Tournament>> load() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Tournament.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('load failed: $e');
      return [];
    }
  }

  @override
  Future<void> saveAll(List<Tournament> ts) async {
    await _prefs?.setString(key, jsonEncode(ts.map((t) => t.toJson()).toList()));
  }

  @override
  Future<void> delete(Tournament t) async {} // saveAll already dropped it
}

/// All tournaments; saved through the current [TournamentStore] after every change.
class AppState extends ChangeNotifier {
  AppState({TournamentStore? store, bool draftRounds = false})
      : _store = store ?? PrefsStore(),
        _draftRounds = draftRounds;

  TournamentStore _store;
  bool _draftRounds;

  /// Online: new rounds are drafts until [publish].
  bool get draftRounds => _draftRounds;

  final List<Tournament> tournaments = [];
  bool loaded = false;

  Future<void> load() async {
    final list = await _store.load();
    tournaments
      ..clear()
      ..addAll(list);
    loaded = true;
    notifyListeners();
  }

  Future<void> attach(TournamentStore store, {required bool draftRounds}) async {
    _store = store;
    _draftRounds = draftRounds;
    loaded = false;
    notifyListeners();
    await load();
  }

  void detach() {
    _store = PrefsStore();
    _draftRounds = false;
    tournaments.clear();
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() => _store.saveAll(tournaments);

  /// Call after mutating a tournament in place.
  void changed() {
    for (final t in tournaments) {
      _autoRounds(t);
    }
    notifyListeners();
    _save();
  }

  void _autoRounds(Tournament t) {
    if (t.autoRounds && !t.started && t.format == TFormat.swiss) {
      t.swissRounds = recommendedSwissRounds(t.activePlayers.length);
    }
  }

  Round _fresh(Round r) => r..published = !_draftRounds;

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
    _store.delete(t);
    changed();
  }

  String exportAll() => const JsonEncoder.withIndent(' ').convert(tournaments.map((t) => t.toJson()).toList());

  /// Imports tournaments from a backup; ones that already exist are replaced.
  int importAll(String raw) {
    final decoded = jsonDecode(raw);
    final list = decoded is List ? decoded : [decoded];
    // Parse everything first so a bad entry leaves the current data alone.
    final parsed = [for (final e in list) Tournament.fromJson(e as Map<String, dynamic>)];
    for (final t in parsed) {
      tournaments.removeWhere((x) => x.id == t.id);
      tournaments.insert(0, t);
    }
    changed();
    return parsed.length;
  }

  // ------------------------------------------------------------ flow

  void start(Tournament t) {
    _autoRounds(t);
    if (t.format == TFormat.roundRobin) {
      t.rrSchedule = buildRoundRobinSchedule(t.activePlayers.map((p) => p.id).toList());
      t.swissRounds = t.rrSchedule!.length;
      t.rounds.add(_fresh(roundRobinRound(t)));
    } else {
      t.rounds.add(_fresh(pairSwissRound(t)));
    }
    resetTimer(t, notify: false);
    changed();
  }

  /// Generates whatever comes next: a Swiss round, the first / next bracket
  /// round, or marks the tournament finished.
  void advance(Tournament t) {
    if (t.finished || t.firstIncompleteRound != null || draftRound(t) != null) return;
    if (!t.swissDone) {
      t.rounds.add(_fresh(t.format == TFormat.roundRobin ? roundRobinRound(t) : pairSwissRound(t)));
    } else if (effectiveTopCut(t) > 0 && !topCutFinished(t)) {
      final r = nextTopRound(t);
      if (r != null) t.rounds.add(_fresh(r));
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
      t.rounds.add(_fresh(t.format == TFormat.roundRobin ? roundRobinRound(t) : pairSwissRound(t)));
    } else {
      final n = nextTopRound(t);
      if (n != null) t.rounds.add(_fresh(n));
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

  /// Sends the draft round to the players and resets the round clock.
  void publish(Tournament t) {
    final r = draftRound(t);
    if (r == null) return;
    r.published = true;
    resetTimer(t, notify: false);
    changed();
  }

  void setResult(Tournament t, Match m, MatchResult? r) {
    if (roundOf(t, m)?.published == false) return; // drafts can't be scored
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
    // May be negative: pausing during overtime keeps the overtime position.
    t.timerPausedMs = t.timerEndMs! - DateTime.now().millisecondsSinceEpoch;
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
      t.timerPausedMs = (t.timerPausedMs ?? t.roundMinutes * 60000) + d;
    }
    changed();
  }
}
