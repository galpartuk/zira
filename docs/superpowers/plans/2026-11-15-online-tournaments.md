# Online Tournaments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Zira tournaments to Firebase so a signed-in host shares a join code, players join from their own phones, see their match live, report results that the opponent confirms, and the host publishes each round only after reviewing it.

**Architecture:** The host's app stays the single writer of the tournament: the whole `Tournament` JSON lives in one Firestore doc (`tournaments/{tid}`) and the existing pure-Dart engine keeps running on the host's phone. Players only write their own tiny docs (`entries/{uid}`, `claims/{matchId}_{uid}`); `HostSync` on the host's phone listens to them and feeds them through pure functions in `lib/engine/online.dart`. Draft rounds live in a host-only doc (`private/host`) until "Send to players".

**Tech Stack:** Flutter 3.44 / Dart 3.12, provider, firebase_core, firebase_auth, cloud_firestore (Spark plan, region `me-west1`), fake_cloud_firestore for Dart tests, Firestore emulator + `@firebase/rules-unit-testing` (Node 22) for rules tests.

**Spec:** `docs/superpowers/specs/2026-11-15-online-tournaments-design.md` (Hebrew). Read it first.

## Global Constraints

- Read `CLAUDE.md` in the repo root before starting. Its rules all apply.
- `lib/engine/` stays pure Dart: **no Flutter, no Firebase imports**, no user-visible text.
- Only `lib/cloud/` and `lib/state/host_sync.dart` / `lib/state/player_session.dart` import Firebase packages.
- Every new user-visible string goes through `S.t` in `lib/l10n.dart`, English **and** Hebrew, using the existing `_('en', 'he')` pattern.
- No push notifications, no Cloud Functions, nothing that needs the Blaze plan.
- Firestore region `me-west1`, Standard edition.
- Sign-in: Google (via `FirebaseAuth.signInWithProvider(GoogleAuthProvider())`, no `google_sign_in` package) **and** email+password with password reset.
- Join codes: 6 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no 0/O/1/I).
- Join modes: `open` (default) / `approval` / `closedOnStart`.
- Result vs a guest (player with `uid == null`) is accepted immediately; two equal claims confirm; two different claims = dispute, host decides; guest vs guest = host enters.
- Rounds created while online are **drafts** (`Round.published == false`) until the host taps "Send to players". Players cannot see or report on a draft.
- Keep `android/gradle.properties` heap at 1536m (low-RAM machine). If a release build OOMs, stop and report — do not raise it.
- APKs: **always** `flutter build apk --release --split-per-abi`, bump `version:` in pubspec above `1.3.1+9`, copies into `releases/`. The global APK guard hook must pass.
- Existing tests must keep passing (`flutter test`). They run with the local `PrefsStore` and `draftRounds: false`, so old behaviour is unchanged there.
- Work on branch `feature/online-tournaments`. Commit after each task, message ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Gal's phone installs over USB adb only (see memory `project_zira`).

## File Map

| File | Status | Responsibility |
|---|---|---|
| `lib/engine/models.dart` | modify | `Player.uid`, `Round.published`, `Tournament.joinCode` / `joinMode` |
| `lib/engine/online.dart` | create | Pure online logic: `Claim`, `ClaimState`, `resolveClaims`, `Entry`, `applyEntries`, `matchUidsFor`, `onlineStatus`, `publishedJson`, `draftRound` |
| `lib/state/app_state.dart` | modify | `TournamentStore` interface, `PrefsStore`, `attach/detach`, `draftRounds`, `publish()`, guards |
| `lib/cloud/firebase_options.dart` | generated | by `flutterfire configure` |
| `lib/cloud/tournament_repo.dart` | create | `CloudStore implements TournamentStore` |
| `lib/cloud/join_codes.dart` | create | `randomJoinCode`, `reserveJoinCode`, `lookupJoinCode` |
| `lib/cloud/claims.dart` | create | `writeClaim`, `writeEntry` (used by host-as-player and players) |
| `lib/cloud/auth_service.dart` | create | `AuthService` wrapper over FirebaseAuth + `users/{uid}` |
| `lib/state/host_sync.dart` | create | Listens to entries/claims of hosted tournaments, applies them |
| `lib/state/player_session.dart` | create | One joined tournament seen by a player |
| `lib/cloud/migrate_local.dart` | create | One-time upload of SharedPreferences tournaments |
| `lib/screens/sign_in_screen.dart` | create | Google / email sign-in, register, reset |
| `lib/screens/account_sheet.dart` | create | Display name, sign out, delete account |
| `lib/screens/join_screen.dart` | create | Enter code → join |
| `lib/screens/player_tournament_screen.dart` | create | Player view |
| `lib/widgets/my_match_card.dart` | create | "My match" card + report/confirm/dispute (player and host-as-player) |
| `lib/widgets/host_strip.dart` | create | Join code, join mode, round counters |
| `lib/screens/tournaments_screen.dart` | modify | Hosted + joined lists, Join button, account button |
| `lib/screens/tournament_screen.dart` | modify | Host strip, my-match card when host plays |
| `lib/screens/tabs/rounds_tab.dart` | modify | Draft banner + Send button, claim badges, dispute resolution |
| `lib/screens/tabs/players_tab.dart` | modify | Join requests, "Add me", remove online player |
| `lib/screens/tabs/bracket_tab.dart` | modify | `readOnly` flag |
| `lib/widgets/round_timer.dart` | modify | `readOnly` flag |
| `lib/main.dart` | modify | Firebase init, providers, auth gate |
| `lib/l10n.dart` | modify | New strings |
| `firebase.json`, `.firebaserc`, `firestore.rules`, `firestore.indexes.json` | create | Firebase config |
| `firebase/package.json`, `firebase/rules.test.mjs` | create | Rules tests |
| `test/online_test.dart` | create | Engine online logic |
| `test/app_state_store_test.dart` | create | AppState drafts / store |
| `test/cloud_store_test.dart` | create | CloudStore with fake Firestore |
| `test/host_sync_test.dart` | create | HostSync with fake Firestore |
| `test/player_session_test.dart` | create | PlayerSession + join with fake Firestore |

---

### Task 1: Engine — model fields

**Files:**
- Modify: `lib/engine/models.dart` (`Player`, `Round`, `Tournament`)
- Test: `test/online_test.dart`

**Interfaces:**
- Produces: `Player.uid` (`String?`, null = guest), `Round.published` (`bool`, mutable, default `true`), `Tournament.joinCode` (`String?`), `Tournament.joinMode` (`String`, default `'open'`). JSON keys: `uid`, `pub` (written only when false), `code`, `join` (written only when not `'open'`).

- [ ] **Step 1: Write the failing test** — create `test/online_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/engine/models.dart';

void main() {
  group('model fields', () {
    test('Player.uid round-trips and old JSON loads as guest', () {
      final p = Player(id: 'a', name: 'Gal', uid: 'u1', tieRand: 1);
      expect(Player.fromJson(p.toJson()).uid, 'u1');
      expect(Player.fromJson({'id': 'b', 'name': 'B', 'dropped': false, 'tieRand': 2}).uid, isNull);
      expect(Player(id: 'c', name: 'C', tieRand: 3).toJson().containsKey('uid'), isFalse);
    });

    test('Round.published defaults true, false survives JSON', () {
      final r = Round(number: 1, stage: Stage.swiss, matches: []);
      expect(r.published, isTrue);
      expect(r.toJson().containsKey('pub'), isFalse);
      r.published = false;
      expect(Round.fromJson(r.toJson()).published, isFalse);
    });

    test('Tournament joinCode / joinMode round-trip with defaults', () {
      final t = Tournament(name: 'T');
      expect(t.joinMode, 'open');
      expect(t.joinCode, isNull);
      t
        ..joinCode = 'K7Q2XM'
        ..joinMode = 'approval';
      final back = Tournament.fromJson(t.toJson());
      expect(back.joinCode, 'K7Q2XM');
      expect(back.joinMode, 'approval');
    });
  });
}
```

- [ ] **Step 2: Run** `flutter test test/online_test.dart` — Expected: FAIL (no named parameter `uid`, no getter `published`, …).

- [ ] **Step 3: Implement** in `lib/engine/models.dart`:

`Player`:
```dart
class Player {
  final String id;
  String name;
  bool dropped;

  /// Firebase user id when the player joined with an account; null = guest
  /// added by name by the host.
  final String? uid;

  final int tieRand;

  Player({required this.id, required this.name, this.dropped = false, this.uid, int? tieRand})
      : tieRand = tieRand ?? _rng.nextInt(1 << 30);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'dropped': dropped, 'tieRand': tieRand, if (uid != null) 'uid': uid};

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        id: j['id'] as String,
        name: j['name'] as String,
        dropped: j['dropped'] as bool? ?? false,
        uid: j['uid'] as String?,
        tieRand: j['tieRand'] as int?,
      );
}
```

`Round` — add the field, constructor param, JSON:
```dart
  /// Online tournaments: false while the host is still reviewing the pairing
  /// (a draft players can't see). Local tournaments always publish at once.
  bool published;

  Round({required this.number, required this.stage, required this.matches, this.published = true});

  Map<String, dynamic> toJson() => {
        'n': number,
        's': stage.index,
        'm': matches.map((m) => m.toJson()).toList(),
        if (!published) 'pub': false,
      };

  factory Round.fromJson(Map<String, dynamic> j) => Round(
        number: j['n'] as int,
        stage: Stage.values[j['s'] as int],
        matches: (j['m'] as List).map((e) => Match.fromJson(e as Map<String, dynamic>)).toList(),
        published: j['pub'] as bool? ?? true,
      );
```

`Tournament` — add after `timerPausedMs`:
```dart
  /// Online: the 6-character code players type to join, and who may join
  /// ('open' | 'approval' | 'closedOnStart').
  String? joinCode;
  String joinMode;
```
constructor params `this.joinCode, this.joinMode = 'open',`; in `toJson` add
`if (joinCode != null) 'code': joinCode, if (joinMode != 'open') 'join': joinMode,`; in `fromJson` add
`joinCode: j['code'] as String?, joinMode: j['join'] as String? ?? 'open',`.

- [ ] **Step 4: Run** `flutter test` — Expected: all PASS (new + existing).

- [ ] **Step 5: Commit**
```bash
git add lib/engine/models.dart test/online_test.dart
git commit -m "engine: Player.uid, Round.published, Tournament join code/mode"
```

---

### Task 2: Engine — online logic (`lib/engine/online.dart`)

**Files:**
- Create: `lib/engine/online.dart`
- Test: `test/online_test.dart` (append groups)

**Interfaces:**
- Consumes: Task 1 fields.
- Produces (all pure):
  - `class Claim { String matchId; String uid; MatchResult result; int atMs; toJson(); Claim.fromJson(Map) }`
  - `bool sameResult(MatchResult a, MatchResult b)`
  - `sealed class ClaimState` with `NoClaims`, `Pending(Claim by)`, `Confirmed(MatchResult result)`, `Disputed(Claim a, Claim b)` (a = p1's claim, b = p2's claim)
  - `ClaimState resolveClaims(Tournament t, Match m, Iterable<Claim> claims)`
  - `enum EntryStatus { joined, requested, dropped, removed }`, `class Entry { String uid; String displayName; EntryStatus status; Entry.fromJson; toJson }`
  - `bool applyEntries(Tournament t, Iterable<Entry> entries)` — returns true if `t` changed
  - `String uniquePlayerName(Tournament t, String name)` — same convention as the players tab (`'Gal'`, `'Gal 2'`, `'Gal 3'`)
  - `Map<String, List<String>> matchUidsFor(Tournament t)`
  - `String onlineStatus(Tournament t)` → `'registration' | 'running' | 'finished'`
  - `Map<String, dynamic> publishedJson(Tournament t)` — `t.toJson()` without unpublished rounds
  - `Round? draftRound(Tournament t)` — last round if unpublished
  - `Round? roundOf(Tournament t, Match m)`

- [ ] **Step 1: Write failing tests** — append to `test/online_test.dart` (add `import 'package:zira/engine/online.dart';`):

