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
- Keep the app offline-first with an optional online map. Recovery history,
  zones, pins and alerts must remain usable without an account, network
  connection, or remote service; the only network use is OSM street tiles.
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

- Persisted recovery JSON is currently state version 11 (v8 added
  `riskWindowLock` and `appLockPending`; v9 added `zones`, `zoneMonitoring`
  and `backgroundGeofencing`; v10 added `streetTiles`, `widgetPrivacy`,
  `quietHoursEnabled`, `quietHours`, `hideSensitiveNotifications` and the
  `codeSession` event type; v11 added `zoneHistory` and the `zoneEntry`
  event type; older states load with safe defaults). Any schema change must
  increment the version and provide a non-destructive migration in
  `RecoveryController.load()`.
- Production history is stored in `recovery/current.json` in application support
  storage. Keep the legacy preference, previous commit, and migration snapshots.
  Serialize mutations, roll back memory on failure, and notify only after commit.
  Unknown/corrupt current history opens a recovery screen and must never reset.
- Legacy day summaries retain date-only facts, not invented timestamps/counts.
  Backup format 3 supports these summaries and imports legacy exports.
  Backup format 4 adds danger zones (merged by ID on import); format ≤3 still
  imports with no zones. Format 5 adds `codeSession` events; format 6 adds
  `zoneEntry` events. A new event type always needs a format bump so older
  apps refuse the file as a whole.
- CSV export (`events_csv.dart`) is a read-only copy of every event, oldest
  first: BOM + CRLF, RFC 4180 quoting, ISO-8601 timestamps with offset, and a
  formula guard (`= + - @` tab/CR get a leading `'`). Unmapped metadata goes in
  the `details` JSON column. JSON stays the only restorable backup. The
  `zone` column (after `details`) carries the zone name of `zoneEntry` rows.
- Milestones (3/7/14/30/60/90/180/365 days, `domain/milestones.dart`) are
  recorded automatically by `syncMilestones()`, stamped at lastDose + N days,
  with `source: 'auto'`; they cannot be deleted from the timeline. The shell
  calls it after load, on resume and on the lock ticker (never inside
  `load()`, which must stay write-free) and celebrates the highest new one
  once, never over the app lock. The celebration honours reduce motion.
- Multiple relapse rows use one protected, idempotent batch operation with a
  separate chosen occurrence time per event. Cooldown support never hides tabs,
  logging, SOS or settings; retain the original cooldown owner on later logs.
- App lock (user decision, Oct 2026): with a PIN set, the shell locks during the
  configured risk window (`riskWindowLock`, on by default, disabling requires
  auth) and after every saved relapse (`appLockPending`). The lock screen must
  keep SOS and craving logging reachable without unlocking; a widget relapse
  action waits until unlock. Import never restores either lock flag.
- PIN lockouts escalate 5 → 15 → 60 minutes; the level lives in secure storage
  and resets only on a verified PIN, a new PIN, or clearing the lock.
- The relapse PIN belongs only in `flutter_secure_storage`. Never put PIN text,
  biometric material, or authentication tokens in SharedPreferences, exports,
  logs, analytics, or notifications.
- `RecoveryController.recordRelapse()` is the enforcement boundary. Do not add
  another timer-reset path that bypasses its biometric/PIN authorization.
- Disabling the relapse lock must remain authenticated.
- Exports deliberately exclude the secure PIN and biometric material.

## Privacy and notifications

- Privacy settings (`streetTiles`, `widgetPrivacy`,
  `hideSensitiveNotifications`, quiet hours) never need auth and are never
  changed by an import. A malformed privacy flag stays private.
- Street tiles off = the tile provider is never built: grid only, zero network.
- Quiet hours (user decision, Oct 2026) mute non-critical notifications only.
  Risk-window and danger-zone alerts are critical and always come through.
  Classify every new notification in `NotificationKind`.
- Every notification is VISIBILITY_PRIVATE so the lock screen shows Android's
  neutral public version. flutter_local_notifications 19.5 cannot set a custom
  `publicVersion`; "hide sensitive content" instead makes the posted title,
  body and action labels neutral (`NotificationPrefs.textFor`/`label`). The
  background geofence isolate reads prefs from the state file and fails
  private if it is unreadable.
- Widget privacy sends no counter, streak, risk or pledge state over the
  channel, and native code removes the stored last-dose time.

## Danger zones and location

- Map is offline-first with an optional online street layer (user decision,
  Oct 2026): standard OSM tiles (`tile.openstreetmap.org`, no key/paid
  provider) restyled by `neonTileMatrix`, over the offline grid + scale bar,
  which must always stay underneath as the no-network fallback.
- OSM tile policy is mandatory: `userAgentPackageName` = app id, visible
  "© OpenStreetMap contributors" whenever tiles show, flutter_map built-in
  cache (app support dir, 150 MB). Never prefetch or bulk-download tiles, and
  no geocoding/address search. Tile requests are the only data that leaves the
  device; zones never do.
