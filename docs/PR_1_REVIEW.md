# PR #1: reviewed fix and feature disposition

[PR #1](https://github.com/abhranilp1998/no-lean-system/pull/1) was reviewed against
base `0f4bc1055185dc03dc90ee44b59b24bd774f2dcb` and original head
`cf4371e10e62299aecebd4988c392f33dcd2fa0c`. This record supersedes the initial
investigation-only report. Final reviewed changes are in the commit containing
this record; GitHub records the precise merged head and merge commit.

## Decision

Merge the corrected implementation after final automated validation; preserve
the useful features and delete the merged feature branch. Device distribution
remains subject to the signed in-place upgrade check in `RELEASING.md`.

## Findings and fixes

| Finding | Implemented result |
| --- | --- |
| Cooldown replaced the entire shell, blocking repeat logging and widget cravings | Tabs remain available. Cooldown, reasons, SOS and reflection remain an optional route. Additional relapses preserve its original event/deadline; reflection is idempotent. |
| No catch-up flow or relapse widget action | Shared multi-event form with date/time per occurrence, add/remove rows, validation, cancellation, one authorization and one atomic save. Same-time separate events survive; retry uses stable IDs. Native request code 12 opens it after startup. |
| App reopening had only a spinner and cached failed loads | Explicit loading, ready, incompatible and error states, retry, bounded read, sanitized recovery-copy export; failed/unsupported reads cannot write defaults. Optional setting damage leaves valid events intact. |
| Legacy migration discarded relapse days and actual pledge times | State 7 migrates known day facts without inventing a count/time. The actual last pledge, baseline, longest streak, cravings, SOS and settings survive. v6 saved originals repair day facts while existing events remain. |
| Failed preference writes appeared successful | Production uses flushed/verified file replacement, a previous commit and immutable migration snapshots. Controller writes serialize, roll back on failure, and update widgets/listeners after commit. The compatibility adapter checks the returned preference-write boolean. |
| Legacy exports were rejected and import could bypass the lock | Backup 3 retains date-only records; importer accepts v1–v3 event backups and v2–v7 legacy/state JSON. Import authenticates and cannot restore a disabled lock from preferences. |
| App version stayed 1.0.0 and releases lacked a convention | App `1.1.0+3`, state 7, backup 3; monotonic build/tag validation, annotated main-only tags, release guide, executable review checks and fresh PR SOP. |
| Current Flutter ListTile assertion inside decorated cards | Transparent Material inside the shared GlassCard preserves styling and gives tile ink its correct surface. |

The greeting appears after a six-hour absence and offers missed-event logging.
Unopened days receive no invented clean/relapse records. Events store occurrence
time separately from recording time. Historical logs do not start a fresh
cooldown. Date-only legacy facts stay clearly labelled in Timeline and backups.

## Useful features retained

- Event history, protected edit/delete, baseline protection, configurable risk
  and cooldown windows, post-SOS calculations and longest-streak preservation.
- SOS start/completion linkage, repeat-safe completion, Better/Same/Worse
  debriefs, encrypted trusted contact and explicit external-dialer action.
- Opt-in private notifications, backup preference preview, secure-data
  exclusions, offline use, accessibility and cyberpunk visual settings.
- Existing native chronometer, widget provider/update contract, root/SOS/craving
  action identities and current package/signing/secure-storage namespaces.
- Product roadmap. No unrelated feature was silently discarded.

Replaced behaviors: silent data resets, global cooldown navigation lock,
optimistic failed-save confirmations and unreliable pre-startup widget dispatch.

## Validation and limits

- Flutter 3.47.2 / Dart 3.13.2. Existing local analyzer exclusions, Gradle Kotlin
  compatibility flags and SDK-compatible dev dependency lockfile updates were
  reviewed and retained. Formatting follows that SDK.
- Automated tests cover migration/reload, false legacy days, exact pledge,
  failed writes and batch retry, concurrent saves, future/malformed state,
  repeat cooldown logs, authorization, backup compatibility, actual file-store
  replacement, widget routing, startup retry and enlarged-text UI.
- Final format check passed with no changes; `dart analyze --fatal-infos` found
  no issues; all **79 tests passed**. Version/base comparison and diff checks
  passed. The final Android debug APK built successfully using the documented
  offline Gradle equivalent after Flutter refreshed version properties.
- No attached Android device or configured emulator was available in this run.
  Native queue behavior was reviewed; Dart cold/warm routing was exercised using
  platform mocks. The affected user's exact crash and real launcher/upgrade
  behavior cannot be claimed as reproduced or device-verified here.
- The APK retains `com.nolean.no_lean`, API 24 minimum/API 36 target, and
  ARMv7/ARM64/x86-64 support. Its local debug certificate matches the preserved
  `1.0.0+1` APK: SHA-256
  `7d72b80dfc2af4b523e21c5779b4363f1b5add5b2b419b01ff0361f476390ec5`.
  This proves the local artifact identity, not every APK previously distributed.
- Old daily storage cannot reveal how many relapses happened on a date or their
  individual times. Those values remain unknown until the user supplies them.

Use the immutable source tag and APK hash in the PR for traceability. Do not ask
users to uninstall, clear storage, accept a different package or force a schema
downgrade. Run the documented in-place device upgrade before APK distribution.
