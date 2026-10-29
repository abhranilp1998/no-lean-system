# NO LEAN delivery SOPs

Active scope: [D1–D8 action plan](DELIVERY_ACTION_PLAN_2026-10-27.md).
Acceptance evidence: [verification matrix](DELIVERY_VERIFICATION_MATRIX.md).
These procedures extend PR_REVIEW_SOP.md and RELEASING.md; they do not replace
the existing data-preserving release contract.

## SOP 01 — Evidence intake and reproduction

1. Record the user's expected/actual behavior, app/build, OS/device, event/time
   and relevant permissions/rule. Separate written reports from code-confirmed
   behavior, reproduced failures and proposed solutions.
2. Read every relevant narrative and metadata field. Keep an event-ID/record
   crosswalk outside public source control when it contains private history.
   A test, future intention, purchase and completed use are distinct evidence.
3. Reproduce with synthetic fixtures or a disposable app instance first. Do not
   edit the original CSV, installed history or an imported personal backup to
   make a test pass. Ask only for genuinely missing native reproduction details.

Done when the issue has a concrete trigger/result, source authority, reproduction
status and an acceptance scenario. A suspected mechanism remains a hypothesis.

## SOP 02 — Scope, branch and change control

1. Read repository guidance; record status, SHA, branches/worktrees and baseline
   versions. Preserve unrelated changes and the retained Android/web branches.
2. Define a reviewable slice by feature IDs, readers/writers, dependencies and
   rollback/recovery effect. For implementation, use an appropriate branch with
   the `9112-deviant/` prefix; reuse a suitable active checkout where possible.
3. Keep raw personal exports, precise locations, secrets and full native incident
   logs out of commits. Make commit/PR descriptions explain what changed, why,
   validation, affected screen/platform and remaining work.
4. Apply the existing PR SOP when creating/reviewing a PR, including refreshing
   its actual base at that time. Local planning refs alone are not fresh remote
   evidence. Never merge unrelated held work to satisfy a checklist.

Done when scope, current base, retained work and evidence ownership are explicit.

## SOP 03 — Record contracts, migrations and projections

1. Specify stable record identity, event type/purpose, relationships, happened-at,
   recorded-at, timezone/precision, origin and revision/correction semantics.
   Keep user annotation tags separate from source/type and audit facts.
2. Represent mixed use plus feedback without discarding the use. Preserve legacy
   event IDs and original text. Legacy/unreviewed purpose is an honest state;
   keyword matching must not silently reclassify historical facts.
3. Original type/time is immutable in the current event model. Define an explicit
   correction/revision relationship and effective-record projection before
   allowing type/time correction. Superseded facts remain auditable but do not
   contribute twice. Projections must be deterministic and reload-safe.
4. Treat app/build, state and backup versions separately. Add explicit migrations
   when the respective persisted contracts change; do not reserve a new version
   merely in this plan. Introduce new event/backup capabilities together.
5. Update persistence, validators, imports/exports, derived state, widgets,
   notification actions and all history readers in the same compatible slice.
   Unknown/future/corrupt state stays preserved and is never an empty writable app.

Done when old→new→reload→export→restore preserves originals and reconstructs the
same effective facts, with failure/unsupported-version fixtures.

## SOP 04 — Capture, drafts, save and retry

1. Offer purpose-specific minimum fields and optional prose. Do not copy a recent
   amount into a new consumption fact without confirmation. Permit saving when
   location is denied/unavailable and keep historical logging reachable.
2. Give the draft its own stable identity/state. Recover it after interruption;
   cancel/discard explicitly. A draft must not affect progress, costs or rechecks.
   Minimize retained sensitive draft content and clear it after successful commit.
3. Validate happened-at, future intentions, amount/unit and cost consistently.
   Serialize writes, guard duplicate taps and reuse the operation ID on retry.
4. Commit transactionally before success feedback, notification scheduling or
   widget updates. On failure, retain the draft and prior committed state;
   retry cannot create a second use, purchase, expense or batch.

