# זירה (Zira) — tournament manager

Flutter Android app (Hebrew, RTL, dark). Local-only: all data in SharedPreferences
(`zira.tournaments.v1`, memory gauge in `zira.memory.v1`). No server, no accounts.

## Layout
- `lib/engine/` — pure Dart, no Flutter imports. Models + JSON, standings/tiebreakers,
  Swiss/round-robin pairing, top cut, placements, prize split, memory gauge rules.
  **All rules logic lives here and is covered by `test/engine_test.dart`.**
- `lib/state/app_state.dart` — ChangeNotifier; every mutation calls `changed()` (notify + save).
- `lib/screens/` — tournaments list, create, tournament screen (tabs in `screens/tabs/`).
- `lib/tools/` — dice, coin, rock-paper-scissors, Digimon memory gauge.
- `tool/seed.dart` — demo tournaments JSON for screenshots; `tool/make_icons.py` — icons.

## Rules implemented (researched from Bandai Digimon event rules)
- Points: win 3, draw 1, loss 0. Swiss time-out with no winner = **double loss** (0 each).
- Tiebreakers: points → OMW% → OOMW% → random (fixed `tieRand` per player). OMW floor 33% (configurable).
- Bye → lowest-ranked player without a bye, counts as a win, not an opponent.
- Swiss rounds by attendance table in `recommendedSwissRounds`. Top cut seeded 1v8, 4v5, 2v7, 3v6.
- Top-cut time-out procedure text shown in the result sheet (extra turns, then security/deck/...).
- Memory: crossing to the opponent's side passes the turn; at 0 it doesn't; pass = 3 on opponent side.

## Build / release
- This PC has ~7.3 GB RAM: `android/gradle.properties` heap is set to 1536m — keep it.
- Release key: `C:\Users\Owner\keys\zira-release.jks` (credentials txt next to it), wired via
  `android/key.properties` (git-ignored).
- **Always** `flutter build apk --release --split-per-abi` (first release was split: arm64 = 2001).
  Bump `version:` in pubspec for every APK. Copies go in `releases/` (git-ignored).
- Visual check: `flutter build web`, serve `build/web`, screenshot with Playwright (system Chrome,
  `channel="chrome"`), seed localStorage key `flutter.zira.tournaments.v1`.
