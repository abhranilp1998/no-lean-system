# NO LEAN delivery action plan — 27 October 2026

This is the active implementation sequence for the feedback-driven D1–D8 work.
It combines the user's delivery brief, the 60-item backlog and the complete
26 October export review. It supersedes the older *suggested delivery sequence*
in ROADMAP.md; existing product, privacy and release rules still apply.

Status: priority queue reviewed; T01 selected for the first implementation slice.
Use [TODO.md](../TODO.md) for the current slice order and
[implementation review](IMPLEMENTATION_REVIEW_2026-10-27.md) for the first decision.
The features below
are acceptance targets, not claims that they have been implemented.

Companion documents:

- [Delivery SOPs](DELIVERY_SOPS.md): how to perform each kind of change.
- [Verification matrix](DELIVERY_VERIFICATION_MATRIX.md): required scenarios and evidence.
- [Starting baseline](DELIVERY_BASELINE_2026-10-27.md): what actually ran, versions and limits.
- [PR review SOP](PR_REVIEW_SOP.md) and [release/upgrade rules](RELEASING.md).

## Decisions carried forward

1. Remain useful offline and without an account. SOS, essential actions and
   truthful logging must remain reachable during protection and cooldown.
2. Stabilize record meaning and projections before reusing them in new history
   views, planning features or synchronization. D2 diagnosis can proceed beside D1.
3. Apply D5 preservation, save/retry, migration, accessibility and export checks
   to every slice. D5 is not a late cleanup phase.
4. Use Recovery History, Settings History and Location History as three views
   of shared records. A record shown twice counts once in metrics.
5. Preserve original IDs, Unicode, unknown quantities, uncertain timestamps and
   source provenance. Do not infer use, diagnoses or precise locations from prose.
6. Support mixed facts: actual use can carry linked feedback. Classifying the
   feedback must not discard the use. Purchase, intended use and completed use
   are different facts.
7. Keep the MSSQL definition provisional. A small support/backup pilot does not
   require implementing all 21 draft tables or introducing Google accounts.
8. No production-readiness claim follows from a build alone. Native protection,
   banking and background-location acceptance require affected-device evidence.

## Delivery order and dependencies

| Delivery | Priority | Dependency / sequence | Exit deliverable |
|---|---|---|---|
| D1 — Trustworthy logging and progress | P0 | First implementation; D5 checks from the first schema change | Correct entry/correction flows and progress, with migration and regression evidence |
| D2 — Protection and banking reliability | P0 | Begin diagnosis now; coordinate new location contracts with D1/D4 | Device-verified fixes and a protection-status screen |
| D3 — Three histories and complete multi-tagging | P1 | D1 effective-record, purpose, correction and identity contracts | Three usable screens, shared details/tags/filters and no duplicate metrics |
| D4 — Manual and automatic location experience | P1 | D2 location feed/health; D1/D3 provenance and history contracts | Understandable capture, coordinate editing and location history without mandatory GPS |
| D5 — Ownership, usability and release quality | P1 / cross-cutting | Begins with D1; full candidate gate after D3/D4 | Compatible, restorable upgrade candidate with documented checks |
| D6 — Recovery planning and everyday quality of life | P2 | Trusted D1 records and D2 behavior; depends on usable D3 history for reflections | Optional planning/reflection features with honest outcomes |
| D7 — Small optional backend | P2 | Stable D1/D3/D4 data contracts and D5 restore/ownership gates; independent of D6 completion | User-controlled support/encrypted-backup pilot and refined MSSQL contract |
| D8 — Accounts, sync and separate work | P3 / held | Account/sync work follows a successful D7 restore pilot; held work needs separate scope | Optional identity/sync only after merge/deletion/account boundaries are proven |

There are no promised dates or effort estimates. Estimate individual slices
after the baseline and native reproduction, rather than treating unknown device
failures as a fixed-size implementation.

## D1 — Trustworthy logging and progress

Scope: F01–F09, F59, F60. SOPs 01–07, 12, 15.

- **D1-A: record contract and compatibility.** Define urge, use, purchase
  attempt/completed purchase, journal, feedback and test/diagnostic purposes.
  Retain existing system types such as SOS, pledge, check-in and milestone.
  Decide the effective-record/revision projection before changing forms.
  Keep unreviewed legacy cravings visible as legacy/unreviewed; do not mass
  reclassify them from keywords. Separate user tags from purpose and provenance.
