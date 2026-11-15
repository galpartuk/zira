import 'models.dart';

/// Pure logic for online tournaments. No Firebase here: the cloud layer
/// turns Firestore docs into [Claim] / [Entry] and calls these.

class Claim {
  final String matchId;
  final String uid;
  final MatchResult result; // always from the match's p1/p2 point of view
  final int atMs;

  const Claim({required this.matchId, required this.uid, required this.result, required this.atMs});

  Map<String, dynamic> toJson() => {'matchId': matchId, 'uid': uid, 'r': result.toJson(), 'at': atMs};

  factory Claim.fromJson(Map<String, dynamic> j) => Claim(
        matchId: j['matchId'] as String,
        uid: j['uid'] as String,
        result: MatchResult.fromJson(Map<String, dynamic>.from(j['r'] as Map)),
        atMs: j['at'] as int? ?? 0,
      );
}

bool sameResult(MatchResult a, MatchResult b) => a.outcome == b.outcome && a.g1 == b.g1 && a.g2 == b.g2;

sealed class ClaimState {
  const ClaimState();
}

class NoClaims extends ClaimState {
  const NoClaims();
}

class Pending extends ClaimState {
  final Claim by;
  const Pending(this.by);
}

class Confirmed extends ClaimState {
  final MatchResult result;
  const Confirmed(this.result);
}

class Disputed extends ClaimState {
  final Claim a; // p1's claim
  final Claim b; // p2's claim
  const Disputed(this.a, this.b);
}

/// One claim vs a guest is accepted; two equal claims confirm; two different
/// claims are a dispute the host decides. Guest vs guest: the host enters it.
ClaimState resolveClaims(Tournament t, Match m, Iterable<Claim> claims) {
  if (m.isBye) return const NoClaims();
  final u1 = t.player(m.p1)?.uid;
  final u2 = t.player(m.p2)?.uid;
  Claim? find(String? uid) {
    if (uid == null) return null;
    for (final c in claims) {
      if (c.matchId == m.id && c.uid == uid) return c;
    }
    return null;
  }

  final c1 = find(u1);
  final c2 = find(u2);
  if (c1 == null && c2 == null) return const NoClaims();
  if (c1 != null && c2 != null) {
    return sameResult(c1.result, c2.result) ? Confirmed(c1.result) : Disputed(c1, c2);
  }
  final otherUid = c1 != null ? u2 : u1;
  final only = (c1 ?? c2)!;
  return otherUid == null ? Confirmed(only.result) : Pending(only);
}

enum EntryStatus { joined, requested, dropped, removed }

class Entry {
  final String uid;
  final String displayName;
  final EntryStatus status;

  const Entry({required this.uid, required this.displayName, required this.status});

  Map<String, dynamic> toJson() => {'displayName': displayName, 'status': status.name};

  factory Entry.fromJson(String uid, Map<String, dynamic> j) => Entry(
        uid: uid,
        displayName: j['displayName'] as String? ?? '?',
        status: EntryStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => EntryStatus.requested),
      );
}

/// Same naming rule as adding players by hand: "Gal", "Gal 2", "Gal 3".
String uniquePlayerName(Tournament t, String name) {
  final existing = t.players.map((p) => p.name).toSet();
  var out = name;
  var k = 2;
  while (existing.contains(out)) {
    out = '$name ${k++}';
  }
  return out;
}

/// Applies joins and drops. Returns true when [t] changed.
bool applyEntries(Tournament t, Iterable<Entry> entries) {
  var changed = false;
  for (final e in entries) {
    Player? p;
    for (final x in t.players) {
      if (x.uid == e.uid) p = x;
    }
    switch (e.status) {
      case EntryStatus.joined:
        if (p == null && t.acceptsNewPlayers) {
          t.players.add(Player(id: newId(), name: uniquePlayerName(t, e.displayName), uid: e.uid));
          changed = true;
        }
      case EntryStatus.dropped:
      case EntryStatus.removed:
        if (p != null) {
          if (!t.started) {
            t.players.remove(p);
            changed = true;
          } else if (!p.dropped) {
            p.dropped = true;
            changed = true;
          }
        }
      case EntryStatus.requested:
        break;
    }
  }
  return changed;
}

/// Who may report on which match: the last round, only once it is published.
Map<String, List<String>> matchUidsFor(Tournament t) {
  final r = t.currentRound;
  if (r == null || !r.published) return {};
  final out = <String, List<String>>{};
  for (final m in r.matches) {
    if (m.isBye) continue;
    final uids = [t.player(m.p1)?.uid, t.player(m.p2)?.uid].whereType<String>().toList();
    if (uids.isNotEmpty) out[m.id] = uids;
  }
  return out;
}

String onlineStatus(Tournament t) => t.finished ? 'finished' : (t.started ? 'running' : 'registration');

Round? draftRound(Tournament t) {
  final r = t.currentRound;
  return (r != null && !r.published) ? r : null;
}

/// What players may see: everything except a draft round.
Map<String, dynamic> publishedJson(Tournament t) {
  final j = t.toJson();
  j['rounds'] = [for (final r in t.rounds) if (r.published) r.toJson()];
  return j;
}

Round? roundOf(Tournament t, Match m) {
  for (final r in t.rounds) {
    if (r.matches.contains(m)) return r;
  }
  return null;
}
