import 'package:cloud_firestore/cloud_firestore.dart';

import '../engine/online.dart';

Future<void> writeClaim(FirebaseFirestore db, String tid, Claim c) =>
    db.doc('tournaments/$tid/claims/${c.matchId}_${c.uid}').set(c.toJson());

Future<void> writeEntry(FirebaseFirestore db, String tid, Entry e) => db.doc('tournaments/$tid/entries/${e.uid}').set({
  ...e.toJson(),
  'at': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));

/// Changes only the status of an existing entry. The rules refuse any change
/// of the stored name, so never send the (possibly renamed) tournament name.
Future<void> setEntryStatus(FirebaseFirestore db, String tid, String uid, EntryStatus status) =>
    db.doc('tournaments/$tid/entries/$uid').update({'status': status.name, 'at': FieldValue.serverTimestamp()});