- **D1-B: quick capture and drafts.** Use short purpose-specific forms,
  optional notes, recent choices and add-details-later. Preserve drafts across
  navigation/restart; prevent duplicate submits and make save/retry honest.
  Entering a draft or future intention never commits a use event.
- **D1-C: time and corrections.** Show happened-at and recorded-at separately,
  including timezone/precision when known. Use normal correction forms with a
  preview, protected authorization where applicable, original evidence and
  links to superseded facts. Build the missing-history review queue (F59),
  match existing events and reuse existing batch entry. Leave unresolved
  periods and approximate quantities unknown.
- **D1-D: amounts and money.** Resolve conflicts between text and structured
  amounts through user review. Preserve historical per-entry bottle size.
  Separate acquisition/spending from consumption; link related records and
  count one expense once. Distinguish actual, estimated, zero and unknown cost.
- **D1-E: progress.** Reconcile streaks, awards, daily state and money after
  reviewed corrections/backfill. Awards need a baseline/rule association;
  preserve valid earlier achievements and keep invalidated awards auditable.
  Distinguish elapsed time, pledge, reported check-in and unknown days.
- **D1-F: follow-ups.** Schedule for appropriate urge records only. Record
  intended due time and actual response, intervention and use-since-urge
  context. An intensity reduction alone cannot establish avoiding use. Late
  backfill must update the interpretation without rewriting the user's rating.

Exit: all D1 acceptance scenarios pass; legacy migrations, failed-save behavior,
restore, metric recalculation and user-visible flows are evidenced. Tests passing
on the old implementation only establish a baseline, not D1 completion.

## D2 — Protection and banking reliability

Scope: F10–F15, F58. SOPs 08–10, 14, 15.

- **Primary reported incident:** the user selected two apps, received the
  danger-area notification, opened a selected app and paid at a shop without
  an interruption. The existing private history contains zone observations and
  payment-block failure/test notes supporting this report. Treat notification
  delivery and selected-app blocking as separate acceptance results.
- Trace zone observation → native policy acknowledgement/service readiness →
  foreground selected-app detection → active rule/no temporary grant → block
  request → visible interruption. A failure at any stage needs a visible reason,
  not a reassuring inference from the zone notification.
- Reproduce banking startup failure separately from intended blocking. Capture
  app/OS/build, active rule, selected package, permission/service state and
  observed launch result. Do not assume NO LEAN caused a bank's refusal.
- Verify temporary native grant acknowledgement, launch result, retry, budget,
  wait, timeout, expiry and re-entry. Never display unlocked/opened success
  based only on sending a platform request.
- Share one fresh foreground location source between status and alert logic.
  Handle resume/pause, stale/coarse/future/out-of-order fixes and late callbacks.
- Measure background entry/exit on affected phones: screen off, background,
  reboot and battery restrictions. Define the visible opt-in background/periodic
  refresh policy (F58); do not confuse a UI timer with a new GPS observation.
- Expose permission, service, location age/accuracy, foreground/background
  monitoring, notification readiness and active-rule health. Unknown location
  is not proof of being outside a zone. Preserve working notifications.
- Keep SOS, emergency calling, navigation/home and historical logging reachable
  throughout block/cooldown/unlock states. Investigate expected payment blocking
  without requiring real purchases or exposing banking credentials.

Exit: affected-device evidence demonstrates the corrected path and denied/
interrupted paths; protection-status UI agrees with observed service state.
When hardware or app details are absent, report partial verification explicitly.

## D3 — Three history screens and complete multi-tagging

Scope: F16–F25. SOPs 03, 11–15.

- Recovery History is the default recovery view. Settings History shows known
  old/new values and source; unknown old values remain unknown. Location History
  includes automatic observations, manual GPS, selected locations and linked logs.
- Provide consistent readable details, happened/recorded times, correction
  history, tags/source and cross-links to the same underlying record.
- Support multiple tags during entry and later editing across every log family,
  including imported, settings, automatic/manual location and feedback records.
- Provide custom tags, autocomplete, recent/favorite choices, rename, archive
  and merge with stable IDs and understandable historical effects.
- Multi-select add/remove must preserve other tags, preview the changes and
  support undo without overwriting later edits or bypassing authorization.
- Combine text/date/type/purpose/source/zone filters with Any selected tag and
  All selected tags. Empty selections mean no tag restriction. Export/import
  preserves definitions and associations, including archived references.

Exit: one geolocated recovery record is discoverable in both relevant screens,
opens the same details and contributes once to metrics; full tag lifecycle and
bulk-operation regression checks pass. Settings facts are never rewritten by tags.

