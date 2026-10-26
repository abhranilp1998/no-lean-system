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

Implementation results will be recorded after the runtime change and final checks.
