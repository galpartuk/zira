import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/pairing.dart';
import 'package:zira/l10n.dart';
import 'package:zira/main.dart';
import 'package:zira/screens/tournament_screen.dart';
import 'package:zira/state/app_state.dart';
import 'package:zira/theme.dart';
import 'package:zira/tools/coin_screen.dart';
import 'package:zira/tools/dice_screen.dart';
import 'package:zira/tools/memory_screen.dart';
import 'package:zira/tools/rps_screen.dart';
import 'package:zira/tools/rules_screen.dart';
import 'package:zira/widgets/result_sheet.dart';
import 'package:zira/widgets/round_timer.dart';

import 'engine_test.dart' show makeT, playOut;

Future<AppState> boot(WidgetTester tester, {Size size = const Size(400, 860)}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final app = AppState();
  await app.load();
  await tester.pumpWidget(ChangeNotifierProvider.value(value: app, child: const ZiraApp()));
  await tester.pumpAndSettle();
  return app;
}

TextDirection dirOf(WidgetTester tester, Finder f) => Directionality.of(tester.element(f));

/// A tournament in the middle of its top cut, with a long player name, so
/// every tab has something to draw.
Tournament midTopCut() {
  final t = makeT(9, rounds: 3, top: 4)..thirdPlace = true;
  t.players.first.name = 'Bartholomew Maximilian the Very Long Named Tamer';
  final rng = Random(3);
  for (var r = 0; r < 3; r++) {
    final round = pairSwissRound(t, rng: rng);
    t.rounds.add(round);
    playOut(round, rng: rng);
  }
  final semis = nextTopRound(t)!;
  t.rounds.add(semis);
  semis.matches.first.result = const MatchResult(Outcome.p1, 2, 1);
  return t;
}