```dart
Tournament online2({String? u1 = 'u1', String? u2 = 'u2'}) {
  final t = Tournament(name: 'T', players: [
    Player(id: 'a', name: 'A', uid: u1, tieRand: 1),
    Player(id: 'b', name: 'B', uid: u2, tieRand: 2),
  ]);
  t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [Match(id: 'm1', table: 1, p1: 'a', p2: 'b')]));
  return t;
}

Claim claim(String uid, Outcome o, [int g1 = 2, int g2 = 1]) =>
    Claim(matchId: 'm1', uid: uid, result: MatchResult(o, g1, g2), atMs: 0);

void onlineGroups() {
  group('resolveClaims', () {
    test('no claims', () {
      final t = online2();
      expect(resolveClaims(t, t.rounds[0].matches[0], []), isA<NoClaims>());
    });
    test('one claim vs account holder is pending', () {
      final t = online2();
      final s = resolveClaims(t, t.rounds[0].matches[0], [claim('u1', Outcome.p1)]);
      expect(s, isA<Pending>());
      expect((s as Pending).by.uid, 'u1');
    });
    test('one claim vs guest is confirmed', () {
      final t = online2(u2: null);
      final s = resolveClaims(t, t.rounds[0].matches[0], [claim('u1', Outcome.p1)]);
      expect((s as Confirmed).result.outcome, Outcome.p1);
    });
    test('two equal claims confirm', () {
      final t = online2();
      final s = resolveClaims(t, t.rounds[0].matches[0], [claim('u1', Outcome.p1), claim('u2', Outcome.p1)]);
      expect(s, isA<Confirmed>());
    });
    test('two different claims dispute, p1 claim first', () {
      final t = online2();
      final s = resolveClaims(t, t.rounds[0].matches[0], [claim('u2', Outcome.p2, 1, 2), claim('u1', Outcome.p1)]);
      expect(s, isA<Disputed>());
      expect((s as Disputed).a.uid, 'u1');
      expect(s.b.uid, 'u2');
    });
    test('claims from outsiders or other matches are ignored', () {
      final t = online2();
      final other = Claim(matchId: 'zzz', uid: 'u1', result: const MatchResult(Outcome.p1, 2, 0), atMs: 0);
      expect(resolveClaims(t, t.rounds[0].matches[0], [claim('u9', Outcome.p1), other]), isA<NoClaims>());
    });
    test('guest vs guest never resolves', () {
      final t = online2(u1: null, u2: null);
      expect(resolveClaims(t, t.rounds[0].matches[0], [claim('u1', Outcome.p1)]), isA<NoClaims>());
    });
  });

  group('applyEntries', () {
    test('joined adds a player once, with a unique name', () {
      final t = Tournament(name: 'T', players: [Player(id: 'x', name: 'Gal', tieRand: 1)]);
      final e = Entry(uid: 'u1', displayName: 'Gal', status: EntryStatus.joined);
      expect(applyEntries(t, [e]), isTrue);
      expect(applyEntries(t, [e]), isFalse);
      expect(t.players.where((p) => p.uid == 'u1').single.name, 'Gal 2');
    });
    test('requested adds nothing', () {
      final t = Tournament(name: 'T');
      expect(applyEntries(t, [Entry(uid: 'u1', displayName: 'A', status: EntryStatus.requested)]), isFalse);
      expect(t.players, isEmpty);
    });
    test('dropped before start removes, after start marks dropped', () {
      final t = Tournament(name: 'T', players: [Player(id: 'a', name: 'A', uid: 'u1', tieRand: 1)]);
      applyEntries(t, [Entry(uid: 'u1', displayName: 'A', status: EntryStatus.dropped)]);
      expect(t.players, isEmpty);
      final s = online2();
      applyEntries(s, [Entry(uid: 'u1', displayName: 'A', status: EntryStatus.dropped)]);
      expect(s.player('a')!.dropped, isTrue);
    });
    test('joined is ignored when the event no longer accepts players', () {
      final t = online2()..finished = true;
      expect(applyEntries(t, [Entry(uid: 'u3', displayName: 'C', status: EntryStatus.joined)]), isFalse);
    });
  });

  group('cloud shape', () {
    test('matchUidsFor uses the last published round and skips guests and byes', () {
      final t = online2(u2: null);
      t.rounds[0].matches.add(Match(id: 'bye', table: 2, p1: 'b'));
      expect(matchUidsFor(t), {'m1': ['u1']});
      t.rounds[0].published = false;
      expect(matchUidsFor(t), isEmpty);
    });
    test('publishedJson drops the draft; draftRound returns it', () {
      final t = online2();
      t.rounds.add(Round(number: 2, stage: Stage.swiss, matches: [], published: false));
      expect((publishedJson(t)['rounds'] as List).length, 1);
      expect(draftRound(t)!.number, 2);
      t.rounds.last.published = true;
      expect(draftRound(t), isNull);
    });
    test('onlineStatus', () {
      expect(onlineStatus(Tournament(name: 'T')), 'registration');
      final t = online2();
      expect(onlineStatus(t), 'running');
      t.finished = true;
      expect(onlineStatus(t), 'finished');
    });
  });
}
```
and call `onlineGroups();` at the end of `main()`.

- [ ] **Step 2: Run** `flutter test test/online_test.dart` — Expected: FAIL (`online.dart` missing).

- [ ] **Step 3: Implement** `lib/engine/online.dart`:

```dart
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
```

- [ ] **Step 4: Run** `flutter test` — Expected: all PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/engine/online.dart test/online_test.dart
git commit -m "engine: claims, entries and cloud shape for online tournaments"
```

---

### Task 3: AppState — store interface, drafts, publish

**Files:**
- Modify: `lib/state/app_state.dart`
- Test: `test/app_state_store_test.dart`

**Interfaces:**
- Consumes: `Round.published`, `roundOf` (Task 2).
- Produces:
  - `abstract class TournamentStore { Future<List<Tournament>> load(); Future<void> saveAll(List<Tournament> ts); Future<void> delete(Tournament t); }`
  - `class PrefsStore implements TournamentStore` (today's behaviour, key `zira.tournaments.v1`)
  - `AppState({TournamentStore? store, bool draftRounds = false})`
  - `Future<void> attach(TournamentStore store, {required bool draftRounds})` — swaps store and reloads
  - `void detach()` — clears tournaments, back to `PrefsStore`, `draftRounds = false`
  - `bool draftRounds` (getter), `void publish(Tournament t)`
  - `start`/`advance`/`repair` create rounds with `published = !draftRounds`; `advance` returns early while a draft exists; `setResult` ignores matches in unpublished rounds.

- [ ] **Step 1: Write failing tests** — `test/app_state_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/state/app_state.dart';

class MemStore implements TournamentStore {
  List<Tournament> saved = [];
  final deleted = <String>[];
  int saves = 0;
  @override
  Future<List<Tournament>> load() async => saved;
  @override
  Future<void> saveAll(List<Tournament> ts) async {
    saves++;
    saved = [...ts];
  }
  @override
  Future<void> delete(Tournament t) async => deleted.add(t.id);
}

Tournament four() => Tournament(name: 'T', players: [
      for (var i = 0; i < 4; i++) Player(id: 'p$i', name: 'P$i', tieRand: i),
    ]);

void main() {
  test('local mode publishes rounds immediately (old behaviour)', () async {
    final app = AppState(store: MemStore());
    await app.load();
    final t = four();
    app.add(t);
    app.start(t);
    expect(t.rounds.single.published, isTrue);
  });

  test('draft mode: start makes a draft, publish sends it, results blocked on drafts', () async {
    final store = MemStore();
    final app = AppState(store: store, draftRounds: true);
    await app.load();
    final t = four();
    app.add(t);
    app.start(t);
    final r = t.rounds.single;
    expect(r.published, isFalse);
    app.setResult(t, r.matches.first, const MatchResult(Outcome.p1, 2, 0));
    expect(r.matches.first.result, isNull);
    app.publish(t);
    expect(r.published, isTrue);
    app.setResult(t, r.matches.first, const MatchResult(Outcome.p1, 2, 0));
    expect(r.matches.first.result, isNotNull);
  });

  test('advance does nothing while a draft is pending; repair keeps it a draft', () async {
    final app = AppState(store: MemStore(), draftRounds: true);
    await app.load();
    final t = four();
    app.add(t);
    app.start(t);
    app.advance(t);
    expect(t.rounds.length, 1);
    app.repair(t);
    expect(t.rounds.single.published, isFalse);
  });

  test('remove calls store.delete; attach reloads from the new store', () async {
    final a = MemStore();
    final app = AppState(store: a);
    await app.load();
    final t = four();
    app.add(t);
    app.remove(t);
    expect(a.deleted, [t.id]);
    final b = MemStore()..saved = [four()];
    await app.attach(b, draftRounds: true);
    expect(app.tournaments.length, 1);
    expect(app.draftRounds, isTrue);
    app.detach();
    expect(app.tournaments, isEmpty);
    expect(app.draftRounds, isFalse);
  });
}
```

- [ ] **Step 2: Run** `flutter test test/app_state_store_test.dart` — Expected: FAIL (`TournamentStore` undefined).

- [ ] **Step 3: Implement.** In `lib/state/app_state.dart` replace the top of the class (fields, `load`, `_save`, `add`, `remove`) and add the store classes:

```dart
import '../engine/online.dart';

/// Where tournaments are kept. [PrefsStore] = the phone (old behaviour, used
/// by tests and before sign-in); the cloud store lives in lib/cloud/.
abstract class TournamentStore {
  Future<List<Tournament>> load();
  Future<void> saveAll(List<Tournament> ts);
  Future<void> delete(Tournament t);
}

class PrefsStore implements TournamentStore {
  static const key = 'zira.tournaments.v1';

  @override
  Future<List<Tournament>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Tournament.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('load failed: $e');
      return [];
    }
  }

  @override
  Future<void> saveAll(List<Tournament> ts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(ts.map((t) => t.toJson()).toList()));
  }

  @override
  Future<void> delete(Tournament t) async {} // saveAll already dropped it
}

class AppState extends ChangeNotifier {
  AppState({TournamentStore? store, bool draftRounds = false})
      : _store = store ?? PrefsStore(),
        _draftRounds = draftRounds;

  TournamentStore _store;
  bool _draftRounds;

  /// Online: new rounds are drafts until [publish].
  bool get draftRounds => _draftRounds;

  final List<Tournament> tournaments = [];
  bool loaded = false;

  Future<void> load() async {
    final list = await _store.load();
    tournaments
      ..clear()
      ..addAll(list);
    loaded = true;
    notifyListeners();
  }

  Future<void> attach(TournamentStore store, {required bool draftRounds}) async {
    _store = store;
    _draftRounds = draftRounds;
    loaded = false;
    notifyListeners();
    await load();
  }

