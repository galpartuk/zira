import 'package:flutter_test/flutter_test.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/stats.dart';

/// Me ('me') against three opponents over three Swiss rounds + a bye round.
Tournament event(String id, List<(String opp, Outcome o, bool iAmP1)> games, {bool bye = false}) {
  final t = Tournament(id: id, name: id, players: [Player(id: 'me', name: 'Me', uid: 'u', tieRand: 0)]);
  var n = 0;
  for (final (opp, o, p1) in games) {
    if (t.player(opp) == null) t.players.add(Player(id: opp, name: opp, tieRand: ++n));
    t.rounds.add(Round(number: t.rounds.length + 1, stage: Stage.swiss, matches: [
      Match(id: '$id-r${t.rounds.length + 1}', table: 1, p1: p1 ? 'me' : opp, p2: p1 ? opp : 'me', result: MatchResult(o, 2, 1)),
    ]));
  }
  if (bye) t.rounds.add(Round(number: t.rounds.length + 1, stage: Stage.swiss, matches: [Match(id: '$id-bye', table: 0, p1: 'me')]));
  t.finished = true;
  return t;
}

void main() {
  test('outcome from my side, whichever seat I had', () {
    final t = event('a', [('x', Outcome.p1, true), ('y', Outcome.p1, false), ('z', Outcome.draw, true)]);
    expect([for (final r in t.rounds) outcomeFor(r.matches.single, 'me')], [1, -1, 0]);
  });

  test('records by my deck and by opponent deck, byes ignored, names grouped', () {
    final a = event('a', [('x', Outcome.p1, true), ('y', Outcome.p2, true), ('z', Outcome.draw, true)], bye: true);
    final b = event('b', [('x', Outcome.p1, true)]);
    final s = computeDeckStats([
      PlayedTournament(t: a, uid: 'u', myDeck: 'Red Hybrid', oppDecks: {'a-r1': 'Blue Flare', 'a-r2': 'blue flare '}),
      PlayedTournament(t: b, uid: 'u', myDeck: ' red hybrid', oppDecks: {'b-r1': 'Purple'}),
    ]);
    final red = s.byDeck['red hybrid']!;
    expect([red.wins, red.losses, red.draws, red.tournaments.length], [2, 1, 1, 2]);
    expect(s.label['red hybrid'], 'Red Hybrid');
    final vsBlue = s.matchups['red hybrid']!['blue flare']!;
    expect([vsBlue.wins, vsBlue.losses], [1, 1]);
    expect(s.matchups['red hybrid']![''], isNotNull); // round 3: opponent deck not recorded
    expect(s.allMatchups()['purple']!.wins, 1);
  });

  test('a tournament without my deck goes under the empty key', () {
    final s = computeDeckStats([PlayedTournament(t: event('a', [('x', Outcome.p1, true)]), uid: 'u')]);
    expect(s.byDeck['']!.wins, 1);
  });

  test('suggestions: one spelling per name, most used first', () {
    expect(deckSuggestions(['Blue', 'red', 'Red', 'Red', ' blue', null, '', 'Green']), ['Red', 'Blue', 'Green']);
  });
}
