import 'models.dart';

/// Match points as in the Bandai rules: win 3, draw 1, loss / double loss 0.
const int kWinPts = 3;
const int kDrawPts = 1;

class Standing {
  final Player player;
  int points = 0;
  int wins = 0;
  int losses = 0;
  int draws = 0;
  int byes = 0;
  int played = 0; // includes byes
  int gamesWon = 0;
  int gamesPlayed = 0;
  final List<String> opponents = []; // byes excluded
  double mwp = 0; // own match-win %, floored
  double omw = 0; // opponents' match-win %
  double oomw = 0; // opponents' opponents' match-win %
  int rank = 0;

  Standing(this.player);

  String get record => draws > 0 ? '$wins-$losses-$draws' : '$wins-$losses';
}

/// Standings after the Swiss / round-robin stage (top cut does not change
/// points). Only reported matches count.
///
/// Tiebreakers: points → OMW% → OOMW% → random (fixed per player), which is
/// the order Bandai uses for the Digimon Card Game.
///
/// [beforeRound] (an index into [Tournament.rounds]) gives the standings as
/// they were when that round was paired — what a match card should show.
List<Standing> computeStandings(Tournament t, {int? beforeRound}) {
  final map = {for (final p in t.players) p.id: Standing(p)};

  final rounds = beforeRound == null ? t.rounds : t.rounds.take(beforeRound);
  for (final r in rounds) {
    if (r.stage != Stage.swiss) continue;
    for (final m in r.matches) {
      if (m.isBye) {
        final s = map[m.p1];
        if (s == null) continue;
        s
          ..points += kWinPts
          ..wins += 1
          ..byes += 1
          ..played += 1;
        continue;
      }
      final res = m.result;
      if (res == null) continue;
      final a = map[m.p1], b = map[m.p2];
      if (a == null || b == null) continue;
      a.played++;
      b.played++;
      a.opponents.add(b.player.id);
      b.opponents.add(a.player.id);
      a.gamesWon += res.g1;
      b.gamesWon += res.g2;
      final games = res.g1 + res.g2;
      a.gamesPlayed += games;
      b.gamesPlayed += games;
      switch (res.outcome) {
        case Outcome.p1:
          a.points += kWinPts;
          a.wins++;
          b.losses++;
        case Outcome.p2:
          b.points += kWinPts;
          b.wins++;
          a.losses++;
        case Outcome.draw:
          a.points += kDrawPts;
          b.points += kDrawPts;
          a.draws++;
          b.draws++;
        case Outcome.doubleLoss:
          a.losses++;
          b.losses++;
      }
    }
  }

  final floor = t.omwFloor;
  for (final s in map.values) {
    final raw = s.played == 0 ? 0.0 : s.points / (kWinPts * s.played);
    s.mwp = raw < floor ? floor : raw;
  }
  for (final s in map.values) {
    s.omw = s.opponents.isEmpty
        ? 0
        : s.opponents.map((o) => map[o]!.mwp).reduce((x, y) => x + y) / s.opponents.length;
  }
  for (final s in map.values) {
    s.oomw = s.opponents.isEmpty
        ? 0
        : s.opponents.map((o) => map[o]!.omw).reduce((x, y) => x + y) / s.opponents.length;
  }

  final list = map.values.toList()..sort(compareStandings);
  for (var i = 0; i < list.length; i++) {
    list[i].rank = i + 1;
  }
  return list;
}

int _cmpPct(double a, double b) {
  // Round so equal fractions computed by different paths compare equal.
  final x = (a * 1e9).round(), y = (b * 1e9).round();
  return y.compareTo(x);
}

int compareStandings(Standing a, Standing b) {
  if (a.points != b.points) return b.points.compareTo(a.points);
  final o = _cmpPct(a.omw, b.omw);
  if (o != 0) return o;
  final oo = _cmpPct(a.oomw, b.oomw);
  if (oo != 0) return oo;
  return a.player.tieRand.compareTo(b.player.tieRand);
}

String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
