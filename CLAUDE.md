# זירה (Zira) — tournament manager

Flutter Android app (+ web build for iPhone players; English by default, Hebrew/RTL optional; dark).
Online since 1.4.0 (branch `feature/online-tournaments`, spec/plan in `docs/superpowers/`): Firebase project
**`tcg-arena-app`** (Spark plan, Firestore `me-west1`, Auth Google + email). Memory gauge stays local (`zira.memory.v1`).

## Online architecture
- The **host's phone is the only writer** of `tournaments/{tid}` (whole `Tournament` JSON in `data`, minus a draft
  round, which sits in host-only `private/host`). Players write only `entries/{uid}` (join/drop) and
  `claims/{matchId}_{uid}` (result reports). `HostSync` (lib/state/host_sync.dart) applies them through the engine.
- Pure rules for this live in `lib/engine/online.dart` (`resolveClaims`, `applyEntries`, `matchUidsFor`...).
  Only `lib/cloud/`, `lib/state/host_sync.dart`, `player_session.dart`, `session.dart` import Firebase.
- `AppState` takes a `TournamentStore`: `PrefsStore` (tests, offline `ZiraApp()`), `CloudStore` once signed in
  (`CloudGate` in lib/state/session.dart attaches it and migrates old local tournaments once per uid).
- Rounds made online are drafts (`Round.published == false`) until the host taps "Send to players".
- Security rules: `firestore.rules`, tests `cd firebase && npm test` (needs JDK 21: portable one in
  `C:\Users\Owner\tools\jdk-21.0.13+9`, set JAVA_HOME/PATH for the command). Deploy:
  `firebase deploy --only firestore:rules --project tcg-arena-app`. Firebase CLI 15.36 is global (v13 is broken on Node 22).
- Google sign-in needs every signing SHA-1/256 registered (release + debug done). If published on Play, also add
  Play App Signing's SHA-1 (`firebase apps:android:sha:create`).
- Web build: if a release web build shows a blank page with a `channel-error`, delete `build/web` and
  `.dart_tool/flutter_build` and rebuild (stale plugin registrant).
- **Web is live** at https://duel-network.web.app (Firebase Hosting site `duel-network`, players without the APK;
  the default site tcg-arena-app.web.app is disabled — don't re-enable it). Deploy:
  `rm -rf build/web .dart_tool/flutter_build && flutter build web --release && firebase deploy --only hosting --project tcg-arena-app`.
- Display name is **Duel Network** (since 1.5.2: app name, Android label, web title). The package id stays
  `com.galpartuk.zira` — changing it would make a different app. Release APKs are named `duel-network-x.y.z-<abi>.apk`.
- Screens for design reviews: `flutter test tool/shots --update-goldens` → `tool/shots/out/*.png` (sample data, he+en).

## Layout
- `lib/engine/` — pure Dart, no Flutter imports. Models + JSON, standings/tiebreakers,
  Swiss/round-robin pairing, top cut, placements, prize split, memory gauge rules.
  **All rules logic lives here and is covered by `test/engine_test.dart`.**
- `lib/state/app_state.dart` — ChangeNotifier; every mutation calls `changed()` (notify + save).
- `lib/screens/` — tournaments list, create, tournament screen (tabs in `screens/tabs/`).
- `lib/tools/` — dice, coin, rock-paper-scissors, Digimon memory gauge.
- `tool/seed.dart` — demo tournaments JSON for screenshots; `tool/make_icons.py` — icons.

## Language
- `lib/l10n.dart`: `Lang` (ChangeNotifier, prefs key `zira.lang`, default `en`) + `S.t.xxx` strings,
  English and Hebrew side by side (same pattern as Judgemon). Hebrew flips the app to RTL.
  Toggle: the "עב"/"EN" button (`LangButton`) in the app bar of the tournaments and tools screens.
- The engine is language-free: it returns data (`topRoundSize`, `MatchResult`, preset percent lists);
  `S` formats it. Never put user-visible text in `lib/engine/`.
- `PrizeConfig.unit` is a code (`packs` / `ILS`); `unitFromJson` maps old saves ("₪", "חבילות", "בוסטרים").
- Widget tests that check overflow load the real Heebo font (`loadHeebo` in `test/l10n_test.dart`).

## Rules implemented (researched from Bandai Digimon event rules)
- Points: win 3, draw 1, loss 0. Swiss time-out with no winner is reported as a **0-0 draw** (1 each);
  old saved double-loss results still load and count 0 each.
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

## Rules: links only (decided 2026-11-10)
- The full in-app rules + Q&A + smart search moved to a separate app, **Judgemon**
  (C:\Users\Owner\judgemon, repo galpartuk/judgemon). Zira keeps only the quick links screen
  (`lib/tools/rules_screen.dart`). The experiment lives on branch `feature/rules-in-app` (tags v1.1.0, v1.2.0 era).
- Versions jumped 1.0.3 → 1.2.1 on main because 1.1.0/1.2.0 (from the branch) were installed on
  Gal's phone; main must stay above them (last branch build: 1.2.0+6 → arm64 2006).
