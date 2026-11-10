import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/main.dart';
import 'package:zira/state/app_state.dart';

void main() {
  testWidgets('create → start → report all → round 2 is paired', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final app = AppState();
    await app.load();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: app, child: const ZiraApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('טורניר חדש').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'אנה\nבן\nגל\nדן\nהדס');
    await tester.pumpAndSettle();
    expect(find.text('יצירת טורניר עם 5 שחקנים'), findsOneWidget);
    await tester.tap(find.text('יצירת טורניר עם 5 שחקנים'));
    await tester.pumpAndSettle();

    final t = app.tournaments.single;
    expect(t.players.length, 5);
    expect(t.swissRounds, 3);

    await tester.tap(find.text('התחלת הטורניר · סיבוב 1'));
    await tester.pumpAndSettle();
    expect(t.rounds.length, 1);
    expect(find.text('BYE'), findsOneWidget);

    // Report every open match by tapping the card and choosing player 1.
    for (final m in t.rounds.first.matches.where((m) => !m.isBye)) {
      await tester.tap(find.text(t.nameOf(m.p1)).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('${t.nameOf(m.p1)} ניצח'));
      await tester.pumpAndSettle();
      expect(m.result?.outcome, Outcome.p1);
    }

    await tester.tap(find.text('זיווג סיבוב 2'));
    await tester.pumpAndSettle();
    expect(t.rounds.length, 2);
    // Saved to storage.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('zira.tournaments.v1'), contains('אנה'));
  });
}
