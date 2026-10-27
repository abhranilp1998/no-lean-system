# History separation review — 27 October 2026

The user selected this milestone before publishing the current feature branch:
separate recovery activity from settings changes and provide a third view for
location records. This is T06-A, a bounded presentation slice of D3. The original
P0 logging/progress and protection work remains open in [TODO.md](../TODO.md).

## Implemented behavior

- Timeline has Recovery, Settings history and Location history tabs. Progress
  keeps its charts and opens Recovery history; Settings and Zones open the
  corresponding history tab. The five main navigation destinations stay intact.
- Recovery excludes settings changes and standalone zone observations. Settings
  contains recorded settings changes. Location includes zone observations and
  recovery records with an explicit saved zone relationship. Text mentioning a
  place, tags and zone-configuration audits do not establish physical presence.
- These are projections of the same event objects and IDs. A located recovery
  record can appear in two views without being copied or counted twice. Opening
  views, filtering and following links perform no storage writes.
- A shared detail route reads the current record by ID and links to its other
  matching view. Its linked-record filter can be cleared. Existing authorized
  edit/delete actions remain available through the shared card and controller.
- Settings show readable previous/new values for both legacy and newer metadata
  keys. False and zero remain values; absent values say "Not recorded". This
  does not add audit writers for settings that were never recorded.
- Location filters distinguish automatic in-app/background observations, manual
  sources, saved context and unknown sources. Manual pins say "Location saved"
  and explicitly do not establish presence. Existing name/time-only records do
  not gain invented coordinates, accuracy or detection times.
- Details separate event time from recorded time when recorded-time metadata
  exists. Missing recording time remains unknown; saved offset/precision text
  is preserved, and an offset-free recording time says timezone not recorded.
- Narrow/large-text generic cards stack their icon/menu above content to retain
  useful text width. History uses the shared gutters, scrolling and theme.

## Compatibility and scope

No writer, stored schema, migration, import/export format, account, native policy
or progress calculation changes. App/build remains 1.2.0+4, recovery state 13,
portable backup 8. This is a review branch, not a distributable version.

Purpose classification, corrections, trustworthy day/milestone calculations,
complete settings-audit coverage, tag management/bulk operations/combined
filters, coordinate capture/editing and retention controls remain deliverables.
The location tab exposes current evidence; it is not the complete D4 experience.

## Verification record

| Check | Observed result |
|---|---|
| New history coverage | Seven pure projection/provenance tests and five widget flows; all existing event families remain discoverable |
| Entry routes | Three new regressions verify Progress/Settings/Zones open the correct tab without creating events |
| Shared identity/read-only behavior | IDs/objects, serialized records, writes, last-use time, streak and spending stay unchanged across tab navigation; detail links use the same ID and their filter can be cleared |
| Full Flutter suite | 485 tests passed on the final responsive-card implementation |
| Formatting/static analysis | 205 Dart files checked without changes; `dart analyze --fatal-infos` reports no issues |
| Visual checks | Real bundled fonts, synthetic 414×896 normal-text and 320×640 at 200%; all tabs and record actions reachable. Initial narrow text columns were corrected with stacked cards and recaptured |
| Android compile checks | Normal `flutter build apk --release` and `--debug` both succeeded, sequentially after tests (Gradle tasks 294.6 s / 81.2 s) |
| Version guard | Correctly refuses unchanged 1.2.0+4 against fetched main build 4; allocation remains a merge gate |
| Physical device | `adb devices -l` returned no devices; native and installed-upgrade acceptance remains unverified |

Local logs and synthetic previews live under ignored `output/history-separation/`;
no private export or real history is included in the branch. Synthetic widget
rendering is not device acceptance. Existing map-tile tests emit invalid-image
diagnostics for their synthetic tile payload; the tests pass.

### Internal artifact identity

The newly built release APK reports package `com.nolean.no_lean`, version
`1.2.0`, code `4`, minimum API 24 and target API 36. SHA-256:
`4df16e766a1876d88acccc9f02a6aa5908da5834f5006e945fedcb7521dd51a0`.
The signer certificate SHA-256 is
`7d72b80dfc2af4b523e21c5779b4363f1b5add5b2b419b01ff0361f476390ec5`.
The newly built debug APK SHA-256 is
`e4ce0fdeb9ebae7f6687e9fd9878b77ad09ce3d0cc93cf426c21b86a59ba0715`.
These are internal compile artifacts with the existing local debug certificate,
not a new distributed release or a same-signer installed-upgrade result.

Publication is authorized after this history milestone is verified. Keep the
PR in draft: release-version allocation, distributed-build inventory, actual
same-signer upgrade and affected-device selected-app interruption/background
verification are separate pending gates. No merge, release tag or APK
distribution is authorized at this checkpoint.

## Publication disposition

Published `9112-deviant/p0-app-lock-activation` to origin with implementation
commit `edc8ea3`, the earlier native-acknowledgement fix and delivery planning.
The local branch tracks origin and the implementation head was verified equal
to upstream after the push. This handoff update changes documentation only.

A draft PR was attempted, but GitHub's connector returned 403, "Resource not
accessible by integration". The local GitHub CLI is not installed and the
browser is signed out, so no PR was created. Review the
[published branch comparison](https://github.com/abhranilp1998/no-lean-system/compare/main...9112-deviant/p0-app-lock-activation)
and use the prepared description in ignored
`output/history-separation/pull-request.md` when PR access is available.
No merge, tag, APK distribution or private-history upload occurred.
