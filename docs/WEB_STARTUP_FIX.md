# Browser startup and backup correction

The browser reached the preserved-history error screen because the production
provider always selected `FileRecoveryStateStore`. Its application-support path
and native filesystem operations are unavailable in a browser. Retrying repeated
the same platform error; the screen did not indicate that user data was damaged.

The provider now selects a platform store through conditional exports. Android
retains the existing file implementation and storage location. Web uses IndexedDB
database `no_lean_recovery`, object store `history`, with current and previous
history updated together in a transaction. Saves complete only after commit.
Legacy browser preferences and migration snapshots are retained. A stale tab
cannot overwrite a newer committed history; reload before saving from that tab.
Corrupt or unsupported history still opens the recovery screen without resetting.

Web backup export now supplies UTF-8 bytes to the browser file picker instead of
trying to write a native file path. Recovery-screen guidance now tells browser
users to preserve site data. Screens and recovery-state/backup versions remain
shared with Android; this change does not add synchronization or claim full web
feature parity.

## Verification

- Flutter 3.47.2 / Dart 3.13.2: analyzer and diff checks passed.
- All 104 existing VM/widget tests passed, including native file persistence.
- Eight Chrome tests passed: production provider startup, craving/settings
  reload, legacy migration, previous committed history, corrupt/future state
  preservation, stale-tab transaction rollback, and legacy credential removal.
- Web release build and Android debug APK build passed.
- Playwright verified the compiled web app in an isolated Chrome profile:
  counter startup, keyboard craving submission, full refresh with the event
  retained, and a downloadable version-3 JSON backup containing that event.
  Test activity was confined to the isolated profile on `127.0.0.1:8765`.

The installed Windows Flutter browser runner returned 404 for CanvasKit files.
For this run, Playwright intercepted only those test-runner requests and served
the same SDK assets from the compiled local web build, then reloaded the test
iframe. No SDK source was changed. The root-level browser test filename also
avoids the runner's observed escaping of Windows subdirectory paths.

```text
flutter test --no-pub --platform=chrome test/web_recovery_state_store_test.dart
flutter build web --no-pub --no-web-resources-cdn
```

Browser storage is scoped to the site origin and browser profile. Use the stable
development port in the README; changing ports does not migrate history. This
work is a local correction on the existing checkout, without a new release tag,
APK distribution, remote merge, or branch deletion.