  void detach() {
    _store = PrefsStore();
    _draftRounds = false;
    tournaments.clear();
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() => _store.saveAll(tournaments);

  void changed() {
    notifyListeners();
    _save();
  }

  // byId, add unchanged

  void remove(Tournament t) {
    tournaments.remove(t);
    _store.delete(t);
    changed();
  }
```
Remove the old `static const _key` and `_prefs` field (keep `exportAll` / `importAll`).

Round creation — in `start`, `advance`, `repair` mark new rounds. Add a helper and use it everywhere a round is added:
```dart
  Round _fresh(Round r) => r..published = !_draftRounds;
```
- `start`: `t.rounds.add(_fresh(roundRobinRound(t)))` / `t.rounds.add(_fresh(pairSwissRound(t)))`.
- `advance`: first line becomes
  `if (t.finished || t.firstIncompleteRound != null || draftRound(t) != null) return;`
  and every `t.rounds.add(x)` becomes `t.rounds.add(_fresh(x))` (`r` from `nextTopRound` too).
- `repair`: the re-paired round gets `_fresh(...)`.

Publish and the result guard:
```dart
  /// Sends the draft round to the players and resets the round clock.
  void publish(Tournament t) {
    final r = draftRound(t);
    if (r == null) return;
    r.published = true;
    resetTimer(t, notify: false);
    changed();
  }

  void setResult(Tournament t, Match m, MatchResult? r) {
    if (roundOf(t, m)?.published == false) return; // drafts can't be scored
    m.result = r;
    changed();
  }
```

- [ ] **Step 4: Run** `flutter test` — Expected: all PASS (old `flow_test` still uses `AppState()` → `PrefsStore`, no drafts).

- [ ] **Step 5: Commit**
```bash
git add lib/state/app_state.dart test/app_state_store_test.dart
git commit -m "state: pluggable TournamentStore, draft rounds and publish"
```

---

### Task 4: Firebase project + app wiring (needs Gal)

**Files:**
- Create: `lib/cloud/firebase_options.dart` (generated), `firebase.json`, `.firebaserc`, `firestore.indexes.json`, `firestore.rules` (placeholder deny-all until Task 5)
- Modify: `pubspec.yaml`, `lib/main.dart`, `android/app/build.gradle(.kts)` only if minSdk < 23

**Interfaces:**
- Produces: `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` runs in `main()` before `runApp`. Packages available to later tasks.

- [ ] **Step 1: Gal — console steps** (send these to Gal in Hebrew and wait):
  1. https://console.firebase.google.com → Add project → name `zira` → **turn Google Analytics off** → Create.
  2. Build → Firestore Database → Create database → **Standard edition**, location **`me-west1` (Tel Aviv)** → Start in **production mode**.
  3. Build → Authentication → Get started → Sign-in method → enable **Google** (pick a support email) and **Email/Password**.
  4. Send back the project ID.

- [ ] **Step 2: CLI login (Gal types it)**: ask Gal to run `! npx firebase-tools@13 login` in the prompt (interactive browser login). Then:
```bash
dart pub global activate flutterfire_cli
cd /c/Users/Owner/zira
flutterfire configure --project=<PROJECT_ID> --platforms=android,web \
  --android-package-name=com.galpartuk.zira --out=lib/cloud/firebase_options.dart --yes
```
Expected: `lib/cloud/firebase_options.dart` and `android/app/google-services.json` created.

- [ ] **Step 3: Register signing fingerprints** (Google sign-in fails without them):
```bash
keytool -list -v -keystore /c/Users/Owner/keys/zira-release.jks   # password: credentials txt next to the .jks
keytool -list -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey
npx firebase-tools@13 apps:list --project <PROJECT_ID>              # Android app id
npx firebase-tools@13 apps:android:sha:create <APP_ID> <SHA1> --project <PROJECT_ID>   # repeat for each SHA-1 and SHA-256
```
If the app is ever published on Play, also add Play App Signing's SHA-1 (Play Console → App integrity). Note this in `CLAUDE.md` in Task 11.

- [ ] **Step 4: Dependencies**
```bash
flutter pub add firebase_core firebase_auth cloud_firestore
flutter pub add --dev fake_cloud_firestore
```
Check `android/app/build.gradle*`: `minSdk` must be ≥ 23 (if it reads `flutter.minSdkVersion`, Flutter 3.44's default is fine — verify by grepping `minSdkVersion` in the Flutter SDK's `flutter.gradle`/`FlutterExtension`; if < 23 set `minSdk = 23`).

- [ ] **Step 5: Firebase config files** — `firebase.json`:
```json
{
  "firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
  "emulators": { "firestore": { "port": 8080 }, "auth": { "port": 9099 }, "ui": { "enabled": false } }
}
```
`.firebaserc`: `{ "projects": { "default": "<PROJECT_ID>" } }`
`firestore.indexes.json`: `{ "indexes": [], "fieldOverrides": [] }`
`firestore.rules` (temporary):
```
rules_version = '2';
service cloud.firestore { match /databases/{db}/documents { match /{d=**} { allow read, write: if false; } } }
```

- [ ] **Step 6: Init in `lib/main.dart`**:
```dart
import 'package:firebase_core/firebase_core.dart';
import 'cloud/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // ...existing SystemChrome / Lang / runApp unchanged
}
```

- [ ] **Step 7: Verify**: `flutter test` (PASS — tests don't call `main()`), `flutter build web` succeeds, and `flutter build apk --debug` succeeds with the 1536m heap. If Gradle OOMs, stop and report to Gal.

- [ ] **Step 8: Commit** (google-services.json and firebase_options.dart contain only public client config — commit them; the repo is private):
```bash
git add pubspec.yaml pubspec.lock lib/main.dart lib/cloud/firebase_options.dart android/app/google-services.json firebase.json .firebaserc firestore.indexes.json firestore.rules android/
git commit -m "firebase: project wiring (core, auth, firestore)"
```

---

### Task 5: Firestore security rules + emulator tests

**Files:**
- Modify: `firestore.rules`
- Create: `firebase/package.json`, `firebase/rules.test.mjs`
- Modify: `.gitignore` (add `firebase/node_modules/`, `firebase-debug.log`, `firestore-debug.log`)

**Interfaces:**
- Consumes: doc shapes from the spec (`tournaments/{tid}` with `hostUid`, `memberUids`, `matchUids`, `joinMode`, `status`; `entries/{uid}` with `status`, `displayName`; `claims/{matchId}_{uid}` with `matchId`, `uid`; `joinCodes/{code}` with `tid`, `hostUid`).
- Produces: deployed rules later tasks rely on.

- [ ] **Step 1: Write the failing tests** — `firebase/package.json`:
```json
{
  "name": "zira-rules-tests",
  "private": true,
  "type": "module",
  "scripts": { "test": "firebase emulators:exec --only firestore --project demo-zira \"node --test rules.test.mjs\"" },
  "devDependencies": {
    "@firebase/rules-unit-testing": "^4.0.0",
    "firebase": "^11.0.0",
    "firebase-tools": "^13.0.0"
  }
}
```
(`firebase-tools` 13 because this PC has Java 17; v14+ emulators need Java 21.)

`firebase/rules.test.mjs`:
```js
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-zira',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'tournaments/t1'), {
      hostUid: 'host', joinMode: 'open', status: 'registration',
      memberUids: ['host', 'alice'], matchUids: { m1: ['alice', 'bob'] }, data: {},
    });
    await setDoc(doc(db, 'tournaments/t1/private/host'), { draftRound: null });
    await setDoc(doc(db, 'joinCodes/ABC234'), { tid: 't1', hostUid: 'host' });
  });
});
const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const claim = (uid, matchId = 'm1') => ({ matchId, uid, r: { o: 0, g1: 2, g2: 1 }, at: 1 });

test('signed-out users read nothing', () => assertFails(getDoc(doc(anon(), 'tournaments/t1'))));
test('any signed-in user can get a tournament and a join code', async () => {
  await assertSucceeds(getDoc(doc(as('zed'), 'tournaments/t1')));
  await assertSucceeds(getDoc(doc(as('zed'), 'joinCodes/ABC234')));
});
test('list only tournaments I am a member of', async () => {
  await assertSucceeds(getDocs(query(collection(as('alice'), 'tournaments'), where('memberUids', 'array-contains', 'alice'))));
  await assertFails(getDocs(collection(as('alice'), 'tournaments')));
});
test('only the host writes the tournament', async () => {
  await assertSucceeds(updateDoc(doc(as('host'), 'tournaments/t1'), { status: 'running' }));
  await assertFails(updateDoc(doc(as('alice'), 'tournaments/t1'), { status: 'running' }));
  await assertFails(updateDoc(doc(as('host'), 'tournaments/t1'), { hostUid: 'alice' }));
});
test('create tournament only as myself', async () => {
  await assertSucceeds(setDoc(doc(as('zed'), 'tournaments/t2'), { hostUid: 'zed', memberUids: ['zed'], joinMode: 'open', status: 'registration', matchUids: {} }));
  await assertFails(setDoc(doc(as('zed'), 'tournaments/t3'), { hostUid: 'host', memberUids: ['zed'] }));
});
test('private/host only for the host', async () => {
  await assertSucceeds(getDoc(doc(as('host'), 'tournaments/t1/private/host')));
  await assertFails(getDoc(doc(as('alice'), 'tournaments/t1/private/host')));
});
test('join codes: create once, never overwrite, delete by host', async () => {
  await assertSucceeds(setDoc(doc(as('zed'), 'joinCodes/ZZZ999'), { tid: 't9', hostUid: 'zed' }));
  await assertFails(setDoc(doc(as('zed'), 'joinCodes/ABC234'), { tid: 't9', hostUid: 'zed' }));
  await assertFails(deleteDoc(doc(as('zed'), 'joinCodes/ABC234')));
  await assertSucceeds(deleteDoc(doc(as('host'), 'joinCodes/ABC234')));
});
test('entries: join only as myself, with the right status for the mode', async () => {
  await assertSucceeds(setDoc(doc(as('bob'), 'tournaments/t1/entries/bob'), { displayName: 'Bob', status: 'joined' }));
  await assertFails(setDoc(doc(as('bob'), 'tournaments/t1/entries/carol'), { displayName: 'C', status: 'joined' }));
  await assertFails(setDoc(doc(as('carol'), 'tournaments/t1/entries/carol'), { displayName: 'C', status: 'requested' }));
});
test('entries: approval mode needs requested; closedOnStart blocks after start', async () => {
  await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'tournaments/t1'), { joinMode: 'approval' }));
  await assertFails(setDoc(doc(as('bob'), 'tournaments/t1/entries/bob'), { displayName: 'Bob', status: 'joined' }));
  await assertSucceeds(setDoc(doc(as('bob'), 'tournaments/t1/entries/bob'), { displayName: 'Bob', status: 'requested' }));
  await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'tournaments/t1'), { joinMode: 'closedOnStart', status: 'running' }));
  await assertFails(setDoc(doc(as('dan'), 'tournaments/t1/entries/dan'), { displayName: 'Dan', status: 'joined' }));
});
test('entries: player may drop, host may approve/remove, removed cannot come back', async () => {
  await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'tournaments/t1/entries/bob'), { displayName: 'Bob', status: 'requested' }));
  await assertSucceeds(updateDoc(doc(as('host'), 'tournaments/t1/entries/bob'), { status: 'joined' }));
  await assertSucceeds(updateDoc(doc(as('bob'), 'tournaments/t1/entries/bob'), { status: 'dropped' }));
  await assertSucceeds(updateDoc(doc(as('host'), 'tournaments/t1/entries/bob'), { status: 'removed' }));
  await assertFails(updateDoc(doc(as('bob'), 'tournaments/t1/entries/bob'), { status: 'joined' }));
  await assertFails(updateDoc(doc(as('host'), 'tournaments/t1/entries/bob'), { displayName: 'X' }));
});
test('claims: only my own, only on my published match', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'tournaments/t1/claims/m1_alice'), claim('alice')));
  await assertFails(setDoc(doc(as('alice'), 'tournaments/t1/claims/m1_bob'), claim('bob')));
  await assertFails(setDoc(doc(as('carol'), 'tournaments/t1/claims/m1_carol'), claim('carol')));
  await assertFails(setDoc(doc(as('alice'), 'tournaments/t1/claims/m2_alice'), claim('alice', 'm2')));
});
test('claims readable by members and host only', async () => {
  await assertSucceeds(getDocs(collection(as('alice'), 'tournaments/t1/claims')));
  await assertSucceeds(getDocs(collection(as('host'), 'tournaments/t1/claims')));
  await assertFails(getDocs(collection(as('zed'), 'tournaments/t1/claims')));
});
test('users: write only my own', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'users/alice'), { displayName: 'A' }));
  await assertFails(setDoc(doc(as('alice'), 'users/bob'), { displayName: 'B' }));
});
```

- [ ] **Step 2: Run** `cd firebase && npm install && npm test` — Expected: FAIL (deny-all rules from Task 4).

- [ ] **Step 3: Write `firestore.rules`**:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn() { return request.auth != null; }
    function me() { return request.auth.uid; }

    match /users/{uid} {
      allow read: if signedIn();
      allow write: if signedIn() && me() == uid;
    }

    match /joinCodes/{code} {
      allow get: if signedIn();
      allow create: if signedIn() && request.resource.data.hostUid == me();
      allow delete: if signedIn() && resource.data.hostUid == me();
    }

    match /tournaments/{tid} {
      function t() { return get(/databases/$(db)/documents/tournaments/$(tid)).data; }
      function isHost() { return signedIn() && t().hostUid == me(); }
      function isMember() { return signedIn() && me() in t().memberUids; }

      allow get: if signedIn();
      allow list: if signedIn() && me() in resource.data.memberUids;
      allow create: if signedIn() && request.resource.data.hostUid == me();
      allow update: if signedIn() && resource.data.hostUid == me() && request.resource.data.hostUid == me();
      allow delete: if signedIn() && resource.data.hostUid == me();

      match /private/{doc} {
        allow read, write: if isHost();
      }

      match /entries/{uid} {
        function joinAllowed(status) {
          return t().status != 'finished'
            && !(t().joinMode == 'closedOnStart' && t().status != 'registration')
            && ((t().joinMode == 'approval' && status == 'requested')
                || (t().joinMode != 'approval' && status == 'joined'));
        }
        allow read: if isHost() || isMember() || (signedIn() && me() == uid);
        allow create: if signedIn() && me() == uid
          && request.resource.data.keys().hasOnly(['displayName', 'status', 'at'])
          && joinAllowed(request.resource.data.status);
        allow update: if signedIn() && (
            (me() == uid && resource.data.status != 'removed'
              && request.resource.data.status == 'dropped'
              && request.resource.data.displayName == resource.data.displayName)
            || (isHost() && request.resource.data.status in ['joined', 'removed']
              && request.resource.data.displayName == resource.data.displayName));
        allow delete: if false;
      }

      match /claims/{cid} {
        allow read: if isHost() || isMember();
        allow create, update: if signedIn()
          && request.resource.data.uid == me()
          && cid == request.resource.data.matchId + '_' + me()
          && me() in t().matchUids.get(request.resource.data.matchId, []);
        allow delete: if false;
      }
    }
  }
}
```

- [ ] **Step 4: Run** `cd firebase && npm test` — Expected: all PASS. If a test needs a different rule than written, fix the rule, not the test, unless the test contradicts the spec.

- [ ] **Step 5: Deploy** `npx firebase-tools@13 deploy --only firestore:rules --project <PROJECT_ID>` — Expected: "Deploy complete".

- [ ] **Step 6: Commit**
```bash
git add firestore.rules firebase/package.json firebase/package-lock.json firebase/rules.test.mjs .gitignore
git commit -m "firestore: security rules + emulator tests"
```

---

### Task 6: CloudStore, join codes, claim/entry writers

**Files:**
- Create: `lib/cloud/tournament_repo.dart`, `lib/cloud/join_codes.dart`, `lib/cloud/claims.dart`
- Test: `test/cloud_store_test.dart`

**Interfaces:**
- Consumes: `TournamentStore` (Task 3), `publishedJson`, `draftRound`, `matchUidsFor`, `onlineStatus`, `Claim`, `Entry` (Task 2).
- Produces:
  - `class CloudStore implements TournamentStore { CloudStore(FirebaseFirestore db, String uid); }` — `load()` returns tournaments this uid **hosts** (draft merged back as last round); `saveAll` writes only tournaments whose JSON changed since last load/save; `delete` removes the doc, `private/host`, and `joinCodes/{code}`.
  - Doc written: `{hostUid, name, joinCode, joinMode, status, memberUids, matchUids, updatedAt, data}`; `private/host`: `{draftRound: Map|null}`.
  - `String randomJoinCode([Random? rng])`
  - `Future<String> reserveJoinCode(FirebaseFirestore db, {required String tid, required String hostUid})`
  - `Future<String?> lookupJoinCode(FirebaseFirestore db, String code)` → tid or null (code upper-cased, trimmed)
  - `Future<void> writeClaim(FirebaseFirestore db, String tid, Claim c)` → doc `claims/${c.matchId}_${c.uid}`
  - `Future<void> writeEntry(FirebaseFirestore db, String tid, Entry e)` → doc `entries/${e.uid}` with `{displayName, status, at: serverTimestamp}` (use `set` with merge)

