import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../cloud/claims.dart';
import '../cloud/join_codes.dart';
import '../engine/models.dart';
import '../engine/online.dart';
import 'app_state.dart';

/// Runs on the host's phone: turns players' entries and claims into engine
/// changes. The host's app is the only writer of the tournament doc.
class HostSync extends ChangeNotifier {
  final FirebaseFirestore db;
  final AppState app;
  final String uid;

  final _subs = <String, List<StreamSubscription>>{};
  final _claims = <String, List<Claim>>{};
  final _entries = <String, List<Entry>>{};
  final _applied = <String>{};

  /// Last entry status seen per tournament+uid, so an entry is applied once per
  /// change and a host's later manual fix (e.g. undoing a drop) sticks.
  final _seenEntries = <String, EntryStatus>{};

  /// How long to wait before listening again after the server refused.
  static Duration retryDelay = const Duration(seconds: 3);

  /// Short messages for the host ("Aviv joined"), shown as a snack bar.
  void Function(String message)? onNotice;

  /// Message texts; the UI layer (which owns the language) replaces them.
  static String Function(String name) noticeJoined = (n) => '$n joined';
  static String Function(String name) noticeRequested = (n) => '$n asks to join';
  bool _disposed = false;

  HostSync(this.db, this.app, this.uid) {
    app.addListener(_resync);
    _resync();
  }

  void _resync() {
    for (final t in app.tournaments) {
      if (t.finished && t.joinCode != null) _releaseCodeIfFinished(t);
    }
    final live = {for (final t in app.tournaments) if (!t.finished) t.id};
    for (final id in _subs.keys.toList()) {
      if (!live.contains(id)) {
        for (final s in _subs.remove(id)!) {
          s.cancel();
        }
      }
    }
    for (final id in live) {
      if (_subs.containsKey(id)) continue;
      final ref = db.collection('tournaments').doc(id);
      _subs[id] = [
        ref.collection('entries').snapshots().listen((s) {
          _entries[id] = [for (final d in s.docs) Entry.fromJson(d.id, d.data())];
          _apply(id);
        }, onError: (Object e) => _listenFailed(id, e)),
        ref.collection('claims').snapshots().listen((s) {
          _claims[id] = [for (final d in s.docs) Claim.fromJson(d.data())];
          _apply(id);
        }, onError: (Object e) => _listenFailed(id, e)),
      ];
    }
  }

  /// A rejected listener (typically: the tournament was just created and has
  /// not reached the server yet, so the rules can't find its host) is dead
  /// for good in Firestore. Drop it and subscribe again shortly.
  void _listenFailed(String id, Object e) {
    debugPrint('listen $id failed: $e');
    final subs = _subs.remove(id);
    if (subs == null) return; // the other stream already scheduled a retry
    for (final s in subs) {
      s.cancel();
    }
    Future.delayed(retryDelay, () {
      if (!_disposed) _resync();
    });
  }

  void _apply(String tid) {
    final t = app.byId(tid);
    if (t == null) return;
    final fresh = [
      for (final e in _entries[tid] ?? const <Entry>[])
        if (_seenEntries['$tid/${e.uid}'] != e.status) e,
    ];
    for (final e in fresh) {
      _seenEntries['$tid/${e.uid}'] = e.status;
    }
    final before = {for (final p in t.players) p.uid};
    var changed = applyEntries(t, fresh);
    for (final p in t.players) {
      if (p.uid != null && !before.contains(p.uid)) onNotice?.call(noticeJoined(p.name));
    }
    for (final e in fresh) {
      if (e.status == EntryStatus.requested) onNotice?.call(noticeRequested(e.displayName));
    }
    final r = t.currentRound;
    if (r != null && r.published) {
      for (final m in r.matches) {
        if (m.isBye || m.result != null) continue;
        final s = resolveClaims(t, m, _claims[tid] ?? const []);
        if (s is Confirmed) {
          final key = '${m.id}|${s.result.outcome.index}|${s.result.g1}|${s.result.g2}';
          if (_applied.add(key)) {
            m.result = s.result;
            changed = true;
          }
        }
      }
    }
    if (changed) app.changed();
    notifyListeners();
  }

  ClaimState stateOf(Tournament t, Match m) => resolveClaims(t, m, _claims[t.id] ?? const []);

  List<Entry> requests(Tournament t) =>
      (_entries[t.id] ?? const []).where((e) => e.status == EntryStatus.requested).toList();

  Future<void> approve(Tournament t, String playerUid) async {
    final e = (_entries[t.id] ?? const []).firstWhere((e) => e.uid == playerUid);
    await writeEntry(db, t.id, Entry(uid: e.uid, displayName: e.displayName, status: EntryStatus.joined));
  }

  /// Before the start the player disappears; after it they are dropped
  /// (results stay). Online players are also blocked from rejoining.
  Future<void> removePlayer(Tournament t, Player p) async {
    if (!t.started) {
      t.players.remove(p);
    } else {
      p.dropped = true;
    }
    app.changed();
    if (p.uid != null) {
      await writeEntry(db, t.id, Entry(uid: p.uid!, displayName: p.name, status: EntryStatus.removed));
    }
  }

  /// A finished tournament gives its join code back.
  Future<void> _releaseCodeIfFinished(Tournament t) async {
    final code = t.joinCode;
    if (!t.finished || code == null) return;
    t.joinCode = null;
    app.changed();
    try {
      await db.collection('joinCodes').doc(code).delete();
    } catch (e) {
      debugPrint('release code failed: $e');
    }
  }

  /// The host also plays in [m]: their own result goes through the opponent's
  /// confirmation like any player's, not straight into the standings.
  bool isOwnMatch(Tournament t, Match m) =>
      !m.isBye && (t.player(m.p1)?.uid == uid || t.player(m.p2)?.uid == uid);

  Future<void> reportOwn(Tournament t, Match m, MatchResult r) => writeClaim(
      db, t.id, Claim(matchId: m.id, uid: uid, result: r, atMs: DateTime.now().millisecondsSinceEpoch));

  bool roundHasClaims(Tournament t, Round r) {
    final ids = r.matches.map((m) => m.id).toSet();
    return (_claims[t.id] ?? const []).any((c) => ids.contains(c.matchId));
  }

  ({int reported, int pending, int disputed, int total}) roundCounts(Tournament t) {
    final r = t.currentRound;
    if (r == null || !r.published) return (reported: 0, pending: 0, disputed: 0, total: 0);
    var reported = 0, pending = 0, disputed = 0, total = 0;
    for (final m in r.matches) {
      if (m.isBye) continue;
      total++;
      if (m.result != null) {
        reported++;
        continue;
      }
      switch (stateOf(t, m)) {
        case Pending():
          pending++;
        case Disputed():
          disputed++;
        default:
      }
    }
    return (reported: reported, pending: pending, disputed: disputed, total: total);
  }

  Future<void> ensureJoinCode(Tournament t) async {
    if (t.joinCode != null) return;
    try {
      t.joinCode = await reserveJoinCode(db, tid: t.id, hostUid: uid);
      app.changed();
    } catch (e) {
      debugPrint('join code failed: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    app.removeListener(_resync);
    for (final l in _subs.values) {
      for (final s in l) {
        s.cancel();
      }
    }
    super.dispose();
  }
}