Done when cancel, restart, duplicate submit and injected failure produce the
expected committed state, draft and visible save result.

## SOP 05 — Corrections and missing-history review

1. Open a normal form from record details or a user-invoked review queue. Show
   original/effective meaning, date, amount and related records.
2. Identify possible existing matches; preview changed counts, amounts, spending,
   streak/award effects and links before committing. Authenticate protected
   history actions at the controller boundary, not only in the UI.
3. Let the user confirm an approximate time/range or keep it unresolved. Do not
   manufacture daily use, infer quantities, convert intentions, or automatically
   add use because prose mentions it. Reuse the existing batch-entry foundation.
4. Apply the linked correction atomically, retain the original, then reconcile
   effective metrics and relevant recheck interpretations. Retry is idempotent.

Done when the review can be cancelled safely, a confirmed correction has a trace,
and exactly one effective fact/expense remains after reload and retry.

## SOP 06 — Progress, milestones and spending

1. Define which effective facts drive the consumption baseline. Purchase,
   intention, journal, feedback, tests and tag edits do not reset that baseline.
   Preserve the existing historical baseline unless a reviewed correction changes it.
2. Show elapsed time, reported clean check-in, pledge and unknown days separately.
   No logged use is not proof of a clean day. Date-only legacy facts must not
   acquire invented occurrence counts/times.
3. Associate awards with baseline and rule version. On correction/backfill,
   preserve valid earlier achievements, mark affected awards for reconciliation
   and prevent an old award suppressing a valid award in a later streak.
4. Link purchase expense and related use so spending counts once. Support
   costed use without a recorded purchase through a defined attribution rule;
   unknown cost is not zero and estimates stay distinct from actual spending.
5. Resolve text/structured quantity conflict by review. Unknown historical bottle
   size remains unknown; a current preference cannot manufacture historical ml.

Done when independently calculated scenarios agree with counters, daily history,
milestones, widgets and spending after correction, import and reload.

## SOP 07 — Urge follow-ups and intervention outcomes

1. Schedule only for appropriate confirmed urge records, honoring opt-in and
   permission state. Feedback/test/journal records must not create urge rechecks.
2. Record due time, notification delivery when observable, actual response time,
   intervention tried and the reported intensity. A late response alone is not
   proof the scheduler failed. Handle deletion/reclassification of the target.
3. Ask about use since the urge. Distinguish reported no-use resolution, use
   reported and unknown; a zero intensity is not sufficient evidence of a win.
4. Reconcile interpretation when earlier-occurring use is recorded later.
   Preserve the original intensity response and represent unresolved timing
   honestly. Do not infer effectiveness solely from missing subsequent use.

Done when purpose filtering, unknown outcomes, delayed responses and late
backfill all produce accurate copy, links and projections.

## SOP 08 — Banking/protection incident diagnosis

For the current primary incident, start from the user's report of a danger-area
notification followed by uninterrupted use of two selected apps and a completed
shop payment. That is a missed selected-app interruption. Keep the earlier bank
startup report separate; do not require a bank-crash explanation to investigate
the documented missed-block path.

1. Distinguish intended NO LEAN block, bank security refusal, blank/crash screen
   and launch failure. Record whether the bank is selected, the active rule,
   lock enablement, permission/service state and foreground application.
2. Compare protection off/on, selected/unselected, active/inactive window,
   inside/outside/unknown zone and fresh/stale location. Use the affected OS/app
   version. Do not weaken all protection to hide a single compatibility failure.
   Trace notification/zone observation, native config acknowledgement, service
   readiness, native zone state, selected foreground app, temporary grant, block
   request and actual screen presentation individually. A zone notification is
   not evidence that the native app-lock service was ready or presented a block.
3. Capture a minimal sanitized native trace and timing sequence with consent.
   Keep credentials, balances, recovery notes and other apps' private content out.
   App launch/block checks do not require completing a real payment.
4. Reproduce and verify the supported remedy; explain the compatibility path
   where necessary. Keep unproven causes and missing hardware evidence visible.