- [ ] **Step 1: Write failing tests** — `test/cloud_store_test.dart`:
```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/cloud/claims.dart';
import 'package:zira/cloud/join_codes.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';

Tournament t2() {
  final t = Tournament(id: 't1', name: 'T', players: [
    Player(id: 'a', name: 'A', uid: 'host', tieRand: 1),
    Player(id: 'b', name: 'B', uid: 'bob', tieRand: 2),
    Player(id: 'c', name: 'Guest', tieRand: 3),
  ]);
  t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [Match(id: 'm1', table: 1, p1: 'a', p2: 'b')]));
  return t;
}

void main() {
  test('save writes the published shape and a host-only draft', () async {
    final db = FakeFirebaseFirestore();
    final store = CloudStore(db, 'host');
    final t = t2()..joinCode = 'ABC234';
    t.rounds.add(Round(number: 2, stage: Stage.swiss, matches: [Match(id: 'm2', table: 1, p1: 'a', p2: 'c')], published: false));
    await store.saveAll([t]);
    final doc = (await db.doc('tournaments/t1').get()).data()!;
    expect(doc['hostUid'], 'host');
    expect(doc['status'], 'running');
    expect(doc['joinCode'], 'ABC234');
    expect(doc['joinMode'], 'open');
    expect(List<String>.from(doc['memberUids']), unorderedEquals(['host', 'bob']));
    expect(doc['matchUids'], isEmpty); // last round is a draft
    expect((doc['data']['rounds'] as List).length, 1);
    final priv = (await db.doc('tournaments/t1/private/host').get()).data()!;
    expect(priv['draftRound']['n'], 2);
  });

  test('load merges the draft back and only returns hosted tournaments', () async {
    final db = FakeFirebaseFirestore();
    final t = t2();
    t.rounds.add(Round(number: 2, stage: Stage.swiss, matches: [], published: false));
    await CloudStore(db, 'host').saveAll([t]);
    await db.doc('tournaments/other').set({'hostUid': 'zed', 'memberUids': ['zed', 'host'], 'data': t2().toJson()});
    final loaded = await CloudStore(db, 'host').load();
    expect(loaded.single.id, 't1');
    expect(loaded.single.rounds.length, 2);
    expect(loaded.single.rounds.last.published, isFalse);
  });

  test('unchanged tournaments are not rewritten', () async {
    final db = FakeFirebaseFirestore();
    final store = CloudStore(db, 'host');
    final t = t2();
    await store.saveAll([t]);
    await db.doc('tournaments/t1').update({'name': 'tampered'});
    await store.saveAll([t]);
    expect((await db.doc('tournaments/t1').get()).data()!['name'], 'tampered');
    t.name = 'New';
    await store.saveAll([t]);
    expect((await db.doc('tournaments/t1').get()).data()!['name'], 'New');
  });

  test('delete removes doc, private and join code', () async {
    final db = FakeFirebaseFirestore();
    final store = CloudStore(db, 'host');
    final t = t2()..joinCode = 'ABC234';
    await store.saveAll([t]);
    await db.doc('joinCodes/ABC234').set({'tid': 't1', 'hostUid': 'host'});
    await store.delete(t);
    expect((await db.doc('tournaments/t1').get()).exists, isFalse);
    expect((await db.doc('joinCodes/ABC234').get()).exists, isFalse);
  });

  test('join codes: alphabet, reserve, lookup', () async {
    final code = randomJoinCode();
    expect(code, matches(RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$')));
    final db = FakeFirebaseFirestore();
    final c = await reserveJoinCode(db, tid: 't1', hostUid: 'host');
    expect(await lookupJoinCode(db, ' ${c.toLowerCase()} '), 't1');
    expect(await lookupJoinCode(db, 'ZZZZZZ'), isNull);
  });

  test('writeClaim and writeEntry doc ids', () async {
    final db = FakeFirebaseFirestore();
    await writeClaim(db, 't1', const Claim(matchId: 'm1', uid: 'bob', result: MatchResult(Outcome.p2, 1, 2), atMs: 5));
    expect((await db.doc('tournaments/t1/claims/m1_bob').get()).data()!['uid'], 'bob');
    await writeEntry(db, 't1', const Entry(uid: 'bob', displayName: 'Bob', status: EntryStatus.joined));
    expect((await db.doc('tournaments/t1/entries/bob').get()).data()!['status'], 'joined');
  });
}
```

- [ ] **Step 2: Run** `flutter test test/cloud_store_test.dart` — Expected: FAIL (files missing).

- [ ] **Step 3: Implement**

`lib/cloud/tournament_repo.dart`:
```dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../engine/models.dart';
import '../engine/online.dart';
import '../state/app_state.dart';

/// Tournaments the signed-in user hosts, stored in Firestore. Only the host
/// writes `tournaments/{tid}`; the draft round goes to `private/host`.
class CloudStore implements TournamentStore {
  final FirebaseFirestore db;
  final String uid;
  final _lastSaved = <String, String>{};

  CloudStore(this.db, this.uid);

  CollectionReference<Map<String, dynamic>> get _col => db.collection('tournaments');

  @override
  Future<List<Tournament>> load() async {
    // The rules only allow listing by membership; the host is always a member.
    final q = await _col.where('memberUids', arrayContains: uid).get();
    final out = <Tournament>[];
    for (final d in q.docs) {
      if (d.data()['hostUid'] != uid) continue;
      final t = Tournament.fromJson(Map<String, dynamic>.from(d.data()['data'] as Map));
      final priv = await d.reference.collection('private').doc('host').get();
      final draft = priv.data()?['draftRound'];
      if (draft != null) {
        t.rounds.add(Round.fromJson(Map<String, dynamic>.from(draft as Map))..published = false);
      }
      _lastSaved[t.id] = jsonEncode(t.toJson());
      out.add(t);
    }
    out.sort((a, b) => b.created.compareTo(a.created));
    return out;
  }

  @override
  Future<void> saveAll(List<Tournament> ts) async {
    for (final t in ts) {
      final sig = jsonEncode(t.toJson());
      if (_lastSaved[t.id] == sig) continue;
      _lastSaved[t.id] = sig;
      final batch = db.batch();
      final ref = _col.doc(t.id);
      batch.set(ref, {
        'hostUid': uid,
        'name': t.name,
        'joinCode': t.joinCode,
        'joinMode': t.joinMode,
        'status': onlineStatus(t),
        'memberUids': {uid, ...t.players.map((p) => p.uid).whereType<String>()}.toList(),
        'matchUids': matchUidsFor(t),
        'updatedAt': FieldValue.serverTimestamp(),
        'data': publishedJson(t),
      });
      batch.set(ref.collection('private').doc('host'), {'draftRound': draftRound(t)?.toJson()});
      // Not awaited by callers: Firestore queues it offline and syncs later.
      await batch.commit();
    }
  }

  @override
  Future<void> delete(Tournament t) async {
    _lastSaved.remove(t.id);
    final ref = _col.doc(t.id);
    final batch = db.batch()
      ..delete(ref.collection('private').doc('host'))
      ..delete(ref);
    if (t.joinCode != null) batch.delete(db.collection('joinCodes').doc(t.joinCode));
    await batch.commit();
  }
}
```

`lib/cloud/join_codes.dart`:
```dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

const joinCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
final _rng = Random.secure();

String randomJoinCode([Random? rng]) {
  final r = rng ?? _rng;
  return List.generate(6, (_) => joinCodeAlphabet[r.nextInt(joinCodeAlphabet.length)]).join();
}

/// Claims a free code for [tid]. Needs a connection (transaction).
Future<String> reserveJoinCode(FirebaseFirestore db, {required String tid, required String hostUid}) async {
  for (var i = 0; i < 10; i++) {
    final code = randomJoinCode();
    final ref = db.collection('joinCodes').doc(code);
    final ok = await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return false;
      tx.set(ref, {'tid': tid, 'hostUid': hostUid});
      return true;
    });
    if (ok) return code;
  }
  throw StateError('no free join code');
}

Future<String?> lookupJoinCode(FirebaseFirestore db, String code) async {
  final c = code.trim().toUpperCase();
  if (c.length != 6) return null;
  final snap = await db.collection('joinCodes').doc(c).get();
  return snap.data()?['tid'] as String?;
}
```

`lib/cloud/claims.dart`:
```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../engine/online.dart';

Future<void> writeClaim(FirebaseFirestore db, String tid, Claim c) =>
    db.doc('tournaments/$tid/claims/${c.matchId}_${c.uid}').set(c.toJson());

Future<void> writeEntry(FirebaseFirestore db, String tid, Entry e) => db
    .doc('tournaments/$tid/entries/${e.uid}')
    .set({...e.toJson(), 'at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
```

- [ ] **Step 4: Run** `flutter test` — Expected: all PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/cloud/ test/cloud_store_test.dart
git commit -m "cloud: CloudStore, join codes, claim/entry writers"
```

---

### Task 7: Auth, sign-in screen, account sheet, app gate, local migration

**Files:**
- Create: `lib/cloud/auth_service.dart`, `lib/cloud/migrate_local.dart`, `lib/screens/sign_in_screen.dart`, `lib/screens/account_sheet.dart`
- Modify: `lib/main.dart`, `lib/screens/tournaments_screen.dart`, `lib/l10n.dart`
- Test: `test/migrate_local_test.dart`

**Interfaces:**
- Consumes: `AppState.attach/detach` (Task 3), `CloudStore` (Task 6), `PrefsStore.key`.
- Produces:
  - `class AuthService extends ChangeNotifier { AuthService(FirebaseAuth auth, FirebaseFirestore db); User? user; String displayName; Future<void> signInGoogle(); Future<void> signInEmail(String email, String pw); Future<void> register(String name, String email, String pw); Future<void> resetPassword(String email); Future<void> setDisplayName(String n); Future<void> signOut(); Future<void> deleteAccount(); }` — on every sign-in writes `users/{uid}` `{displayName, createdAt}` (merge).
  - `Future<int> migrateLocalTournaments(SharedPreferences prefs, CloudStore store, String uid)` — uploads `PrefsStore.key` tournaments once per uid (flag `zira.migrated.<uid>`), leaves the local copy in place, returns count.
  - `ZiraApp({AuthService? auth})` — `auth == null` (tests) keeps the old local behaviour.
  - Provider tree: `ChangeNotifierProvider<AppState>`, `ChangeNotifierProvider<AuthService>` (when present), `Provider<FirebaseFirestore>` (when present), `ChangeNotifierProvider<HostSync>` added in Task 8.

- [ ] **Step 1: Write the failing migration test** — `test/migrate_local_test.dart`:
```dart
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zira/cloud/migrate_local.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/state/app_state.dart';

void main() {
  test('uploads local tournaments once per user and keeps the local copy', () async {
    final local = [Tournament(id: 'old1', name: 'Old', players: [Player(id: 'a', name: 'A', tieRand: 1)])];
    SharedPreferences.setMockInitialValues({PrefsStore.key: jsonEncode(local.map((t) => t.toJson()).toList())});
    final prefs = await SharedPreferences.getInstance();
    final db = FakeFirebaseFirestore();
    expect(await migrateLocalTournaments(prefs, CloudStore(db, 'gal'), 'gal'), 1);
    expect((await db.doc('tournaments/old1').get()).data()!['hostUid'], 'gal');
    expect(await migrateLocalTournaments(prefs, CloudStore(db, 'gal'), 'gal'), 0);
    expect(prefs.getString(PrefsStore.key), isNotNull);
  });
}
```

- [ ] **Step 2: Run** `flutter test test/migrate_local_test.dart` — Expected: FAIL.

- [ ] **Step 3: Implement `lib/cloud/migrate_local.dart`**:
```dart
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_state.dart';
import 'tournament_repo.dart';

