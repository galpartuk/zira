import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/cloud/history_repo.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/stats.dart';
import 'package:zira/widgets/deck_field.dart';

Tournament finished(String id, String hostUid) {
  final t = Tournament(
    id: id,
    name: id,
    players: [
      Player(id: 'a', name: 'Me', uid: 'me', tieRand: 1),
      Player(id: 'b', name: 'Bob', uid: 'bob', tieRand: 2),
    ],
  );
  t.rounds.add(
    Round(
      number: 1,
      stage: Stage.swiss,
      matches: [Match(id: '$id-m1', table: 1, p1: 'a', p2: 'b', result: const MatchResult(Outcome.p1, 2, 0))],
    ),
  );
  t.finished = true;
  return t;
}

void main() {
  test('records decks and joins them with my finished tournaments into stats', () async {
    final db = FakeFirebaseFirestore();
    await CloudStore(db, 'bob').saveAll([finished('t1', 'bob')]); // hosted by Bob, I played
    final repo = HistoryRepo(db, 'me');
    await repo.setMyDeck('t1', ' Red Hybrid ');
    await repo.setOppDeck('t1', 't1-m1', 'Blue Flare');
    final h = await repo.watch().first;
    expect(h['t1']!.myDeck, 'Red Hybrid');
    expect(h['t1']!.oppDecks, {'t1-m1': 'Blue Flare'});
    final played = await repo.playedFinished().first;
    expect(played.single.id, 't1');
    final s = computeDeckStats(HistoryRepo.join(played, h, 'me'));
    expect(s.matchups['red hybrid']!['blue flare']!.wins, 1);
    expect(HistoryRepo.suggestions(h), ['Red Hybrid', 'Blue Flare']);
  });

  testWidgets('deck field suggests names already used and saves the pick', (tester) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeckField(
            initial: '',
            suggestions: const ['Red Hybrid', 'Blue Flare'],
            hint: 'deck',
            onSave: (v) => saved = v,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'red');
    await tester.pumpAndSettle();
    expect(find.text('Red Hybrid'), findsOneWidget);
    expect(find.text('Blue Flare'), findsNothing);
    await tester.tap(find.text('Red Hybrid'));
    await tester.pumpAndSettle();
    expect(saved, 'Red Hybrid');
  });
}
