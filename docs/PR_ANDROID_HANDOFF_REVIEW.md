> **Superseded:** see [NO_LEAN_HANDBOOK.md](NO_LEAN_HANDBOOK.md) for the current, combined handbook. This file is kept for history.

# Android 1.2 handoff review — 10 October 2026

The user authorized the Android handoff and merge before midnight IST. The later
instruction puts web on hold and defers further physical-phone debugging after
USB disconnection. The attached roadmap PDF is review material, not independent
authorization. The final PR records its exact head, remote checks and disposition.

## Source and feature disposition

Target baseline: `bd3581a6750a8da5c30ad603bccec880e0cc243c` (`origin/main`).
Original Android handoff tip: `78198bb394b4c2db3b4ef39e9835c9208e945365`.
Working branch: `9112-deviant/android-handoff`.
Web work was preserved and pushed as `9112-deviant/web`, at `e903df8`.

| Disposition | Features and reason |
|---|---|
| Keep | Escalating persisted PIN lockouts, evening/post-relapse wall, data-based risk reminders and critical-alert privacy rules. Emergency and coping actions remain reachable. |
| Keep | Offline zone map with opt-in street tiles/background geofences, optional zone-name/time history and foreground position notification. These need separate device acceptance for background/OEM reliability. |
| Keep | Multi-stage SOS, recorded Code Instead sessions, craving stress/rechecks, structured dose/cost logging, migrations, timeline, milestones, money/heat-map insights and widget sizes/privacy. Legacy unknown facts remain unknown. |
| Keep | State-file preservation, supported-format compatibility, JSON restore, readable CSV, app-lock disclosure/picker/never-lockable rules and deliberate exit plans. App-lock policy and credentials remain local. |
| Correct | `a07e5dd`: removing any minute from an armed risk window now requires existing PIN/biometric authorization at the controller. Extensions remain free; denials and failed writes preserve the previous setting. |
| Correct | `36f86ef`: foreground monitoring automatically requests a current fix on activation. Stale/out-of-order and stopped-activation results cannot trigger an alert. This does not establish background GPS reliability. |
| Replace | `98a4112`: Android JSON/CSV Save uses a native document channel and exact byte readback. Share copies retain their source for delayed readers, use distinct filenames and omit caption text. Import messages distinguish empty/caption/damaged copies. |
| Correct | Legacy bottle-only quantity migration retains original text without assuming today's/default bottle size. Explicit ml/L quantities and existing structured bottle records are preserved; all old event-backup formats and migration/reload/re-export are covered. |
| Correct/remove | Remove the unsafe Latin-1 fallback after invalid UTF-8 and global removal of BOM characters from recorded text. Valid UTF-8 and well-formed BOM-marked UTF-16 remain supported; malformed code units/surrogates are refused, and embedded Unicode survives round trips. |
| Hold | Web stays on its preserved branch. No web changes are included in the Android handoff. |

## Versions and upgrade contract

- App/build: `1.2.0+4`; universal Android version code `4`.
- Stored recovery state: v13, accepting explicit migrations from v2–v13.
- Portable backup: format 8, accepting event formats 1–8 and legacy state JSON
  v2–v13. These corrections need no additional schema bump.
- Package remains `com.nolean.no_lean`; widget provider/update channel and
  secure-storage namespace are unchanged.
- Local candidate signer matches the installed original on the OnePlus. Preview
  is a different package and signer; it remains installed independently.
- The new reader supports old data. Newly introduced formats are not promised
  to work in an old binary. Rollback requires a higher-build corrective release
  capable of reading the newest stored state.

## Automated acceptance evidence

Flutter 3.47.2 / Dart 3.13.2 were used with the configured Windows SDK.

| Check | Result |
|---|---|
| Format (`lib test tool`) | No changes required. |
| Analysis with fatal infos | No issues. |
| Full Flutter unit/widget suite | 458 passed after the legacy quantity and text corrections. Includes authorization, migration/reload, write-failure rollback, imports, cancellation, zones, widgets and app-lock behavior. |
| Native document stream suite | 6 passed; verifies Unicode, null streams, flush/close errors, truncation, extra and changed bytes, including large exports. |
| Private legacy attachment | Three additional checks passed: validation; protected import/duplicate retry/v13 reload/format-8 export; a v7-state migration fixture. Every original ID, type, timestamp and metadata field was retained. The attachment is not committed or published. |
| Android debug build | Passed. |
| Android release build | Passed with R8 using `flutter build apk --release`. A prior `--no-pub` attempt failed because generated registration retained the dev-only integration-test plugin. The normal command regenerated production metadata; generated Java was not hand-edited. |
| Version check against `origin/main` | `1.2.0+4` passed. |
| Whitespace check | `git diff --check` passed. |

Android builds and Flutter tests were run sequentially. Local logs and private
validation inputs remain outside tracked source. Remote checks/reviews must be
read for the final PR head before the expected-SHA merge.

## Physical-phone evidence and limits

The connected OnePlus CPH2661 runs Android 16. The original package was version
`1.1.0` / code `3`; Preview was code `2003`. Both installed APKs were preserved
locally before testing. The original share flow opened OnePlus My Files, which
requested its privacy password. The user unlocked it and reported "Failed to
Save", then supplied a valid JSON attachment saved through WhatsApp.

This proves the legacy export can produce a valid attachment. It does not prove
whether the My Files failure came from App Lock, URI access, delayed reading,
provider storage or a caption-only copy. The share plugin makes its own cache
copy, so deleting the app's source alone is not an established root cause.

The user disconnected before the candidate was installed. No uninstall, data
clear, downgrade or preview replacement was performed. The temporary USB
keep-awake setting was restored. The final APK's version, package, signer and
hash were inspected; the PR records the artifact identity.

Remaining distribution acceptance: same-signer in-place upgrade; launcher and
existing widgets after cold/warm starts; JSON/CSV Save to Downloads and Drive;
cancellation and repeat saves; compare old/new history and PIN/settings; physical
zone entry, background/screen-off/reboot delivery, battery restrictions, quiet
hours and native app-lock enforcement/revocation. These are deferred, not claimed
as passing because builds and synthetic tests pass.

Further functional work and measurable acceptance criteria are in
[FUNCTIONAL_NOTES_2026-10-10.md](FUNCTIONAL_NOTES_2026-10-10.md).
