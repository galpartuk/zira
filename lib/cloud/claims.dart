import 'package:cloud_firestore/cloud_firestore.dart';

import '../engine/online.dart';

Future<void> writeClaim(FirebaseFirestore db, String tid, Claim c) =>
    db.doc('tournaments/$tid/claims/${c.matchId}_${c.uid}').set(c.toJson());

Future<void> writeEntry(FirebaseFirestore db, String tid, Entry e) => db
    .doc('tournaments/$tid/entries/${e.uid}')
    .set({...e.toJson(), 'at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