/// First sign-in: the tournaments that lived only on this phone become cloud
/// tournaments hosted by [uid]. The local copy stays as a backup.
Future<int> migrateLocalTournaments(SharedPreferences prefs, CloudStore store, String uid) async {
  final flag = 'zira.migrated.$uid';
  if (prefs.getBool(flag) ?? false) return 0;
  final local = await PrefsStore().load();
  if (local.isNotEmpty) await store.saveAll(local);
  await prefs.setBool(flag, true);
  return local.length;
}
```

- [ ] **Step 4: Run** the test — Expected: PASS.

- [ ] **Step 5: Implement `lib/cloud/auth_service.dart`**:
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  User? user;

  AuthService(this.auth, this.db) {
    user = auth.currentUser;
    auth.userChanges().listen((u) {
      user = u;
      notifyListeners();
    });
  }

  String get displayName => user?.displayName?.trim().isNotEmpty == true ? user!.displayName! : (user?.email ?? '?');

  Future<void> _profile() async {
    final u = auth.currentUser;
    if (u == null) return;
    await db.doc('users/${u.uid}').set(
        {'displayName': displayName, 'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> signInGoogle() async {
    final p = GoogleAuthProvider();
    kIsWeb ? await auth.signInWithPopup(p) : await auth.signInWithProvider(p);
    await _profile();
  }

  Future<void> signInEmail(String email, String pw) async {
    await auth.signInWithEmailAndPassword(email: email.trim(), password: pw);
    await _profile();
  }

  Future<void> register(String name, String email, String pw) async {
    final c = await auth.createUserWithEmailAndPassword(email: email.trim(), password: pw);
    await c.user!.updateDisplayName(name.trim());
    await c.user!.reload();
    user = auth.currentUser;
    await _profile();
  }

  Future<void> resetPassword(String email) => auth.sendPasswordResetEmail(email: email.trim());

  Future<void> setDisplayName(String n) async {
    await auth.currentUser!.updateDisplayName(n.trim());
    await auth.currentUser!.reload();
    user = auth.currentUser;
    await _profile();
    notifyListeners();
  }

  Future<void> signOut() => auth.signOut();

  /// Throws FirebaseAuthException(code: 'requires-recent-login') when the
  /// sign-in is old; the UI then asks the user to sign in again and retries.
  Future<void> deleteAccount() async {
    final u = auth.currentUser!;
    await db.doc('users/${u.uid}').delete();
    await u.delete();
  }
}
```

- [ ] **Step 6: Strings** — add to `lib/l10n.dart` under a new `// ---- account` section:
```dart
  String get signIn => _('Sign in', 'התחברות');
  String get signInGoogle => _('Continue with Google', 'המשך עם Google');
  String get email => _('Email', 'אימייל');
  String get password => _('Password', 'סיסמה');
  String get displayNameLabel => _('Your name', 'השם שלך');
  String get register => _('Create account', 'יצירת חשבון');
  String get haveAccount => _('I have an account', 'יש לי חשבון');
  String get noAccount => _('New here? Create an account', 'חדש כאן? יצירת חשבון');
  String get forgotPassword => _('Forgot password?', 'שכחתי סיסמה');
  String get resetSent => _('Reset link sent — check your email', 'נשלח קישור לאיפוס — בדוק את האימייל');
  String get signInNeeded => _('Sign in to run and join tournaments', 'התחבר כדי לנהל טורנירים ולהצטרף אליהם');
  String get account => _('Account', 'חשבון');
  String get signOut => _('Sign out', 'התנתקות');
  String get deleteAccount => _('Delete account', 'מחיקת חשבון');
  String get deleteAccountBody => _('Your account is deleted. Your name stays in past tournaments.',
      'החשבון יימחק. השם שלך יישאר בטורנירים שהיו.');
  String get signInAgain => _('Please sign in again, then delete.', 'צריך להתחבר שוב ואז למחוק.');
  String authError(String code) => switch (code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => _('Wrong email or password', 'אימייל או סיסמה שגויים'),
        'email-already-in-use' => _('This email already has an account', 'לאימייל הזה כבר יש חשבון'),
        'weak-password' => _('Password must be at least 6 characters', 'סיסמה של 6 תווים לפחות'),
        'invalid-email' => _('Invalid email', 'אימייל לא תקין'),
        'network-request-failed' => _('No connection', 'אין חיבור'),
        _ => _('Sign-in failed ($code)', 'ההתחברות נכשלה ($code)'),
      };
  String migrated(int n) => _('$n tournaments moved to your account', '$n טורנירים הועברו לחשבון שלך');
```

- [ ] **Step 7: `lib/screens/sign_in_screen.dart`** — a single scrollable screen: app name, Google button, divider, email + password fields (+ name field in register mode), primary button, toggle register/sign-in, "Forgot password?" link. Errors from `FirebaseAuthException` shown with `toast(context, S.t.authError(e.code))`; Google cancel (`code == 'web-context-canceled'` / `'canceled'`) is silent. Full code:
```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cloud/auth_service.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _register = false;
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on FirebaseAuthException catch (e) {
      if (mounted && !e.code.contains('cancel')) toast(context, S.t.authError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return Scaffold(
      appBar: AppBar(title: Text(S.t.signIn), actions: const [LangButton()]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(S.t.signInNeeded, style: const TextStyle(color: Z.muted)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(auth.signInGoogle),
          icon: const Icon(Icons.login),
          label: Text(S.t.signInGoogle),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),
        if (_register) TextField(controller: _name, decoration: InputDecoration(labelText: S.t.displayNameLabel)),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: S.t.email)),
        TextField(controller: _pw, obscureText: true, decoration: InputDecoration(labelText: S.t.password)),
        const SizedBox(height: 16),
        FilledButton.tonal(
          onPressed: _busy
              ? null
              : () => _run(() => _register
                  ? auth.register(_name.text, _email.text, _pw.text)
                  : auth.signInEmail(_email.text, _pw.text)),
          child: Text(_register ? S.t.register : S.t.signIn),
        ),
        TextButton(
            onPressed: () => setState(() => _register = !_register),
            child: Text(_register ? S.t.haveAccount : S.t.noAccount)),
        if (!_register)
          TextButton(
            onPressed: () => _run(() async {
              await auth.resetPassword(_email.text);
              if (mounted) toast(context, S.t.resetSent);
            }),
            child: Text(S.t.forgotPassword),
          ),
      ]),
    );
  }
}
```

- [ ] **Step 8: `lib/screens/account_sheet.dart`** — bottom sheet: name (tap → `promptText` → `setDisplayName`), "Sign out", "Delete account" (`confirm(...)` with `deleteAccountBody`; on `requires-recent-login` toast `signInAgain` and sign out). Function `Future<void> showAccountSheet(BuildContext context)`.
```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cloud/auth_service.dart';
import '../l10n.dart';
import '../widgets/common.dart';

Future<void> showAccountSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      builder: (c) {
        final auth = c.read<AuthService>();
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(auth.displayName),
              subtitle: Text(auth.user?.email ?? ''),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final n = await promptText(c, S.t.displayNameLabel, initial: auth.displayName);
                if (n != null && n.trim().isNotEmpty) await auth.setDisplayName(n);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(S.t.signOut),
              onTap: () {
                Navigator.pop(c);
                auth.signOut();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: Text(S.t.deleteAccount),
              onTap: () async {
                final ok = await confirm(c, S.t.deleteAccount, S.t.deleteAccountBody, ok: S.t.deleteAccount);
                if (!ok || !c.mounted) return;
                Navigator.pop(c);
                try {
                  await auth.deleteAccount();
                } on FirebaseAuthException catch (e) {
                  if (e.code == 'requires-recent-login') {
                    if (context.mounted) toast(context, S.t.signInAgain);
                    await auth.signOut();
                  }
                }
              },
            ),
          ]),
        );
      },
    );
```
(Check `confirm`'s signature in `lib/widgets/common.dart:143` and adapt the named `ok:` argument if it differs.)

- [ ] **Step 9: Gate in `lib/main.dart`**:
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  SystemChrome.setSystemUIOverlayStyle(/* unchanged */);
  Lang.instance.load();
  final db = FirebaseFirestore.instance;
  final auth = AuthService(FirebaseAuth.instance, db);
  runApp(MultiProvider(providers: [
    ChangeNotifierProvider(create: (_) => AppState()), // loaded by CloudGate
    ChangeNotifierProvider.value(value: auth),
    Provider<FirebaseFirestore>.value(value: db),
  ], child: const ZiraApp(online: true)));
}
```
`ZiraApp({super.key, this.online = false})`. When `online`, `home:` is `CloudGate(child: HomeScreen(...))`, else unchanged. `CloudGate` (in `lib/main.dart`) is a `StatefulWidget` that listens to `AuthService`; when `user` changes:
- signed in → `final store = CloudStore(db, uid); final n = await migrateLocalTournaments(prefs, store, uid); await app.attach(store, draftRounds: true); if (n > 0) toast(S.t.migrated(n))`
- signed out → `app.detach()`.
It only reacts when the uid actually changes (keep `_uid`). It always shows `child`; the tournaments tab decides what to render.

Existing tests build `ZiraApp()` with `online: false` → they don't touch Firebase.

- [ ] **Step 10: Tournaments tab when signed out** — in `TournamentsScreen.build`, if `context.watch<AuthService?>()` is non-null and `user == null`, return a `Scaffold` with `EmptyState(icon: Icons.lock_outline, title: S.t.signIn, body: S.t.signInNeeded, action: FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignInScreen())), child: Text(S.t.signIn)))`. Pop the sign-in route automatically when sign-in succeeds (in `SignInScreen`, listen to `AuthService` and `Navigator.maybePop` once `user != null`). Use `Provider.of<AuthService?>(context)` guarded with try/catch-free lookup: `context.watch<AuthService?>()` requires the provider to be registered as nullable — register as `ChangeNotifierProvider<AuthService?>.value` in online mode and don't register in tests; use `Provider.of<AuthService?>(context, listen: true)` wrapped in a helper `AuthService? authOf(BuildContext c)` that catches `ProviderNotFoundException` and returns null. Add an account `IconButton(icon: Icon(Icons.account_circle_outlined), onPressed: () => showAccountSheet(context))` to the app bar when signed in. Remove the "Copy backup / Restore backup" menu only if Gal asks — keep it.

- [ ] **Step 11: Verify** — `flutter test` all PASS. Manual: `flutter run -d chrome` → sign in with Google and with a new email account, sign out, sign in again; check `users/{uid}` in the Firebase console; local tournaments appear after first sign-in on the phone build.

- [ ] **Step 12: Commit**
```bash
git add lib/ test/migrate_local_test.dart
git commit -m "auth: Google + email sign-in, account sheet, cloud gate, local migration"
```

---

### Task 8: HostSync — entries and claims into the engine

**Files:**
- Create: `lib/state/host_sync.dart`
- Modify: `lib/main.dart` (provider; start/stop with sign-in), `lib/screens/tournaments_screen.dart` (`_create` reserves a join code)
- Test: `test/host_sync_test.dart`

**Interfaces:**
- Consumes: `AppState`, `applyEntries`, `resolveClaims`, `Claim`, `Entry`, `writeEntry`, `reserveJoinCode`.
- Produces:
  - `class HostSync extends ChangeNotifier { HostSync(FirebaseFirestore db, AppState app, String uid); void dispose(); }`
  - `ClaimState stateOf(Tournament t, Match m)` (from cached claims)
  - `List<Entry> requests(Tournament t)` — entries with `requested`
  - `Future<void> approve(Tournament t, String uid)` → entry status `joined`
  - `Future<void> removePlayer(Tournament t, Player p)` → entry `removed` + same local effect as `applyEntries`
  - `bool roundHasClaims(Tournament t, Round r)`
  - `({int reported, int pending, int disputed, int total}) roundCounts(Tournament t)`
  - `Future<void> ensureJoinCode(Tournament t)` — reserves a code if `t.joinCode == null`, sets it, `app.changed()`; on failure leaves it null (UI shows "Get code").
  - Behaviour: for each hosted, unfinished tournament keeps two listeners (`entries`, `claims`). On every snapshot: `applyEntries`; then for each match of the last **published** round with `result == null` whose state is `Confirmed`, call `app.setResult` once per claim signature (`_applied` set keyed `matchId|o|g1|g2`) so a result the host cleared on purpose is not re-applied in the same session. Calls `notifyListeners()` after every snapshot. Re-syncs its listener set whenever `AppState` notifies (tournament added/removed/finished).

- [ ] **Step 1: Write failing tests** — `test/host_sync_test.dart`:
```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/cloud/claims.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';
import 'package:zira/state/app_state.dart';
import 'package:zira/state/host_sync.dart';

Future<(FakeFirebaseFirestore, AppState, HostSync, Tournament)> setup() async {
  final db = FakeFirebaseFirestore();
  final app = AppState(store: CloudStore(db, 'host'), draftRounds: true);
  await app.load();
  final t = Tournament(id: 't1', name: 'T', players: [
    Player(id: 'a', name: 'A', uid: 'alice', tieRand: 1),
    Player(id: 'b', name: 'B', uid: 'bob', tieRand: 2),
    Player(id: 'c', name: 'C', tieRand: 3),
    Player(id: 'd', name: 'D', uid: 'dan', tieRand: 4),
  ]);
  app.add(t);
  final sync = HostSync(db, app, 'host');
  await pumpEventQueue();
  return (db, app, sync, t);
}

Claim c(String matchId, String uid, Outcome o) =>
    Claim(matchId: matchId, uid: uid, result: MatchResult(o, o == Outcome.p1 ? 2 : 0, o == Outcome.p1 ? 0 : 2), atMs: 0);

