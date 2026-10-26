# First implementation review — 27 October 2026

This review precedes the first runtime edit. Queue: [TODO.md](../TODO.md).

## Reviewed starting point

- HEAD and freshly fetched origin/main:
  `a246605776a5b4ad577f1974342c8e6781f127fc`.
- Branch created: `9112-deviant/p0-app-lock-activation`.
- Existing README/ROADMAP and delivery-document edits are preserved on this
  branch; no unrelated work or retained branch was discarded.
- Existing D1 baseline: 153 tests passed. App/build 1.2.0+4, state 13, backup 8.
- The implementation is local; no release, merge or version allocation follows
  merely from creating this branch. Refresh/review the final base again for a PR.

## Findings and selected priority

1. **Confirmed code defect, P0 slice:** AppLockHost caches config before native
   apply/disable returns and ignores the result. A failed start can be treated
   as pushed, so another ordinary sync of the same config is skipped. A failed
   new config can also leave the old cache incorrectly trusted.
2. **User-visible gap:** native permission/service flags can appear healthy even
   though the requested config was not acknowledged. The last failed update
   needs its own transient health message until an acknowledged retry clears it.
3. **Larger incident remains separate:** notification and app-blocking location
   paths can disagree, and no affected phone is connected. Fixing acknowledgement
   does not prove that the user's shop-payment interruption has been repaired.
4. **D1 remains the next foundation:** purpose/time/revision schema changes must
   update migrations, exports and all projections together. Do not rush a partial
   persisted contract into this small no-schema fix.

Decision: implement the bounded T01/D2-N09 acknowledgement, retry and failure
visibility fix first, then continue D1-A. D2 device diagnosis and D5 quality
checks continue beside that sequence. This small verified prelude refines the
earlier D1-first sequence without moving all of D2 ahead of the record foundation.

## Keep / replace / remove

| Disposition | Behavior |
|---|---|
| Keep | Saved device-local policy, protection authorization, lifecycle sync, essential routes, native fail-open behavior and existing permission/service diagnostics |
| Replace | Cache-before-apply with acknowledgement only after successful native result; invalidate acknowledgement before a changed/forced attempt |
| Replace | Silent configuration failure with a transient health warning, retryable on state change/resume and cleared only after success |
| Remove | No features or historical data removed; only false acknowledgement and hidden update failure are corrected |

## Scope and regression plan

- Reproduce the missing retry with a failing gateway before the runtime edit.
- Check returned failure, thrown exception and failed disable, including a
  previously acknowledged policy followed by failed replacement and restoration.
- Check acknowledged unchanged config is not repeatedly pushed; a later state
  change/resume retries failure, and in-flight changed config is eventually applied.
- Check warning visibility even with healthy permission/service flags, clearing
  after success, and disposal while an async request is pending.
- Keep error state ephemeral and avoid raw exception/config/private data in copy.
- Run focused app-lock tests, then repository formatting/analysis/full tests and
  the applicable Android build/release checks. Record actual limits in the
  implementation evidence; target scenarios are not test results.

## Data and distribution impact

No persisted model, event, backup, application ID, signer or installed data change
is required for this slice. State/backup versions remain unchanged. A distributed
candidate still needs an inventoried higher app build and same-signer upgrade
evidence through RELEASING.md. Existing Android/web branches remain retained.

## Implementation results

The acknowledgement/retry fix is implemented. A failed or throwing native
apply/disable clears the acknowledged-config cache; only an accepted result can
populate it. Failed updates remain visible with RETRY and FIX actions. Pending
forced retries are serialized without losing their force flag. Known unsupported
platforms use their no-op capability without a false Android failure warning.
No native method/persistence contract was changed.

| Check | Observed result |
|---|---|
| Before-fix regression | Failed as expected: second sync made no native retry (one call instead of two) |
| New host regressions | 12 cases cover failures, retry, old-policy invalidation, disable, lifecycle, concurrent updates, disposal and unsupported-platform behavior |
| App-lock plus app smoke suite | 63 tests passed, including cooldown navigation/repeat logging |
| Full Flutter suite | 470 tests passed after the unsupported-platform correction |
| Static analysis | `dart analyze --fatal-infos`: no issues |
| Formatting | 203 Dart files checked; zero changes required |
| Android compile checks | Both `flutter build apk --release` and `flutter build apk --debug` succeeded, sequentially after the tests |
| Release version gate | Pending allocation: unchanged 1.2.0+4 correctly fails `check --base-ref=origin/main` |
| Device / complete D2 | Not verified; affected-device interruption, shared location and banking diagnosis remain open |

The unsupported-platform correction was prompted by the full app cooldown
regression; that flow and the full suite now pass. Native update failures on
Android remain visible rather than being classified as an unsupported platform.

Logs are retained locally under ignored `output/p0-app-lock-activation/`.
The version gate must pass before merge readiness; distributed-build inventory,
same-signer upgrade and device evidence remain separate release gates. No release
tag, deployment or merge is part of this checkpoint.

### Internal compile artifact identity

The release compile output was inspected with aapt/apksigner: package
`com.nolean.no_lean`, version `1.2.0`, code `4`, minimum API 24 and target API 36.
Its SHA-256 is `0a7bb416a402e81e65be05fd88da4f4b5c6eeb501a09deaed46f9d33bb79a8fa`;
the signer SHA-256 is
`7d72b80dfc2af4b523e21c5779b4363f1b5add5b2b419b01ff0361f476390ec5`.
The debug output SHA-256 is
`f6b5d7d83bf785e3cc7322026f331e921441471d7aab307eb12e1744d85bb1b3`.
These are internal compile checks with the unchanged build number, not a new
distributable release or evidence of an installed-app upgrade. Build outputs are
ignored; no APK is committed. The next candidate must satisfy the version and
device/signing/upgrade gates rather than reusing these outputs for distribution.
