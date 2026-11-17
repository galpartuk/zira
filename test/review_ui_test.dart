import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zira/screens/create_tournament_screen.dart';
import 'package:zira/screens/tabs/standings_tab.dart';
import 'package:zira/screens/tournament_screen.dart';
import 'package:zira/screens/tournament_settings_sheet.dart';
import 'package:zira/state/app_state.dart';
import 'package:zira/theme.dart';

import 'engine_test.dart' show makeT, playOut;

Widget host(AppState app, Widget child) => ChangeNotifierProvider.value(
  value: app,
  child: MaterialApp(theme: buildTheme(), home: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('create button follows the name field', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const CreateTournamentScreen()));
    FilledButton button() => tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNotNull);
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'an empty name must disable the button');
    await tester.enterText(find.byType(TextField).first, 'Cup');
    await tester.pump();
    expect(button().onPressed, isNotNull, reason: 'typing a name must enable it again');
  });

  testWidgets('settings sheet does not overflow with a very long tournament name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    final app = AppState();
    final t = makeT(4)..name = 'A very very long tournament name that goes on and on and on forever';
    app.tournaments.add(t);
    await tester.pumpWidget(host(app, Scaffold(body: TournamentSettingsSheet(t: t))));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finished tournament cannot change rounds or top cut', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    final app = AppState();
    final t = makeT(4, rounds: 1);
    app.tournaments.add(t);
    app.start(t);
    playOut(t.rounds.last);
    app.advance(t); // finish
    expect(t.finished, isTrue);
    await tester.pumpWidget(host(app, Scaffold(body: TournamentSettingsSheet(t: t))));
    await tester.pump();
    expect(tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>)).onChanged, isNull);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    expect(t.swissRounds, 1);
  });

  testWidgets('standings with top-cut markers render without errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final app = AppState();
    final t = makeT(8, rounds: 3, top: 4);
    app.tournaments.add(t);
    app.start(t);
    playOut(t.rounds.last);
    await tester.pumpWidget(host(app, Scaffold(body: StandingsTab(t: t))));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning the top cut on mid-event swaps the tabs cleanly', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final app = AppState();
    final t = makeT(8, rounds: 3);
    app.tournaments.add(t);
    app.start(t);
    await tester.pumpWidget(host(app, TournamentScreen(id: t.id)));
    await tester.pumpAndSettle();
    t.topCut = 4;
    app.changed();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Tab), findsNWidgets(5));
    t.topCut = 0;
    app.changed();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Tab), findsNWidgets(4));
  });
}