void main() {
  test('a joined entry adds the player', () async {
    final (db, app, sync, t) = await setup();
    await writeEntry(db, 't1', const Entry(uid: 'eve', displayName: 'Eve', status: EntryStatus.joined));
    await pumpEventQueue();
    expect(t.players.any((p) => p.uid == 'eve'), isTrue);
    sync.dispose();
  });

  test('requests are listed and approve joins them', () async {
    final (db, app, sync, t) = await setup();
    await writeEntry(db, 't1', const Entry(uid: 'eve', displayName: 'Eve', status: EntryStatus.requested));
    await pumpEventQueue();
    expect(sync.requests(t).single.uid, 'eve');
    await sync.approve(t, 'eve');
    await pumpEventQueue();
    expect(t.players.any((p) => p.uid == 'eve'), isTrue);
    sync.dispose();
  });

  test('confirmed claims set the result; disputes and pending do not', () async {
    final (db, app, sync, t) = await setup();
    app.start(t);
    app.publish(t);
    final r = t.currentRound!;
    final m = r.matches.firstWhere((m) => !m.isBye && t.player(m.p1)!.uid != null && t.player(m.p2)!.uid != null);
    final u1 = t.player(m.p1)!.uid!, u2 = t.player(m.p2)!.uid!;
    await writeClaim(db, 't1', c(m.id, u1, Outcome.p1));
    await pumpEventQueue();
    expect(m.result, isNull);
    expect(sync.stateOf(t, m), isA<Pending>());
    await writeClaim(db, 't1', c(m.id, u2, Outcome.p2));
    await pumpEventQueue();
    expect(m.result, isNull);
    expect(sync.stateOf(t, m), isA<Disputed>());
    await writeClaim(db, 't1', c(m.id, u2, Outcome.p1));
    await pumpEventQueue();
    expect(m.result!.outcome, Outcome.p1);
    // host clears it on purpose → not re-applied this session
    app.setResult(t, m, null);
    await writeClaim(db, 't1', c(m.id, u2, Outcome.p1));
    await pumpEventQueue();
    expect(m.result, isNull);
    sync.dispose();
  });

  test('a claim vs a guest is applied at once', () async {
    final (db, app, sync, t) = await setup();
    app.start(t);
    app.publish(t);
    final m = t.currentRound!.matches.firstWhere((m) => !m.isBye && (t.player(m.p1)!.uid == null || t.player(m.p2)?.uid == null));
    final reporter = t.player(m.p1)!.uid ?? t.player(m.p2)!.uid!;
    await writeClaim(db, 't1', c(m.id, reporter, Outcome.p2));
    await pumpEventQueue();
    expect(m.result!.outcome, Outcome.p2);
    sync.dispose();
  });

  test('finishing releases the join code', () async {
    final (db, app, sync, t) = await setup();
    await db.doc('joinCodes/ABC234').set({'tid': 't1', 'hostUid': 'host'});
    t
      ..joinCode = 'ABC234'
      ..finished = true;
    app.changed();
    await pumpEventQueue();
    expect(t.joinCode, isNull);
    expect((await db.doc('joinCodes/ABC234').get()).exists, isFalse);
    sync.dispose();
  });

  test('removePlayer before start removes and blocks rejoin', () async {
    final (db, app, sync, t) = await setup();
    await sync.removePlayer(t, t.player('b')!);
    expect(t.player('b'), isNull);
    expect((await db.doc('tournaments/t1/entries/bob').get()).data()!['status'], 'removed');
    sync.dispose();
  });

  test('roundCounts', () async {
    final (db, app, sync, t) = await setup();
    app.start(t);
    app.publish(t);
    expect(sync.roundCounts(t).total, t.currentRound!.matches.where((m) => !m.isBye).length);
    sync.dispose();
  });
}
```
(4 players with pairing randomness: the guest test finds whichever match includes guest `C`; the dispute test finds a match with two account holders — with 4 players, one of the two matches always has C, the other always has two uids.)

- [ ] **Step 2: Run** `flutter test test/host_sync_test.dart` — Expected: FAIL.

- [ ] **Step 3: Implement `lib/state/host_sync.dart`**:
```dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../cloud/claims.dart';
import '../cloud/join_codes.dart';
import '../engine/models.dart';
import '../engine/online.dart';
import 'app_state.dart';

/// Runs on the host's phone: turns players' entries and claims into engine
/// changes. The host's app is the only writer of the tournament doc.
class HostSync extends ChangeNotifier {
  final FirebaseFirestore db;
  final AppState app;
  final String uid;

  final _subs = <String, List<StreamSubscription>>{};
  final _claims = <String, List<Claim>>{};
  final _entries = <String, List<Entry>>{};
  final _applied = <String>{};

  HostSync(this.db, this.app, this.uid) {
    app.addListener(_resync);
    _resync();
  }

  void _resync() {
    for (final t in app.tournaments) {
      if (t.finished && t.joinCode != null) _releaseCodeIfFinished(t);
    }
    final live = {for (final t in app.tournaments) if (!t.finished) t.id};
    for (final id in _subs.keys.toList()) {
      if (!live.contains(id)) {
        for (final s in _subs.remove(id)!) {
          s.cancel();
        }
      }
    }
    for (final id in live) {
      if (_subs.containsKey(id)) continue;
      final ref = db.collection('tournaments').doc(id);
      _subs[id] = [
        ref.collection('entries').snapshots().listen((s) {
          _entries[id] = [for (final d in s.docs) Entry.fromJson(d.id, d.data())];
          _apply(id);
        }),
        ref.collection('claims').snapshots().listen((s) {
          _claims[id] = [for (final d in s.docs) Claim.fromJson(d.data())];
          _apply(id);
        }),
      ];
    }
  }

  void _apply(String tid) {
    final t = app.byId(tid);
    if (t == null) return;
    var changed = applyEntries(t, _entries[tid] ?? const []);
    final r = t.currentRound;
    if (r != null && r.published) {
      for (final m in r.matches) {
        if (m.isBye || m.result != null) continue;
        final s = resolveClaims(t, m, _claims[tid] ?? const []);
        if (s is Confirmed) {
          final key = '${m.id}|${s.result.outcome.index}|${s.result.g1}|${s.result.g2}';
          if (_applied.add(key)) {
            m.result = s.result;
            changed = true;
          }
        }
      }
    }
    if (changed) app.changed();
    notifyListeners();
  }

  ClaimState stateOf(Tournament t, Match m) => resolveClaims(t, m, _claims[t.id] ?? const []);

  List<Entry> requests(Tournament t) =>
      (_entries[t.id] ?? const []).where((e) => e.status == EntryStatus.requested).toList();

  Future<void> approve(Tournament t, String playerUid) async {
    final e = (_entries[t.id] ?? const []).firstWhere((e) => e.uid == playerUid);
    await writeEntry(db, t.id, Entry(uid: e.uid, displayName: e.displayName, status: EntryStatus.joined));
  }

  /// Before the start the player disappears; after it they are dropped
  /// (results stay). Online players are also blocked from rejoining.
  Future<void> removePlayer(Tournament t, Player p) async {
    if (!t.started) {
      t.players.remove(p);
    } else {
      p.dropped = true;
    }
    app.changed();
    if (p.uid != null) {
      await writeEntry(db, t.id, Entry(uid: p.uid!, displayName: p.name, status: EntryStatus.removed));
    }
  }

  /// A finished tournament gives its join code back.
  Future<void> _releaseCodeIfFinished(Tournament t) async {
    final code = t.joinCode;
    if (!t.finished || code == null) return;
    t.joinCode = null;
    app.changed();
    try {
      await db.collection('joinCodes').doc(code).delete();
    } catch (e) {
      debugPrint('release code failed: $e');
    }
  }

  bool roundHasClaims(Tournament t, Round r) {
    final ids = r.matches.map((m) => m.id).toSet();
    return (_claims[t.id] ?? const []).any((c) => ids.contains(c.matchId));
  }

  ({int reported, int pending, int disputed, int total}) roundCounts(Tournament t) {
    final r = t.currentRound;
    if (r == null || !r.published) return (reported: 0, pending: 0, disputed: 0, total: 0);
    var reported = 0, pending = 0, disputed = 0, total = 0;
    for (final m in r.matches) {
      if (m.isBye) continue;
      total++;
      if (m.result != null) {
        reported++;
        continue;
      }
      switch (stateOf(t, m)) {
        case Pending():
          pending++;
        case Disputed():
          disputed++;
        default:
      }
    }
    return (reported: reported, pending: pending, disputed: disputed, total: total);
  }

  Future<void> ensureJoinCode(Tournament t) async {
    if (t.joinCode != null) return;
    try {
      t.joinCode = await reserveJoinCode(db, tid: t.id, hostUid: uid);
      app.changed();
    } catch (e) {
      debugPrint('join code failed: $e');
    }
  }

  @override
  void dispose() {
    app.removeListener(_resync);
    for (final l in _subs.values) {
      for (final s in l) {
        s.cancel();
      }
    }
    super.dispose();
  }
}
```
Note: `_apply` writes `m.result` directly (not `app.setResult`) because the round is known published here; this keeps the "cleared on purpose" test valid.

- [ ] **Step 4: Run** `flutter test` — Expected: all PASS.

- [ ] **Step 5: Wire it** — in `CloudGate` (Task 7), create `HostSync(db, app, uid)` after `attach`, expose it with a `ChangeNotifierProvider<HostSync?>.value` placed above `child`; dispose it on sign-out. Helper `HostSync? hostSyncOf(BuildContext c)` (same nullable-lookup pattern as `authOf`). In `TournamentsScreen._create`, after `app.add(t)`: `hostSyncOf(context)?.ensureJoinCode(t);` (unawaited).

- [ ] **Step 6: Commit**
```bash
git add lib/state/host_sync.dart lib/main.dart lib/screens/tournaments_screen.dart test/host_sync_test.dart
git commit -m "state: HostSync applies joins, drops and confirmed claims"
```

---

### Task 9: Host UI — code strip, drafts, claims, disputes, requests

**Files:**
- Create: `lib/widgets/host_strip.dart`
- Modify: `lib/screens/tournament_screen.dart`, `lib/screens/tabs/rounds_tab.dart`, `lib/screens/tabs/players_tab.dart`, `lib/screens/tournament_settings_sheet.dart`, `lib/l10n.dart`
- Test: `test/host_ui_test.dart`

**Interfaces:**
- Consumes: `HostSync` API (Task 8), `AppState.publish`, `draftRound`, `ClaimState` types.
- Produces: no new public API.

- [ ] **Step 1: Strings** — add to `lib/l10n.dart`:
```dart
  // ---- online host
  String get joinCodeLabel => _('Join code', 'קוד הצטרפות');
  String get getCode => _('Get code', 'קבל קוד');
  String shareCodeText(String name, String code) =>
      _('Join "$name" in Zira with code $code', 'הצטרפו ל"$name" בזירה עם הקוד $code');
  String get joinModeLabel => _('Who can join', 'מי יכול להצטרף');
  String get joinOpen => _('Anyone with the code', 'כל מי שיש לו קוד');
  String get joinApproval => _('Only after I approve', 'רק אחרי אישור שלי');
  String get joinClosedOnStart => _('Code closes when the event starts', 'הקוד נסגר כשהטורניר מתחיל');
  String roundCounts(int rep, int total, int pend, int disp) => _(
      'Reported $rep/$total · Waiting $pend · Disputes $disp',
      'דווחו $rep/$total · ממתינים לאישור $pend · מחלוקות $disp');
  String get draftBanner => _('Draft — players can\'t see this round yet', 'טיוטה — השחקנים עוד לא רואים את הסבב');
  String get sendToPlayers => _('Send to players', 'שלח לשחקנים');
  String get waitingConfirm => _('Waiting for confirmation', 'ממתין לאישור');
  String get disputed => _('Disputed', 'במחלוקת');
  String claimedBy(String name, String score) => _('$name says $score', '$name טוען $score');
  String get chooseResult => _('Choose the result', 'בחר את התוצאה');
  String get otherResult => _('Other result…', 'תוצאה אחרת…');
  String get joinRequests => _('Join requests', 'בקשות הצטרפות');
  String get approve => _('Approve', 'אישור');
  String get addMe => _('Add me as a player', 'הוסף אותי כשחקן');
  String get online => _('Online', 'אונליין');
  String get guest => _('Guest', 'אורח');
```

- [ ] **Step 2: `lib/widgets/host_strip.dart`** — shown at the top of the host's `TournamentScreen` body (above the `TabBarView`) when `hostSyncOf(context) != null`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/models.dart';
import '../l10n.dart';
import '../state/host_sync.dart';
import '../theme.dart';
import 'common.dart';

class HostStrip extends StatelessWidget {
  final Tournament t;
  final HostSync sync;
  const HostStrip({super.key, required this.t, required this.sync});

  @override
  Widget build(BuildContext context) {
    final c = sync.roundCounts(t);
    return Container(
      color: Z.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(S.t.joinCodeLabel, style: const TextStyle(fontSize: 12, color: Z.muted)),
            Text(t.joinCode ?? '——————',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 4, fontFeatures: Z.tabular)),
            if (c.total > 0)
              Text(S.t.roundCounts(c.reported, c.total, c.pending, c.disputed),
                  style: TextStyle(fontSize: 12.5, color: c.disputed > 0 ? Z.danger : Z.muted)),
          ]),
        ),
        if (t.joinCode == null)
          TextButton(onPressed: () => sync.ensureJoinCode(t), child: Text(S.t.getCode))
        else
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => copyText(context, S.t.shareCodeText(t.name, t.joinCode!), S.t.joinCodeLabel),
          ),
      ]),
    );
  }
}
```
Wire into `tournament_screen.dart`: wrap the existing body in `Column(children: [if (sync != null && !t.finished) HostStrip(t: t, sync: sync), Expanded(child: <existing TabBarView>)])`, where `final sync = hostSyncOf(context);` and `context.watch<HostSync?>()` via the helper so counts refresh.

