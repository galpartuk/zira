// Renders the online screens with sample data into PNGs (for design reviews).
// Run:  flutter test tool/shots --update-goldens
// Output: tool/shots/out/*.png  (git-ignored)
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zira/cloud/auth_service.dart';
import 'package:zira/cloud/claims.dart';
import 'package:zira/cloud/history_repo.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';
import 'package:zira/l10n.dart';
import 'package:zira/screens/about_screen.dart';
import 'package:zira/screens/history_screen.dart';
import 'package:zira/screens/home_screen.dart';
import 'package:zira/screens/player_tournament_screen.dart';
import 'package:zira/screens/stats_screen.dart';
import 'package:zira/screens/tournament_screen.dart';
import 'package:zira/state/app_state.dart';
import 'package:zira/state/host_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zira/theme.dart';
import 'package:zira/tools/memory_screen.dart';
import 'package:zira/widgets/lobby_card.dart';
import 'package:zira/widgets/round_timer.dart';

Future<void> loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

const me = 'gal';
final names = ['Alex Rivera', 'Sam Carter', 'Noa Levi', 'Daniel Cohen', 'Maya Ben-David', 'Omer Katz'];

/// A Swiss event, round 2 published, Alex (the signed-in player) plays table 1 against Sam.
Tournament live() {
  final t = Tournament(
    id: 'live',
    name: 'Friday Locals',
    joinCode: 'K7Q2XM',
    swissRounds: 4,
    players: [
      for (var i = 0; i < names.length; i++) Player(id: 'p$i', name: names[i], uid: i == 0 ? me : 'u$i', tieRand: i),
    ],
  );
  t.rounds.add(
    Round(
      number: 1,
      stage: Stage.swiss,
      matches: [
        Match(id: 'r1a', table: 1, p1: 'p0', p2: 'p3', result: MatchResult(Outcome.p1, 2, 1)),
        Match(id: 'r1b', table: 2, p1: 'p1', p2: 'p4', result: MatchResult(Outcome.p1, 2, 0)),
        Match(id: 'r1c', table: 3, p1: 'p2', p2: 'p5', result: MatchResult(Outcome.p2, 1, 2)),
      ],
    ),
  );
  t.rounds.add(
    Round(
      number: 2,
      stage: Stage.swiss,
      matches: [
        Match(id: 'r2a', table: 1, p1: 'p0', p2: 'p1'),
        Match(id: 'r2b', table: 2, p1: 'p5', p2: 'p2'),
        Match(id: 'r2c', table: 3, p1: 'p3', p2: 'p4', result: MatchResult(Outcome.p2, 0, 2)),
      ],
    ),
  );
  t.timerEndMs = DateTime.now().millisecondsSinceEpoch + 31 * 60000 + 12000;
  return t;
}

Tournament done(String id, String name, String hostUid) {
  final t = live()..finished = true;
  return Tournament.fromJson({...t.toJson(), 'id': id, 'name': name})
    ..rounds.last.matches[0].result = MatchResult(Outcome.p2, 1, 2)
    ..rounds.last.matches[1].result = MatchResult(Outcome.p1, 2, 0)
    ..finished = true;
}

