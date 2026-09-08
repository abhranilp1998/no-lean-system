# NO LEAN

NO LEAN is an offline-first Android recovery tracker built around a direct intervention loop for the highest-risk hours after work.

## Included MVP

- Live clean-time counter with current and longest streaks.
- Daily pledge confirmation and evening clean/relapse check-in.
- Craving log with intensity, trigger tags, notes, and a progress chart.
- Full-screen SOS mode with a 60-second breathing/urge-surfing timer.
- Four high-visibility reminders distributed through a configurable risk window.
- Calendar-style clean-day heat map and milestone tracker.
- Offline recovery persistence plus encrypted secure storage for the relapse PIN.
- JSON export through the Android share sheet.
- Encrypted relapse lock with biometric-first authentication and PIN fallback.
- Configurable risk windows with high-visibility scheduled interrupts.
- Trigger, time-of-day, weekly, and SOS-completion recovery insights.
- Native Android home-screen widget with live clean-time seconds and streak.
- Four-level visual effects with an Ultra glyph/glitch overdrive mode.
- Independent tap sounds, vibration, and selectable cyberpunk sound profiles.
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

## Roadmap

Release numbering, Git tags, and data-preserving APK upgrades are documented in
[docs/RELEASING.md](docs/RELEASING.md). Use `tool/release_version.dart` to prepare
and validate app versions before distributing a build.

The PR review, validation, merge/reject decision and branch cleanup procedure is
in [docs/PR_REVIEW_SOP.md](docs/PR_REVIEW_SOP.md).

See [ROADMAP.md](ROADMAP.md) for the production gate and planned functionality,
accessibility, and UI/UX direction.

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