- [ ] **Step 3: Rounds tab — drafts.** In `_RoundsTabState.build`:
  - `final draft = !round.published;`
  - Above the round title row, when `draft`: a `Card(color: Z.gold.withValues(alpha: .15))` with `Text(S.t.draftBanner)` and `FilledButton.icon(icon: Icon(Icons.send), label: Text(S.t.sendToPlayers), onPressed: () => context.read<AppState>().publish(t))`.
  - Hide `RoundTimer` while `draft`.
  - Repair/undo menu condition becomes:
    `if (isCurrent && !t.finished && (draft || (!round.anyResult && !(sync?.roundHasClaims(t, round) ?? false))))`
  - `_MatchCard.onTap` is null while `draft`.

- [ ] **Step 4: Rounds tab — claim badges and disputes.** Pass `ClaimState? claim` into `_MatchCard` (`sync?.stateOf(t, m)` when `m.result == null`, else null). In `_MatchCard`, under the score area, show `Pill(S.t.waitingConfirm, color: Z.gold)` for `Pending` and `Pill(S.t.disputed, color: Z.danger)` for `Disputed`. In `_report`, when the state is `Disputed d`, first show a dialog:
```dart
final pick = await showDialog<MatchResult?>(
  context: context,
  builder: (c) => SimpleDialog(title: Text(S.t.chooseResult), children: [
    for (final cl in [d.a, d.b])
      SimpleDialogOption(
        onPressed: () => Navigator.pop(c, cl.result),
        child: Text(S.t.claimedBy(t.nameOf(t.players.firstWhere((p) => p.uid == cl.uid).id),
            S.t.scoreText(cl.result, bestOf: t.bestOfFor(round.stage)))),
      ),
    SimpleDialogOption(onPressed: () => Navigator.pop(c, null), child: Text(S.t.otherResult)),
  ]),
);
if (pick != null) { context.read<AppState>().setResult(t, m, pick); return; }
// else fall through to the normal ResultSheet
```

- [ ] **Step 5: Players tab.** When `sync != null`:
  - Section "Join requests" listing `sync.requests(t)` with an "Approve" button each (`sync.approve(t, e.uid)`).
  - "Add me as a player" `OutlinedButton` when no player has `uid == authOf(context)!.user!.uid` and `t.acceptsNewPlayers`: adds `Player(id: newId(), name: uniquePlayerName(t, auth.displayName), uid: auth.user!.uid)` then `app.changed()`.
  - Each player row: small `Pill(S.t.online)` when `uid != null`, `Pill(S.t.guest)` otherwise.
  - The existing "Remove" action calls `sync.removePlayer(t, p)` instead of `t.players.remove(p)` when `p.uid != null`.

- [ ] **Step 6: Settings sheet.** In `tournament_settings_sheet.dart` add a `SettingRow(title: S.t.joinModeLabel, child: DropdownButton<String>(value: t.joinMode, items: [open/approval/closedOnStart → S.t.joinOpen/joinApproval/joinClosedOnStart], onChanged: (v) { t.joinMode = v!; app.changed(); }))`, only when `hostSyncOf(context) != null`.

- [ ] **Step 7: Widget test** — `test/host_ui_test.dart`: build `TournamentScreen` for a 4-player tournament with `AppState(store: CloudStore(fakeDb,'host'), draftRounds: true)`, `HostSync(fakeDb, app, 'host')` provided as `ChangeNotifierProvider<HostSync?>.value`; start the tournament; expect `find.text('Send to players')` and no `RoundTimer`; tap it; expect the timer card and that `t.currentRound!.published` is true. Then write a pending claim to fakeDb, `pumpAndSettle`, expect `find.text('Waiting for confirmation')`. Load Heebo via `loadHeebo` from `test/l10n_test.dart` and run once with `Lang.instance.code = 'he'` checking no overflow exceptions (`tester.takeException()` is null).

- [ ] **Step 8: Run** `flutter test` — Expected: all PASS.

- [ ] **Step 9: Commit**
```bash
git add lib/ test/host_ui_test.dart
git commit -m "host UI: join code strip, draft rounds, claim badges, disputes, join requests"
```

---

### Task 10: Player side — join, player screen, my-match card, drop

**Files:**
- Create: `lib/state/player_session.dart`, `lib/screens/join_screen.dart`, `lib/screens/player_tournament_screen.dart`, `lib/widgets/my_match_card.dart`
- Modify: `lib/screens/tournaments_screen.dart` (joined list + Join button), `lib/screens/tournament_screen.dart` (my-match card when host plays), `lib/screens/tabs/bracket_tab.dart` (`readOnly`), `lib/widgets/round_timer.dart` (`readOnly`), `lib/l10n.dart`
- Test: `test/player_session_test.dart`

**Interfaces:**
- Consumes: `lookupJoinCode`, `writeEntry`, `writeClaim`, `resolveClaims`, `Claim`, `Entry`.
- Produces:
  - `enum JoinResult { ok, requested, badCode, closed, removed }`
  - `Future<JoinResult> joinWithCode(FirebaseFirestore db, {required String uid, required String name, required String code})` → returns the outcome; on `ok`/`requested` the tid is available via the second return: use `Future<(JoinResult, String?)>`.
  - `class PlayerSession extends ChangeNotifier { PlayerSession(FirebaseFirestore db, String tid, String uid); Tournament? t; String? hostUid; EntryStatus? myStatus; Player? get me; Match? get myMatch; Round? get myRound; ClaimState get myState; Future<void> report(MatchResult r); Future<void> confirm(); Future<void> drop(); void dispose(); }`
  - `Stream<List<({String tid, String name, String status})>> joinedTournaments(FirebaseFirestore db, String uid)` — `memberUids array-contains uid`, excluding `hostUid == uid`.
  - `MyMatchCard({required Tournament t, required String uid, required ClaimState state, required Future<void> Function(MatchResult) onReport})`
  - `BracketTab(t: t, readOnly: true)`, `RoundTimer(t: t, readOnly: true)`

- [ ] **Step 1: Write failing tests** — `test/player_session_test.dart`:
```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/engine/online.dart';
import 'package:zira/state/player_session.dart';

Future<FakeFirebaseFirestore> hosted({String joinMode = 'open', bool started = true, String? bobUid = 'bob'}) async {
  final db = FakeFirebaseFirestore();
  final t = Tournament(id: 't1', name: 'T', joinMode: joinMode, joinCode: 'ABC234', players: [
    Player(id: 'a', name: 'Alice', uid: 'alice', tieRand: 1),
    Player(id: 'b', name: 'Bob', uid: bobUid, tieRand: 2),
  ]);
  if (started) t.rounds.add(Round(number: 1, stage: Stage.swiss, matches: [Match(id: 'm1', table: 3, p1: 'a', p2: 'b')]));
  await CloudStore(db, 'host').saveAll([t]);
  await db.doc('joinCodes/ABC234').set({'tid': 't1', 'hostUid': 'host'});
  return db;
}

void main() {
  test('join with code: open → joined entry', () async {
    final db = await hosted(started: false);
    final (res, tid) = await joinWithCode(db, uid: 'eve', name: 'Eve', code: 'abc234');
    expect(res, JoinResult.ok);
    expect(tid, 't1');
    expect((await db.doc('tournaments/t1/entries/eve').get()).data()!['status'], 'joined');
  });

  test('join: approval → requested; bad code; closedOnStart after start', () async {
    expect((await joinWithCode(await hosted(joinMode: 'approval', started: false), uid: 'eve', name: 'E', code: 'ABC234')).$1,
        JoinResult.requested);
    expect((await joinWithCode(await hosted(), uid: 'eve', name: 'E', code: 'ZZZZZZ')).$1, JoinResult.badCode);
    expect((await joinWithCode(await hosted(joinMode: 'closedOnStart'), uid: 'eve', name: 'E', code: 'ABC234')).$1,
        JoinResult.closed);
  });

  test('session shows my match and reports a claim', () async {
    final db = await hosted();
    final s = PlayerSession(db, 't1', 'alice');
    await pumpEventQueue();
    expect(s.me!.name, 'Alice');
    expect(s.myMatch!.table, 3);
    await s.report(const MatchResult(Outcome.p1, 2, 1));
    await pumpEventQueue();
    expect((await db.doc('tournaments/t1/claims/m1_alice').get()).exists, isTrue);
    expect(s.myState, isA<Pending>());
    s.dispose();
  });

  test('confirm copies the opponent claim', () async {
    final db = await hosted();
    await db.doc('tournaments/t1/claims/m1_alice').set(
        const Claim(matchId: 'm1', uid: 'alice', result: MatchResult(Outcome.p1, 2, 0), atMs: 1).toJson());
    final s = PlayerSession(db, 't1', 'bob');
    await pumpEventQueue();
    expect(s.myState, isA<Pending>());
    await s.confirm();
    await pumpEventQueue();
    expect(s.myState, isA<Confirmed>());
    s.dispose();
  });

  test('drop writes a dropped entry', () async {
    final db = await hosted();
    final s = PlayerSession(db, 't1', 'alice');
    await pumpEventQueue();
    await s.drop();
    expect((await db.doc('tournaments/t1/entries/alice').get()).data()!['status'], 'dropped');
    s.dispose();
  });
}
```

- [ ] **Step 2: Run** `flutter test test/player_session_test.dart` — Expected: FAIL.

- [ ] **Step 3: Implement `lib/state/player_session.dart`**:
```dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../cloud/claims.dart';
import '../cloud/join_codes.dart';
import '../engine/models.dart';
import '../engine/online.dart';

enum JoinResult { ok, requested, badCode, closed, removed }

Future<(JoinResult, String?)> joinWithCode(FirebaseFirestore db,
    {required String uid, required String name, required String code}) async {
  final tid = await lookupJoinCode(db, code);
  if (tid == null) return (JoinResult.badCode, null);
  final doc = (await db.doc('tournaments/$tid').get()).data();
  if (doc == null) return (JoinResult.badCode, null);
  final mine = (await db.doc('tournaments/$tid/entries/$uid').get()).data();
  if (mine?['status'] == 'removed') return (JoinResult.removed, null);
  if (mine?['status'] == 'joined') return (JoinResult.ok, tid);
  final mode = doc['joinMode'] as String? ?? 'open';
  final status = doc['status'] as String? ?? 'registration';
  if (status == 'finished' || (mode == 'closedOnStart' && status != 'registration')) {
    return (JoinResult.closed, null);
  }
  final approval = mode == 'approval';
  await writeEntry(db, tid,
      Entry(uid: uid, displayName: name, status: approval ? EntryStatus.requested : EntryStatus.joined));
  return (approval ? JoinResult.requested : JoinResult.ok, tid);
}

Stream<List<({String tid, String name, String status})>> joinedTournaments(FirebaseFirestore db, String uid) => db
    .collection('tournaments')
    .where('memberUids', arrayContains: uid)
    .snapshots()
    .map((s) => [
          for (final d in s.docs)
            if (d.data()['hostUid'] != uid)
              (tid: d.id, name: d.data()['name'] as String? ?? '?', status: d.data()['status'] as String? ?? '')
        ]);

/// One tournament as a player sees it, live.
class PlayerSession extends ChangeNotifier {
  final FirebaseFirestore db;
  final String tid;
  final String uid;

  Tournament? t;
  String? hostUid;
  EntryStatus? myStatus;
  List<Claim> _claims = [];
  final _subs = <StreamSubscription>[];

  PlayerSession(this.db, this.tid, this.uid) {
    final ref = db.doc('tournaments/$tid');
    _subs
      ..add(ref.snapshots().listen((s) {
        final d = s.data();
        if (d == null) return;
        hostUid = d['hostUid'] as String?;
        t = Tournament.fromJson(Map<String, dynamic>.from(d['data'] as Map));
        notifyListeners();
      }))
      ..add(ref.collection('claims').snapshots().listen((s) {
        _claims = [for (final d in s.docs) Claim.fromJson(d.data())];
        notifyListeners();
      }))
      ..add(ref.collection('entries').doc(uid).snapshots().listen((s) {
        final d = s.data();
        myStatus = d == null ? null : Entry.fromJson(uid, d).status;
        notifyListeners();
      }));
  }

  Player? get me {
    for (final p in t?.players ?? const <Player>[]) {
      if (p.uid == uid) return p;
    }
    return null;
  }

  Round? get myRound => t?.currentRound;

  Match? get myMatch {
    final p = me;
    final r = myRound;
    if (p == null || r == null) return null;
    for (final m in r.matches) {
      if (m.involves(p.id)) return m;
    }
    return null;
  }

  ClaimState get myState {
    final m = myMatch;
    if (t == null || m == null) return const NoClaims();
    return resolveClaims(t!, m, _claims);
  }

  Future<void> report(MatchResult r) async {
    final m = myMatch;
    if (m == null || m.isBye || m.result != null) return;
    await writeClaim(db, tid, Claim(matchId: m.id, uid: uid, result: r, atMs: DateTime.now().millisecondsSinceEpoch));
  }

  /// "Confirm" = report exactly what the opponent reported.
  Future<void> confirm() async {
    final s = myState;
    if (s is Pending && s.by.uid != uid) await report(s.by.result);
  }

  Future<void> drop() async {
    final p = me;
    await writeEntry(db, tid, Entry(uid: uid, displayName: p?.name ?? '?', status: EntryStatus.dropped));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
```

