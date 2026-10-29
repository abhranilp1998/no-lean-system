> **Superseded:** see [NO_LEAN_HANDBOOK.md](NO_LEAN_HANDBOOK.md) for the current, combined handbook. This file is kept for history.

# Android functional notes — 10 October 2026

This records the user's export/GPS reports, the corrections in this handoff and
the remaining work. The PDF is review material; the user's later instructions
authorize the Android merge and put web work on hold.

## Corrections in this handoff

| Flow | Behavior | Acceptance evidence |
|---|---|---|
| Risk-window times | With the evening wall or risk-window app schedule armed, removing any protected minute needs the existing PIN/biometrics. Moving 17:00–21:00 to 02:00–03:00 or shrinking to 17:00–20:00 requires authentication. Extending to 16:00–22:00 stays free. Committed edits log old/new labels. | Daytime, overnight, full-day, denial, lockout, no-op, reload and failed-write rollback tests. |
| Android JSON/CSV Save | Pick a destination. Success follows write, flush, close and exact byte readback, including Unicode. Cancellation stays silent. Failure suggests Downloads or another location and preserves local recovery data. | Native stream tests, Dart channel/notice tests and device results in the review record. No broad storage permission. |
| Shared JSON | Share the attachment without competing caption text. Retain the source after the sheet returns; rapid exports get distinct names. Clean source copies older than one hour on a later share. | Delayed file read and import validation with a mocked share. This does not prove an OEM receiver saved the file. |
| Import errors and text | Distinguish empty files, old share-caption-only files, damaged JSON and damaged encoding. Remove padding only outside JSON; preserve Unicode inside notes/preferences. Require valid UTF-8 or BOM-marked UTF-16 instead of guessing Latin-1 after a UTF-8 failure. CSV is a readable copy; JSON is the restore format. | Empty/BOM/NUL, caption-only, malformed UTF-8/UTF-16, embedded U+FEFF, Bengali/emoji round trips and compatibility fixtures. |
| Legacy quantities | Old bottle-only notes retain their original text when no per-entry bottle size was recorded. Today's/default bottle size cannot create a historical ml value. Explicit ml/L quantities and existing structured doses retain their values. | All event-backup versions 1–6, a legacy-state migration/reload, re-export and the user's private legacy fixture. |
| Foreground GPS | On open/resume with monitoring, zones and permission, subscribe to movement and request a current fix automatically. Ignore fixes older than two minutes, substantially future-dated/out-of-order fixes and results from a stopped activation. Existing accuracy/radius and repeat-alert rules apply. | Stationary position, pause during permission/GPS, resume, stale/coarse fixes, initial GPS failure and duplicate-fix tests. A widget test opens directly into the zone alert without Locate me. |

The old export path immediately deleted its original temporary file and supplied
a caption. The Android share plugin also creates a cache copy, so deletion alone
is **not established as the cause** of this OnePlus failure. Caption-only saving,
a later share clearing the plugin cache, destination access, provider/full-storage
errors and truncation are other possibilities. An import toast does not identify
which one happened. The new Settings Save route avoids the share receiver and
verifies the actual document. A write-only provider that cannot return readable
bytes cannot produce a verified-success notice; use a local destination instead.

Original and preview are separate packages with different signers. Updating the
original does not migrate preview history. Keep both until any desired transfer
has been verified through valid JSON. The PIN, trusted contact, app-lock policy
and local privacy/location choices are not portable backup settings.

The user's private legacy format-3 WhatsApp backup passed validation, protected
import, duplicate retry, state-v13 reload and format-8 re-export. Tests compared
every original event ID, type, timestamp and metadata field. A state-v7 fixture
built from that file also migrated without losing those records. Public review
notes contain no private attachment or recovery history. New code reads supported
old formats; an old binary is not expected to read newly introduced formats.

## Upcoming work, in order

| Priority | Change | Acceptance criteria |
|---|---|---|
| Next | Reliable background zones on OnePlus | Measure entry/exit latency with the app open, backgrounded, screen off, after reboot and under battery restrictions. Explain location, notification and service health separately. Record missed detections and the last usable fix. |
| Next | Visible location health | Show permission, location-services state, fix age/accuracy and foreground/background monitoring health. Offer the relevant settings action. Stale/coarse location must not reassure the user that they are outside a zone. |
| Next | Fresh native zone-based app locking | The current service reads last-known positions up to ten minutes old and does not request GPS. Choose fresh geofence state or an opt-in location foreground service with the appropriate Android service type/disclosure, then measure battery cost and permission-loss behavior. |
| Next | One foreground location source | ZoneMonitor and the position-status notification currently own separate streams/current requests. Share a source, stop it on pause, reject late results and keep notification display independent of alert deduplication. |
| Next | App-lock health and failed unlocks | Verify restarts, Usage access revocation, background screen-launch limits, budget/PIN/long-wait exits and five-minute expiry. Distinguish a failed native grant from an app that cannot launch; give a retry without falsely claiming an unlock. |
| Next | Export diagnostics and transfer | Show filename/size and destination outcome without logging history. Exercise Downloads, Drive, offline/full storage, cancellation and repeat exports. Preserve old-source recovery options until export validates. |
| Next | Existing quantity provenance | If an earlier preview already converted bottle-only notes with an assumed size, compare its preserved source before repairing values. Do not guess which structured records were actually entered by the user. New migration/import no longer makes that assumption. |
| Later | Automatic encrypted backup | User chooses destination/retention; show the last verified backup, handle revoked access/full storage and prove restore. Exclude credentials. |
| Later | Reviewable insights | Keep recorded/estimated cost explicit and show pattern evidence. Record-count confidence describes available evidence rather than a validated medical probability. Weekly reports remain user-controlled. |
| Later | Safety copy and historical logs | Review tolerance and repeated-dose wording with clinical guidance. Avoid presenting a fixed number of logged clean days as a biological certainty or calling a backdated log a dose taken today. Preserve clear overdose and mixing-risk warnings. |
| Later | Android build tools | Upgrade Gradle, AGP and Kotlin together with the Flutter compatibility baseline. Build warnings currently announce future minimum versions; validate notification restoration and native plugins after the upgrade. Run tests/builds sequentially and refresh production plugin registration before release builds. |
| Hold | Web | Existing work is preserved and pushed as `9112-deviant/web` at `e903df8`. Bring in the reviewed Android baseline when work resumes, then address browser storage, import/download and unsupported native features independently. |

Mocked GPS and passing builds do not establish physical travel, background
geofence delivery, OEM battery behavior, reboot notifications or app-lock service
enforcement. The review record lists actual device coverage and limitations.

App version `1.2.0+4`, recovery state v13 and backup format 8 are independent.
These corrections require no schema bump. Android Save follows the
[document creation flow](https://developer.android.com/training/data-storage/shared/documents-files);
shared attachments follow the existing plugin's
[content-URI sharing model](https://developer.android.com/training/secure-file-sharing).