Done when the incident's actual failure class and corrected/unsupported path are
demonstrated on the affected device. A mock or build is supporting evidence only.

## SOP 09 — Native temporary access and essential actions

1. Model requested → native-granted → launch-attempt/result → active grant →
   expiry/revocation explicitly. Acknowledgement, grant and app opening differ.
2. Use native-confirmed grant/expiry state. Verify timeout, denied grant, missing
   package, launch failure, duplicate action, process restart and clock behavior.
   Report budget/grant consumption honestly if launch fails after a grant.
3. Verify payment/other waits, budget/PIN paths and re-entry after expiry. Do not
   claim that an app opened because an intent was dispatched.
4. Exercise SOS, call, home/navigation and historical logging from every relevant
   protection state. Preserve controller authorization for actions that weaken
   protection while keeping essential access available.

Done when Dart and native state agree on the affected device, including failure,
expiry and recovery; essential-action routes remain reachable.

## SOP 10 — Location source, freshness and device measurement

1. Share one foreground observation source for status and alerts. Start/refresh
   appropriately on activation, stop lifecycle-specific work on pause, and reject
   stale, inaccurate, future, out-of-order and stopped-generation results.
2. Define an opt-in monitoring/refresh policy and show last request/success,
   capture time, age, accuracy and unavailable states. A refresh timer does not
   prove a new fix. Unknown location cannot be reassuringly labeled outside.
3. Separate foreground observations from OS background geofencing. Measure
   request/fix, physical boundary reference when available, detection and delivery
   times on affected devices under screen-off/reboot/battery conditions. State
   missing timestamps rather than inventing latency or promising instant updates.
4. Support manual coordinate/pin entry with bounds validation and protected zone
   edits. Selected pins are not physical-presence evidence; capture and occurrence
   times differ. Saving a log remains possible without any location.
5. Version the optional precise-location relationship explicitly: existing
   zoneEntry metadata rejects coordinates. Preserve older name/time observations.
   Deduplicate visit detections without erasing provenance or intentional check-ins.

Done when UI/status, alerts and exported observation provenance agree, opt-out
works, drafts survive refresh, and native measurement is recorded separately.

## SOP 11 — Histories, tags, filters and bulk operations

1. Project shared effective records into Recovery, Settings and Location routes.
   Cross-links open one detail identity; settings old/new/source and correction
   evidence remain readable without exposing secrets or inventing missing values.
2. Support stable tag identities and associations for every log family. Define
   name normalization, custom/autocomplete/recent/favorite behavior and imported
   name collisions. Tags annotate facts; they do not change purpose/provenance.
3. Preview rename/archive/merge. Preserve historical associations and explain
   whether an archived tag remains visible/selectable. Export stable references.
4. Bulk add is set union; remove affects only chosen tags. Preview selected
   records and changes, authorize the operation and commit atomically or expose
   explicit partial failure. Undo must not overwrite unrelated later edits;
   use revision checks/conflict handling rather than restoring an old whole record.
5. Combine text/date/type/purpose/source/zone restrictions. Any matches at least
   one selected tag; All matches every selected tag. No tags means no restriction.
   Include clear/reset, archived-tag search and honest empty/error states.

Done when tags survive rename/merge/bulk undo/restore and neither screen choice,
tag editing nor cross-linking changes consumption or spending totals.

## SOP 12 — Export, restore, ownership and diagnostics

1. Define portable versus device-private fields. Exclude PINs, trusted-contact data,
   permission grants, active app-lock policy and device privacy/protection flags
   from history synchronization. Review new location fields by explicit scope.
2. Extend lossless JSON and append-compatible CSV, retaining quoting, Unicode,
   original IDs/time precision and formula guards. Readable CSV is not a restore
   backup. Validate bytes and display cancellation/failure/success honestly.
3. Preview imports, versions, conflicts and duplicates. Preserve rejected copies,
   authenticate protected actions, and test repeated import plus interrupted save.
   Restoring history must not silently arm/disarm device protection or enable GPS.
