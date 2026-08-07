# NO LEAN

NO LEAN is an offline-first Android recovery tracker built around a direct intervention loop for the highest-risk hours after work.

## Included MVP

- Live clean-time counter with current and longest streaks.
- Daily pledge confirmation and evening clean/relapse check-in.
- Craving log with intensity, trigger tags, notes, and a progress chart.
- Full-screen SOS mode with a 60-second breathing/urge-surfing timer.
- Risk-window notifications scheduled for 17:30, 18:15, 19:00, and 19:45.
- Calendar-style clean-day heat map and milestone tracker.
- Offline local persistence using `shared_preferences`.
- JSON export through the Android share sheet.
- Optional PIN lock setting and biometric availability check.
- Native Android home-screen widget showing clean time and streak.
- Generated cyberpunk icon at `assets/no_lean_icon.png` and Android launcher resource.

## Run

```bash
flutter pub get
flutter test
flutter run
```

The debug APK is produced at `build/app/outputs/flutter-apk/app-debug.apk` after:

```bash
flutter build apk --debug
```

The visual system bundles a condensed display face (`NoLeanDisplay`) and a monospace terminal face (`NoLeanMono`) under `assets/fonts/`, so the look does not depend on network font loading at runtime.

## Project structure

```text
lib/
├── app/                         # App composition and tab shell
├── core/
│   ├── theme/                   # Shared visual tokens and ThemeData
│   ├── utils/                   # Formatting helpers
│   └── widgets/                 # Reusable UI primitives
├── features/
│   ├── cravings/                # Craving log and entry flow
│   ├── dashboard/               # Counter and daily actions
│   ├── emergency/               # SOS override experience
│   ├── progress/                # Heat map, chart, and milestones
│   ├── recovery/                # Shared models, state, persistence, services
│   └── settings/                # Settings UI and platform-facing actions
└── main.dart                    # Platform bootstrap only
```

Feature folders own their presentation code. Cross-feature recovery state lives
under `features/recovery`, while visual primitives that are reused by multiple
features live under `core`.
