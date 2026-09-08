# Pull request review and branch closure SOP

This procedure applies to every NO LEAN change. Protect installed history and
finish with an explicit PR and branch disposition. A conflict-free PR alone is
not evidence that the app works.

## 1. Establish the exact change

1. Read `memory.md`. Inspect `git status`, remotes, local branches and worktrees.
   Preserve unrelated working changes and commits; never reset a user's branch
   to make a review easier.
2. Fetch the target branch and tags. Record the PR number, base SHA, head SHA,
   changed files, reviews, unresolved discussions and check results.
3. Read the complete base-to-head diff, including Android, dependencies,
   migration, authentication and generated-file changes. Check the actual
   implementation against the user-visible trigger and expected result.
4. Classify useful features as **keep**, **replace with a corrected behavior**,
   or **remove with a reason**. Do not silently abandon useful work.

## 2. Review data and upgrade compatibility

- Keep the Android package, compatible signing certificate, widget provider,
  widget update channel and secure-storage namespace stable.
- Keep app/build, recovery-state and portable-backup versions independent.
  Check the distributed APK inventory and fetched tags before choosing a build.
- Test every supported migration: known dates, events, relationships, settings,
  PIN migration, and reload. Missing information must remain unknown.
- Preserve migration sources. Unsupported or malformed current history must
  not become an empty writable app. Optional preference errors must not discard
  valid history. Recovery export must exclude credentials.
- Inject read and write failures. A failed save must not return success, update
  the widget, partially commit a batch, or lose the previous committed state.
- Exercise authorization at controller boundaries, including imports, edits,
  deletes, batch logging and disabling the lock.

## 3. Validate the final implementation

Use Flutter 3.47.2 / Dart 3.13.2 for this baseline. Run `tool/review.ps1`, or the
following commands using the configured SDK:

```text
dart format --output=none --set-exit-if-changed lib test tool
dart analyze --fatal-infos
flutter test
flutter build apk --debug
dart tool/release_version.dart check --base-ref=origin/main
git diff --check
```

For a network-constrained, already provisioned Windows SDK, run the same tests
with `flutter test --no-pub`, then `android/gradlew.bat assembleDebug --offline`
after Flutter has refreshed Android version properties. Record this substitution
and inspect the resulting APK's version; do not reuse an older APK by accident.

Exercise launcher and widget entry, cold/warm startup, cooldown navigation,
multiple events with different and identical times, date validation, cancellation,
duplicate taps/retries, large text, and settings/history access. Inspect native
intent delivery as well as mocked Dart routing. Record exactly which checks used
a device, which used synthetic fixtures, and which remain unavailable.

Before distributing an APK, perform the same-signer `adb install -r` upgrade
matrix in [RELEASING.md](RELEASING.md). No uninstall, data clear or forced
downgrade is an acceptable workaround. A source merge/tag does not replace this
distribution check.

## 4. Decide and finish

1. Fix merge-blocking defects on the PR branch and rerun affected checks. Update
   the title and description to explain the final problem, behavior and evidence.
   Re-review the final diff; earlier passing checks do not cover later changes.
2. If the useful result passes code review and required automated checks, merge
   using the reviewed **expected head SHA**. If the head or base moved, inspect
   the new delta before merging. Never bypass required remote checks.
3. If an acceptable implementation cannot be completed, close the PR with the
   concrete rejection reason. Preserve useful commits in a named follow-up or
   archive reference before removing an unmerged branch; never use force-delete
   as branch cleanup.
4. After a successful merge, fetch and verify its ancestry. Fast-forward local
   main; preserve local commits. Delete only the merged remote and local feature
   branch, and verify that the PR is merged/closed and the working tree is clean.
5. Record the disposition, retained/replaced features, final checks, release
   versions and remaining distribution checks in the PR review record.

## 5. Release traceability

Create an immutable annotated `vMAJOR.MINOR.PATCH+BUILD` tag from the clean,
reviewed main commit with `tool/release_version.dart tag`. Validate its target
and push the exact tag. Keep the APK hash, signer hash, version and Git commit
together. Use a higher build for every distributed correction. A rollback must
still understand the newest stored schema.