- Zones: 100–2000 m radius, max 20, name ≤ 40. Deleting or shrinking a zone is
  protected by the relapse lock; adding, growing, and toggling monitoring are
  not. Location toggles never require auth, so the user can always switch
  tracking off. Imported preferences never switch location features on.
- In-app checks (`ZoneMonitor`) stream balanced-accuracy fixes only while the
  app is resumed, monitoring is on and zones exist. Background alerts use
  `native_geofence` (enter-only, ids `nolean_zone_<id>`), are opt-in behind the
  disclosure screen, and the isolate callback reads only the local state file.
- Zone history (P3, opt-in, default OFF, no auth to change or clear, never
  switched on by import): each entry is a `zoneEntry` event with zoneId,
  zoneName, time and source only; coordinate keys are stripped even from
  crafted events. Same-zone reports within 15 min merge (in-app monitor and
  geofence both fire). The background isolate never writes the state file;
  it appends to `recovery/zone_entries.jsonl` and the app imports that inbox
  on open/resume (drain → commit → acknowledge; discarded if history is off).
- Zone alerts are firm and factual and always offer one-tap exit ("I'M
  LEAVING"/close); never block leaving the alert.
- Insight patterns need ≥5 cravings+relapses and ≥3 repeats before being
  shown; relapse context tags count as triggers. Money lost is an estimate
  (relapse days × daily spend) and must be labelled as one. The cumulative
  kept/lost chart (`money_series.dart`) applies today's daily spend to all
  history; at ₹0 the chart and dashboard prompt the user to set it instead.
- SOS is staged (breathe → 5-4-3-2-1 → reasons → re-pledge). Leaving is held
  only for the first 15 s of breathing; completion is recorded at the pledge.

## Shared UI and feedback

- Use `AppNotice.show(...)` for user-facing transient messages. Do not create
  ad-hoc SnackBars with unverified foreground/background contrast.
- Use `AppDialog` for app-styled modal content. Dialogs with text fields wrap
  their body in `KeyboardSafeScroll` and give fields
  `KeyboardSafeScroll.fieldScrollPadding` so the primary button stays
  reachable with the keyboard open.
- Shell tabs (Dashboard, Cravings, Progress, Timeline, Settings) scroll in
  `TabListView` (`core/layout/tab_layout.dart`): shared gutters, one bottom
  clearance, drag-to-dismiss keyboard. The shell owns the only Scaffold and
  SafeArea; tabs never add their own.
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
- Widget actions `sos`, `craving`, `relapse`, `code` use request codes 10, 11,
  12, 13; root remains 0. Queue native actions until the loaded shell drains them. Remove
  consumed intent extras so recreation does not replay a completed action.
- Required source of truth: `lastDoseEpochMillis` as a positive integer.
- `cleanTime` and `streak` remain compatibility fallback strings.
- Payload also carries `privacy`. One provider class renders three sizes
  (`NoLeanWidgetSize`: 2x1 small, 4x2 original, 4x3 large); each layout must
  contain exactly the ids its size flags promise, because RemoteViews fails the
  whole widget on a missing id. `test/android/widget_resources_test.dart`
  enforces this. The agent box now has an Android SDK and emulator
  (`source /workspace/tools/android_env.sh`, AVD `nolean35`). The 4x2
  receiver owns the shared boundary alarm and refreshes every size.
- Code Instead: tasks rotate by history (`nextCodeTask`), never by the clock;
  catalogue ids are stable, append-only. Blocks are logged as `codeSession`
  when time is up, the task is done, or the user stops after ≥1 minute.
  Notification action `action_code` (pre-window risk alert) and widget action
  `code` open the timer, which opens over the app lock like SOS.
- The native widget uses a launcher-side Chronometer for live seconds. Do not
  replace it with a per-second Dart timer or alarm.
- `MainActivity` must remain a `FlutterFragmentActivity` for `local_auth`.
- Android minimum SDK is 24 for the resolved biometric plugin.

## Release versioning

- `pubspec.yaml` owns `MAJOR.MINOR.PATCH+BUILD`. The app/build version, stored
  recovery schema, and backup format are independent version contracts.
- Use `tool/release_version.dart` and `docs/RELEASING.md` for version increments,
  validation, and annotated `vMAJOR.MINOR.PATCH+BUILD` Git tags. Fetch existing
  tags and inventory distributed APKs before reserving a build number.
- Preserve the existing application ID, compatible signing identity, storage
  keys, and secure-storage namespaces so upgrades retain installed user data.
- Create a source release tag only after the main commit and migration/reload
  behavior pass review and validation; device upgrade validation gates APK distribution.

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

## PR completion

Follow `docs/PR_REVIEW_SOP.md` and the PR template. Review the complete diff, fix
blocking findings, and merge the verified head or close with reasons. Preserve
useful features and local commits. Remove only merged feature branches.
