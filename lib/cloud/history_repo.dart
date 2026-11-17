import 'package:cloud_firestore/cloud_firestore.dart';

import '../engine/models.dart';
import '../engine/stats.dart';

/// What a player recorded about one tournament (private to them).
class HistoryEntry {
  final String tid;
  final String? myDeck;
  final Map<String, String> oppDecks;
  const HistoryEntry({required this.tid, this.myDeck, this.oppDecks = const {}});

  factory HistoryEntry.fromDoc(String tid, Map<String, dynamic> d) => HistoryEntry(
    tid: tid,
    myDeck: d['myDeck'] as String?,
    oppDecks: Map<String, String>.from((d['opp'] as Map?) ?? const {}),
  );
}

/// `users/{uid}/history/{tid}` plus the finished tournaments the player was in.
class HistoryRepo {
  final FirebaseFirestore db;
  final String uid;
  HistoryRepo(this.db, this.uid);

  CollectionReference<Map<String, dynamic>> get _col => db.collection('users/$uid/history');

  Stream<Map<String, HistoryEntry>> watch() =>
      _col.snapshots().map((s) => {for (final d in s.docs) d.id: HistoryEntry.fromDoc(d.id, d.data())});

  Future<void> setMyDeck(String tid, String deck) =>
      _col.doc(tid).set({'myDeck': deck.trim()}, SetOptions(merge: true));

  Future<void> setOppDeck(String tid, String matchId, String deck) => _col.doc(tid).set({
    'opp': {matchId: deck.trim()},
  }, SetOptions(merge: true));

  /// Finished tournaments (hosted or joined) in which I had a player seat.
  Stream<List<Tournament>> playedFinished() => db
      .collection('tournaments')
      .where('memberUids', arrayContains: uid)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            if (d.data()['status'] == 'finished' && d.data()['data'] != null)
              Tournament.fromJson(Map<String, dynamic>.from(d.data()['data'] as Map)),
        ].where((t) => t.players.any((p) => p.uid == uid)).toList()..sort((a, b) => b.created.compareTo(a.created)),
      );

  static List<PlayedTournament> join(List<Tournament> ts, Map<String, HistoryEntry> h, String uid) => [
    for (final t in ts)
      PlayedTournament(t: t, uid: uid, myDeck: h[t.id]?.myDeck, oppDecks: h[t.id]?.oppDecks ?? const {}),
  ];

  static List<String> suggestions(Map<String, HistoryEntry> h) => deckSuggestions([
    for (final e in h.values) ...[e.myDeck, ...e.oppDecks.values],
  ]);
}
