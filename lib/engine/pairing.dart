import 'dart:math';

import 'models.dart';
import 'standings.dart';

String _key(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

/// Every pair that has already met in the Swiss / round-robin stage.
Set<String> playedPairs(Tournament t) {
  final s = <String>{};
  for (final r in t.swissRoundsList) {
    for (final m in r.matches) {
      if (!m.isBye) s.add(_key(m.p1, m.p2!));
    }
  }
  return s;
}

Set<String> playersWithBye(Tournament t) =>
    {for (final r in t.swissRoundsList) for (final m in r.matches) if (m.isBye) m.p1};

/// Builds the next Swiss round.
///
/// * Round 1 is random.
/// * Later rounds pair inside point groups (random order within a group),
///   floating down only when needed, never a rematch unless no legal pairing
///   exists at all.
/// * With an odd count, the bye goes to the lowest-ranked player who has not
///   had one yet (worth a win, 3 points).
Round pairSwissRound(Tournament t, {Random? rng}) {
  rng ??= Random();
  final number = t.swissRoundsList.length + 1;
  final standings = computeStandings(t).where((s) => !s.player.dropped).toList();

  // Order for pairing: by points, shuffled within each point group.
  final groups = <int, List<Standing>>{};
  for (final s in standings) {
    groups.putIfAbsent(s.points, () => []).add(s);
  }
  final pointsDesc = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  final order = <String>[];
  for (final p in pointsDesc) {
    final g = groups[p]!..shuffle(rng);
    order.addAll(g.map((s) => s.player.id));
  }

  final played = playedPairs(t);
  final hadBye = playersWithBye(t);

  List<String?> byeCandidates = [null];
  if (order.length.isOdd) {
    // Lowest ranked first. In round 1 the order is already random.
    final ranked = number == 1 ? (order.toList()..shuffle(rng)) : standings.map((s) => s.player.id).toList();
    final reversed = ranked.reversed.toList();
    final fresh = reversed.where((id) => !hadBye.contains(id)).toList();
    byeCandidates = fresh.isNotEmpty ? fresh : reversed;
  }

  List<(String, String)>? pairs;
  String? bye;
  for (final allowRematch in [false, true]) {
    for (final c in byeCandidates) {
      final pool = order.where((id) => id != c).toList();
      final budget = _Budget(200000);
      final res = _pair(pool, played, allowRematch, budget);
      if (res != null) {
        pairs = res;
        bye = c;
        break;
      }
    }
    if (pairs != null) break;
  }
  pairs ??= const [];

  final matches = <Match>[];
  var table = 1;
  for (final (a, b) in pairs) {
    matches.add(Match(table: table++, p1: a, p2: b));
  }
  if (bye != null) matches.add(Match(table: 0, p1: bye));
  return Round(number: number, stage: Stage.swiss, matches: matches);
}

class _Budget {
  int left;
  _Budget(this.left);
}

List<(String, String)>? _pair(List<String> ids, Set<String> played, bool allowRematch, _Budget budget) {
  if (ids.isEmpty) return [];
  if (--budget.left < 0) return null;
  final a = ids.first;
  for (var j = 1; j < ids.length; j++) {
    final b = ids[j];
    if (!allowRematch && played.contains(_key(a, b))) continue;
    final rest = [...ids.sublist(1, j), ...ids.sublist(j + 1)];
    final r = _pair(rest, played, allowRematch, budget);
    if (r != null) return [(a, b), ...r];
    if (budget.left < 0) return null;
  }
  return null;
}

/// Circle-method schedule: every player meets every other player once.
List<List<List<String?>>> buildRoundRobinSchedule(List<String> ids, {Random? rng}) {
  final list = <String?>[...ids]..shuffle(rng ?? Random());
  if (list.length.isOdd) list.add(null);
  final n = list.length;
  final rounds = <List<List<String?>>>[];
  var arr = [...list];
  for (var r = 0; r < n - 1; r++) {
    final pairs = <List<String?>>[];
    for (var i = 0; i < n ~/ 2; i++) {
      var a = arr[i], b = arr[n - 1 - i];
      // Alternate seats so nobody is always "player 1".
      if (r.isOdd && i == 0) (a, b) = (b, a);
      pairs.add([a, b]);
    }
    rounds.add(pairs);
    // Rotate everyone except the first.
    arr = [arr.first, arr.last, ...arr.sublist(1, n - 1)];
  }
  return rounds;
}

/// The next round of a round robin. A pairing that involves a dropped player
/// becomes a bye for the opponent.
Round roundRobinRound(Tournament t) {
  final number = t.swissRoundsList.length + 1;
  final sched = t.rrSchedule![number - 1];
  final matches = <Match>[];
  final byes = <String>[];
  var table = 1;
  for (final pair in sched) {
    final a = pair[0], b = pair[1];
    final aOk = a != null && !(t.player(a)?.dropped ?? true);
    final bOk = b != null && !(t.player(b)?.dropped ?? true);
    if (aOk && bOk) {
      matches.add(Match(table: table++, p1: a, p2: b));
    } else if (aOk) {
      byes.add(a);
    } else if (bOk) {
      byes.add(b);
    }
  }
  for (final id in byes) {
    matches.add(Match(table: 0, p1: id));
  }
  return Round(number: number, stage: Stage.swiss, matches: matches);
}

// ---------------------------------------------------------------- top cut

/// Standard seeded bracket order, e.g. 8 → [1,8,4,5,2,7,3,6].
List<int> bracketOrder(int size) {
  var order = [1, 2];
  while (order.length < size) {
    final n = order.length * 2;
    order = [for (final s in order) ...[s, n + 1 - s]];
  }
  return order;
}

/// The top cut actually used: the configured size, shrunk to the largest
/// power of two the active players can fill. Once the cut has started its
/// size is whatever the first bracket round holds (later drops don't shrink it).
int effectiveTopCut(Tournament t) {
  final tops = t.topRoundsList;
  if (tops.isNotEmpty) return tops.first.matches.where((m) => !m.thirdPlace).length * 2;
  if (t.topCut < 2) return 0;
  final active = t.activePlayers.length;
  var size = t.topCut;
  while (size > active && size > 1) {
    size ~/= 2;
  }
  return size >= 2 ? size : 0;
}

/// Players who make the cut, best seed first. Dropped players are skipped and
/// the next player moves up.
List<String> topCutQualifiers(Tournament t) {
  final size = effectiveTopCut(t);
  return computeStandings(t).where((s) => !s.player.dropped).take(size).map((s) => s.player.id).toList();
}

Round firstTopRound(Tournament t) {
  final q = topCutQualifiers(t);
  final order = bracketOrder(q.length);
  final matches = <Match>[];
  for (var i = 0; i < order.length; i += 2) {
    matches.add(Match(table: i ~/ 2 + 1, p1: q[order[i] - 1], p2: q[order[i + 1] - 1]));
  }
  return Round(number: 1, stage: Stage.top, matches: matches);
}

/// Next bracket round from the winners of the last one (plus a 3rd-place
/// match next to the final when enabled). Null when the bracket is over.
Round? nextTopRound(Tournament t) {
  final tops = t.topRoundsList;
  if (tops.isEmpty) return firstTopRound(t);
  final last = tops.last;
  if (!last.complete) return null;
  final main = last.matches.where((m) => !m.thirdPlace).toList();
  if (main.length <= 1) return null; // final played
  final winners = main.map((m) => m.winner!).toList();
  final matches = <Match>[];
  for (var i = 0; i < winners.length; i += 2) {
    matches.add(Match(table: i ~/ 2 + 1, p1: winners[i], p2: winners[i + 1]));
  }
  if (main.length == 2 && t.thirdPlace) {
    matches.add(Match(table: 2, p1: main[0].loser!, p2: main[1].loser!, thirdPlace: true));
  }
  return Round(number: last.number + 1, stage: Stage.top, matches: matches);
}

bool topCutFinished(Tournament t) {
  final tops = t.topRoundsList;
  if (tops.isEmpty) return false;
  final last = tops.last;
  return last.complete && last.matches.where((m) => !m.thirdPlace).length == 1;
}

/// Name of a bracket round by how many players are left in it.
String topRoundName(Round r) {
  final n = r.matches.where((m) => !m.thirdPlace).length * 2;
  switch (n) {
    case 2:
      return 'גמר';
    case 4:
      return 'חצי גמר';
    case 8:
      return 'רבע גמר';
    default:
      return 'טופ $n';
  }
}

// ---------------------------------------------------------------- placements

class Placement {
  final String playerId;
  final int place; // 1-based position in the final list
  final int groupFrom; // e.g. 3 for "3-4"
  final int groupTo; // e.g. 4 for "3-4"

  const Placement(this.playerId, this.place, this.groupFrom, this.groupTo);

  String get label => groupFrom == groupTo ? '$groupFrom' : '$groupFrom-$groupTo';
}

/// Final order of every player: bracket results first (when there is a top
/// cut), then everyone else by Swiss standings. Players knocked out in the
/// same bracket round share a group (e.g. 5-8) and are ordered by seed.
List<Placement> finalPlacements(Tournament t) {
  final standings = computeStandings(t);
  final seed = {for (final s in standings) s.player.id: s.rank};
  final out = <Placement>[];
  final placed = <String>{};

  void addGroup(List<String> ids) {
    if (ids.isEmpty) return;
    ids.sort((a, b) => seed[a]!.compareTo(seed[b]!));
    final from = out.length + 1, to = out.length + ids.length;
    for (final id in ids) {
      out.add(Placement(id, out.length + 1, from, to));
      placed.add(id);
    }
  }

  final tops = t.topRoundsList;
  if (tops.isEmpty && effectiveTopCut(t) > 0) {
    // Cut not played yet: whoever would qualify comes first (dropped
    // players can't make the cut, so they can't hold a top spot either).
    for (final id in topCutQualifiers(t)) {
      addGroup([id]);
    }
  }
  if (tops.isNotEmpty) {
    if (topCutFinished(t)) {
      final finalMatch = tops.last.matches.firstWhere((m) => !m.thirdPlace);
      addGroup([finalMatch.winner!]);
      addGroup([finalMatch.loser!]);
    } else {
      // Bracket still running: everyone not yet knocked out comes first, in
      // seed order, above anyone already eliminated.
      final out = {
        for (final r in tops)
          for (final m in r.matches)
            if (!m.thirdPlace && m.loser != null) m.loser!
      };
      final alive = tops.first.matches
          .expand((m) => [m.p1, if (m.p2 != null) m.p2!])
          .where((id) => !out.contains(id))
          .toList()
        ..sort((a, b) => seed[a]!.compareTo(seed[b]!));
      for (final id in alive) {
        addGroup([id]);
      }
    }
    for (var i = tops.length - 1; i >= 0; i--) {
      final r = tops[i];
      final third = r.matches.where((m) => m.thirdPlace && m.done).toList();
      if (third.isNotEmpty) {
        addGroup([third.first.winner!]);
        addGroup([third.first.loser!]);
      }
      final losers = r.matches
          .where((m) => !m.thirdPlace && m.done && m.loser != null)
          .map((m) => m.loser!)
          .where((id) => !placed.contains(id))
          .toList();
      addGroup(losers);
    }
  }
  for (final s in standings) {
    if (!placed.contains(s.player.id)) addGroup([s.player.id]);
  }
  return out;
}