/// Real glyph widths (the default test font draws every glyph as a wide
/// square, which would report overflows a phone never shows).
Future<void> loadHeebo() async {
  final bytes = File('assets/fonts/Heebo.ttf').readAsBytesSync();
  final loader = FontLoader('Heebo')..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(loadHeebo);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Lang.instance.code = 'en';
    KeepAwake.apply = (_) {};
  });

  testWidgets('English is the default and the layout is left-to-right', (tester) async {
    await Lang.instance.load();
    expect(Lang.instance.code, 'en');
    await boot(tester);
    expect(find.text('Tournaments'), findsOneWidget);
    expect(find.text('Game tools'), findsOneWidget);
    expect(find.text('No tournaments yet'), findsOneWidget);
    expect(dirOf(tester, find.text('Tournaments')), TextDirection.ltr);
    expect(find.text('עב'), findsWidgets);
  });

  testWidgets('switching to Hebrew is right-to-left and remembered', (tester) async {
    await Lang.instance.load();
    await boot(tester);
    // Toggle from the tools tab: the tab must stay selected after the rebuild.
    await tester.tap(find.text('Game tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lang-toggle')).last);
    await tester.pumpAndSettle();
    expect(find.text('כלי משחק'), findsWidgets);
    expect(find.text('מד זיכרון'), findsOneWidget, reason: 'still on the tools tab');
    expect(dirOf(tester, find.text('מד זיכרון')), TextDirection.rtl);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('zira.lang'), 'he');

    // A fresh start reads it back.
    Lang.instance.code = 'en';
    await Lang.instance.load();
    expect(Lang.instance.code, 'he');

    // And back to English.
    await tester.tap(find.byKey(const ValueKey('lang-toggle')).last);
    await tester.pumpAndSettle();
    expect(find.text('Memory gauge'), findsOneWidget);
    expect(prefs.getString('zira.lang'), 'en');
  });

  for (final lang in ['en', 'he']) {
    testWidgets('[$lang] tournament tabs render without overflow on a narrow phone', (tester) async {
      Lang.instance.code = lang;
      final app = await boot(tester, size: const Size(360, 740));
      final t = midTopCut();
      app.tournaments.add(t);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(),
          locale: Locale(lang),
          localizationsDelegates: const [DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
          home: Directionality(textDirection: Lang.instance.direction, child: TournamentScreen(id: t.id)),
        ),
      ));
      await tester.pumpAndSettle();
      final tabs = find.byType(Tab);
      expect(tabs, findsNWidgets(5));
      for (var i = 0; i < 5; i++) {
        await tester.tap(tabs.at(i));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'tab $i');
      }
      // Settings sheet.
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(lang == 'en' ? 'Tournament settings' : 'הגדרות טורניר'), findsOneWidget);
    });

    testWidgets('[$lang] each score sits on its own player\'s side', (tester) async {
      Lang.instance.code = lang;
      final app = await boot(tester);
      final t = makeT(2, rounds: 1);
      app.tournaments.add(t);
      app.start(t);
      final m = t.rounds.single.matches.single;
      m.result = const MatchResult(Outcome.p1, 2, 1);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(),
          home: Directionality(textDirection: Lang.instance.direction, child: TournamentScreen(id: t.id)),
        ),
      ));
      await tester.pumpAndSettle();
      final p1 = tester.getCenter(find.text(t.nameOf(m.p1))).dx;
      final p2 = tester.getCenter(find.text(t.nameOf(m.p2))).dx;
      Finder score(String v) => find.byWidgetPredicate((w) => w is Text && w.data == v && w.style?.fontSize == 20);
      final two = tester.getCenter(score('2')).dx;
      final one = tester.getCenter(score('1')).dx;
      expect(p1 < p2, lang == 'en', reason: 'player 1 starts on the reading side');
      expect(two < one, p1 < p2, reason: "player 1's games are on player 1's side");
    });

    testWidgets('[$lang] game tools render without overflow', (tester) async {
      Lang.instance.code = lang;
      await boot(tester, size: const Size(360, 740));
      Future<void> show(Widget w) async {
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(),
          home: Directionality(textDirection: Lang.instance.direction, child: w),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${w.runtimeType}');
      }

      await show(const DiceScreen());
      await tester.tap(find.byIcon(Icons.casino));
      await tester.pumpAndSettle();
      expect(find.text(lang == 'en' ? 'Who goes first?' : 'מי מתחיל?'), findsOneWidget);
      await show(const CoinScreen());
      await tester.tap(find.byIcon(Icons.flip));
      await tester.pumpAndSettle();
      expect(find.text(S.t.heads).evaluate().isNotEmpty || find.text(S.t.tails).evaluate().isNotEmpty, isTrue);
      await show(const RpsScreen());
      await show(const RulesScreen());
      await show(const MemoryScreen());
      expect(find.text(lang == 'en' ? 'Blue player' : 'שחקן כחול'), findsOneWidget);
      await show(Scaffold(
        body: ResultSheet(
            p1: 'Bartholomew Maximilian the Long', p2: 'Ann', bestOf: 3, elimination: true, current: null),
      ));
      await show(const Scaffold(
        body: ResultSheet(p1: 'Ann', p2: 'Ben', bestOf: 3, elimination: false, current: MatchResult(Outcome.doubleLoss)),
      ));
      await tester.pumpWidget(const SizedBox()); // dispose before the memory screen's timers matter
    });
  }

  testWidgets('memory gauge: a saved Hebrew default name shows in English', (tester) async {
    SharedPreferences.setMockInitialValues({
      'zira.memory.v1': '{"m":{"v":0,"t":0,"n":1},"bn":"שחקן כחול","tn":"Dana","bw":0,"tw":0}',
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const MemoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Blue player'), findsOneWidget);
    expect(find.text('Dana'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('memory gauge: the Win button records a game win', (tester) async {
    Lang.instance.code = 'en';
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const MemoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Win'), findsNWidgets(2)); // one per player
    await tester.tap(find.text('Win').last);
    await tester.pumpAndSettle();
    // Who starts the next game is asked, not assumed: the winner may start too.
    expect(find.text(S.t.gameWonBody), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('first-bottom')));
    await tester.pumpAndSettle();
    final saved = (await SharedPreferences.getInstance()).getString('zira.memory.v1')!;
    expect(saved, contains('"bw":1')); // .last = the bottom player's button
    expect(saved, contains('"t":0')); // and the bottom player (the winner) goes first
    await tester.pump(const Duration(seconds: 2)); // the "goes first" banner timer
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('memory gauge: Pay takes the cost off the player; the turn changes only on End turn', (tester) async {
    Lang.instance.code = 'en';
    SharedPreferences.setMockInitialValues({
      'zira.memory.v1': '{"m":{"v":3,"t":0,"n":1},"bn":null,"tn":null,"bw":0,"tw":0}',
    });
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const MemoryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay').last); // the bottom player
    await tester.pumpAndSettle();
    expect(find.text(S.t.payHowMuch), findsOneWidget);
    // At 3 memory, 14 would pass the opponent's 10: not a legal payment, nothing happens.
    await tester.tap(find.byKey(const ValueKey('pay-bottom-14')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text(S.t.payHowMuch), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('zira.memory.v1')!, contains('"v":3'));
    await tester.tap(find.byKey(const ValueKey('pay-bottom-7')));
    await tester.pumpAndSettle();
    expect(find.text(S.t.payHowMuch), findsNothing);
    final saved = (await SharedPreferences.getInstance()).getString('zira.memory.v1')!;
    expect(saved, contains('"v":-4')); // 3 − 7 = 4 on the opponent's side
    expect(saved, contains('"t":0')); // still the bottom player's turn: nothing passes by itself
    await tester.tap(find.text(S.t.endTurn));
    await tester.pumpAndSettle();
    final after = (await SharedPreferences.getInstance()).getString('zira.memory.v1')!;
    expect(after, contains('"v":-4')); // ending the turn leaves the memory alone
    expect(after, contains('"t":1'));
    await tester.pump(const Duration(seconds: 2));
    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox());
  });
}
