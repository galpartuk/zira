import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../cloud/claims.dart';
import '../cloud/join_codes.dart';
import '../engine/models.dart';
import '../engine/online.dart';

enum JoinResult { ok, requested, badCode, closed, removed }

Future<(JoinResult, String?)> joinWithCode(FirebaseFirestore db,
    {required String uid, required String name, required String code}) async {
  final tid = await lookupJoinCode(db, code);
  if (tid == null) return (JoinResult.badCode, null);
  final doc = (await db.doc('tournaments/$tid').get()).data();
  if (doc == null) return (JoinResult.badCode, null);
  final mine = (await db.doc('tournaments/$tid/entries/$uid').get()).data();
  if (mine?['status'] == 'removed') return (JoinResult.removed, null);
  if (mine?['status'] == 'joined') return (JoinResult.ok, tid);
  final mode = doc['joinMode'] as String? ?? 'open';
  final status = doc['status'] as String? ?? 'registration';
  if (status == 'finished' || (mode == 'closedOnStart' && status != 'registration')) {
    return (JoinResult.closed, null);
  }
  final approval = mode == 'approval';
  await writeEntry(db, tid,
      Entry(uid: uid, displayName: name, status: approval ? EntryStatus.requested : EntryStatus.joined));
  return (approval ? JoinResult.requested : JoinResult.ok, tid);
}

Stream<List<({String tid, String name, String status})>> joinedTournaments(FirebaseFirestore db, String uid) => db
    .collection('tournaments')
    .where('memberUids', arrayContains: uid)
    .snapshots()
    .map((s) => [
          for (final d in s.docs)
            if (d.data()['hostUid'] != uid)
              (tid: d.id, name: d.data()['name'] as String? ?? '?', status: d.data()['status'] as String? ?? '')
        ]);

/// One tournament as a player sees it, live.
class PlayerSession extends ChangeNotifier {
  final FirebaseFirestore db;
  final String tid;
  final String uid;

  Tournament? t;
  String? hostUid;

  /// The host deleted the tournament.
  bool gone = false;
  EntryStatus? myStatus;
  List<Claim> _claims = [];
  final _subs = <StreamSubscription>[];

  PlayerSession(this.db, this.tid, this.uid) {
    final ref = db.doc('tournaments/$tid');
    _subs
      ..add(ref.snapshots().listen((s) {
        final d = s.data();
        if (d == null) {
          gone = s.metadata.isFromCache == false;
          notifyListeners();
          return;
        }
        gone = false;
        hostUid = d['hostUid'] as String?;
        t = Tournament.fromJson(Map<String, dynamic>.from(d['data'] as Map));
        notifyListeners();
      }))
      ..add(ref.collection('claims').snapshots().listen((s) {
        _claims = [for (final d in s.docs) Claim.fromJson(d.data())];
        notifyListeners();
      }))
      ..add(ref.collection('entries').doc(uid).snapshots().listen((s) {
        final d = s.data();
        myStatus = d == null ? null : Entry.fromJson(uid, d).status;
        notifyListeners();
      }));
  }

  Player? get me {
    for (final p in t?.players ?? const <Player>[]) {
      if (p.uid == uid) return p;
    }
    return null;
  }

  Round? get myRound => t?.currentRound;

  Match? get myMatch {
    final p = me;
    final r = myRound;
    if (p == null || r == null) return null;
    for (final m in r.matches) {
      if (m.involves(p.id)) return m;
    }
    return null;
  }

  ClaimState get myState {
    final m = myMatch;
    if (t == null || m == null) return const NoClaims();
    return resolveClaims(t!, m, _claims);
  }

  Future<void> report(MatchResult r) async {
    final m = myMatch;
    if (m == null || m.isBye || m.result != null) return;
    await writeClaim(db, tid, Claim(matchId: m.id, uid: uid, result: r, atMs: DateTime.now().millisecondsSinceEpoch));
  }

  /// "Confirm" = report exactly what the opponent reported.
  Future<void> confirm() async {
    final s = myState;
    if (s is Pending && s.by.uid != uid) await report(s.by.result);
  }

  Future<void> drop() async {
    final p = me;
    await writeEntry(db, tid, Entry(uid: uid, displayName: p?.name ?? '?', status: EntryStatus.dropped));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
