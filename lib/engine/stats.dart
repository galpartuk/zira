import 'models.dart';

/// Personal deck statistics. Pure: the cloud layer supplies finished
/// tournaments plus the player's own labels (their deck, opponents' decks).

/// Names are free text; group them ignoring case and outer spaces.
String deckKey(String? s) => (s ?? '').trim().toLowerCase();

/// One finished tournament the player played in, with what they recorded.
class PlayedTournament {
  final Tournament t;
  final String uid;
  final String? myDeck;
  final Map<String, String> oppDecks; // matchId -> opponent's deck

  const PlayedTournament({required this.t, required this.uid, this.myDeck, this.oppDecks = const {}});

  Player? get me => t.players.where((p) => p.uid == uid).firstOrNull;
}

/// Wins / losses / draws. Byes are not counted.
class Record {
  int wins = 0, losses = 0, draws = 0;
  final Set<String> tournaments = {};

  int get matches => wins + losses + draws;
  double get winRate => matches == 0 ? 0 : wins / matches;
}

/// The outcome of [m] for player [pid]: 1 win, -1 loss, 0 draw, null = no result / bye.
int? outcomeFor(Match m, String pid) {
  if (m.isBye || m.result == null) return null;
  final o = m.result!.outcome;
  if (o == Outcome.draw) return 0;
  if (o == Outcome.doubleLoss) return -1;
  final p1Won = o == Outcome.p1;
  return (m.p1 == pid) == p1Won ? 1 : -1;
}

class DeckStats {
  /// My deck key -> record (key '' = deck not recorded).
  final Map<String, Record> byDeck;

  /// My deck key -> opponent deck key -> record ('' = not recorded).
  final Map<String, Map<String, Record>> matchups;

  /// Key -> how to show it (the spelling used most often).
  final Map<String, String> label;

  DeckStats(this.byDeck, this.matchups, this.label);

  /// Matchups across all my decks.
  Map<String, Record> allMatchups() {
    final out = <String, Record>{};
    for (final per in matchups.values) {
      for (final e in per.entries) {
        final r = out.putIfAbsent(e.key, Record.new);
        r
          ..wins += e.value.wins
          ..losses += e.value.losses
          ..draws += e.value.draws
          ..tournaments.addAll(e.value.tournaments);
      }
    }
    return out;
  }
}

DeckStats computeDeckStats(Iterable<PlayedTournament> played) {
  final byDeck = <String, Record>{};
  final matchups = <String, Map<String, Record>>{};
  final spellings = <String, Map<String, int>>{};
  void spell(String? s) {
    final k = deckKey(s);
    if (k.isEmpty) return;
    final m = spellings.putIfAbsent(k, () => {});
    m[s!.trim()] = (m[s.trim()] ?? 0) + 1;
  }

  for (final pt in played) {
    final me = pt.me;
    if (me == null) continue;
    final mine = deckKey(pt.myDeck);
    spell(pt.myDeck);
    final deckRec = byDeck.putIfAbsent(mine, Record.new)..tournaments.add(pt.t.id);
    for (final r in pt.t.rounds) {
      for (final m in r.matches) {
        if (!m.involves(me.id)) continue;
        final o = outcomeFor(m, me.id);
        if (o == null) continue;
        final opp = deckKey(pt.oppDecks[m.id]);
        spell(pt.oppDecks[m.id]);
        final mu = matchups.putIfAbsent(mine, () => {}).putIfAbsent(opp, Record.new)..tournaments.add(pt.t.id);
        for (final rec in [deckRec, mu]) {
          if (o > 0) {
            rec.wins++;
          } else if (o < 0) {
            rec.losses++;
          } else {
            rec.draws++;
          }
        }
      }
    }
  }
  final label = {
    for (final e in spellings.entries)
      e.key: (e.value.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key,
  };
  return DeckStats(byDeck, matchups, label);
}

/// Every deck name the player has used (their own and opponents'), most used
/// first, one spelling per name. Feeds the autocomplete.
List<String> deckSuggestions(Iterable<String?> names) {
  final count = <String, int>{};
  final spelling = <String, Map<String, int>>{};
  for (final n in names) {
    final k = deckKey(n);
    if (k.isEmpty) continue;
    count[k] = (count[k] ?? 0) + 1;
    final m = spelling.putIfAbsent(k, () => {});
    m[n!.trim()] = (m[n.trim()] ?? 0) + 1;
  }
  final keys = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
  return [
    for (final k in keys) (spelling[k]!.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key,
  ];
}
