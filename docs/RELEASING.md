# Release versioning and safe upgrades

`pubspec.yaml` is the authoritative app version: `MAJOR.MINOR.PATCH+BUILD`.
Android inherits the public `versionName` and integer `versionCode` from Flutter.
Settings already displays both as `VERSION 1.1.0 (3)`, for example; Android App
Info may only display the public version. Never infer the build from App Info.

Use patch releases for fixes, minor releases for compatible functionality, and
major releases for deliberate product compatibility changes. Increase BUILD for
every distributed APK, including rebuilds and test releases using this package.
Do not derive it from commit count or restart numbering on a new branch.

The app version, `RecoveryController.stateVersion` (currently 7), and
`BackupService.currentBackupVersion` (currently 3) are separate contracts.
A UI fix does not require a data migration. Change a schema version only when
its stored format changes, with explicit migrations and round-trip fixtures.

## Preparing a release

1. Fetch the current main branch and all release tags:

   ```sh
   git fetch origin main --tags
   ```

2. Check the highest build actually distributed, including APKs sent outside
   GitHub. The original repository used `1.0.0+1` and had no release tags at the
   time this scheme was introduced. Untracked APKs can have overridden build
   numbers, so inspect them before allocating the next release. An existing APK
   can be inspected with Android build tools:

   ```sh
   aapt dump badging previous.apk
   apksigner verify --print-certs previous.apk
   ```

3. On the release PR branch, prepare a version. The tool selects a build above
   the current pubspec and every fetched `vMAJOR.MINOR.PATCH+BUILD` tag:

   ```sh
   dart tool/release_version.dart bump patch
   dart tool/release_version.dart check --base-ref=origin/main
   ```

   Choose `minor`, `major`, or `build` where appropriate. If a distributed APK
   has a higher build than the repository knows, set the pubspec build above it
   before validation. Do not pass ad-hoc `--build-name` or `--build-number`
   overrides to a release build; they detach the APK from its reviewed version.

4. Run analysis, tests, Android builds, and the upgrade checks below. Review and
   merge the PR. The version command validates numbering; it does not establish
   that an app is safe to release.

5. On the clean main commit that passed review and migration/reload tests, create
   the annotated source tag. A source tag identifies code; distribution still
   requires the device upgrade checks below:

   ```sh
   dart tool/release_version.dart tag
   dart tool/release_version.dart check --tag=v1.1.0+3
   ```

   Substitute the actual tag. The tool rejects dirty checkouts, other branches,
   duplicate releases, decreasing versions, and reused build numbers. It never
   force-moves a tag or pushes. After source validation, push only the exact tag:

   ```sh
   git push origin v1.1.0+3
   ```

   Keep the APK SHA-256, signing-certificate SHA-256, Git commit, app/build
   versions, schema versions, and upgrade-test result with the release notes.
   Corrections receive a new build and tag; existing tags are immutable.

## Preserving installed user data

Keep `com.nolean.no_lean`, the installed app's compatible signing identity,
`FlutterSharedPreferences` / `recovery_state`, secure-storage namespaces, and
the `NoLeanWidgetProvider` class stable. Before distribution, compare the new
APK's certificate with an APK users already installed. The current Gradle
release configuration uses the local debug key: a different machine's debug key
is not automatically compatible. Do not simply replace it with a new production
key for existing users. Plan a supported signing transition separately.

An update must install over the previous app. Uninstalling, clearing app storage,
or changing the application ID is not an upgrade strategy. Android cloud backup
and device transfer are disabled for recovery data in this PR.

Test on a disposable emulator/device populated with synthetic legacy data:

- Install the previous signed APK; create cravings, pledges, relapse days, SOS
  sessions, a PIN, and customized settings; add its widget.
- Install the candidate with `adb install -r candidate.apk`, without uninstall,
  downgrade flags, or clearing storage.
- Open from launcher and existing widget, with the process stopped and running.
- Compare event counts, IDs, known dates, PIN behavior, settings, and counters.
- Test two or more relapses on the same day and during cooldown; restart between
  writes and reopen from the widget.
- Test rejected data, read/write failure, and future schema versions. Preserve
  the original state; an unsupported version must not be replaced with defaults.

Rollback means a corrective release with a higher BUILD that can still read the
newest stored schema. Installing an old binary that interprets newer state as
corrupt can erase active history.

## State version 7 and backup version 3

The app now commits history to `recovery/current.json` in application support
storage using a flushed, verified temporary file and rename. `previous.json`
holds the previous commit, and immutable `preserved-*.json` migration snapshots
retain source records. The original `recovery_state` preference is retained
(plaintext legacy PIN is removed only after secure migration); it is read only
when no current file exists. A damaged current file never silently falls back
to stale preferences. Do not ship a corrective binary that reads only the old
preference: that would hide records written after this migration.

Versions 2–5 preserve clean/relapse dates as day summaries and the actual last
pledge timestamp. A day summary explicitly lacks an occurrence count/time.
Version 6 preserves all event IDs and repairs available legacy day facts from
its saved backup. Previously synthesized v6 events without provenance are kept;
the app cannot safely distinguish them from real events and delete them.

Backup v3 supports day summaries; imports accept event backups v1–v3 and legacy
state/export JSON v2–v7. Imports merge by event ID and authenticate when the
relapse lock is enabled. Preferences remain opt-in and cannot disable the lock.
Startup recovery exports a sanitized bundle of readable current/preserved copies
for manual recovery; a bundle is not an automatic instruction to replace current
history. Unreadable originals stay on the device.

For an unsupported schema, install a compatible higher-build corrective app.
Never force a downgrade. For corrupted current data, export readable copies,
investigate the saved originals, and prepare a reviewed recovery migration.

## Platform references

- [Android app version ordering](https://developer.android.com/studio/publish/versioning)
- [Flutter Android release version configuration](https://docs.flutter.dev/deployment/android#update-the-apps-version-number)
- [Android signing and update identity](https://developer.android.com/studio/publish/app-signing)
