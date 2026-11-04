# Delivery starting baseline — 27 October 2026

Purpose: establish a truthful starting point for the
[D1–D8 action plan](DELIVERY_ACTION_PLAN_2026-10-27.md). This record does not
claim that new logging, tagging, location or protection behavior is implemented.

## Source and contracts

| Item | Observed baseline |
|---|---|
| Source commit | `a246605776a5b4ad577f1974342c8e6781f127fc` |
| Initial checkout | `main`, clean before this documentation change |
| Local origin/main reference | Same commit; no remote refresh performed for this planning pass |
| Retained branches | `9112-deviant/android-handoff`, `9112-deviant/web`; neither modified/deleted |
| App/build | `1.2.0+4` from pubspec.yaml |
| Recovery state | 13 from RecoveryController.stateVersion |
| Portable backup | 8 from BackupService.currentBackupVersion |
| Provisioned Flutter | 3.47.2, cached SDK identity |
| Dart | 3.13.2, verified with the live Dart executable |
| Android device inventory | `adb devices -l` succeeded; no connected devices |

The current immutable event model permits metadata-only copies; changing the
meaning/time requires a designed correction relationship rather than silently
overwriting original type/time. Existing zoneEntry validation rejects coordinate
keys. Both constraints must be addressed explicitly by D1/D4 contracts.

## Existing D1 regression run

Result: **153 tests passed across 15 existing test files**, exit code 0.
The run used the provisioned SDK and existing dependencies (`--no-pub`).

```powershell
flutter test --no-pub --reporter expanded `
  test/features/recovery/domain/recovery_event_test.dart `
  test/features/recovery/domain/event_derived_state_test.dart `
  test/features/recovery/domain/events_csv_test.dart `
  test/features/recovery/domain/dose_units_test.dart `
  test/features/recovery/domain/craving_entry_test.dart `
  test/features/recovery/application/recovery_controller_test.dart `
  test/features/recovery/application/recovery_safety_test.dart `
  test/features/recovery/application/dose_data_test.dart `
  test/features/progress/milestones_test.dart `
  test/features/progress/money_series_test.dart `
  test/features/cravings/craving_stress_recheck_test.dart `
  test/features/recovery/presentation/relapse_dose_form_test.dart `
  test/relapse_log_sheet_test.dart `
  test/features/recovery/services/compat_matrix_test.dart `
  test/features/recovery/services/backup_service_test.dart
```

The actual executable was `F:\Dev\Flutter\bin\flutter.bat`.
Local command output is retained under ignored
`output/delivery-baseline-2026-10-27/d1-tests.log` in this checkout.
The initial sandboxed tool probe could not access the SDK cache; the regression
run completed after SDK-cache access was allowed. No dependency upgrade was run.

## What this proves and what remains

- Existing event, derivation, CSV, quantity, entry, controller/safety, milestone,
  money, recheck, form, compatibility and backup regressions passed at the SHA above.
- These tests predate the new D1 contract. Passing them does not prove the new
  purposes, correction queue, honest day states or use-aware outcomes work.
- New synthetic regression cases are specified in the verification matrix;
  implementation and case-to-test evidence remain pending.
- Banking startup, missed payment blocking, native temporary access and affected
  phone background-location behavior are **not device verified**. No phone is
  connected. The user subsequently clarified the missed-block symptom below;
  native permission/service/package/rule state at the incident is still unavailable.
- Full analysis, all tests, APK builds, signing and same-signer upgrade were not
  rerun for this documentation-only change. Follow the full gates after behavior
  changes and before distribution. No new APK is being claimed or distributed.
- The private export and installed app history were not modified. No account,
  backend deployment, schema-version bump or application code change is included.

## First execution slice

Start D1-A: define the purpose/effective-record/correction/time contract and
synthetic fixtures for C01/C03/C06/C07/C08/C09/C10. Update every affected
reader/writer and compatibility fixture together before presenting new entry UI.
Collect D2 native reproduction details alongside that work; missing hardware does
not prevent local model, UI, diagnostics or synthetic regression implementation.

## D2 clarification — detected zone, missing app interruption

The user clarified that two apps were selected for locking, the danger-area
notification appeared, and a shop payment proceeded without interruption.
Treat this as the primary D2 missed-interruption incident. The separate earlier
report that some banking apps would not open remains unresolved; do not collapse
these into a single bank-startup diagnosis.

The private history corroborates the symptom sequence (CSV record numbering
includes the header):

- Records 172/173: foreground zone entry at 11 October 17:50:57 IST, followed
  about 52 seconds later by the payment-app/no-block report.
- Records 182/183: background zone entry and a shop-payment test note on
  14 October, about 51 seconds apart.
- Records 210–213: already-inside/late-interruption/location-refresh feedback on
  26 October. That later in-app interruption does not prove selected-app blocking.

Private note text and zone names are intentionally not copied into this public
source document. The source export is unchanged.

### Starting-code observations at a246605, before T01

1. `zones/services/native_geofence_gateway.dart:80` handles background entry by
   writing the optional history inbox and showing a zone alert. It does not
   establish native app-lock readiness or deliver its inside-zone state to that
   service. A zone notification can therefore succeed independently of blocking.
2. `AppLockService.kt:118` refreshes its separate zone decision on a roughly
   30-second check; `currentZone()` at line 158 reads cached last-known positions
   rather than requesting a new fix. No eligible fix means no zone activation;
   schedule rules are evaluated separately. This differs from the foreground
   Dart monitor and background geofence path.
3. `AppLockService.kt:200` attempts the block activity only on the applicable
   overlay-permission path and falls back to a separate block-prompt notification
   when it cannot start. The danger-area alert and this fallback are distinct.
   Usage-access/service failure can stop enforcement independently.
4. `app_lock/application/app_lock_host.dart:84` marks the configuration pushed
   before awaiting apply and does not inspect its returned result. A failed
   start is not an acknowledged configuration; ordinary unchanged syncs can be
   skipped until a forced resume/retry. This needs fault-injection regression.

The observations identify concrete investigation/fix targets. They do not select
which permission, service, location, rule or presentation failure caused the
reported device incident. Cases N02/N08/N09 now make that distinction explicit.

These observations describe the starting SHA. The later T01 implementation
addresses acknowledgement/retry in point 4; see the
[implementation review/results](IMPLEMENTATION_REVIEW_2026-10-27.md).
The full selected-app interruption and location/device diagnosis remain open.
