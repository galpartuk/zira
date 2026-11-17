import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../engine/models.dart';
import '../engine/online.dart';
import '../state/app_state.dart';

/// Tournaments the signed-in user hosts, stored in Firestore. Only the host
/// writes `tournaments/{tid}`; the draft round goes to `private/host`.
class CloudStore implements TournamentStore {
  final FirebaseFirestore db;
  final String uid;
  final _lastSaved = <String, String>{};

  CloudStore(this.db, this.uid);

  CollectionReference<Map<String, dynamic>> get _col => db.collection('tournaments');

  @override
  Future<List<Tournament>> load() async {
    // The rules only allow listing by membership; the host is always a member.
    final q = await _col.where('memberUids', arrayContains: uid).get();
    final out = <Tournament>[];
    for (final d in q.docs) {
      if (d.data()['hostUid'] != uid) continue;
      final t = Tournament.fromJson(Map<String, dynamic>.from(d.data()['data'] as Map));
      final priv = await d.reference.collection('private').doc('host').get();
      final draft = priv.data()?['draftRound'];
      if (draft != null) {
        t.rounds.add(Round.fromJson(Map<String, dynamic>.from(draft as Map))..published = false);
      }
      _lastSaved[t.id] = jsonEncode(t.toJson());
      out.add(t);
    }
    out.sort((a, b) => b.created.compareTo(a.created));
    return out;
  }

  @override
  Future<void> saveAll(List<Tournament> ts) async {
    // Commits finish only once the server has them (later, when offline), so
    // they run side by side instead of one tournament waiting on another.
    final pending = <Future<void>>[];
    for (final t in ts) {
      final sig = jsonEncode(t.toJson());
      if (_lastSaved[t.id] == sig) continue;
      _lastSaved[t.id] = sig;
      final batch = db.batch();
      final ref = _col.doc(t.id);
      batch.set(ref, {
        'hostUid': uid,
        'name': t.name,
        'joinCode': t.joinCode,
        'joinMode': t.joinMode,
        'status': onlineStatus(t),
        // Read by the join screen and the rules: no joins once no round is left to pair.
        'acceptsPlayers': !t.finished && t.acceptsNewPlayers,
        'memberUids': {uid, ...t.players.map((p) => p.uid).whereType<String>()}.toList(),
        'matchUids': matchUidsFor(t),
        'updatedAt': FieldValue.serverTimestamp(),
        'data': publishedJson(t),
      });
      batch.set(ref.collection('private').doc('host'), {'draftRound': draftRound(t)?.toJson()});
      pending.add(
        batch.commit().catchError((Object e) {
          // Not saved: forget the signature so the next change tries again.
          if (_lastSaved[t.id] == sig) _lastSaved.remove(t.id);
          debugPrint('save ${t.id} failed: $e');
        }),
      );
    }
    await Future.wait(pending);
  }

  @override
  Future<void> delete(Tournament t) async {
    _lastSaved.remove(t.id);
    final ref = _col.doc(t.id);
    final batch = db.batch()
      ..delete(ref.collection('private').doc('host'))
      ..delete(ref);
    if (t.joinCode != null) batch.delete(db.collection('joinCodes').doc(t.joinCode));
    await batch.commit();
  }
}
