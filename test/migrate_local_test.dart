import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zira/cloud/migrate_local.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/state/app_state.dart';

void main() {
  test('uploads local tournaments once per user and keeps the local copy', () async {
    final local = [Tournament(id: 'old1', name: 'Old', players: [Player(id: 'a', name: 'A', tieRand: 1)])];
    SharedPreferences.setMockInitialValues({PrefsStore.key: jsonEncode(local.map((t) => t.toJson()).toList())});
    final prefs = await SharedPreferences.getInstance();
    final db = FakeFirebaseFirestore();
    expect(await migrateLocalTournaments(prefs, CloudStore(db, 'gal'), 'gal'), 1);
    expect((await db.doc('tournaments/old1').get()).data()!['hostUid'], 'gal');
    expect(await migrateLocalTournaments(prefs, CloudStore(db, 'gal'), 'gal'), 0);
    expect(prefs.getString(PrefsStore.key), isNotNull);
  });
}