Future<Widget> app({
  required WidgetTester tester,
  required FakeFirebaseFirestore db,
  required Widget home,
  AppState? appState,
  HostSync? sync,
}) async {
  final auth = AuthService(
    MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: me, displayName: 'Alex Rivera', email: 'alex@example.com'),
    ),
    db,
  );
  final st = appState ?? (AppState(store: CloudStore(db, me), draftRounds: true)..loaded = true);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: st),
      ChangeNotifierProvider<AuthService?>.value(value: auth),
      Provider<FirebaseFirestore?>.value(value: db),
      ChangeNotifierProvider<HostSync?>.value(value: sync),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: Locale(Lang.instance.code),
      supportedLocales: [Locale('en'), Locale('he')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle(Duration(milliseconds: 300));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    KeepAwake.apply = (_) {}; // no wakelock plugin in tests
    lobbyAnimations = false; // endless animations never settle
    await loadFont('Rubik', 'assets/fonts/Rubik.ttf');
    await loadFont('BarlowCondensed', 'assets/fonts/BarlowCondensed-Bold.ttf');
    const sdk = 'C:/tools/flutter';
    await loadFont('MaterialIcons', '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  });

  // 'light' = English in the light look.
  for (final lang in ['he', 'en', 'light']) {
    group(lang, () {
      setUp(() async {
        Lang.instance.code = lang == 'light' ? 'en' : lang;
        Looks.instance.light = lang == 'light';
        final b = TestWidgetsFlutterBinding.instance;
        b.platformDispatcher.views.first.physicalSize = Size(1080, 2340);
        b.platformDispatcher.views.first.devicePixelRatio = 2.625;
      });

      testWidgets('host rounds (live round, pending + dispute)', (tester) async {
        final db = FakeFirebaseFirestore();
        final st = AppState(store: CloudStore(db, me), draftRounds: true);
        await st.load();
        final t = live();
        st.add(t);
        final sync = HostSync(db, st, me);
        await writeClaim(db, 'live', Claim(matchId: 'r2a', uid: 'u1', result: MatchResult(Outcome.p2, 1, 2), atMs: 1));
        await writeClaim(db, 'live', Claim(matchId: 'r2b', uid: 'u5', result: MatchResult(Outcome.p1, 2, 0), atMs: 1));
        await writeClaim(db, 'live', Claim(matchId: 'r2b', uid: 'u2', result: MatchResult(Outcome.p2, 0, 2), atMs: 1));
        await tester.pumpWidget(
          await app(
            tester: tester,
            db: db,
            home: TournamentScreen(id: 'live'),
            appState: st,
            sync: sync,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(S.t.tabRounds));
        await shot(tester, '${lang}_01_host_rounds');
        sync.dispose();
      });

      testWidgets('host draft round', (tester) async {
        final db = FakeFirebaseFirestore();
        final st = AppState(store: CloudStore(db, me), draftRounds: true);
        await st.load();
        final t = live();
        t.rounds.last.published = false;
        for (final m in t.rounds.last.matches) {
          m.result = null;
        }
        st.add(t);
        final sync = HostSync(db, st, me);
        await tester.pumpWidget(
          await app(
            tester: tester,
            db: db,
            home: TournamentScreen(id: 'live'),
            appState: st,
            sync: sync,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(S.t.tabRounds));
        await shot(tester, '${lang}_02_host_draft');
        sync.dispose();
      });

      testWidgets('player: opponent reported (card + pop-up)', (tester) async {
        final db = FakeFirebaseFirestore();
        await CloudStore(db, 'host').saveAll([live()]);
        await writeClaim(db, 'live', Claim(matchId: 'r2a', uid: 'u1', result: MatchResult(Outcome.p2, 1, 2), atMs: 1));
        await tester.pumpWidget(
          await app(
            tester: tester,
            db: db,
            home: PlayerTournamentScreen(tid: 'live'),
          ),
        );
        await shot(tester, '${lang}_03_player_popup');
        await tester.tap(find.text(S.t.later));
        await shot(tester, '${lang}_04_player_card_pending');
      });

      testWidgets('player: I reported, waiting', (tester) async {
        final db = FakeFirebaseFirestore();
        await CloudStore(db, 'host').saveAll([live()]);
        await writeClaim(db, 'live', Claim(matchId: 'r2a', uid: me, result: MatchResult(Outcome.p1, 2, 1), atMs: 1));
        await tester.pumpWidget(
          await app(
            tester: tester,
            db: db,
            home: PlayerTournamentScreen(tid: 'live'),
          ),
        );
        await shot(tester, '${lang}_05_player_waiting');
      });

      testWidgets('player: report button', (tester) async {
        final db = FakeFirebaseFirestore();
        await CloudStore(db, 'host').saveAll([live()]);
        await tester.pumpWidget(
          await app(
            tester: tester,
            db: db,
            home: PlayerTournamentScreen(tid: 'live'),
          ),
        );
        await shot(tester, '${lang}_06_player_report');
        await tester.tap(find.text(S.t.tabRounds));
        await shot(tester, '${lang}_07_player_pairings');
      });

      testWidgets('player: joined, before the first round', (tester) async {
        final db = FakeFirebaseFirestore();
        final t = live()..rounds.clear();
        await CloudStore(db, 'host').saveAll([t]);
        await db.doc('tournaments/live/entries/$me').set({'displayName': 'Alex Rivera', 'status': 'joined'});
        await tester.pumpWidget(
          await app(
            tester: tester,
            db: db,
            home: PlayerTournamentScreen(tid: 'live'),
          ),
        );
        await shot(tester, '${lang}_11_player_lobby');
      });

      testWidgets('memory gauge', (tester) async {
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({
          'zira.memory.v1': '{"m":{"v":3,"t":0,"n":5},"bn":null,"tn":null,"bw":1,"tw":0}',
        });
        final db = FakeFirebaseFirestore();
        await tester.pumpWidget(await app(tester: tester, db: db, home: MemoryScreen()));
        await shot(tester, '${lang}_12_memory');
        await tester.tap(find.text(S.t.pay).last);
        await shot(tester, '${lang}_13_memory_pay');
        await tester.pumpWidget(SizedBox());
      });

      testWidgets('home (playing / hosting / history)', (tester) async {
        final db = FakeFirebaseFirestore();
        await CloudStore(
          db,
          'host',
        ).saveAll([live(), done('old1', 'Sunday Cup', 'host'), done('old2', 'Store Championship', 'host')]);
        final st = AppState(store: CloudStore(db, me), draftRounds: true);
        await st.load();
        st.add(
          Tournament(
            id: 'mine',
            name: 'Thursday Weekly',
            joinCode: 'BWE3GK',
            players: [for (var i = 0; i < 5; i++) Player(id: 'q$i', name: names[i], tieRand: i)],
          ),
        );
        await tester.pumpWidget(await app(tester: tester, db: db, home: HomeScreen(), appState: st));
        await shot(tester, '${lang}_08_home');
      });

      testWidgets('about', (tester) async {
        final db = FakeFirebaseFirestore();
        await tester.pumpWidget(await app(tester: tester, db: db, home: AboutScreen()));
        await shot(tester, '${lang}_14_about');
      });

      testWidgets('history + stats', (tester) async {
        final db = FakeFirebaseFirestore();
        await CloudStore(
          db,
          'host',
        ).saveAll([done('old1', 'Sunday Cup', 'host'), done('old2', 'Store Championship', 'host')]);
        final repo = HistoryRepo(db, me);
        await repo.setMyDeck('old1', 'Red Hybrid');
        await repo.setOppDeck('old1', 'r1a', 'Blue Flare');
        await repo.setOppDeck('old1', 'r2a', 'Purple Hybrid');
        await repo.setMyDeck('old2', 'Red Hybrid');
        await repo.setOppDeck('old2', 'r1a', 'Blue Flare');
        await tester.pumpWidget(
          await app(
            tester: tester,
            db: db,
            home: TournamentHistoryScreen(tid: 'old1'),
          ),
        );
        await shot(tester, '${lang}_09_history');
        await tester.pumpWidget(await app(tester: tester, db: db, home: StatsScreen()));
        await shot(tester, '${lang}_10_stats');
      });
    });
  }
}
