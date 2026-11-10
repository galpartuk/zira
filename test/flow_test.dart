import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/l10n.dart';
import 'package:zira/main.dart';
import 'package:zira/state/app_state.dart';

void main() {
  testWidgets('create → start → report all → round 2 is paired', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Lang.instance.code = 'en';
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final app = AppState();
    await app.load();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: app, child: const ZiraApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New tournament').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'אנה\nבן\nגל\nדן\nהדס');
    await tester.pumpAndSettle();
    expect(find.text('Create tournament with 5 players'), findsOneWidget);
    await tester.tap(find.text('Create tournament with 5 players'));
    await tester.pumpAndSettle();

    final t = app.tournaments.single;
    expect(t.players.length, 5);
    expect(t.swissRounds, 3);
    expect(t.topCut, 0);
    expect(t.swissBestOf, 3);
    expect(t.roundMinutes, 45);

    await tester.tap(find.text('Start the tournament · Round 1'));
    await tester.pumpAndSettle();
    expect(t.rounds.length, 1);
    expect(find.text('BYE'), findsOneWidget);

    // Report every open match by tapping the card and choosing player 1.
    for (final m in t.rounds.first.matches.where((m) => !m.isBye)) {
      await tester.tap(find.text(t.nameOf(m.p1)).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2-0')); // default is best-of-3
      await tester.pumpAndSettle();
      expect(m.result?.outcome, Outcome.p1);
      expect(m.result?.g1, 2);
    }

    // Drop a player from inside the round: they finish it but are not paired again.
    final quitter = t.rounds.first.matches.firstWhere((m) => !m.isBye).p2!;
    final card = find.ancestor(of: find.text(t.nameOf(quitter)).first, matching: find.byType(InkWell)).first;
    await tester.tap(find.descendant(of: card, matching: find.byIcon(Icons.person_remove_outlined)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, t.nameOf(quitter)));
    await tester.pumpAndSettle();
    expect(t.player(quitter)!.dropped, isTrue);
    await tester.tapAt(const Offset(200, 60)); // close the sheet
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pair round 2'));
    await tester.pumpAndSettle();
    expect(t.rounds.length, 2);
    expect(t.rounds.last.matches.any((m) => m.involves(quitter)), isFalse);
    // Saved to storage.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('zira.tournaments.v1'), contains('אנה'));
  });
}
