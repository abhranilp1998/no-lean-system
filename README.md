# NO LEAN

NO LEAN is an offline-first Android recovery tracker built around a direct intervention loop for the highest-risk hours after work.

## Included MVP

- Live clean-time counter with current and longest streaks.
- Daily pledge confirmation and evening clean/relapse check-in.
- Craving log with intensity, trigger tags, notes, and a progress chart.
- Full-screen SOS mode with a 60-second breathing/urge-surfing timer.
- Data-driven risk-window alerts with a pre-window warning, quiet hours and a hide-sensitive mode.
- Calendar-style clean-day heat map and milestone tracker.
- Offline recovery persistence plus encrypted secure storage for the relapse PIN.
- JSON backup and CSV history export through the system Save screen (pick
  Downloads, Drive, ...), with verified byte readback on Android; import accepts
  any file and validates it, including
  BOM/UTF-16 re-saves and every older backup format.
- Danger zones on an offline map (optional OpenStreetMap tiles) with in-app and
  opt-in background geofence alerts, plus an always-on position notification
  while the app is open.
- Dose logging with ml/L/bottle/drink/tablet units, cost and stress, safety
  warnings with a 112 call card, and a 15-minute craving recheck.
- Encrypted relapse lock with biometric-first authentication and PIN fallback.
- App lock for other apps (Android): lock chosen apps always, in the risk
  window or inside danger zones. Detection uses Usage access + a lightweight
  foreground service (no AccessibilityService). The blocking screen always has
  SOS, Call 112 and Go home, and an emergency exit plan: pick a reason, a 30 s
  mindful wait (10 s for payment apps), then that app only for 5 minutes;
  after the daily budget (default 3) the PIN, and a 120 s wait if there is no
  PIN. Dialer, emergency, maps, settings, launchers and NO LEAN are never
  lockable. Every unlock is logged on the timeline.
- Configurable risk windows with high-visibility scheduled interrupts.
  Removing armed protection hours requires authentication; extending them is free.
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

Start with the [prioritized TODO queue](TODO.md) for current implementation
status and branch/review policy.

Current work follows the [D1–D8 delivery action plan](docs/DELIVERY_ACTION_PLAN_2026-10-27.md),
with [delivery SOPs](docs/DELIVERY_SOPS.md), an
[acceptance matrix](docs/DELIVERY_VERIFICATION_MATRIX.md) and a
[verified starting baseline](docs/DELIVERY_BASELINE_2026-10-27.md).

Release numbering, Git tags, and data-preserving APK upgrades are documented in
[docs/RELEASING.md](docs/RELEASING.md). Use `tool/release_version.dart` to prepare
and validate app versions before distributing a build.

The PR review, validation, merge/reject decision and branch cleanup procedure is
in [docs/PR_REVIEW_SOP.md](docs/PR_REVIEW_SOP.md).

See [ROADMAP.md](ROADMAP.md) for the production gate and planned functionality,
accessibility, and UI/UX direction.

Current Android corrections, OnePlus GPS/export follow-ups and the parked web
branch are recorded in [functional notes](docs/FUNCTIONAL_NOTES_2026-10-10.md).

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
│   ├── app_lock/                # Locking other apps + exit plan (native: android/.../AppLock*.kt)
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
