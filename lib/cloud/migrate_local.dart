import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_state.dart';
import 'tournament_repo.dart';

/// First sign-in: the tournaments that lived only on this phone become cloud
/// tournaments hosted by [uid]. The local copy stays as a backup.
Future<int> migrateLocalTournaments(SharedPreferences prefs, CloudStore store, String uid) async {
  final flag = 'zira.migrated.$uid';
  if (prefs.getBool(flag) ?? false) return 0;
  final local = await PrefsStore().load();
  if (local.isNotEmpty) await store.saveAll(local);
  await prefs.setBool(flag, true);
  return local.length;
}
