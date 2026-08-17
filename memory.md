# NO LEAN agent memory

This file is the handoff contract for AI agents working in this repository.
Read it before changing code.

## Non-negotiable product direction

- Preserve the cyberpunk identity: near-black panels, vibrant cyan/magenta/
  purple/toxic accents, monospace telemetry, display glyphs, scanlines,
  controlled glitches, glow, and direct copy.
- Accessibility settings refine that identity; they must not replace it with a
  generic Material look. High contrast keeps the neon palette. Reduce motion
  removes animation without flattening the visual hierarchy.
- Keep the app offline-first. Recovery history must remain usable without an
  account, network connection, or remote service.
- Never seed fake recovery activity. Default reasons/reminders are
  configuration; cravings, clean days, relapses, and SOS sessions are user data.

## Architecture boundaries

- `lib/main.dart`: bootstrap only.
- `lib/app/`: app composition and navigation shell.
- `lib/core/`: shared theme, feedback services, formatters, and reusable UI.
- `lib/features/<feature>/domain`: models and pure calculations.
- `lib/features/<feature>/application`: state orchestration.
- `lib/features/<feature>/services`: persistence/platform integrations.
- `lib/features/<feature>/presentation`: screens, dialogs, and feature widgets.
- Prefer a focused file over extending a god file. Do not create a new folder
  for a single trivial helper; group by feature and responsibility.

## Recovery and security rules

- Persisted recovery JSON is currently state version 5. Any schema change must
  increment the version and provide a non-destructive migration in
  `RecoveryController.load()`.
- The relapse PIN belongs only in `flutter_secure_storage`. Never put PIN text,
  biometric material, or authentication tokens in SharedPreferences, exports,
  logs, analytics, or notifications.
- `RecoveryController.recordRelapse()` is the enforcement boundary. Do not add
  another timer-reset path that bypasses its biometric/PIN authorization.
- Disabling the relapse lock must remain authenticated.
- Exports deliberately exclude the secure PIN and biometric material.

## Shared UI and feedback

- Use `AppNotice.show(...)` for user-facing transient messages. Do not create
  ad-hoc SnackBars with unverified foreground/background contrast.
- Use `AppDialog` for app-styled modal content.
- Use `AppFeedback` for haptic/sound feedback. Shared controls already emit
  interaction feedback, so avoid adding a second haptic for the same tap.
- Tap sound, vibration, and sound profile are independent persisted settings.
  Android custom UI tones use the `no_lean/feedback` channel; keep a safe
  platform fallback and never make feedback failures block an action.
- Runtime appearance values come from `NoLeanVisuals.of(context)`. Wire new
  effects to high contrast, reduce motion, and effect intensity.
- `EffectIntensity.ultra` is the deliberate visual maximum: animated glyphs,
  chromatic glitches, bloom, and faster motion. `Reduce motion` must always
  override Ultra animation without erasing the neon visual hierarchy.

## Android bridge contract

- Channel: `no_lean/widget`, method: `update`.
- Required source of truth: `lastDoseEpochMillis` as a positive integer.
- `cleanTime` and `streak` remain compatibility fallback strings.
- The native widget uses a launcher-side Chronometer for live seconds. Do not
  replace it with a per-second Dart timer or alarm.
- `MainActivity` must remain a `FlutterFragmentActivity` for `local_auth`.
- Android minimum SDK is 24 for the resolved biometric plugin.

## Verification before handoff

Run all of the following after behavior changes:

```text
dart format lib test
dart analyze
flutter test
flutter build apk --debug
```

Also run `git diff --check` and ensure no generated `build/` or `.dart_tool/`
files are added to version control.
