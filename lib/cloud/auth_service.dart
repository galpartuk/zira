import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  User? user;

  AuthService(this.auth, this.db) {
    user = auth.currentUser;
    auth.userChanges().listen((u) {
      user = u;
      notifyListeners();
    });
  }

  /// Never the full email: other players see this name.
  String get displayName {
    final n = user?.displayName?.trim();
    if (n != null && n.isNotEmpty) return n;
    final email = user?.email;
    return email == null ? '?' : email.split('@').first;
  }

  Future<void> _profile() async {
    final u = auth.currentUser;
    if (u == null) return;
    await db.doc('users/${u.uid}').set(
        {'displayName': displayName, 'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> signInGoogle() async {
    final p = GoogleAuthProvider();
    kIsWeb ? await auth.signInWithPopup(p) : await auth.signInWithProvider(p);
    await _profile();
  }

  Future<void> signInEmail(String email, String pw) async {
    await auth.signInWithEmailAndPassword(email: email.trim(), password: pw);
    await _profile();
  }

  Future<void> register(String name, String email, String pw) async {
    final c = await auth.createUserWithEmailAndPassword(email: email.trim(), password: pw);
    await c.user!.updateDisplayName(name.trim());
    await c.user!.reload();
    user = auth.currentUser;
    await _profile();
  }

  Future<void> resetPassword(String email) => auth.sendPasswordResetEmail(email: email.trim());

  Future<void> setDisplayName(String n) async {
    await auth.currentUser!.updateDisplayName(n.trim());
    await auth.currentUser!.reload();
    user = auth.currentUser;
    await _profile();
    notifyListeners();
  }

  Future<void> signOut() => auth.signOut();

  /// Throws FirebaseAuthException(code: 'requires-recent-login') when the
  /// sign-in is old; the UI then asks the user to sign in again and retries.
  Future<void> deleteAccount() async {
    final u = auth.currentUser!;
    await db.doc('users/${u.uid}').delete();
    await u.delete();
  }
}
