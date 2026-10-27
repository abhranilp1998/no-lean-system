# NO LEAN delivery verification matrix

Use with the [action plan](DELIVERY_ACTION_PLAN_2026-10-27.md) and
[SOPs](DELIVERY_SOPS.md). These are required acceptance scenarios, not existing
passing tests. The [baseline](DELIVERY_BASELINE_2026-10-27.md) records the
existing tests actually run. Each implementation links its scenario IDs to real
test names, source SHA and any device evidence.

Use synthetic data that reproduces the logical problem. Personal source exports,
raw notes, account details and exact locations must not become public fixtures.
Existing green tests do not establish that the new contracts below are satisfied.

## Evidence levels

- **Domain:** independently expected facts, amounts, relationships and projections.
- **Flow:** widget/integration rendering and interaction, plus storage reload.
- **Native:** actual platform acknowledgement/service/intent behavior.
- **Device:** affected phone/OS/app, observed result, timestamps and limitations.
- **Upgrade:** identified previous/candidate APK and signer; preserved synthetic
  history before/after same-signer installation without clearing data.
- **Human:** observed completion and comprehension, recorded separately from tests.

## D1 — Logging and progress

| Case | Features | Required scenario / expected result | Evidence |
|---|---|---|---|
| C01 | F01 | Urge/use/purchase/journal/feedback/test produce the correct facts; purchase attempt and intended future use never become completed consumption. Mixed use + feedback preserves both. Legacy/unreviewed records remain visible without keyword reclassification. | Domain + Flow + migration |
| C02 | F02, F32 | Short entry with optional notes; cancel, navigate, restart and resume draft. Draft changes no metric/recheck. Save failure retains draft; retry creates one event. | Flow + fault injection |
| C03 | F03, F04, F59 | Friendly type/time correction previews matching records and consequences, authenticates where required and preserves original IDs/evidence. Cancel changes nothing; retry is idempotent. | Domain + Flow + reload |
| C04 | F07 | Text says one 100 ml bottle, structured amount says two. Conflict remains unresolved until review. Unknown bottle size stays text; exact known units retain precision. | Domain + Flow + round trip |
| C05 | F08 | Purchase plus linked consumption counts one expense. Buying does not reset a consumption streak. Actual/estimated/zero/unknown costs remain distinct; costed use without purchase follows the defined rule. | Independent money projection + reload |
| C06 | F06 | Pledge, confirmed clean check-in, elapsed time and an unlogged day remain distinct. Date-only legacy summaries do not acquire invented doses or times. | Domain + calendar/widget Flow |
| C07 | F05 | A valid three-day award survives later corrected use. A later conflicting seven-day award is reconciled with an audit trail. Another streak can earn its own valid award; repeat sync/import does not duplicate awards. | Independent baseline math + reload/import |
| C08 | F09, F60 | Feedback/test/journal does not schedule urge follow-up. Zero intensity with reported intervening use is not labeled no-use resolution. Unknown remains unknown; prior response rating survives late backfill. | Domain + notification/Flow |
| C09 | F04, F59 | Forgotten history with an approximate time/range stays pending until user confirmation. Show happened/recorded time separately. Do not duplicate a matching entry or invent daily use from a broad note. | Domain + Flow + timezone boundaries |
| C10 | F03, F05, F08, F60 | Correct/import/delete/reclassify an effective fact; all affected metrics, expense attribution and follow-up interpretations reconcile once, including equal timestamps and out-of-order recording. | Domain + transaction/reload |

## D2 — Protection and banking

| Case | Features | Required scenario / expected result | Evidence |
|---|---|---|---|
| N01 | F10 | Bank selected/unselected; protection off/on; rule inactive/active. Distinguish intended block, NO LEAN launch failure, bank security refusal and crash/blank state. | Device + sanitized native trace |
| N02 | F10, F14 | Primary report: two selected apps, danger-area notification, selected-app use/shop payment without interruption. Reproduce selected-app launch under a confirmed active rule without completing a real purchase. Trace zone observation, native config/service/fix/grant state and actual block presentation separately. | Device + time sequence |
| N03 | F11 | Native grant denied/timed out; missing package; grant succeeds but launch fails; duplicate taps; process recreation; expiry/re-entry and budget/PIN paths. No false opened/unlocked result. | Native + affected Device |
| N04 | F12 | Shared feed on open/resume, stationary first fix, pause during request, stale/coarse/future/out-of-order fixes and delayed callback after stop. Status and alert use the same accepted observation. | Domain + Flow + Device |
| N05 | F13, F58 | Screen off/background/reboot/battery restrictions with opt-in enabled/disabled. Measure detection/delivery with available timing references; no arbitrary interval guarantee. Preserve working notification behavior. | Affected Device measurements |
| N06 | F14, F58 | Permission denied/permanently denied, services off, stale/no fix, notification denied, foreground service interrupted and inactive rule. UI shows actual health; unknown is not outside-zone reassurance. | Flow + Device |
| N07 | F15 | SOS, emergency calling, navigation/home and historical logging from active block, cooldown, denied unlock and expired grant. Protected changes still require authorization. | Flow + Native + Device |
| N08 | F12, F14, F58 | Zone notification/foreground zone state says inside while the native enforcement location is absent, stale or different. Show honest enforcement readiness; exercise the shared-source/state handoff without inferring readiness from notification delivery. | Domain/bridge + affected Device |
| N09 | F14 | Native apply/disable fails or throws; saved intent differs from native acceptance, including cold start and late acknowledgements. Keep essential requests/retry reachable, preserve SOS above a removed stale prompt, and never issue an unlock from a screen disposed during saving. Show failure and permission/service warnings together without consuming the narrow/large-text shell. | [Host regressions](../test/features/app_lock/app_lock_host_test.dart), [banner layout](../test/features/app_lock/app_lock_banner_layout_test.dart), settings Flow; native durability/Device pending |

