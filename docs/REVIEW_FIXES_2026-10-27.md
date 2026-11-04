# History/protection review fixes — 27 October 2026

This follows the user's six review findings on the published history checkpoint.
The active branch remains `9112-deviant/p0-app-lock-activation`; main is unchanged.
Complete this review before starting the next D1-A record-contract slice.

## Version and preservation decisions

- Candidate app/build is **1.3.0+4005**. Fetched main and the highest release tag
  are 1.2.0+4. Inspected local universal NO LEAN APKs also report code 4.
  The existing release policy documents older source-build-4 ABI codes
  1004/2004/4004; choosing universal code 4005 also clears that known range.
  Keep this candidate universal and use the next higher build for a later
  distributed rebuild. External APKs not available locally cannot be inventoried
  here, and no installed-upgrade result is claimed.
- State **13**, portable backup **8**, Android package, widget contracts and
  secure-storage namespace remain unchanged. UI and stream-cleanup changes do
  not require a migration or conversion of existing data.
- PR [#3](https://github.com/abhranilp1998/no-lean-system/pull/3) was open/unmerged.
  Both changes were absent in the history branch before this review. Exact head
  `75a88ea945633e688b2a081d2dccf03bd20024c9` is now merged into this feature branch
  with its original ancestry, rather than recreated or dropped. It is not merged
  into main by this action; retain the original PR and branch.
- PR #3 preserves two behaviors: best-effort deletion of a newly created export
  document after write/readback verification fails, and a settings audit when
  importing preferences actually changes the risk window. The audit remains
  inside the existing authorized, atomic transaction.
- Native cleanup is factored around the existing byte verifier for regression
  testing. A provider may refuse deletion; cleanup must never mask the original
  failed-save result or delete a verified successful export.

## Review targets

| Finding | Required corrected behavior |
|---|---|
| 1 — Reused build | Higher candidate version, passing version guard and rebuilt APK identity |
| 2 — PR #3 missing | Ancestor proof plus native cleanup/import/compatibility evidence on the combined branch |
| 3 — Failed disable | Saved Off is treated as requested intent until native acknowledgement; unresolved native enforcement keeps essential block actions reachable and retry visible |
| 4 — History route growth | Cross-links switch the owning history's tabs; detail cross-links return to that history, with one Back to its entry page |
| 5 — Manual-source mismatch | All supported manual aliases use consistent saved-location title and uncertainty copy without rewriting stored provenance |
| 6 — Warning suppression | Sync failure and missing-permission/service warnings can be visible together |

The native block queue is private to the app and populated by its selected-app
service checks; exported activity intents only signal draining. During an
unacknowledged change, Dart continues to show essential exits for those native
requests even if saved intent is Off or no longer lists that package. Both Dart
and the native handoff retain protected-app exclusions. An accepted stop/removal
removes only its stale block route, preserving an SOS route above it.
Here acknowledgement means acceptance of the native method. The existing native
implementation does not measure durable `SharedPreferences.apply()` completion
or service destruction; those native diagnostics and affected-device behavior
remain part of full T05, rather than being claimed by mocked Dart tests.

History detail cross-links return a destination to the owning history route,
then switch tabs there. Direct links switch without pushing any route. Explicit
record links clear an incompatible source filter; ordinary tab switches preserve
filter/scroll state. The three manual source aliases share a presentation rule
without rewriting their stored source values.

The combined-warning message area is height-bounded and scrollable. RETRY/FIX
remain outside it, leaving room for the shell's content at narrow/large-text
sizes. Showing additional health warnings must not displace essential actions.

## Verification and release boundary

| Check | Observed result |
|---|---|
| PR #3 preservation | Exact `75a88ea...` head is an ancestor of the feature branch; both previously absent fixes are present |
| Version guard | `1.3.0+4005` passes against fetched main and release tags; final APK identity recorded below |
| Full Flutter suite | **504 passed**, including 19 additional Dart regressions over the original 485-test history checkpoint |
| Native Gradle unit suite | **12 passed**, zero failures/errors; `:app:testDebugUnitTest` succeeded with normal dependency resolution (58 s), including Android Kotlin/channel compilation |
| Native direct JVM cross-check | The same six original stream tests and six new cleanup tests also passed with the cached Kotlin/JUnit runner |
| Formatting / analysis | 206 Dart files checked with zero formatting changes; fatal-info analysis reports no issues |
| Layout / navigation | Synthetic normal and 200% text previews inspected; bounded warnings retain visible actions/body; repeated history links and one-Back return are covered |
| Authorization / compatibility | Denied/locked-out imports, no-op/omitted restoration, failed-save rollback, legacy format 6 → state 13 → backup 8, original IDs, unknown bottles, embedded U+FEFF and Unicode covered |
| Native acknowledgement safety | Cold saved-Off/empty selection, pending stop, old-ack/current-intent race, throwing stop, protected apps, SOS route preservation and disposed-during-save/no-grant covered with controlled gateways |
| Final Android APK builds | Normal universal release/debug builds both passed sequentially after tests; Gradle 234.7 s / 51.2 s. Both inspected APKs report 1.3.0 / code 4005 and the existing signer |

The first offline Gradle unit attempt could not resolve uncached
`androidx.test:runner:1.2+` metadata. Normal dependency resolution succeeded; the
final Gradle result above supersedes that failed attempt. No dependency pins or
build-validation bypasses were introduced.

Tests use synthetic data; private CSV contents and device logs are not uploaded.
Logs, JVM runner/dependency inventory and previews are retained under ignored
`output/history-review-fixes/`. Existing map-tile tests print invalid-image
diagnostics for synthetic responses; the complete suite passes.

### Candidate artifact identity

Both APKs report package `com.nolean.no_lean`, version `1.3.0`, code `4005`.
The release APK retains minimum API 24 and target API 36. Certificate SHA-256
for both matches the previous candidate:
`7d72b80dfc2af4b523e21c5779b4363f1b5add5b2b419b01ff0361f476390ec5`.

- Release APK SHA-256:
  `505272eed8b8a80460e5d19dbe1521a68a266bf99f286ed9d73e103b48b4c090`.
- Debug APK SHA-256:
  `e5de451d6e89b5947ff72f6089469fde74e83b7d1eb64b305dfebf0545695916`.

These ignored local artifacts are compile candidates, not distributed releases.
The existing local debug signer has been retained; production signing remains
its separately tracked release task.

### Review disposition

All six review findings are addressed on the retained feature branch. PR #3's
original head remains in its ancestry and its original PR/branch is preserved.
The published branch comparison is the review surface; no new PR was created
through the integration that previously denied PR creation. The next delivery
is D1-A record/purpose/correction contracts in [TODO.md](../TODO.md).

No device is connected (`adb devices -l`). Physical selected-app interruption,
banking startup, background/OEM behavior, real document-provider behavior and
same-signer installed upgrade remain device acceptance gates. Build/test success
alone does not establish those outcomes. No main merge, release tag or APK
distribution is included in this checkpoint.

## 28 October follow-up — sync status cleanup

The stale-prompt check now inspects the package-list type safely. An unknown
list is not evidence that a package was removed. When synchronization exits,
`finally` clears its pending indicator unless a queued successor has taken
ownership, retaining the existing late-acknowledgement/queued-retry behavior.

Two fault-injection regressions reproduced the previous stuck `true` flag
before the fix, then passed afterward. All 21 host regressions and the full
506-test Flutter suite pass; fatal-info analysis is clean and 209 Dart files
including integration/driver sources pass formatting. Stored contracts and the
undistributed 1.3.0+4005 candidate version are unchanged. Both sequential compile
checks passed: debug (208.5 s Gradle task) and release (134.1 s). Package/version
and the existing signer were verified on both APKs. Prior hashes above describe
the 27 October checkpoint; the 28 October internal compile hashes are:

- Debug: `35860f301124f63bfeedc70e2a36f0091ce192bf228dd5b1a5deafa7a47bdede`.
- Release: `9df504b4755bd2482830117e60efbee722813d6bafeeb0b9c40c5441d3ebe09c`.

Logs are in ignored `output/app-lock-sync-cleanup/`. The refreshed main/tag
version guard and PR #3 ancestor check pass. No merge, release tag, distribution
or new physical-device acceptance is part of this follow-up.