4. Test export→fresh instance→restore→reload, including tags, revisions, locations,
   unknown amounts, unsupported versions and interrupted operations. A saved file
   or completed upload is not proof of restoration.
5. Give retention/deletion controls explicit scope. Removing precise location
   must retain associated recovery facts. Explain preserved local/cloud copies
   and backup retention; do not imply selective erasure from an old encrypted
   snapshot without actually replacing/removing it.
6. Diagnostics are allowlisted, previewable and user-controlled. Reports omit
   sensitive prose/coordinates/credentials and broad app inventories by default.

Done when compatible restore and rejection paths are evidenced, privacy choices
survive, and success/failure wording matches the observed result.

## SOP 13 — Optional backend, encryption and later identity/sync

1. Start with support intake and encrypted snapshots. Keep guest/offline core
   flows independent of network availability and backend outages.
2. Freeze a versioned API/ownership contract only after local record, correction,
   tagging and location contracts pass their gates. Refine the MSSQL draft;
   histories remain projections of shared data. Deploy only the pilot's tables.
3. Design recoverable encryption keys, owner isolation, attachment limits,
   verification and retention before cloud storage. Never log keys or silently
   upload private history. Exercise interrupted/replayed/malformed requests.
4. Prove restore to a clean instance with the supported key-recovery path. Test
   wrong/lost keys and expired/deleted backups; explain the actual recovery limit.
5. Later Google identity must deliberately link local history. Account switching
   and logout cannot mix owners. Before sync, test outbox idempotency, revisions,
   conflicts, tombstones and stale-device/old-backup deletion reconciliation.

Done when pilot access isolation and recovery evidence exist. Full sync/account
completion is a separate deliverable and never implied by successful sign-in.

## SOP 14 — Usability, accessibility and essential-flow validation

1. Use existing shared layout, fields, dialogs, notices and feedback components.
   Keep the cyberpunk identity with tactical-calm reading/SOS states, reduced
   motion, readable contrast and independent sound/haptic choices.
2. Exercise empty/loading/error/offline/permission-denied states, keyboard-open
   saving, large text, TalkBack labels/order, targets, widget and cold/warm entry.
3. Walk through quick log, later correction, multi-tag search, backup restore and
   denied-location logging without developer guidance. Record observed confusion;
   passing widget tests alone does not establish that the flow is understandable.
4. Keep essential actions reachable and explain sensitive/destructive operations
   with useful previews. Planning features remain optional and skippable.

Done when affected screens have rendered and interaction evidence, accessibility
results and named remaining user/device checks.

## SOP 15 — Regression, PR handoff, upgrade and release

1. Start from the baseline record and verification matrix. Run focused domain,
   widget, compatibility and native checks for each slice. Add regressions that
   demonstrate the reported failure; do not count existing green tests as new fixes.
2. After behavior changes, follow repository verification commands in memory.md
   and PR_REVIEW_SOP.md: formatting, analysis, full Flutter tests, appropriate
   Android build(s), diff checks and release-version validation. Run tests and
   Android builds sequentially. CI must enforce applicable gates.
3. Allocate app/build and schema/backup versions through the release rules after
   inventorying actual distributed builds. Preserve package/storage identity and
   compatible signing. A new production key must not strand existing installs.
4. Validate same-signer `adb install -r` over synthetic legacy/current history,
   without uninstall/data clear/downgrade. Compare IDs, relationships, quantities,
   tags, corrections, settings, secure fields and widget/counter behavior.
5. Keep exact source SHA, commands/results, APK hash/version/signer and device
   evidence together. Rollback is a forward-compatible corrective release with
   a higher build, not an old binary that cannot read current state.
6. Finish with the change's purpose, before/after behavior, relevant test results,
   migration/restore evidence, platform limits and next action. Keep Planned,
   Automated verified and Device verified distinct. Use the existing PR SOP for
   final review and branch disposition; retained branches remain retained.

Done when the slice is reviewable and required gates actually pass. Native
verification, store declarations/signing and external deployment remain explicit
gates rather than assumptions based on a successful build.
