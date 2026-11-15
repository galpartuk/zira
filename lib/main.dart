import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'cloud/auth_service.dart';
import 'cloud/firebase_options.dart';
import 'l10n.dart';
import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'state/session.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Z.surface,
  ));
  Lang.instance.load();
  final db = FirebaseFirestore.instance;
  final auth = AuthService(FirebaseAuth.instance, db);
  runApp(MultiProvider(providers: [
    ChangeNotifierProvider(create: (_) => AppState()), // loaded by CloudGate on sign-in
    ChangeNotifierProvider<AuthService?>.value(value: auth),
    Provider<FirebaseFirestore?>.value(value: db),
  ], child: const ZiraApp(online: true)));
}

class ZiraApp extends StatelessWidget {
  /// Online = Firebase sign-in and cloud tournaments. Tests build it offline.
  final bool online;
  const ZiraApp({super.key, this.online = false});

  @override
  Widget build(BuildContext context) {
    // English by default; Hebrew flips the whole app to right-to-left.
    final app = ListenableBuilder(
      listenable: Lang.instance,
      builder: (context, _) => MaterialApp(
        title: S.t.appName,
        scaffoldMessengerKey: messengerKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: Locale(Lang.instance.code),
        supportedLocales: const [Locale('en'), Locale('he')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Keyed so every string is rebuilt in the new language.
        home: HomeScreen(key: ValueKey(Lang.instance.code)),
      ),
    );
    return online ? CloudGate(child: app) : app;
  }
}
