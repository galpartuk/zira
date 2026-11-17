import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

const joinCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
final _rng = Random.secure();

String randomJoinCode([Random? rng]) {
  final r = rng ?? _rng;
  return List.generate(6, (_) => joinCodeAlphabet[r.nextInt(joinCodeAlphabet.length)]).join();
}

/// Claims a free code for [tid]. Needs a connection (transaction).
Future<String> reserveJoinCode(FirebaseFirestore db, {required String tid, required String hostUid}) async {
  for (var i = 0; i < 10; i++) {
    final code = randomJoinCode();
    final ref = db.collection('joinCodes').doc(code);
    final ok = await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return false;
      tx.set(ref, {'tid': tid, 'hostUid': hostUid});
      return true;
    });
    if (ok) return code;
  }
  throw StateError('no free join code');
}

Future<String?> lookupJoinCode(FirebaseFirestore db, String code) async {
  final c = code.trim().toUpperCase();
  if (c.length != 6) return null;
  final snap = await db.collection('joinCodes').doc(c).get();
  return snap.data()?['tid'] as String?;
}