## D4 — Manual and automatic location experience

Scope: F26–F31. SOPs 10–15.

- Keep Locate me / Refresh accessible on relevant routes, while already in a
  zone and while logging. Preserve the draft and explain denied/unavailable/stale
  states; do not require location to save a recovery record.
- Add coordinate entry/paste and movable zone pins with bounds validation,
  preview and existing authorization for weakening armed protection.
- Attach a location only by explicit choice. Label fresh GPS, selected zone,
  manual pin, automatic foreground/background and imported/unknown separately.
  Capture time, event occurrence time, fix age and accuracy are distinct.
- Current zoneEntry records deliberately reject coordinate keys. Introduce the
  new optional location relationship/observation contract with consent, versioning
  and export rules; do not silently loosen that privacy boundary.
- Coalesce repeated detections of one visit while retaining observation source;
  preserve intentional manual check-ins. Neither a visit nor app access proves
  a purchase or consumption.
- Provide list/map and source filters, retention, selective deletion and export.
  Erasing coordinates must not erase the associated recovery fact. Old name/time
  visits remain name/time-only, without a reconstructed GPS position.

Exit: GPS unavailable/declined still permits logging; observation provenance,
retention and deduplication remain correct through reload and restore.

## D5 — Ownership, usability and release quality

Scope: F32–F37; applied throughout D1–D8. SOPs 03–05, 11–15.

- Preserve transactional saves, retry idempotency, drafts and recoverable
  rejected-state copies. Extract a repository boundary where useful; changing
  to SQLite is an evaluated implementation choice, not an automatic prerequisite.
- Extend lossless JSON and readable CSV for new fields, correction links, tags
  and location provenance. Preserve CSV column compatibility and formula guards.
- Improve import preview, duplicate/conflict handling and backup history with
  verified save/restore status. Preserve IDs, Unicode, legacy text and unknowns.
- Keep PIN/contact, permissions and active device-protection/private settings
  out of portable history sync. Explain storage, export, deletion and restore.
- Use shared fields, cards, pickers, badges and design tokens. Check TalkBack,
  large text, keyboard access, contrast, reduced motion and widgets on changed flows.
- Add/enforce CI and release gates. Preserve compatible installed signing;
  production signing needs a supported transition for existing installations.
  Validate same-signer upgrades without uninstall, clearing data or downgrading.

Exit: documented compatible-upgrade and restore candidate. Separate source
checks, emulator evidence, affected-device acceptance and store readiness.

## D6 — Recovery planning and everyday quality of life

Scope: F38–F48. SOPs 06–07, 12–15.

- Optional travel/away dates and return-home check-ins; absent logs do not prove
  travel or clean days and never silently disable protection.
- Adjustable evening/weekend/return-home plans, skippable personal-plan setup,
  preferred interventions and lightweight sleep/wake/state observations.
- Extend cooldown choices, resumable SOS and appropriate follow-ups. Distinguish
  started/completed/cancelled/unknown, not an inferred treatment effect.
- Add weekly reflection/report cards, evidence-aware spending/context summaries
  and non-streak goals that survive unrelated later use.
- Prepare trusted-contact templates for the user to review and send. Never send
  automatically; private journaling does not authorize uploading/sharing.
- Refine tactical-calm appearance, empty/error states and independent motion/
  feedback preferences while preserving the recognizable visual identity.

Exit: opt-in plans can be skipped/changed; reflections agree with effective
records, show missingness and do not overstate what the data establishes.

## D7 — Small optional backend

Scope: F49–F51. SOPs 12–13, 15.

- Structured support intake with expected/actual behavior, explicit attachment
  choices and allowlisted diagnostics. A default report excludes recovery prose,
  precise locations, credentials and a full installed-app inventory.
- User-controlled encrypted snapshots with a recoverable key flow, verification,
  retention, retry and tested restore on another clean app instance. Server-side
  upload acknowledgement alone is not a restore result.
- Refine the existing MSSQL draft for stable identities, purposes, revisions,
  tags/associations, milestone baselines and location provenance. Model history
  screens as projections, not three duplicate event tables.
- Agree a versioned API/ownership and encryption boundary before deployment.
  Test owner isolation, malformed/replayed requests and interrupted upload/restore.

Exit: a limited support/backup pilot with access-control and restore evidence;
no requirement to finish all drafted tables or introduce account-wide sync first.

## D8 — Accounts, synchronization and separate work

Scope: F52–F57. SOPs 12–13, 15. P3 or explicitly held.

