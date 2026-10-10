# NO LEAN: changes, merge handoff and roadmap

Prepared 10 Oct 2026 for Abhranil and the reviewer who merges this branch.
Sources: `git log main..stillpoint-8`, `memory.md`, the code and the tests. Nothing here is guessed.

## 1. Summary

| Item | Status |
|---|---|
| Branch | `stillpoint-8` (pushed to GitHub). `main` is untouched. |
| Scope | P0, P1, P2 and P3, 8 StillPoint-inspired features, always-on position notification, app-lock placeholders, import/export fixes |
| Tests | **384 automated tests pass**. `flutter analyze`: no issues. `dart format`: clean |
| Release build | `flutter build apk --release --split-per-abi` succeeds (R8 on) |
| App version | still `1.1.0+3`, the same as `main` (see Gaps found) |
| Preview APK | [NO-LEAN-Preview.apk](https://github.com/abhranilp1998/no-lean-system/releases/download/preview-2026-10-09/NO-LEAN-Preview.apk). Separate app ID `com.nolean.no_lean.preview`, so it installs next to the original |
| Real phone | **Not yet tested on a real phone.** Background geofence, street tiles, quiet hours and widgets have only been checked by automated tests |

The StillPoint repo was only used as a reference. Nothing in it was changed.

## 2. Merge handoff

**What to merge:** `stillpoint-8` into `main`. **The reviewer does the merge, not us.** No agent has merged anything into `main` or pushed to it.

**Commit range:** `bd3581a..stillpoint-8`, where `bd3581a` is the current `main` and the merge base. That is 47 commits including the one adding this document, from `e240a25` to the branch tip (full list in the Appendix). `main` is an ancestor of the branch, so this is a **clean fast-forward with no conflicts** (checked with `git merge-tree`).

**Pre-merge checks (run on the branch):**

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze            # expect: No issues found
flutter test               # expect: 384 tests, all passed
flutter build apk --release --split-per-abi
```

**Risky areas to review closely:**

1. **State migrations to v12** (`RecoveryController.load()` in `lib/features/recovery/application/recovery_controller.dart`). v8 adds the lock flags, v9 zones, v10 privacy, v11 zone history, and v12 doses, cost, stress and `bottleMl`, with free-text quantity conversion. Every stored version from v2 to v12 is covered by `test/features/recovery/services/compat_matrix_test.dart`.
2. **Backup format 7** (`lib/features/recovery/services/backup_service.dart`). Formats 1–7 and raw state files from v2 to v12 import. A newer format is refused as a whole.
3. **Notification channels** (`lib/features/recovery/services/notification_service.dart`): `risk_window_v2`, `danger_zone_v1`, `position_status_v1`, `code_timer_v1` and `craving_check_v1`. Android fixes a channel's importance once it is created, so changing any of these means creating a new channel ID.
4. **Geofence** (`lib/features/zones/services/native_geofence_gateway.dart`, `zone_entry_inbox.dart`). This is a background isolate with an `@pragma('vm:entry-point')` callback. It only reads the state file and appends entries to `recovery/zone_entries.jsonl`.
5. **Export/import changes**: the system Save screen, saved-or-cancelled results, and the tolerant decoder (see §3.10).

**Signing, before any release:**

- **A real release signing key is required before any Play Store release.** `android/app/build.gradle.kts` still signs release builds with the debug key (`signingConfig = signingConfigs.getByName("debug")`).
- **Phones that already have the original app need an APK signed with the same key to update without losing data.** The original app was built on Abhranil's PC, so it is signed with `C:\Users\Abhranil\.android\debug.keystore`. An APK signed with any other key will not install over it, and uninstalling the original wipes its data. Either build the update on that PC, or copy that keystore to the build machine.

## 3. What was implemented

### 3.1 P0: core safety

- **Format fix:** the codebase was reformatted with `dart format`.
- **Escalating PIN lockouts:** wrong PINs lock you out for 5, then 15, then 60 minutes. The level is kept in secure storage and only resets on a correct PIN, a new PIN or clearing the lock.
- **Risk-window lock:** with a PIN set, the app locks during the risk window (default 17:00–21:00) and again after every saved relapse. SOS and craving logging stay reachable while locked (state v8).
- **Smart notifications:** risk-window alerts are based on your own data and come with a pre-window warning. Exact alarms are used when allowed, with an inexact fallback. The scheduled-notification receivers are now registered.
- **Map:** a dark-styled OpenStreetMap layer sits over an offline grid that always stays underneath. Tiles are cached by flutter_map (150 MB), with no bulk downloads.

### 3.2 P1: danger zones, insights and SOS

- **Danger zones:** long-press to add pins, with a radius of 100–2000 m and up to 20 zones (state v9, backup format 4).
- **Zone alerts:** an in-app alert while the app is open, and an opt-in background geofence alert (`native_geofence`, entry only) shown after a disclosure screen. The full-screen zone alert always has a one-tap exit: the top close button, the back button or **I'M LEAVING**.
- **Insights:** patterns across cravings and relapses. One is only shown once there are at least 5 events and the pattern repeats at least 3 times.
- **4-stage SOS:** breathe, then 5-4-3-2-1 grounding, then your reasons, then a re-pledge.

### 3.3 P2: privacy and tools

- **Street tiles off switch:** grid only and zero network (state v10).
- **CSV export** of the full history. It's a read-only copy, and JSON stays the restorable backup.
- **Quiet hours:** non-critical notifications are muted, but risk-window and zone alerts always come through.
- **Hide sensitive:** neutral notification text.
- **Widgets:** 2x1, 4x2 and 4x3 sizes, with a privacy mode and previews.
- **Code Instead:** a logged focus timer (`codeSession` events).

### 3.4 P3: progress

- **Milestones** at 3, 7, 14, 30, 60, 90, 180 and 365 days are recorded automatically, with a one-time celebration that respects reduce motion.
- **Money chart:** money kept vs lost, with a prompt for your daily spend when it's set to ₹0.
- **Zone visit history:** opt-in and off by default. It stores the zone name and time only, never coordinates (state v11, backup format 6).

### 3.5 Eight StillPoint-inspired features (state v12, backup format 7)

1. **Dose units:** ml, L, bottle, drink and tablet.
   - All maths is done in ml. A bottle counts at your bottle-size setting (100 ml by default, valid range 10–2000).
   - Changing the bottle size never rewrites old entries.
   - Drinks and tablets are counts and never mix into ml totals.
   - Accepted inputs include `2,5`, `1/2`, `half` and `2 and a half`.
   - Sanity prompts catch likely mistakes, for example 250 bottles gets "Did you mean 250 ml?".
2. **Per-type insights and escalation:** the latest dose is flagged as escalation when it is at least 1.2× the average of the previous doses of the same type and unit.
3. **Safety warnings:** mixing depressants, a second dose on the same day, or a tolerance drop after 3 or more clean days. Any of these shows the overdose-signs card with **CALL 112**.
4. **Stress:** a 1–5 rating on relapses and cravings.
5. **15-minute craving recheck:** a notification on `craving_check_v1`, skipped during quiet hours.
6. **Insight confidence, WHY and dismiss:** confidence is labelled early, moderate or strong. A dismissed insight stays hidden until its evidence changes. High-need insights can never be dismissed.
7. **Real cost:** recorded relapse costs are used, and the rest is estimated from your daily spend and clearly labelled as an estimate.
8. **Heat map modes:** days, count, amount, cost and stress, plus a weekday card covering 12 weeks.

### 3.6 Always-on position notification

- While the app is open, a quiet ongoing notification shows your rounded coordinates and the nearest zone with its distance, or **INSIDE <zone>** when you're in one.
- It updates within 15 seconds, or immediately when your state changes.
- Hide sensitive reduces it to `NO LEAN // position active`.
- It is on by default, with a toggle under Settings > Protection.
- It never triggers or suppresses zone alerts.

### 3.7 App-lock placeholders (intentional, no enforcement)

- `lib/features/app_lock/` contains the model, schedules and a stand-in gateway that reports "not available yet".
- Settings shows a disabled **App lock (coming soon)** tile.
- No new permissions were added. The manifest only has comments for now.

### 3.8 Import fixes

- **Any file can be picked.** Backups that passed through Drive, WhatsApp or Downloads used to show up greyed out.
- **Files re-saved by other apps import:** a BOM, UTF-16, padding and share text wrapped around the backup are all handled.
- **Plain error messages.** "Unexpected character" no longer appears.

### 3.9 Export fix

- **The original bug (`main`):** export wrote a temp file, opened the share sheet, then deleted the file as soon as the sheet closed. Apps that took a moment to read it got nothing ("save failed") or just the share text.
- **Fix, commit `90d12fd`:** export now uses Android's own "Save to" screen (`FilePicker.saveFile` with the bytes), so the file is written directly to Downloads or Drive. Copies sent through the share sheet are kept for an hour.
- **Fix, commit `4a79d8d`, from today's review:**
  - **Cancelling the Save screen used to show "EXPORT READY", which was false.** Exports now report whether the file was saved or cancelled. A cancel shows nothing, a save shows "ready", and an error shows an error.
  - The startup emergency export now confirms when it has saved, and the 5 MB backup limit no longer blocks it.
  - Size errors now say what went wrong.

## 4. Data and compatibility

| Contract | Current | Still accepted |
|---|---|---|
| Stored state (`recovery/current.json`) | v12 | v2–v12, migrated forward without data loss. Corrupt or unknown state opens a recovery screen and is never reset |
| JSON backup format | 7 | formats 1–7, plus raw state files v2–v12. Newer formats are refused as a whole |
| CSV | columns only appended | read-only, not importable |

- Old backups still import. This is tested for every format and every state version.
- The secure PIN and trusted contact are never included in exports.
- An import never turns on location features or lock flags, and never changes privacy settings.

## 5. Verification

- **Automated:** 384 unit and widget tests, covering units, migrations, the backup round trip, import tolerance, the export cancel path, notification policy, zones, SOS, widgets, the app-lock stub and the zone-alert exit.
- **Emulator** (software rendering only, because hardware acceleration kept crashing): app launch, the milestone celebration and the in-app zone alert passed. On-device integration tests are in `integration_test/`.
- **Release build:** succeeds with R8 and the new keep rules. The scheduled-notification restore after a reboot has not been run on a device.
- **Not yet verified on a real phone:**
  - background geofence alerts with the app closed;
  - street tiles over mobile data;
  - quiet hours;
  - widgets on the home screen;
  - the position notification;
  - the Save screen on your phone;
  - risk-window alerts after a reboot.

## 6. Known issues and caveats

- **The original installed app still has the export bug.** It will keep it until it's updated with an APK signed by your PC's debug key (`C:\Users\Abhranil\.android\debug.keystore`). Your PC is currently offline. Until then, try these in the original app:
  1. Tap Export backup, share to **Gmail**, and send it to yourself. Retry if it fails the first time.
  2. Or share to **Telegram Saved Messages** or **Quick Share**.
  3. Download the `.json` file, which should be a few KB and not 186 bytes, and import it into the Preview or the updated app.
- **Debug signing:** the release build is signed with the debug key, so it isn't fit for the Play Store.
- **Android 13+:** notifications need the notification permission. If it's denied, alerts and the position notification don't show.
- **The position notification only shows while the app is open.** It is removed when the app goes to the background.
- **Background zone alerts** need "Allow all the time" location access. Android may delay geofence events.
- **Android 14+:** a full-screen zone alert only appears when the system allows full-screen intents. Otherwise it shows as a heads-up notification.

## 7. Gaps found (pre-merge audit, 10 Oct)

**Fixed on `stillpoint-8`, each with tests:**

| Gap | Fix | Commit |
|---|---|---|
| Cancelling the export Save screen showed a false "EXPORT READY" | Exports return saved or cancelled, and a cancel shows nothing | `4a79d8d` |
| The emergency export could be blocked by the 5 MB limit | The limit no longer applies to the emergency export | `4a79d8d` |
| No R8 keep rules for Gson. Scheduled notifications (risk window, recheck) could fail to restore after a reboot in release builds | Added `android/app/proguard-rules.pro` and wired it into the release build | `9fbf1dd` |
| No single test covering every backup format and state version | `compat_matrix_test.dart`: formats 1–7 and state v2–v12 | `4a79d8d` |
| No focused test that the zone alert's close and I'M LEAVING buttons exit | `zone_alert_exit_test.dart` | `6ad8997` |
| README still said "export through the share sheet" and listed none of the new features | README and memory.md updated | `114559a` |

**Still open:**

| Severity | Gap | Why it matters / what to do |
|---|---|---|
| **High** | Release builds are signed with the debug key | Set up a real upload key before any Play release. Updating existing phones needs the PC's debug key (see §2) |
| **High** | Not tested on a real phone | Run the checklist in §8 before calling it released |
| Medium | Version is still `1.1.0+3`, the same as `main` | Bump it (for example to `1.2.0+4`) with `tool/release_version.dart` before release, so stores and phones see a newer build |
| Medium | The scheduled-notification restore after reboot is untested in a release build | This is a device test, done after installing the release APK |
| Low | Some screens have no direct widget test: zone editor, zone monitoring panel, geofence disclosure, map markers, relapse-type card. The geofence gateway is platform code | They are covered indirectly or by integration tests. Add widget tests when those screens next change |
| Low | `cupertino_icons` is declared but unused | Template leftover, harmless. Removing it is optional |
| Info | `TODO(app-lock)` notes in `settings_screen.dart`, `app_lock_gateway.dart`, `locked_app.dart`, `app_lock_providers.dart` and the manifest | Intentional placeholders. No other TODOs or FIXMEs were found |

**Checked and OK:**

- Merge conflicts: none (fast-forward).
- Every other dependency is used.
- Manifest permissions match the features: notifications, biometrics, boot, exact alarm, fine, coarse and background location, wake lock, full-screen intent, and internet (for tiles only). No storage permission is needed, because the Save screen uses the system document picker.
- Notification channel IDs are unique and versioned.
- `res/raw/keep.xml` keeps the notification icon.
- The geofence callback has `vm:entry-point`.

## 8. Proposed next steps

1. **A real app lock, with an exit plan for genuine needs.** For example, you might need to pay in an app while you're inside a danger zone.
   - **Reason picker:** payment, work, navigation or other.
   - **A 30-second mindful wait**, showing your own reasons for quitting.
   - **A time-boxed 5-minute unlock**, after which the app locks again.
   - **A "payments only" app class** (GPay, PhonePe) that opens quickly for a short time while other apps stay locked.
   - **A daily unlock budget.** After it runs out, the PIN is required.
   - **Every unlock is logged** with its reason and zone, and patterns show up in insights.
   - **Never lockable:** the phone dialer, maps and NO LEAN itself. SOS is always reachable.
   - Needs Usage Access plus a foreground service, or an Accessibility service, with a disclosure screen and a Play policy declaration. The notes are in `app_lock_gateway.dart`.
2. **Evening game-plan check-ins** at 16:45, 19:00 and 21:00.
3. **Automatic encrypted backup** to a folder you choose.
4. **Trusted-person check-in:** the app drafts the message and you send it yourself. It never sends automatically.
5. **Taper plan mode:** planned step-downs, tracked against the logged doses.
6. **Weekly report card:** clean days, cravings beaten, money kept and the top trigger.
7. **A proper release signing key** and a versioned release (§2, §7).
8. **Real-device test checklist:**
   - install over the original with the PC key, and check the data is kept;
   - export to Downloads and Drive, then cancel an export;
   - import an old backup;
   - background zone alert with the app closed;
   - risk-window alert after a reboot;
   - quiet hours;
   - widgets in all 3 sizes;
   - position notification inside and outside a zone;
   - street tiles on and off;
   - deny notifications on Android 13+.

## Appendix A: key files

| Area | Files |
|---|---|
| Backup/export/import | `lib/features/recovery/services/backup_service.dart`, `lib/features/settings/services/recovery_export_service.dart`, `lib/features/recovery/presentation/recovery_startup_screen.dart` |
| State and migrations | `lib/features/recovery/application/recovery_controller.dart`, `lib/features/recovery/domain/quantity_upgrade.dart`, `legacy_recovery_migration.dart` |
| Doses and safety | `lib/features/recovery/domain/dose_units.dart`, `dose_safety.dart`, `lib/features/recovery/presentation/dose_safety_cards.dart`, `lib/features/progress/domain/dose_insights.dart` |
| Notifications | `lib/features/recovery/services/notification_service.dart`, `lib/features/recovery/domain/notification_policy.dart`, `risk_alert_plan.dart` |
| Zones and position | `lib/features/zones/` (`application/zone_monitor.dart`, `application/position_status_host.dart`, `domain/position_status.dart`, `services/native_geofence_gateway.dart`, `services/zone_entry_inbox.dart`, `presentation/zone_alert_screen.dart`, `presentation/zones_screen.dart`) |
| Lock | `lib/features/recovery/domain/app_lock_session.dart`, `lib/features/recovery/presentation/app_lock_screen.dart`, `lib/features/recovery/services/relapse_lock_service.dart` |
| App-lock placeholders | `lib/features/app_lock/` |
| Progress | `lib/features/progress/domain/heat_map_data.dart`, `money_series.dart`, `lib/features/recovery/domain/milestones.dart` |
| Android | `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`, `android/app/proguard-rules.pro`, `android/app/src/main/res/raw/keep.xml` |
| Tests | `test/features/settings/services/export_flow_test.dart`, `test/features/recovery/services/compat_matrix_test.dart`, `test/features/recovery/services/backup_service_test.dart`, `integration_test/` |

## Appendix B: commits on `stillpoint-8` (oldest first, after `main` = `bd3581a`)

- `e240a25` 2026-10-08 style: apply dart format to relapse lock service test
- `3b7b708` 2026-10-08 feat: escalate persisted PIN lockouts 5, 15, then 60 minutes
- `a313d60` 2026-10-08 feat: persist risk-window lock and post-relapse relock in state v8
- `f03e498` 2026-10-08 feat: lock the shell during the risk window and after relapse logs
- `8654480` 2026-10-08 fix: register scheduled-notification receivers and exact-alarm permission
- `74e89cb` 2026-10-08 feat: data-driven risk-window alerts with pre-window warning
- `ba3d12a` 2026-10-08 feat: danger zone model in state v9 and backup format 4
- `23743f4` 2026-10-08 feat: offline danger-zone map with long-press pins
- `f267331` 2026-10-08 feat: in-app zone entry alerts while the app is open
- `de75b88` 2026-10-08 feat: opt-in background zone alerts via native_geofence
- `5152666` 2026-10-08 feat: insight engine over cravings and relapses
- `4267ac0` 2026-10-08 feat: multi-stage SOS (breathe, ground, reasons, re-pledge)
- `920e622` 2026-10-08 docs: memory for state v9, backup format 4, zones, insights and SOS
- `bbfe943` 2026-10-09 chore: drop unused direct http dependency, document INTERNET use
- `07deca9` 2026-10-09 feat: OpenStreetMap street layer and danger-zone map redesign
- `78f310b` 2026-10-09 docs: memory for offline-first map with optional OSM layer
- `b7b85f9` 2026-10-09 feat: street tile privacy switch (state v10)
- `ec84b73` 2026-10-09 feat: CSV export of the full event history
- `e812a55` 2026-10-09 Add quiet hours and hide-sensitive notification privacy
- `19672b6` 2026-10-09 Share one tab layout and make the craving dialog keyboard-safe
- `afa48e1` 2026-10-09 Add home widget privacy mode, previews and 2x1/4x3 sizes
- `d6696b4` 2026-10-09 Turn Code Instead into a logged focus timer
- `b6e68ad` 2026-10-09 Update memory.md for state v10, backup format 5 and P2 conventions
- `ac8e987` 2026-10-09 Record streak milestones automatically and celebrate them
- `c14c49f` 2026-10-09 Chart money kept vs lost and ask for daily spend at ₹0
- `1e3b535` 2026-10-09 Add opt-in zone visit history (state v11, backup format 6)
- `af8b0f6` 2026-10-09 Record P3 contracts in agent memory
- `cd9ce56` 2026-10-09 Add on-device integration tests for the map and zone flows
- `347774d` 2026-10-09 Use a real status-bar icon and proper launcher mipmaps
- `c4b0ade` 2026-10-09 Capture key screens from an on-device screenshot flow
- `2955adb` 2026-10-09 Screenshot flow: dismiss the milestone celebration, scroll Progress itself
- `bd582c4` 2026-10-09 Add dose units: ml/L/bottle/drink/tablet parsing, conversion and sanity checks
- `b55cbcc` 2026-10-09 Store structured doses, cost, stress and craving rechecks (state v12, backup format 7, CSV columns)
- `8c950b8` 2026-10-09 Add dose insights: per-type stats, escalation, same-day repeats, high need, mixing/tolerance warnings, insight confidence and real cost
- `22dd06d` 2026-10-09 Log doses with amount, unit, cost and stress; sanity prompt, mixing/repeat/tolerance warnings, overdose card with 112; bottle-size setting; craving stress and 15-minute recheck
- `b880c66` 2026-10-09 Progress: heat map modes (days/count/amount/cost/stress) with weekday card, per-type card, real-cost money chart, insight confidence, WHY sheet and dismiss-until-evidence-changes
- `42db348` 2026-10-09 Test the recheck notification action; document v12 units, money and insight rules in memory.md
- `2a743e8` 2026-10-09 Backup import: allow any file on mobile so shared/downloaded backups aren't greyed out by MIME filtering
- `e627847` 2026-10-09 Backup import: tolerate BOM, UTF-16, padding and share-text wrappers; clearer errors
- `90d12fd` 2026-10-09 Export: save via the system Save screen; shared copies are no longer deleted before the target reads them
- `f424e16` 2026-10-10 Position status: always-on, quiet position notification while the app is open
- `9b47057` 2026-10-10 App lock (other apps): placeholders only, no enforcement
- `4a79d8d` 2026-10-10 Export: cancelling the Save screen shows no notice; exports return saved/cancelled; emergency export not size-capped; export/import round-trip and cancel tests
- `9fbf1dd` 2026-10-10 Release: R8 keep rules for Gson-backed scheduled notifications and geofence
- `114559a` 2026-10-10 Docs: README features and memory export/import contract; compat matrix for backup formats 1-7 and state v2-v12
- `6ad8997` 2026-10-10 Test: zone alert close and I'M LEAVING each exit in one tap
- *(plus the commit that adds this document)*