## D3 — Histories and multi-tagging

| Case | Features | Required scenario / expected result | Evidence |
|---|---|---|---|
| H01 | F16, F18, F19, F25 | Same geolocated recovery record appears in relevant Recovery/Location views, opens the same details/correction trail and counts once. Cross-links switch tabs in place; repeated links do not grow the Back stack and one Back returns to the entry page. Settings/default-history separation remains clear; manual source aliases use consistent saved-location copy without changing provenance. | Domain + navigation Flow |
| H02 | F17 | Known before/after/source shown; unknown prior values stay unknown. No-op/failed setting write is not a committed change. User annotations cannot rewrite setting facts or expose secrets. | Controller + Flow |
| H03 | F20, F21 | Multi-tag entry and later editing on every log family: custom/autocomplete/recent/favorite, imported, system, location, feedback and settings. Existing tags survive. | Family matrix + Flow + reload |
| H04 | F23 | Rename/archive/merge, case/name collision and imported references. Stable identity and historical associations survive; operations preview consequences. | Domain + Flow + restore |
| H05 | F22 | Bulk add is additive; removal preserves other tags. Preview/authorization/failure/undo work, including another edit after the bulk change. Undo does not overwrite that later edit. | Transaction + Flow + revision conflict |
| H06 | F24 | Any/All selected tags, no selection, archived tags and combined text/date/type/purpose/source/zone filters. Clear/reset and no-match states are correct. | Query/domain + Flow |
| H07 | F20, F23, F25, F33 | Lossless JSON round-trip preserves tags/associations; readable CSV represents them. Duplicate JSON import/reload, tag edits and cross-screen viewing do not change recovery/spending totals. | Round trip + projection assertions |

## D4 — Location capture and history

| Case | Features | Required scenario / expected result | Evidence |
|---|---|---|---|
| L01 | F26 | Refresh while inside a zone or writing a draft; success/denied/unavailable/stale states. Draft remains intact; saving without location works. | Flow + Device |
| L02 | F27 | Enter/paste valid/invalid lat/long, move zone pin, change radius/name, cancel and confirm. Changes weakening armed protection retain authorization. | Domain + map Flow + Device |
| L03 | F28 | Fresh GPS vs selected zone/manual pin; capture/occurrence times and accuracy when known. New precise-location capability is explicit; legacy zoneEntry remains name/time-only. | Migration + Flow + export |
| L04 | F29 | Repeated foreground/background detections of one visit coalesce correctly; a deliberate manual check remains distinct. Neither observation becomes purchase/use. | Domain + device event sequence |
| L05 | F30 | Location list/map sources/dates, cross-links, missing coordinates, offline/no tiles and unavailable services. No invented position for older visits. | Flow + offline Device |
| L06 | F31 | Location opt-out, retention/deletion and scoped export; removing position leaves the linked recovery fact. Explain retained backup copies honestly. | Storage + Flow + restore |

## D5 — Ownership and release