- [ ] **Step 4: Run** `flutter test` — Expected: all PASS.

- [ ] **Step 5: Strings** — add:
```dart
  // ---- online player
  String get joinWithCode => _('Join with code', 'הצטרף עם קוד');
  String get codeHint => _('6-character code from the host', 'קוד של 6 תווים מההוסט');
  String get join => _('Join', 'הצטרף');
  String get badCode => _('No tournament with this code', 'אין טורניר עם הקוד הזה');
  String get joinClosed => _('This tournament is closed for joining', 'הטורניר סגור להצטרפות');
  String get joinRemoved => _('The host removed you from this tournament', 'ההוסט הסיר אותך מהטורניר');
  String get requestSent => _('Request sent — waiting for the host', 'הבקשה נשלחה — ממתינים להוסט');
  String get hosting => _('Hosting', 'מארח');
  String get playing => _('Playing', 'משחק');
  String get myMatch => _('My match', 'המשחק שלי');
  String get waitingNextRound => _('Waiting for the next round', 'ממתינים לסבב הבא');
  String get reportResult => _('Report result', 'דווח תוצאה');
  String opponentReported(String name, String score) => _('$name reported $score', '$name דיווח $score');
  String get confirmResult => _('Confirm', 'אשר');
  String get disputeResult => _('Dispute', 'ערער');
  String get youReported => _('You reported — waiting for your opponent', 'דיווחת — ממתין ליריב');
  String get disputeSent => _('Disputed — the host will decide', 'במחלוקת — ההוסט יכריע');
  String get dropFromEvent => _('Drop from the tournament', 'פרישה מהטורניר');
  String get dropFromEventBody => _('You won\'t be paired from the next round.', 'לא תשובץ החל מהסבב הבא.');
  String get youDropped => _('You dropped from this tournament', 'פרשת מהטורניר');
  String get notInEventYet => _('Waiting for the host to add you', 'ממתינים שההוסט יוסיף אותך');
```

- [ ] **Step 6: `lib/widgets/my_match_card.dart`**:
```dart
import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../engine/online.dart';
import '../l10n.dart';
import '../theme.dart';
import 'result_sheet.dart';

/// The signed-in player's current match: table, opponent, report / confirm /
/// dispute. Used by players and by a host who also plays.
class MyMatchCard extends StatelessWidget {
  final Tournament t;
  final String uid;
  final ClaimState state;
  final Future<void> Function(MatchResult) onReport;

  const MyMatchCard({super.key, required this.t, required this.uid, required this.state, required this.onReport});

  @override
  Widget build(BuildContext context) {
    final me = t.players.where((p) => p.uid == uid).firstOrNull;
    final r = t.currentRound;
    final m = (me == null || r == null) ? null : r.matches.where((m) => m.involves(me.id)).firstOrNull;
    if (me == null) return _shell(Text(S.t.notInEventYet));
    if (me.dropped) return _shell(Text(S.t.youDropped));
    if (m == null || r == null) return _shell(Text(S.t.waitingNextRound));
    final oppId = m.p1 == me.id ? m.p2 : m.p1;
    final bo = t.bestOfFor(r.stage);

    Future<void> openSheet() async {
      final res = await showModalBottomSheet<MatchResult>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ResultSheet(
            p1: t.nameOf(m.p1), p2: t.nameOf(m.p2), bestOf: bo, elimination: r.stage == Stage.top, current: m.result),
      );
      if (res != null && !identical(res, ResultSheet.clear)) await onReport(res);
    }

    final Widget action = switch (state) {
      _ when m.isBye => Text(S.t.autoWin),
      _ when m.result != null => Text(S.t.scoreText(m.result!, bestOf: bo)),
      Pending(by: final c) when c.uid == uid => Text(S.t.youReported, style: const TextStyle(color: Z.muted)),
      Pending(by: final c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(S.t.opponentReported(t.nameOf(oppId), S.t.scoreText(c.result, bestOf: bo)),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: FilledButton(onPressed: () => onReport(c.result), child: Text(S.t.confirmResult))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: openSheet, child: Text(S.t.disputeResult))),
          ]),
        ]),
      Disputed() => Text(S.t.disputeSent, style: const TextStyle(color: Z.danger)),
      _ => FilledButton.icon(onPressed: openSheet, icon: const Icon(Icons.edit_note), label: Text(S.t.reportResult)),
    };

    return _shell(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${S.t.roundLabel(r)} · ${m.isBye ? 'BYE' : S.t.table(m.table)}', style: const TextStyle(color: Z.muted)),
      const SizedBox(height: 4),
      Text(m.isBye ? 'BYE' : '${S.t.vs} ${t.nameOf(oppId)}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      action,
    ]));
  }

  Widget _shell(Widget child) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(S.t.myMatch, style: const TextStyle(fontSize: 12.5, color: Z.gold, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            child,
          ]),
        ),
      );
}
```
(Check the exact names `S.t.roundLabel`, `S.t.table`, `S.t.autoWin`, `S.t.scoreText` in `lib/l10n.dart` — they're used by `rounds_tab.dart` today.)

- [ ] **Step 7: Read-only flags.** `RoundTimer({required this.t, this.readOnly = false})`: when `readOnly`, hide the +1 / reset / play buttons, keep the clock and full-screen; `_BigTimer` gets `readOnly` too and ignores taps; skip `RoundAlarm.check` when read-only (the alarm belongs to the host's phone). `BracketTab({required this.t, this.readOnly = false})`: pass through to `_BracketMatch`, and the tap handler at `bracket_tab.dart:238` becomes `onTap: readOnly ? null : ...`.

- [ ] **Step 8: `lib/screens/player_tournament_screen.dart`** — `ChangeNotifierProvider(create: (_) => PlayerSession(db, tid, uid))`, `Scaffold` with app bar (tournament name; menu with "Drop from the tournament" → `confirm(...)` → `session.drop()`), and a `DefaultTabController` with tabs **My match / Pairings / Standings / Bracket (if topCut > 0)**:
  - My match: `ListView` with `RoundTimer(t: t, readOnly: true)` (only when the current round is published and not finished) and `MyMatchCard(t: t, uid: uid, state: session.myState, onReport: session.report)`. If `session.myStatus == EntryStatus.requested` show `EmptyState(icon: Icons.hourglass_top, title: S.t.requestSent, body: '')` instead.
  - Pairings: list of the current round's matches as `ListTile(leading: Text('${m.table}'), title: Text('${t.nameOf(m.p1)} ${S.t.vs} ${t.nameOf(m.p2)}'), trailing: m.result == null ? null : Text(S.t.scoreText(m.result!, bestOf: t.bestOfFor(r.stage))))`, the player's own match highlighted with `Z.gold`.
  - Standings: `StandingsTab(t: t)`.
  - Bracket: `BracketTab(t: t, readOnly: true)`.
  While `session.t == null`: `Center(child: CircularProgressIndicator())`.

- [ ] **Step 9: `lib/screens/join_screen.dart`** — text field (auto-uppercase, 6 chars, `textCapitalization: TextCapitalization.characters`), "Join" button → `joinWithCode(db, uid: auth.user!.uid, name: auth.displayName, code: ...)`; on `ok`/`requested` `Navigator.pushReplacement` to `PlayerTournamentScreen(tid: tid)`; else toast `badCode` / `joinClosed` / `joinRemoved`. Network errors → toast `S.t.authError('network-request-failed')`.

- [ ] **Step 10: Home list.** In `TournamentsScreen` (signed in): a second `FloatingActionButton.extended` is awkward — instead put a `TextButton.icon(icon: Icon(Icons.qr_code_2), label: Text(S.t.joinWithCode))` in the app bar actions, and render the list as two sections with `SectionTitle`: **Hosting** (`app.tournaments`, as today) and **Playing** (`StreamBuilder` over `joinedTournaments(db, uid)`, each row a `ListTile(title: name, subtitle: status)` → `PlayerTournamentScreen(tid)`). Empty sections are hidden; when both are empty show the existing `EmptyState`.

- [ ] **Step 11: Host who plays.** In `tournament_screen.dart`, when `sync != null` and some player has the host's uid and the current round is published: put `MyMatchCard(t: t, uid: hostUid, state: sync.stateOf(t, myMatch), onReport: (r) => writeClaim(db, t.id, Claim(matchId: m.id, uid: hostUid, result: r, atMs: now)))` at the top of the Rounds tab list (pass it into `RoundsTab` as an optional `Widget? header`).

- [ ] **Step 12: Run** `flutter test` — Expected: all PASS. Add a short widget test in `test/player_session_test.dart` that pumps `MyMatchCard` with a `Pending` claim from the opponent and taps "Confirm", asserting `onReport` received the opponent's result.

- [ ] **Step 13: Commit**
```bash
git add lib/ test/player_session_test.dart
git commit -m "player side: join with code, live player screen, report/confirm/dispute, drop"
```

---

### Task 11: End-to-end check, docs, release build

**Files:**
- Modify: `CLAUDE.md`, `pubspec.yaml` (version), `README.md` (one paragraph)

- [ ] **Step 1: Deploy rules again** if they changed: `cd firebase && npm test && cd .. && npx firebase-tools@13 deploy --only firestore:rules --project <PROJECT_ID>`.

- [ ] **Step 2: Two-device run** (Gal is the host on the phone, Claude plays in Chrome):
  1. `flutter build web --release`, serve `build/web` (`python -m http.server 8090 -d build/web`), add `localhost` to Firebase Auth → Settings → Authorized domains if needed.
  2. Install a debug build on Gal's phone over USB (`flutter run --release -d <device>` or the split APK from Step 4).
  3. Host creates a tournament with 3 guests + "Add me"; web user (second account) joins with the code → appears in Players.
  4. Start → draft visible only on the host (web shows "Waiting for the next round") → Send to players → web shows table + opponent + timer.
  5. Web reports 2-1 → host shows "Waiting" → host (as player) confirms → result in standings on both.
  6. Next round: report different results on each side → dispute on host → host picks one.
  7. Web drops → host sees the player dropped from the next pairing.
  8. Airplane mode on the host for one report, then back → result lands.
  Record anything off as a bug and fix before Step 4 (TDD: failing test first).

- [ ] **Step 3: `CLAUDE.md`** — replace the "Local-only…" line with the online architecture summary (one paragraph: host-authoritative doc, entries/claims, drafts, `lib/cloud/` boundary, region, Spark plan, rules tests command `cd firebase && npm test`, deploy command, SHA-1 note for Play App Signing, project id).

- [ ] **Step 4: Release APK** — bump `version:` to `1.4.0+10`, then:
```bash
flutter build apk --release --split-per-abi
mkdir -p releases && cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk releases/zira-1.4.0-arm64.apk
python ~/.claude/hooks/apk_version_guard.py check releases/zira-1.4.0-arm64.apk
```
Expected: guard passes (arm64 versionCode 2010 > 2009). Install over USB:
`"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" install -r releases/zira-1.4.0-arm64.apk` (ask Gal to unlock the phone if needed).

- [ ] **Step 5: Commit**
```bash
git add CLAUDE.md README.md pubspec.yaml
git commit -m "1.4.0: online tournaments"
```
Do **not** merge to `main` or push without Gal's go-ahead (use superpowers:finishing-a-development-branch).

---

## Spec coverage check

| Spec item | Task |
|---|---|
| Firebase Auth Google + email, reset | 4, 7 |
| Spark only, no push, me-west1 | 4 (constraints) |
| Local tournaments migrate once | 7 |
| Tools work signed out | 7 (gate only affects the tournaments tab) |
| Host-authoritative single doc + entries/claims | 3, 6, 8 |
| Join code 6 chars, no 0/O/1/I, freed on delete/finish | 6 (`delete` removes the code), 8 (`_releaseCodeIfFinished` in `_resync`) |
| Join modes open/approval/closedOnStart, host decides | 5, 9, 10 |
| Player self-drop from next round | 2 (`applyEntries`), 10 |
| Claims: guest → immediate, equal → confirm, different → dispute → host | 2, 8, 9 |
| Host can play and confirm/decide own match | 9 (Add me), 10 (Step 11) |
| Draft round, "Send to players", repair/undo rules | 3, 6, 9 |
| Timer synced to players | 6 (in `data`), 10 (read-only timer) |
| Duplicate names get a suffix | 2 (`uniquePlayerName`; follows the existing "Gal 2" convention, not "(2)") |
| Removed can't rejoin | 5 (rules), 10 (`JoinResult.removed`) |
| Account deletion | 7 |
| Rules tests via emulator | 5 |
| fake_cloud_firestore tests | 6, 8, 10 |
| Manual two-device test | 11 |
