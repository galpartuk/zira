import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n.dart';
import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Z.surface,
  ));
  Lang.instance.load();
  runApp(ChangeNotifierProvider(create: (_) => AppState()..load(), child: const ZiraApp()));
}

class ZiraApp extends StatelessWidget {
  const ZiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    // English by default; Hebrew flips the whole app to right-to-left.
    return ListenableBuilder(
      listenable: Lang.instance,
      builder: (context, _) => MaterialApp(
        title: S.t.appName,
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
  }
}