| Case | Features | Required scenario / expected result | Evidence |
|---|---|---|---|
| Q01 | F32 | Concurrent operations, interrupted/failed writes, retry, rejected current state and draft recovery. No partial commit, false success or empty reset. | Fault injection + restart |
| Q02 | F33 | Backup history/status and export diagnostics; cancel/error/verified save differ. Failed new export documents receive best-effort cleanup; cleanup refusal/error cannot mask save failure and verified exports are never deleted. Imported risk-window changes audit only on a committed authorized restore; legacy text/unknown quantities survive reload/re-export. New tags/purpose/revisions/location survive JSON as their contracts ship; CSV guards, columns, offsets and Unicode remain correct. | Dart/native export + fresh restore |
| Q03 | F34 | Every supported old version, future-version refusal, corrupt/UTF-8/BOM-UTF-16/Unicode inputs, duplicates and divergent revisions. Preview conflict and preserve original; no silent device-policy change. | Compatibility + Flow |
| Q04 | F35 | TalkBack, large text, contrast, reduced motion, keyboard, targets, notification denial, widget and shared-component consistency on changed flows. | Automated + rendered/Device/Human |
| Q05 | F36 | Clear local/cloud/export/deletion controls; PIN/contact/device-policy fields excluded; delete/restore has explicit scope. No automatic contact message or private-history upload. | Data boundary tests + Flow |
| Q06 | F37 | CI, version/schema checks, signing compatibility and exact artifact identity. Upgrade previous→candidate without uninstall/data clear/downgrade; compare records/widgets/security and recover rejected state. | CI + APK hashes/signer + Upgrade |

## D6 — Planning and everyday use

| Case | Features | Required scenario / expected result | Evidence |
|---|---|---|---|
| P01 | F38 | Optional away dates and return check-in; missing logs never infer travel/clean days or disable protection. | Domain + Flow |
| P02 | F39, F41 | Skip/edit personal plan, adjustable evening/weekend/return prompts and user-chosen trigger actions. No hardcoded personal risk schedule for everybody. | Flow + notification checks + Human |
| P03 | F40 | Optional sleep/wake/state observation without required diagnosis, inferred medical meaning or dose recommendation. | Flow + export |
| P04 | F42 | Cooldown choice/length preserves authorization and essential routes. | Domain + Flow + Device |
| P05 | F43 | SOS resume/interruption/start/complete/cancel/unknown; missing later use is not proof of effectiveness. | Session/controller + Flow |
| P06 | F44 | Preferred intervention and relevant follow-up; purpose filtering and reported intervention/outcome remain linked. | Flow + Domain |
| P07 | F45, F46 | Weekly reflection/non-streak goals agree with effective facts, show missingness and actual/estimated/unknown spending; later use preserves unrelated valid progress. | Independent report projection + Flow |
| P08 | F47 | Contact template is previewed and user-sent; cancellation/offline/error never sends automatically or exposes private data. | Flow + Native intent |
| P09 | F48 | Tactical-calm/empty/error/motion/haptic/sound choices remain usable, recognizable and accessible. | Rendered + Device/Human |

## D7 — Backend pilot

| Case | Features | Required scenario / expected result | Evidence |
|---|---|---|---|
| B01 | F49 | Support expected/actual, diagnostics preview/allowlist, explicit attachments, offline retry and owner isolation. Private recovery/locations are absent by default. | API/access tests + Flow |
| B02 | F50 | User-controlled encrypted snapshot, recoverable-key path, verification/retention, wrong/lost key, interrupted upload and clean-instance restore. Upload acknowledgement is not restore verification. | Security boundary + restore demonstration |
| B03 | F51 | MSSQL/API definitions agree with effective local purpose/revision/tag/milestone/location contracts; only pilot-required tables deployed; migrations and ownership verified. | Contract/schema review + pilot tests |

## D8 — Later / held

| Case | Features | Required scenario / expected result | Evidence |
|---|---|---|---|
| A01 | F52 | Optional Google linking preserves offline/guest history; retry/account change cannot replace or mix it. | Auth/link integration + restore |
| A02 | F53 | Offline outbox, idempotency, revision conflict, tombstone, stale device, cursor reset and old-backup import do not resurrect deleted facts or duplicate spending. | Multi-instance synchronization tests |
| A03 | F54 | Logout/switch/revoke/export/delete/new-device restore respects ownership and explicit local/cloud choices. | Integration + data-control Flow |
| A04 | F55 | Native extras do not regress proven protection, banking or essential access. | Native + affected Device |
| A05 | F56 | If web is separately resumed, validate browser storage/import/download and clear unsupported-native behavior. Do not merge held work by default. | Separate browser/release evidence |
| A06 | F57 | Held taper/planning exploration stays out of current Android delivery; any future work has separately defined clinical/product scope. | Scope review; no current implementation acceptance |

## Recording results

For each slice, record: case IDs, feature IDs, exact source SHA, fixture/input,
command/test or walkthrough, expected/actual, pass/fail/not-run, device/app/OS,
artifact identity when relevant and evidence path. Give an unavailable check a
named reason. Do not replace an unrun device case with an automated pass.

The baseline currently provides regression evidence for existing behavior only.
Each new acceptance case must be linked to its own evidence before its delivery
is accepted. Preserve test results and sanitized captures with the reviewed SHA;
keep personal originals in private local storage rather than the repository.
