# NO LEAN handbook

The single, current reference for NO LEAN. It replaces three older notes, which are kept for history:
[CHANGES_AND_ROADMAP.md](CHANGES_AND_ROADMAP.md), [FUNCTIONAL_NOTES_2026-10-10.md](FUNCTIONAL_NOTES_2026-10-10.md) and
[PR_ANDROID_HANDOFF_REVIEW.md](PR_ANDROID_HANDOFF_REVIEW.md). It also folds in the post-merge review of 10 Oct.
Last checked against `main` at `a246605` on 26 Oct 2026, and against release 1.3.0 (PR #4, `9112-deviant/p0-app-lock-activation` at `8b81ca2`) on 29 Oct 2026. All times are IST.

> **Read this first.** Section 0 describes version 1.3.0. It applies to `main` only **after PR #4 merges**. Sections 1–9 describe `main` as it is today (1.2.0+4).

## 0. Release 1.3.0 (PR #4, applies once PR #4 merges)

Source: [PR #4](https://github.com/abhranilp1998/no-lean-system/pull/4), branch `9112-deviant/p0-app-lock-activation` at `8b81ca2`. Test pre-release: [v1.3.0-test.1](https://github.com/abhranilp1998/no-lean-system/releases/tag/v1.3.0-test.1). Tests at `8b81ca2`: 506 pass, `flutter analyze` clean.

### Version and build numbers

App version is **`1.3.0+4005`** (`pubspec.yaml`). When built split per ABI, Flutter adds a per-ABI offset, so each file has its own build number:

| APK | Build number |
|---|---|
| universal | 4005 |
| armeabi-v7a | 5005 |
| arm64-v8a | 6005 |
| x86_64 | 8005 |

**Warning:** Android only installs an update if its build number is equal or higher. After the arm64 build (6005) is on a phone, every later build for that phone must have a build number of at least 6005, or it won't install over it. A later universal build needs `+6005` or higher.

### What changed for the user

**App lock (T01)**
- The app lock now confirms the phone actually applied its settings, and retries if not. A blocked app no longer quietly stays open.
- The status no longer gets stuck on "syncing" after a rare error: it is always cleared at the end (`app_lock_host.dart`, `finally`).
- If the list of locked apps can't be read, the app no longer assumes the blocked app was uninstalled, so it stays blocked (`packages is List` check).
- If switching the lock off fails, the block screen stays up instead of letting the app through.

**History (T06-A)**
- History is split into three tabs: recovery, settings changes and locations (`timeline_screen.dart`).
- Links inside history switch to the right tab in place instead of opening a new screen.
- Manual locations are labelled the same way everywhere through one shared check (`isManualLocationRecord`, `history_projection.dart`).

**Warnings**
- One combined app-lock health banner replaces several stacked ones (`AppLockHealthBanner`).

**Export and import (from PR #3, included in PR #4)**
- A failed export deletes the empty or half-written file it left behind (`DocumentsContract.deleteDocument` in `DocumentExportChannel.kt`).
- If importing a backup changes the evening risk window, the timeline records the change.

**Still in place (unchanged)**
- Export goes through Android's "Save to" screen and checks the saved bytes match.
- Moving or shrinking the risk window needs the PIN (when a PIN is required; see open questions).
- Stored state is still **v13** and backups are still **format 8**, so old data and old backups load.

### How to build and sign (box)

```bash
source /workspace/tools/android_env.sh   # sets Flutter, Android SDK and JAVA_HOME=/workspace/tools/jdk-21.0.13+9
cd <repo>
flutter test && flutter analyze
flutter build apk --release --split-per-abi   # arm64 / v7a / x86_64 APKs
flutter build apk --release                   # universal APK
```

- Signing uses the debug keystore at `~/.android/debug.keystore` (store password `android`). It is a copy of Abhranil's PC key `C:\Users\Abhranil\.android\debug.keystore`, so builds install as updates over his current app.
- Its SHA-256 fingerprint is `7D:72:B8:0D:FC:2A:F4:B5:23:E2:1C:57:79:B4:36:3F:1B:5A:DD:5B:2B:41:9B:01:FF:03:61:F4:76:39:0E:C5`. Check a built APK with `apksigner verify --print-certs <apk>`; the SHA-256 must match. A different key means the APK won't install over the existing app, and uninstalling wipes data.

### How to install the test release

1. In NO LEAN, export a backup first.
2. On the phone, open the [v1.3.0-test.1 release](https://github.com/abhranilp1998/no-lean-system/releases/tag/v1.3.0-test.1) and download `NO-LEAN-1.3.0-arm64-v8a.apk` (fits almost every recent phone). If it won't install, use `NO-LEAN-1.3.0-universal.apk`.
3. Tap the file and allow installing from this source. It installs as an update; your data stays.
4. Go through the testing checklist in the release notes.

### To-do status

| Item | Status |
|---|---|
| T01 app-lock activation | Done (PR #4) |
| T06-A three history tabs | Done (PR #4). Rest of T06 later |
| Release version gate | Met (1.3.0+4005) |
| Real-phone testing | **Pending** |
| T02 record contract | Next, on a new branch from updated `main` |
| T03 capture and drafts, T04 progress follow-ups, T05 full protection path | After T02, with T08 release gate alongside each |
| T07 location | Later |
| T09–T12 | Parked |

### Open questions

- **Risk-window authentication (T05).** Fingerprint unlock is intentional and stays. The open question is whether changing the risk window should always need authentication, even when "require PIN after relapse" is off. Today it doesn't.
- **Production signing.** All builds use a debug key. A real upload key is needed before any Play Store release (not planned now).

### After PR #4 merges

- Close PR #3 as superseded (its fixes arrive with PR #4).
- In sections 2, 5, 6 and 7 below, treat the 1.2.0+4 version, 458-test count, "PR #3 open" and the two PR #3 known issues as historical.

## 1. Summary

- NO LEAN is an Android-first Flutter app for addiction recovery: a PIN-protected risk window, danger zones, SOS, dose and craving logging, insights and an app lock for other apps.
- `main` holds version **1.2.0+4**. All Android work (P0–P3, the 8 StillPoint-derived features, app lock, export/import fixes, risk-window PIN) is merged via PR #2 on 10 Oct.
- **458 Flutter tests pass on `main`** (re-run 26 Oct). 6 native export tests passed in the 10 Oct review.
- Open: PR #3 (two small export/import fixes, 460 tests). Nothing has been tested on a real phone since the merge.
- The StillPoint repo was only a reference. Nothing in it was changed.

## 2. Current state of `main`

| Item | Value |
|---|---|
| Head | `a246605`, "Merge pull request #2: Android 1.2 handoff", 10 Oct 2026 23:05 IST |
| App version | `1.2.0+4` (`pubspec.yaml`), tagged `v1.2.0+4` (tag only, no GitHub release or APK) |
| Stored state | v13 (`RecoveryController.stateVersion`) |
| Backup format | 8 (`BackupService.currentBackupVersion`) |
| Package | `com.nolean.no_lean` (preview: `com.nolean.no_lean.preview`) |
| Release signing | Debug key (`android/app/build.gradle.kts`, line 45) |
| CI / branch protection | None. `.github/` only has a PR template |

App version, state version and backup format are independent of each other.

## 3. What is implemented

### P0: core safety
- Escalating PIN lockouts: 5, then 15, then 60 minutes, kept in secure storage.
- Risk-window lock (default 17:00–21:00) and relock after every saved relapse, when a PIN is set. SOS and craving logging stay reachable (state v8).
- Data-driven risk-window notifications with a pre-window warning; exact alarms when allowed, inexact fallback.
- Map: offline grid with an optional dark OpenStreetMap layer (150 MB tile cache, no bulk downloads).

### P1: danger zones, insights, SOS
- Danger zones: long-press pins, radius 100–2000 m, up to 20 zones (state v9, backup format 4).
- Zone alerts: in-app while open; opt-in background geofence (entry only) after a disclosure. The full-screen alert always exits in one tap (close, Back, **I'M LEAVING**).
- Foreground GPS requests a current fix on open/resume and drops stale, future-dated or late results (`36f86ef`).
- Insights shown only after 5+ events with a pattern repeating 3+ times.
- 4-stage SOS: breathe, 5-4-3-2-1 grounding, reasons, re-pledge.

### P2: privacy and tools
- Street tiles off switch (grid only, zero network; state v10).
- CSV export (read-only; JSON is the restore format).
- Quiet hours (risk-window and zone alerts still come through); hide-sensitive notification text.
- Home widgets 2x1, 4x2, 4x3 with privacy mode.
- Code Instead: logged focus timer (`codeSession` events).

### P3: progress
- Milestones at 3, 7, 14, 30, 60, 90, 180, 365 days.
- Money kept vs lost chart.
- Opt-in zone visit history: zone name and time only, never coordinates (state v11, backup format 6).

### StillPoint-derived features (state v12, backup format 7)
1. Dose units ml, L, bottle, drink, tablet. Maths in ml; bottle size setting (default 100 ml, 10–2000). Old bottle-only notes stay as text when their historical size is unknown (`3c0ab86`).
2. Per-type insights and escalation (latest dose ≥ 1.2× the average of earlier same-type doses).
3. Safety warnings: mixing depressants, second dose same day, tolerance drop after 3+ clean days, with an overdose card and **CALL 112**.
4. Stress rating 1–5 on relapses and cravings.
5. 15-minute craving recheck notification (skipped in quiet hours).
6. Insight confidence, WHY sheet, dismiss until evidence changes.
7. Real cost: recorded costs plus labelled estimates.
8. Heat map modes (days, count, amount, cost, stress) and a 12-week weekday card.

Also: an always-on, quiet position notification while the app is open (rounded coordinates, nearest zone).

### App lock for other apps, with exit plan (state v13, backup format 8)
- Settings > Protection > App lock. Pick launchable apps; schedules Always, Risk window or Danger zones, plus "also lock inside danger zones".
- `AppLockService` (foreground service, `specialUse`) polls `UsageStatsManager` about every 1 s and brings up NO LEAN's blocking screen. No AccessibilityService.
- Blocking screen always shows **SOS**, **CALL 112**, **GO HOME**; Back goes home. Exit plan: pick a reason, 30-second mindful wait (10 s for payment apps) within a daily budget (default 3), then that app opens for 5 minutes. After the budget: PIN or biometrics. With no PIN or during a lockout, a 120-second wait still opens it. Every unlock is logged as an `appUnlock` event.
- Never lockable: dialer and in-call, emergency apps, maps, NO LEAN itself, Settings, permission controller, launchers.
- Fail-safe: revoked permission, killed service or bad config means nothing is locked, and a PAUSED/STOPPED banner with FIX appears.
- Loosening the lock needs the PIN when one is set; tightening is always free.

### Export and import
- Android export uses the system Save screen through a native channel (`DocumentExportChannel.kt`): it writes off the main thread, reads the file back and compares every byte before saying "saved". Cancel shows nothing; failure shows an error (`98a4112`).
- Emergency export at startup is not size-capped (`4a79d8d`).
- Shared copies keep their source for an hour, carry no caption and get unique names.
- Import accepts any picked file and handles BOM, UTF-16, padding and share-text wrappers. It names empty, caption-only and damaged files. Malformed UTF-8 is refused (no Latin-1 guessing).

### Risk-window PIN
- When the evening wall or risk-window app lock is armed and a PIN exists, removing any protected minute (moving or shrinking 17:00–21:00) needs the PIN or biometrics. Extending is free. Each change is logged as a `settingsChange` event (`a07e5dd`).

## 4. Data compatibility

| Contract | Current | Still accepted |
|---|---|---|
| Stored state (`recovery/current.json`) | v13 | v2–v13, migrated forward. Corrupt or unknown state opens a recovery screen and is never reset |
| JSON backup | format 8 | formats 1–8 and raw state files v2–v13. Newer formats are refused as a whole |
| CSV | columns only appended | not importable |

- Every format and state version is covered by `test/features/recovery/services/compat_matrix_test.dart`.
- PIN, trusted contact, app-lock policy and privacy/location choices are never exported. An import never turns on location features, lock flags or the app lock.
- New code reads old data; an old app is not expected to read new formats.
- The preview and the original are different packages with different signers. Updating the original does not bring over preview history.

## 5. Verification

| Check | Result |
|---|---|
| `flutter test` on `main` | **458 / 458 passed** (re-run 26 Oct 2026) |
| `flutter analyze` on `main` | No issues (10 Oct review) |
| Native `DocumentBytesTest` | 6 / 6 passed (10 Oct review) |
| Release build | Builds with R8. Split-ABI builds get versionCode 2004 (arm64); universal gets 4 |
| PR #3 branch | 460 / 460 passed |
| Real phone | **Not tested.** Only the old share failure was inspected on the OnePlus CPH2661 (Android 16). The new build was never installed on it |

Not yet verified on a real phone: install over the original, Save to Downloads/Drive, app lock service, background/screen-off/reboot zone alerts, quiet hours, widgets, the position notification, risk-window alerts after reboot.

## 6. Branch and PR history (IST)

| Item | Status |
|---|---|
| PR #1 `9112-deviant/production-hardening` | Merged 8 Sep 2026 09:55 (`4be697e`, tag `v1.1.0+3`). Branch deleted |
| PR #2 `9112-deviant/android-handoff` | Merged 10 Oct 2026 23:05 (`a246605`, tag `v1.2.0+4`). Branch fully in `main` |
| `nolean-v2-handoff` | Fully in `main` via PR #2 (its tip `78198bb` was the base of the android-handoff branch) |
| PR #3 `review-fixes-export-import-log` | **Open, not merged.** 1 commit (`75a88ea`) ahead of `main`, 0 behind. Included in PR #4; close after PR #4 merges |
| PR #4 `9112-deviant/p0-app-lock-activation` | **Draft, open.** 1.3.0 (T01, T06-A, PR #3 fixes) at `8b81ca2`, 506 tests. Merge with a normal merge commit after phone testing |
| `v1.3.0-test.1` pre-release | Test APKs for 1.3.0, signed with the PC debug key |
| `9112-deviant/web` | **Not merged, on hold.** Web work from 6 Oct (`e903df8`). 1 commit ahead, 58 behind; conflicts with `main` in `.gitignore`, `pubspec.yaml`, `recovery_provider.dart`, `backup_service.dart` |
| `preview-2026-10-09` pre-release | Stale: built before the 10 Oct fixes, still named "stillpoint-8" |

## 7. Known issues

- **Debug signing.** Release builds use the debug key, so they aren't fit for the Play Store and the signer depends on the build machine.
- **No PIN, no friction.** Without a PIN, the app lock and risk window can be loosened freely, and the app lock can be turned on without a PIN.
- **Stale location for zone-based app lock.** The service uses last-known location up to 10 minutes old and never asks for GPS.
- **Failed export leaves a file behind** (fixed in PR #3, not on `main`).
- **Risk-window change from a backup import is not logged** (fixed in PR #3, not on `main`).
- **Two foreground location streams** (zone monitor and position notification) double GPS use.
- **Version codes differ:** universal build = 4, split-ABI arm64 = 2004. A later universal build can't update a 2004 install. In 1.3.0: universal 4005, arm64 6005 (see section 0).
- App lock limits: up to ~1–2 s before the blocking screen appears; OEM battery savers can kill the service (no battery-exemption helper yet); "Display over other apps" is needed on Android 10+.
- Background zone alerts need "Allow all the time"; Android 13+ needs notification permission; Android 14+ may show the zone alert as a heads-up instead of full screen.
- If the phone clock is off by more than ~1–2 minutes, foreground zone alerts silently drop every fix.
- Bottle quantities converted by earlier previews are not repaired.
- No custom lock-window editor; `cupertino_icons` unused; Gradle/AGP/Kotlin deprecation warnings.
- Play release needs declarations for Usage access, overlay, `specialUse` foreground service, background location and full-screen intent. Sideloading is unaffected.

## 8. Open items and roadmap

**Now**
1. **PR #3**: merge decision. Deletes the half-written file when an export fails and logs risk-window changes from backup imports.
2. **Require a PIN to enable the app lock** (or add a delay to loosen it when no PIN exists).
3. **Fresher location for the zone lock**: geofence state or an opt-in location foreground service.
4. **One version-code scheme** (universal or split-ABI), documented in `docs/RELEASING.md`.

**Before anyone else installs it**
5. **Update over the installed app.** The installed 1.1.0 was built on Abhranil's PC and signed with `C:\Users\Abhranil\.android\debug.keystore`. An update must be signed with that same key (build on that PC or copy the keystore to the build machine); otherwise it won't install, and uninstalling wipes data.
6. **Real-phone testing**: install over the original and check data survives; export to Downloads and Drive, cancel, re-import; app lock (grants, blocking screen, exit plan, budget then PIN, revoke, reboot); zones in foreground, background, screen off, after reboot and under battery limits; quiet hours; widgets; position notification.
7. Rebuild or retire the stale preview APK.

**Process**
8. **CI**: GitHub Actions running analyze, tests, native tests and a debug build; protect `main`.
9. Real upload keystore for release builds; Play Console declarations.
10. Upgrade Gradle, AGP and Kotlin together.

**Later**
- One shared foreground location source; location health screen; battery-exemption helper.
- Custom lock-window editor; unlock patterns in insights.
- Automatic encrypted backup; evening check-ins; trusted-person check-in (user sends); taper plan; weekly report.
- Review tolerance/dose safety wording with clinical guidance.
- Web: rebase `9112-deviant/web` onto `main` when work resumes.

## 9. Key files

| Area | Files |
|---|---|
| State and migrations | `lib/features/recovery/application/recovery_controller.dart`, `lib/features/recovery/domain/quantity_upgrade.dart` |
| Backup/export/import | `lib/features/recovery/services/backup_service.dart`, `lib/features/settings/services/recovery_export_service.dart`, `android/.../DocumentExportChannel.kt`, `DocumentBytes.kt` |
| Doses and safety | `lib/features/recovery/domain/dose_units.dart`, `dose_safety.dart`, `lib/features/progress/domain/dose_insights.dart` |
| Notifications | `lib/features/recovery/services/notification_service.dart`, `lib/features/recovery/domain/notification_policy.dart` |
| Zones and position | `lib/features/zones/` (`zone_monitor.dart`, `position_status_host.dart`, `native_geofence_gateway.dart`, `zone_alert_screen.dart`) |
| PIN lock | `lib/features/recovery/services/relapse_lock_service.dart`, `lib/features/recovery/presentation/app_lock_screen.dart` |
| App lock | `lib/features/app_lock/`, `android/app/src/main/kotlin/com/nolean/no_lean/AppLock*.kt` |
| Android config | `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`, `android/app/proguard-rules.pro` |
| Tests | `test/features/recovery/services/compat_matrix_test.dart`, `test/features/settings/services/export_flow_test.dart`, `integration_test/` |
| Release process | `docs/RELEASING.md`, `docs/PR_REVIEW_SOP.md`, `memory.md` |
