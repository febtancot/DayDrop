# DayDrop Delivery State

## Current status

The PRD v1.1 MVP is implemented. The current source passes 70 automated tests, and the latest arm64 Debug build is installed locally through `npm run mac`. A fresh universal DMG containing the 2026-08-12 source was built through `npm run release:mac`, Developer ID signed, accepted by Apple notarization, stapled, and accepted by Gatekeeper. Signed real-browser, permission-denial, login-item, notification, visual, minimum-OS, and performance acceptance remain open.

- Native macOS 13+ menu-bar app and first-run onboarding.
- Security-scoped Downloads-folder authorization with no direct-path fallback.
- Event-driven root and today-folder monitoring with conservative completion checks and retry.
- Full date routing, existing-file metadata resolution, collision-safe moves, and source-preserving failures.
- Identity-bound, ownership-marked day-folder migration with persisted crash recovery, cancellable safe merge, and ownership-aware empty-parent cleanup.
- Pause/resume baselines, an interactive today module that safely creates/opens today's managed folder, recent 50 records, login item, and optional notifications.
- A dedicated Settings page, runtime-backed quick settings, and a safely reopenable welcome/setup window.
- A compact shared toggle style and standard onboarding title bar based on current visual feedback.
- App Sandbox, hardened runtime, Apple Silicon/Intel Release output, and local-only data flow.
- npm development automation for build, test, recoverable `/Applications` replacement, signature verification, and installed-path launch.

## Current focus

Complete visual and signed real-Mac acceptance against the notarized distribution artifact.

## Milestones

1. Native project and tested date/path core — complete.
2. Authorization, monitoring, move/migration engine, history, and notifications — implemented.
3. Menu-bar and first-run UI — implemented and iterated from user screenshots; systematic visual/VoiceOver/minimum-OS acceptance remains pending.
4. Automated verification — current source passes 70 tests; the earlier baseline also passed strict concurrency, static analysis, universal Release build, and ad-hoc entitlement/signature checks.
5. Development installation — `npm run mac` builds, safely replaces `/Applications/DayDrop.app`, verifies, and launches the arm64 Debug app; complete.
6. Distribution packaging — current-source universal Developer ID DMG, `.p8` notarization, stapling, and Gatekeeper verification complete; signed real-Mac acceptance remains pending.

## Risks and dependencies

- Download completion is observable only through conservative filesystem signals; advisory locks are not guaranteed for every writer.
- Security-scoped bookmarks, login items, notifications, and real browser downloads require a signed installed app for authoritative manual verification.
- Replacing a Developer ID app with the ad-hoc Debug build is suitable for local iteration only and does not preserve release-signing evidence.
- Filesystem watchers report that a directory changed, not a transactional “download finished” event.
- Advisory locks are cooperative; browser temporary suffixes and repeated size checks remain the primary completion signals.
- Identity revalidation closes deterministic replacement cases, but a malicious external process racing the final path-based filesystem syscall is not fully eliminated without a future file-descriptor-relative migration implementation.

## Next actions

- Confirm the production bundle identifier, signing identity ownership, and distribution channel.
- Run the remaining release acceptance against `dist/DayDrop-1.0.0.dmg`; do not substitute the ad-hoc Debug app as release evidence.
- Run `ACCEPTANCE.md` signed-app checks in Safari, Chrome, Edge, and Firefox.
- Perform a focused visual pass for the compact toggle states, today-module hit targets, Settings navigation, and onboarding scrolling.
- Run a signed compatibility pass on the minimum supported macOS 13 Ventura runtime.
- Profile idle CPU and resident memory in a release-like build.
