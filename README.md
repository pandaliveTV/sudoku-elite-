# Sudoku Elite — EliteP

Classic Sudoku for Android (Flutter). Package: `com.elitep.sudoku`.

## Features
- Puzzle generator + backtracking solver. Every puzzle has exactly **one** solution.
- 4 difficulties:

  | Difficulty | Target clues | Rule |
  | --- | --- | --- |
  | Easy | ~38 | solvable with naked singles only |
  | Medium | ~32 | solvable with naked + hidden singles |
  | Hard | ~27 | unique solution |
  | Expert | ~22–26 | unique, and singles alone are not enough |

- Tools: notes (pencil marks), eraser, undo. Highlights the row, column and box of the selected cell, plus identical numbers (can be turned off in Settings).
- 3 mistakes = game over. A **second chance** is available through a rewarded ad (once per game).
- 1 free hint per game. More hints each need a rewarded ad.
- Daily challenge: the same puzzle for every player on a given day (seeded by date), a calendar, and monthly trophies (bronze 10 days, silver 20 days, gold for the whole month).
- Statistics per difficulty: games, wins, win rate, best time, average time, streaks.
- Coins and XP/level. You can double your coins after a win with a rewarded ad.
- The game in progress is saved on every move, on app background and on exit. **Continue** on the home screen resumes it.
- Arabic and English (RTL supported), light/dark theme, portrait only. The board is drawn with a single `CustomPainter`, and puzzles are generated in a background isolate to keep 60fps.

## Run
```bash
flutter pub get
flutter run
flutter analyze   # must be clean
flutter test      # generator / solver / game logic / storage / widget tests
```

## Project layout
```
lib/
  game/      sudoku_engine.dart (board, solver, generator), game_controller.dart (rules, undo, autosave JSON)
  screens/   splash, home, difficulty (levels), game, daily, stats, settings
  services/  ad_service, iap_service, storage_service, audio_service
  widgets/   sudoku_board (painter + number pad), end_dialogs, common (banner slot, buttons…)
  data/      difficulty, daily (seed, trophies), strings (AR/EN)
assets/sounds/   short sound effects
store_icon_512.png   Play Store hi-res icon
```

## AdMob: where to change IDs
The app ships with **Google test IDs**. Before release:
1. `lib/services/ad_service.dart` → class `AdIds` (banner, interstitial, rewarded, app open).
2. `android/app/src/main/AndroidManifest.xml` → meta-data `com.google.android.gms.ads.APPLICATION_ID`.
3. In AdMob → *Privacy & messaging*, create the GDPR message. UMP is already wired: consent is requested before the SDK initializes and before any ad loads. "Ad privacy options" appears in Settings when UMP requires it.

Ad rules (all in `AdService`):
- Banner: only on the Home and Difficulty (levels) screens, never during play.
- Interstitial: after every 3 finished games (win or final loss).
- At least 120s between any two full-screen ads (interstitial, app open, rewarded).
- App Open: when returning from background, with the same 120s gap. It is skipped after opening the store or privacy link.
- No banner, interstitial or app-open ads during the first 60s after the very first launch.
- Rewarded: only when the player taps (hint / second chance / x2 coins).
- The "Remove Ads" purchase disables banner, interstitial and app open only. Rewarded stays available.

## In-app purchase
Create a managed, non-consumable product with id `remove_ads` in Play Console (the id is in `lib/services/iap_service.dart`). Restore purchases is in Settings.

## Privacy policy
Set the URL in `lib/widgets/common.dart` (`privacyPolicyUrl`) and enter the same URL in Play Console.

## Build AAB for Google Play
1. Create an upload keystore:
   `keytool -genkey -v -keystore ~/elitep-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Create `android/key.properties` (it is git-ignored, so it won't be committed):
   ```
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=/absolute/path/to/elitep-upload.jks
   ```
   `android/app/build.gradle.kts` picks it up automatically. Without this file, release builds are signed with the debug key.
3. Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`), then:
   `flutter build appbundle --release`
4. Upload `build/app/outputs/bundle/release/app-release.aab` to Play Console.
   Store texts are in `store_listing.md`. The 512×512 icon is `store_icon_512.png`.
