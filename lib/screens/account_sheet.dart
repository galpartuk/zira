import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cloud/auth_service.dart';
import '../l10n.dart';
import '../widgets/common.dart';

Future<void> showAccountSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (c) {
    final auth = c.read<AuthService?>()!;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(auth.displayName),
            subtitle: Text(auth.user?.email ?? ''),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final n = await promptText(c, S.t.displayNameLabel, initial: auth.displayName);
              if (n != null && n.trim().isNotEmpty) await auth.setDisplayName(n);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(S.t.signOut),
            onTap: () {
              Navigator.pop(c);
              auth.signOut();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: Text(S.t.deleteAccount),
            onTap: () async {
              final ok = await confirm(c, S.t.deleteAccount, S.t.deleteAccountBody, ok: S.t.deleteAccount);
              if (!ok || !c.mounted) return;
              Navigator.pop(c);
              try {
                await auth.deleteAccount();
              } on FirebaseAuthException catch (e) {
                if (e.code == 'requires-recent-login') {
                  if (context.mounted) toast(context, S.t.signInAgain);
                  await auth.signOut();
                }
              }
            },
          ),
        ],
      ),
    );
  },
);
