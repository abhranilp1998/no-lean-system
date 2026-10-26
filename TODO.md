# NO LEAN prioritized TODO

Updated 27 October 2026. This is the execution queue for the
[D1–D8 plan](docs/DELIVERY_ACTION_PLAN_2026-10-27.md),
[SOPs](docs/DELIVERY_SOPS.md) and
[acceptance matrix](docs/DELIVERY_VERIFICATION_MATRIX.md).
Feature IDs remain F01–F60; work packages below can contain overlapping fixes.

## Current work and branch policy

- Current branch: `9112-deviant/p0-app-lock-activation`.
- Base: freshly fetched `origin/main` at `a246605776a5b4ad577f1974342c8e6781f127fc`.
- [Pre-implementation review](docs/IMPLEMENTATION_REVIEW_2026-10-27.md) completed
  before starting T01. It selects one bounded D2 fix before the larger D1 work.
- Use short feature/fix branches from reviewed main, one coherent slice per PR.
  Run applicable checks, review the final diff, then merge through a reviewed PR.
  Do not keep all D1–D8 work on a long-lived version branch.
- Allocate the app release version when preparing a distributable candidate;
  branch names do not allocate versions. State/backup versions change only when
  their contracts change. Keep retained Android/web branches separate.
  This repository's version check also gates merge readiness: allocate/check a
  build above main and the distributed inventory before the feature PR is merged.

## P0 — current queue

- [ ] **T01 — Native app-lock acknowledgement and retry (D2, F14; N09).**
  First bounded implementation. A failed/throwing apply or disable must not be
  cached as acknowledged. Show an honest update-failure state and allow the next
  state change/resume to retry. Test failed→success, policy change after failure,
  exception, disable failure, in-flight updates and removal while awaiting native.
  This does not establish that selected-app interruption works on the phone.
- [ ] **T02 — Record contract and compatibility (D1-A; F01, F03, F04, F06).**
  Define purpose, mixed facts, effective revisions, occurrence/recording time,
  legacy/unreviewed meaning and honest day state. Update affected readers/writers
  and compatible fixtures together before new entry forms.
- [ ] **T03 — Capture, drafts and reviewed correction (D1-B/C/D;
  F02, F03, F04, F07, F08, F59).** Short forms, optional notes, saved drafts,
  missing-history queue, duplicate matching, amount conflict review and one
  expense per linked acquisition. Preserve originals and unknowns.
- [ ] **T04 — Progress and appropriate follow-ups (D1-E/F;
  F05, F06, F09, F60).** Reconcile milestone baselines after corrections;
  preserve valid achievements, distinguish unknown days and record use-since-urge
  without turning a lower rating into an automatic recovery win.
- [ ] **T05 — Full missed-interruption/protection path (D2;
  F10, F11, F12, F13, F14, F15, F58).** Trace zone observation → native policy/
  service readiness → selected app → active rule/no grant → visible block.
  Unify foreground location, define refresh policy, verify unlock/expiry and
  essential access, then measure background behavior on affected phones.
  The separate banking-startup report remains an investigation item.

## P1 — next deliveries; quality work starts immediately

- [ ] **T06 — Three histories and complete multi-tagging (D3; F16–F25).**
  Shared records/details; custom/recent/favorite tags; rename/archive/merge;
  bulk additive add/remove with preview/undo; combined filters and Any/All tags;
  round-trip preservation and no duplicate metrics.
- [ ] **T07 — Optional manual/automatic location experience (D4; F26–F31).**
  Refresh during logging, coordinate/pin editing, explicit attachment/source,
  accuracy/freshness, visit deduplication, list/map, retention/deletion/export.
  No-location logging and uncertain old visits remain supported.
- [ ] **T08 — Cross-cutting ownership and release gate (D5; F32–F37).**
  Apply save/retry/recovery, compatible JSON/CSV/import, shared accessible UI and
  privacy checks to every slice. Complete backup/restore, CI/signing transition
  and same-signer upgrade evidence before distribution. This is not deferred
  until after D3/D4; only the integrated candidate gate occurs then.

## P2 — after trustworthy core records and protection

- [ ] **T09 — Optional planning and quality of life (D6; F38–F48).**
  Travel/return, evening/weekend plans, sleep/wake context, skippable setup,
  cooldown/SOS continuity, preferred interventions, weekly reflection,
  non-streak goals, user-sent contact templates and tactical-calm refinements.
- [ ] **T10 — Small support/encrypted-backup pilot (D7; F49–F51).**
  Allowlisted support diagnostics, user-controlled encrypted snapshots,
  recoverable-key/retention/restore evidence and the refined MSSQL contract.
  Stable local contracts and ownership/restore gates are prerequisites;
  completing D6 or all 21 draft tables is not.

## P3 / held

- [ ] **T11 — Optional identity, sync and native extras (D8; F52–F55).**
  Google linking, account ownership/lifecycle, outbox/revisions/conflicts/
  tombstones and stale-device deletion tests, then separately scoped native extras.
- [ ] **T12 — Held work (D8; F56–F57).** Web remains separate; taper/planning
  exploration requires its own product/clinical scope. Neither is current Android
  implementation scope.

## Established starting evidence

- [x] Complete source-export review and stable 60-item feature mapping.
- [x] Eight deliveries, 15 SOPs and 56 target acceptance scenarios documented.
- [x] Existing D1 baseline: 153 tests in 15 files passed; see the
  [baseline record](docs/DELIVERY_BASELINE_2026-10-27.md).
- [x] Fresh main/tags inspected and first implementation branch created.
- [ ] New implementation regression evidence recorded for T01.
- [ ] Affected-device selected-app blocking/background verification. No device
  is connected at the starting baseline; this gate remains pending.

A checked planning/baseline item does not mark its feature implemented. T01 can
be automated-verified while T05/D2 device acceptance remains pending. Every
handoff names what passed, what remains and the next slice.
