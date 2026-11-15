import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/auth_service.dart';
import '../cloud/migrate_local.dart';
import '../cloud/tournament_repo.dart';
import '../l10n.dart';
import 'app_state.dart';
import 'host_sync.dart';

/// Lets toasts be shown from above the MaterialApp (the gate lives there so a
/// language switch, which rebuilds the home screen, doesn't sign anyone out).
final messengerKey = GlobalKey<ScaffoldMessengerState>();

T? _maybe<T>(BuildContext c, bool listen) {
  try {
    return Provider.of<T?>(c, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

/// Null in tests and other offline builds.
AuthService? authOf(BuildContext c, {bool listen = true}) => _maybe<AuthService>(c, listen);
HostSync? hostSyncOf(BuildContext c, {bool listen = true}) => _maybe<HostSync>(c, listen);
FirebaseFirestore? dbOf(BuildContext c) => _maybe<FirebaseFirestore>(c, false);

/// Follows sign-in: attaches the cloud store and HostSync for the signed-in
/// user, detaches on sign-out.
class CloudGate extends StatefulWidget {
  final Widget child;
  const CloudGate({super.key, required this.child});

  @override
  State<CloudGate> createState() => _CloudGateState();
}

class _CloudGateState extends State<CloudGate> {
  late final AuthService _auth;
  String? _uid;
  HostSync? _sync;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthService?>()!;
    _auth.addListener(_onAuth);
    _onAuth();
  }

  Future<void> _onAuth() async {
    final uid = _auth.user?.uid;
    if (uid == _uid) return;
    _uid = uid;
    final app = context.read<AppState>();
    _sync?.dispose();
    setState(() => _sync = null);
    if (uid == null) {
      app.detach();
      return;
    }
    final db = context.read<FirebaseFirestore?>()!;
    final store = CloudStore(db, uid);
    var moved = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      moved = await migrateLocalTournaments(prefs, store, uid).timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('migration failed: $e');
    }
    await app.attach(store, draftRounds: true);
    if (!mounted || _uid != uid) return;
    setState(() => _sync = HostSync(db, app, uid));
    if (moved > 0) {
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text(S.t.migrated(moved))));
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    _sync?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<HostSync?>.value(value: _sync, child: widget.child);
}
