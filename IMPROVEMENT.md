# DayDrop Improvements

| ID | Candidate improvement | Evidence or reason | Status | Next step |
| --- | --- | --- | --- | --- |
| IMP-001 | Add browser-specific signed-app acceptance fixtures | Temporary suffix and write behavior vary across browsers | Proposed | Run Safari, Chrome, Edge, and Firefox downloads on a real Mac |
| IMP-002 | Add crash-recovery journaling for multi-folder merges | A process interruption during a merge can leave a partially merged tree | Implemented | Persisted migration intent, identities, restart recovery, and cancellation tests are in place |
| IMP-003 | Measure idle CPU and resident memory | PRD targets near-zero idle CPU and less than 50 MB | Proposed | Profile a release build with Instruments |
| IMP-004 | Add undo for the most recent batch | Listed as a post-MVP candidate in the PRD | Proposed | Validate demand after MVP |
| IMP-005 | Add accessibility and localization audits | The MVP UI is user-facing and menu-bar constrained | Proposed | Run VoiceOver and string-catalog review before release |
| IMP-006 | Make directory creation and final migration syscalls file-descriptor-relative | Repeated identity checks reject deterministic replacements, but path-based create/mark/move syscalls retain a very narrow adversarial TOCTOU window | Proposed | Evaluate `openat`/`mkdirat`/`renameat`-style traversal with no-follow semantics before security-sensitive distribution |
| IMP-007 | Add deterministic SwiftUI/AppKit visual-regression coverage | Onboarding title-bar overlap and oversized switch styling were found through screenshots rather than automated checks | Proposed | Add preview fixtures or screenshot tests for main, settings, empty/populated today, and scrolled onboarding states |
| IMP-008 | Refresh the universal Developer ID package from current source | The 2026-08-11 DMG predates settings navigation, today-folder interaction, onboarding, toggle, and npm workflow changes | Required before release | Produce a fresh universal archive, DMG, checksum, notarization ticket, and stapled verification evidence |
| IMP-009 | Make development-backup retention configurable | Every `npm run mac` replacement intentionally leaves a recoverable Trash backup, which may accumulate during rapid iteration | Proposed | Add a non-destructive backup inventory command and document manual cleanup; never auto-purge without an explicit policy |