- **F52 — Google sign-in later:** preserve guest/offline use, stable internal
  identity and deliberate linking of local history. Sign-in is not a backup.
- **F53 — Multi-device sync later:** outbox, idempotent operations, revisions,
  conflicts, deletion tombstones, cursors/epochs and stale-device/old-backup tests.
- **F54 — Account lifecycle later:** logout, switching, device revocation,
  portability and account/cloud deletion without mixing histories or silently
  erasing local records. Device protection remains device-local.
- **F55 — Native extras later:** app icons, schedule editor and OEM battery
  guidance after core enforcement and banking compatibility are proven.
- **F56 — Web held:** retain its separate branch and validate browser storage,
  export/import and unsupported native behavior before any renewed release scope.
- **F57 — Taper/planning exploration held:** separate product/clinical scope;
  automated dosing or treatment planning is not in these implementation deliveries.

Exit: account/sync work has its own approved scope and data-ownership evidence.
Held items are neither merged nor represented as current Android capabilities.

## Reviewable implementation slices

| Order | Slice | Required evidence before advancing |
|---|---|---|
| B0 | Baseline, contract map and synthetic fixture specification | Exact SHA/SDK/schema; relevant existing tests; device availability; named gaps |
| P0 prelude | T01 / D2-N09 native acknowledgement, retry and visible update failure | Failing-before regression, healthy-status/failure warning and successful-retry evidence; D2 device gate stays pending |
| 1 | D1-A effective record / purpose / time / correction contract + D5 readers/writers | Legacy fixtures, failed-save rollback, future-version refusal and JSON/CSV round trip |
| 2 | D1-B/C/D capture, drafts, correction queue and amount/money handling | Widget/user-flow tests, duplicate retry, original preservation and transaction-linked spending |
| 3 | D1-E/F progress, awards and use-aware follow-ups | Independent expected projections, backfill/revision boundaries and valid-award preservation |
| 4 | D2 banking/unlock diagnosis and corrected native transitions | Reproduction trace, native grant/launch/expiry checks; essential-access matrix |
| 5 | D2 shared location, explicit refresh policy and health | Mock regressions plus affected-device foreground/background measurements |
| 6 | D3 three routes/shared details + complete tag lifecycle/bulk/filtering | Shared-identity metrics, Any/All semantics, undo and import/export evidence |
| 7 | D4 optional location capture/editing/map/history/privacy | Provenance, no-GPS logging, deduplication and selective retention tests |
| 8 | D5 integrated upgrade/restore/accessibility/CI candidate gate | Current schema restore and real same-signer upgrade without clearing data |
| 9 | D6 planning/reflection; D7 support/backup as separate slices | Independent scope-specific outcomes; D7 does not depend on completing D6 |
| 10 | D8 account/sync proposal or separately resumed held work | Explicit scope, ownership/conflict/deletion design and preceding gates |

D2 reproduction and D5 checks run while D1 is developed; this ordering does not
require waiting for D1 to finish before collecting native evidence. Each slice
must remain reviewable and include every reader/writer affected by its contract.
Do not distribute an intermediate APK with partially upgraded serialization.

The reviewed TODO queue inserts one bounded, no-schema D2 acknowledgement fix
before D1-A. The rest of D2 does not have to finish before D1 begins.

## SOP index

| SOP | Procedure | Applies to |
|---|---|---|
| 01 | Evidence intake and reproduction | Every delivery |
| 02 | Scope, branch and change control | Every delivery |
| 03 | Record contracts, migrations and projections | D1, D3–D8 |
| 04 | Capture, drafts, save and retry | D1, D3–D7 |
| 05 | Corrections and missing-history review | D1, D3, D5 |
| 06 | Progress, milestones and spending | D1, D3, D6 |
| 07 | Urge follow-ups and intervention outcomes | D1, D6 |
| 08 | Banking/protection incident diagnosis | D2 |
| 09 | Native temporary access and essential actions | D2 |
| 10 | Location source, freshness and device measurement | D2, D4 |
| 11 | Histories, tags, filtering and bulk operations | D3, D4, D5 |
| 12 | Export, restore, ownership and diagnostics | D1, D3–D8 |
| 13 | Optional backend, encryption and later identity/sync | D7, D8 |
| 14 | Usability, accessibility and essential-flow validation | D1–D6 |
| 15 | Regression, PR handoff, upgrade and release | Every delivery |

## Status and evidence rules

Use: Planned → Implementing → Automated verified → Device verified (where
required) → Accepted. Track a named dependency separately when evidence is
unavailable; do not mark a whole delivery complete because one slice passed.

