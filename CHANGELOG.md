# Changelog

All notable changes to NO LEAN. Versions follow `MAJOR.MINOR.PATCH[-pre]+versionCode`
(Flutter `version:` in `pubspec.yaml`). The Android `versionCode` only ever goes up,
so every build installs over the previous one and keeps your data.

## 1.8.0-beta.1 (versionCode 22700) — 2026-11-27 — pre-release

Pre-release for phone testing. Built from `release/1.8.0-beta.1-all-open-prs`
(all open PRs #25–#45 merged on top of `main` 53344ff). Nothing here is merged
into `main` yet. Same signing key as 1.6.1 / 1.7.x, so it installs as an update.

Data formats: app state v17 → **v18**, backup v12 → **v13**. Older states and
backups (1.0.0 – 1.7.x) still load and import with nothing lost; new keys are
optional and older builds ignore them.

### Fixes
- Late-logged relapses correct milestones and best streak, using the time it happened (#25).
- PIN is required to shrink the risk window whenever a PIN is set (#27).
- Widgets screen says "1 DAY CLEAN" (#28).
- Widgets: live risk/pledge status, privacy on legacy widgets, "I USED" previews, 2x1 fit (#29).
- Biometric/PIN prompt no longer says "update clean time" for benzo-only logs (release branch).
- Timeline entry "⋮" menu is reachable by screen readers and UI automation (release branch).
- App lock re-checks the app already in front right after the lock service restarts,
  instead of waiting for the next app switch (release branch).

### Features
- Log several missed days at once, edit any single day later (#26).
- Danger zone "Did you use?" follow-up with zones-resisted count (#30).
- Optional 3-tap slip review and calm mixing safety card (#31).
- Lower-tolerance warning after a long clean streak (#32).
- Private notification wording on every alert (#33).
- Rough-day mode: calm 3-button home after a slip or "I'm struggling" (#34).
- Substance swap watch (#35).
- Hold-to-text SOS with a maps link to your own contact (#36).
- Craving-peak heads-up 30 minutes before a usual peak (#37).
- Urge timer: 10-minute ride-it-out with "what works for you" ranking (#38).
- Daily check-in notification: Okay / Struggling / Used (#39).
- Craving trigger tags, pattern insights and if-then plans (#40).
- High-risk dates planner with 3-day plan nudges (#41).
- Money saved counter and goal jar (#42).
- Weekly recap card and notification; offline doctor summary PDF (#43).
- Future-self notes (text and voice), sealed with your PIN, played at urges and after slips;
  voice recordings included in backups within the 5 MB limit (#44).
- Warm post-relapse lock screen: streak, 24-hour plan, mixing risk, breathing guide (#45).

### Known issues
- After GO HOME on the block screen, reopening NO LEAN can still show the block screen
  until the app is restarted.
- Parts of this build are not yet tested on a phone (see release notes).

## 1.7.0 (versionCode 18600–22600) — 2026-11-06 — phone-test pre-release
Not promoted to stable. See the `v1.7.0-test.1` release notes.

## 1.6.1 — Companion — 2026-11-04
Current stable release.
