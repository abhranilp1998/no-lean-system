# NO LEAN Roadmap

This roadmap describes direction, not promised dates. Work is ordered by user
safety and data integrity first, recovery usefulness second, and visual polish
third.

## Product principles

- Emergency actions must remain reachable in one deliberate tap.
- Recovery history belongs to the user: keep it local by default, explain every
  export or restore, and never silently discard damaged data.
- The voice can be direct without becoming punitive, manipulative, or shaming.
- Personalization must improve the user's plan without hiding essential safety
  actions or weakening accessibility.
- Insights should describe patterns only when there is enough evidence; they
  should not present guesses as diagnoses.

## Production gate

These items should be completed before a store release:

- Replace the intentionally temporary debug signing configuration with a
  protected production keystore and document key rotation and recovery.
- Add migration fixtures covering every supported stored-state version,
  duplicate or malformed events, clock changes, and restoration from the
  rejected-state backup.
- Serialize persistence writes and add interruption tests for relapse, SOS,
  pledge, backup import, and settings changes.
- Show notification permission and scheduling health in Settings, including a
  route to system settings after a permanent denial.
- Run TalkBack, 200% text scaling, reduced-motion, high-contrast, and switch
  access checks across onboarding, SOS, relapse, import, and the widget.
- Verify Android API 24, 29, 33, and the current target API, including at least
  one Samsung-class launcher for widget sizing and pending-intent behavior.
- Resolve the generated `local.properties` and dependency lint-environment
  blockers, then enforce analysis, tests, lint, and release builds in CI.
- Publish a short, plain-language privacy statement confirming that recovery
  data is offline by default and naming the secure fields excluded from backup.

## Functionality direction

### Recovery plan

- Add a short, skippable setup flow for reasons, risk window, trusted contact,
  typical triggers, and preferred intervention style.
- Let users create a versioned "when the urge hits" plan with ordered actions
  such as breathe, move, delay, call, or open a personal note.
- Offer multiple cooldown styles and lengths instead of assuming one technique
  works for every person.

### Cravings and interventions

- Add optional follow-up check-ins so a craving can record what action was
  tried and whether intensity changed.
- Surface locally computed trigger and time patterns only after a minimum sample
  size, with clear wording that correlation is not causation.
- Allow users to pin the interventions that work for them and make those the
  first actions shown during their risk window.
- Support explicit, user-initiated call or message templates for a trusted
  contact; never send automatically.

### Progress without punishment

- Add weekly reflection cards covering cravings survived, SOS completion,
  money retained, and helpful interventions—not only streak length.
- Treat relapse as a recovery event with context and next actions rather than a
  destructive reset of all progress.
- Add optional goals that are not streak based, such as completing a daily
  plan or contacting support during a difficult window.

### Data ownership and reliability

- Add an in-app backup history and validation report before import.
- Offer CSV export for users who want a readable journal, while retaining JSON
  as the lossless restore format.
- Provide an explicit recovery screen for preserved rejected-state data instead
  of requiring manual extraction.
- Consider encrypted user-controlled backup only after a recoverable key flow
  and failure-mode review are designed.

### Platform direction

- Add small and large Android widget variants after the 4x2 widget is validated
  across common launchers.
- Keep web support out of scope until secure-storage, notification, backup, and
  privacy behavior can reach feature parity rather than shipping a partial
  recovery experience.

## UI/UX direction

### Vibe: tactical calm

Keep the recognizable neon/cyberpunk identity, but make it feel like a focused
instrument rather than a constantly alarming dashboard.

- Use cyan and toxic green for stable actions and progress; reserve red for a
  real risk state, destructive confirmation, or relapse cooldown.
- Reduce ambient glow, scanlines, and glitch motion around reading-heavy areas.
  Let Ultra remain an explicit personalization rather than the default tone.
- During SOS, progressively remove decoration and choices so breathing, the
  countdown, personal reasons, and contact action dominate the screen.
- Prefer short, concrete copy. Avoid language that implies moral failure or
  guarantees an outcome.

### Hierarchy and navigation

- Keep Counter, Cravings, Progress, Timeline, and Settings stable; do not move
  emergency entry points based on personalization.
- Give each screen one primary action and visually demote diagnostic or advanced
  controls.
- Add clear empty, loading, permission-denied, import-conflict, and offline
  states rather than relying on generic snackbars.
- Use progressive disclosure for raw history tools and other irreversible or
  expert-only controls.

### Accessibility and customization

- Maintain readable contrast without relying on neon glow or color alone.
- Support large text without truncating counters, dialog actions, widget status,
  or trusted-contact names.
- Respect reduced motion across animated backgrounds, scanlines, countdowns,
  chart transitions, and haptic/sound feedback.
- Let users independently tune visual intensity, animation, haptics, sound,
  reminder tone, and directness of copy.
- Keep touch targets generous in the app and provide accessible labels and
  state descriptions for widget actions.

## Suggested delivery sequence

1. **Release hardening:** signing, migration matrix, persistence serialization,
   permission clarity, accessibility audit, device matrix, and CI gates.
2. **Personal recovery plan:** onboarding, intervention ordering, craving
   follow-ups, and trusted-contact templates.
3. **Balanced progress:** reflection summaries, non-streak goals, evidence
   thresholds, and readable exports.
4. **Visual refinement:** tactical-calm defaults, simplified SOS, responsive
   typography, widget variants, and deeper appearance customization.

Each phase should preserve offline operation, include migration and widget
regression tests where relevant, and be validated with users who rely on the
feature during an actual high-risk moment.