Every handoff records: affected feature IDs, concrete before/after behavior,
changed files, tests actually run, migrations/restore impact, native/device
evidence, unresolved risks and next slice. Follow PR_REVIEW_SOP.md for any PR
and retain explicitly kept branches. No automatic publication, deployment,
messages to contacts, or private-history upload is part of preparing this plan.

## Complete feature-to-delivery crosswalk

All 60 proposed items are retained. Acceptance cases describe target behavior;
implementation evidence is pending unless a later slice explicitly records it.
Feature IDs are stable, including the later additions F58–F60.

| ID | Delivery | Item | Acceptance cases |
|---|---|---|---|
| F01 | D1 | Distinct log purposes | C01 |
| F02 | D1 | Quick capture | C02 |
| F03 | D1 | Friendly correction workflow | C03, C10 |
| F04 | D1 | Occurrence versus recording time | C03, C09 |
| F05 | D1 | Milestone and streak reconciliation | C07, C10 |
| F06 | D1 | Honest daily progress | C06 |
| F07 | D1 | Quantity confirmation | C04 |
| F08 | D1 | Purchase and money semantics | C05, C10 |
| F09 | D1 | Relevant urge follow-ups | C08 |
| F10 | D2 | Banking-app compatibility | N01, N02 |
| F11 | D2 | Reliable temporary app access | N03 |
| F12 | D2 | One fresh foreground location source | N04, N08 |
| F13 | D2 | Background zone reliability | N05 |
| F14 | D2 | Visible protection health | N02, N06, N08, N09 |
| F15 | D2 | Always-reachable essential actions | N07 |
| F16 | D3 | Recovery History screen | H01 |
| F17 | D3 | Settings History screen | H02 |
| F18 | D3 | Location History screen | H01 |
| F19 | D3 | Shared readable log details | H01 |
| F20 | D3 | Multi-tag every log family | H03, H07 |
| F21 | D3 | Fast reusable tag entry | H03 |
| F22 | D3 | Bulk add/remove tags | H05 |
| F23 | D3 | Tag management | H04, H07 |
| F24 | D3 | Search and combined filters | H06 |
| F25 | D3 | No duplicate histories or metrics | H01, H07 |
| F26 | D4 | Accessible Locate me / refresh | L01 |
| F27 | D4 | Coordinate and zone editing | L02 |
| F28 | D4 | Optional location on a log | L03 |
| F29 | D4 | Observation versus visit deduplication | L04 |
| F30 | D4 | Location list and map views | L05 |
| F31 | D4 | Location controls | L06 |
| F32 | D5 | Durable saves and drafts | C02, Q01 |
| F33 | D5 | Backup history and export diagnostics | H07, Q02 |
| F34 | D5 | Import preview and conflict handling | Q03 |
| F35 | D5 | Accessibility and shared components | Q04 |
| F36 | D5 | Plain-language data controls | Q05 |
| F37 | D5 | Safe release and upgrade evidence | Q06 |
| F38 | D6 | Away/travel context | P01 |
| F39 | D6 | Return-home, evening and weekend plan | P02 |
| F40 | D6 | Sleep/wake and personal-state context | P03 |
| F41 | D6 | Skippable personal-plan setup | P02 |
| F42 | D6 | Cooldown choices | P04 |
| F43 | D6 | Resumable SOS and honest outcomes | P05 |
| F44 | D6 | Preferred interventions and useful follow-ups | P06 |
| F45 | D6 | Weekly reflection/report card | P07 |
| F46 | D6 | Non-streak goals | P07 |
| F47 | D6 | Trusted-person message templates | P08 |
| F48 | D6 | Tactical-calm refinement | P09 |
| F49 | D7 | Structured support intake | B01 |
| F50 | D7 | Verified encrypted backup | B02 |
| F51 | D7 | Finalize the backend contract after core fixes | B03 |
| F52 | D8 | Optional Google sign-in | A01 |
| F53 | D8 | Multi-device history synchronization | A02 |
| F54 | D8 | Account lifecycle and portability | A03 |
| F55 | D8 | Native app-lock extras | A04 |
| F56 | D8 | Web continuation | A05 |
| F57 | D8 | Taper/planning mode | A06 |
| F58 | D2 | Explicit location refresh policy | N05, N06, N08 |
| F59 | D1 | Missing-history review queue | C03, C09 |
| F60 | D1 | Recheck outcome with use context | C08, C10 |
