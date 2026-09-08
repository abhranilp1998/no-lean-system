# NO LEAN 1.1.0+3 source and candidate APK record

The immutable source tag is `v1.1.0+3` on reviewed main. App version is 1.1.0,
Android build is 3, recovery state is 7 and portable backup format is 3.

This release adds multiple dated relapse events from the app and widget,
welcome-back guidance, accessible cooldown support, non-destructive legacy
migration, durable serialized saves, startup retry/recovery export, and release
and PR review tooling. Existing SOS, history, personalization and privacy
features are retained. See `PR_1_REVIEW.md` for the review and feature disposition.

## Verified candidate

- Flutter 3.47.2 / Dart 3.13.2; 79 tests passed; format, fatal-info analysis,
  version and diff checks passed; Android debug build passed.
- Package `com.nolean.no_lean`; minimum API 24; target API 36;
  ARMv7, ARM64 and x86-64.
- Debug APK SHA-256:
  `6246db248d16889b7f5e3703b66ea8aac687baab34a6d7fb2e161498b06e26a7`.
- Signing certificate SHA-256:
  `7d72b80dfc2af4b523e21c5779b4363f1b5add5b2b419b01ff0361f476390ec5`.
  This matches the locally preserved 1.0.0+1 APK.
- Local candidate: `build/releases/no-lean-1.1.0+3-debug.apk`.

The source tag and debug APK are traceability artifacts, not evidence of a
completed user rollout. No device/emulator was available for an actual signed
`adb install -r` upgrade in this run, and no APK was distributed. Before
distribution, test the real previous APK, PIN, history and existing widget using
`RELEASING.md`. Preserve the existing signing identity. Do not uninstall or clear
data. Use a higher-build corrective release for any later change.
