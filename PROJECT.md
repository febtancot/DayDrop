# DayDrop Delivery State

## Current status

DayDrop 1.4.0 (build 12) is published and installed locally as a Developer ID-signed, notarized universal app. It adds ZIP/RAR/RAR5/7z extracted-folder recognition and intact moves while preserving delay/pause behavior. The release passed 167 tests, strict concurrency/source-warnings checks, Release static analysis, universal build, signing/entitlement checks, Apple notarization, stapling, Gatekeeper assessment, signed feed generation, and complete-package hash checks on both the Pages deployment and production domain. The installed version/build and executable hash match the release package. Actual extraction-utility trials, direct Sparkle UI installation, real overnight/wake behavior, minimum-OS runtime compatibility, broader visual acceptance, and large-tree performance remain open.

- Native macOS 13+ menu-bar app and first-run onboarding.
- Security-scoped Downloads-folder authorization with no direct-path fallback.
- Event-driven root and today-folder monitoring plus per-file vnode finalization
  monitoring, two-second metadata/event quiet windows, and fail-closed retry.
- Recursive, metadata-only Downloads indexing with FSEvents-triggered reconciliation, current/unavailable file query, permanent change history, package boundaries, and no symbolic-link traversal.
- Full date routing, existing-file metadata resolution, collision-safe moves, and source-preserving failures.
- Explicit one-level deep organization for existing files, isolated from automatic monitoring and guarded by a destructive second confirmation about folder-structure disruption.
- Identity-bound, ownership-marked day-folder migration with persisted crash recovery, cancellable safe merge, and ownership-aware empty-parent cleanup.
- Pause/resume organization baselines, an interactive today module that safely creates/opens today's managed folder, a unified current-file/operation-history query, deterministic file-type filters, CSV/JSON history export, login item, and optional notifications. Read-only indexing remains active while organization is paused.
- A dedicated Settings page, runtime-backed quick settings, and a safely reopenable welcome/setup window.
- A compact shared toggle style, standard onboarding title bar, and opaque dynamic panel surface based on current visual feedback.
- Current-version display in the menu and Settings, manual/daily update checks, a signed HTTPS appcast, and a two-step release pipeline that prepares and validates website content before an explicit Cloudflare Pages deployment.
- App Sandbox, hardened runtime, Apple Silicon/Intel Release output, local file data, and a narrowly scoped official-site update network path.
- npm development automation for build, test, recoverable `/Applications` replacement, signature verification, and installed-path launch.

## Current focus

Version 1.4.0 ships conservative extracted-folder recognition and intact directory moves, archive lookup after the source has been organized, ten-second stabilization, final tree/identity/lock checks, collision handling, manual/deep protection, and Settings control. RAR volume flags are rejected explicitly because a first-volume fixture showed that the system library could otherwise return a partial manifest. The October 6 release passed all 167 tests and was published and installed from its notarized DMG. Real extraction-application compatibility remains distinct from fixture/controller evidence.

The published 1.3.0 release includes optional delayed organization in Settings. The switch
defaults off; enabling it retains today's downloads and catches up yesterday's and
older top-level files on midnight, wake, startup, or resume. Policy, persistence, and
temporary-directory routing tests are automated; installed UI and real overnight
sleep/wake acceptance remain pending; startup catch-up was observed in the September 24 Debug installation.

The September 24 delayed-organization investigation found installed-app crashes in
`DownloadsIndexStore.reconcile`: duplicate current paths trapped at dictionary
construction, including during startup before overdue processing. Development source
now recovers legacy duplicates while retaining history and validates new scan entries
before writing them. The same crash was reproduced with a temporary legacy database;
all 148 tests and the Debug build pass. The updated local installation stayed running
and automatically caught up 36 September 23 files into `Day 2026-09-23`, preserving
their filesystem identities. Today's file paths remained at the Downloads root.
One remaining September 23 document was advisory-locked and its companion was hidden,
so both were correctly left in place. Real overnight/wake acceptance remains separate.

Complete visual and signed real-Mac acceptance against the notarized distribution artifact.

## Milestones

1. Native project and tested date/path core — complete.
2. Authorization, monitoring, move/migration engine, history, and notifications — implemented.
3. Menu-bar and first-run UI — implemented and iterated from user screenshots; systematic visual/VoiceOver/minimum-OS acceptance remains pending.
4. Automated verification — current source passes 167 tests, strict concurrency/source-warnings checks, Release static analysis, and an `arm64` + `x86_64` universal Release build. The 1.4.0 artifact also includes extracted-folder recognition and intact moves.
5. Development installation — `npm run mac` builds, safely replaces `/Applications/DayDrop.app`, verifies, and launches the arm64 Debug app; complete.
6. Distribution packaging — DayDrop 1.4.0 universal Developer ID DMG, notarization, stapling, Gatekeeper, signed feed/release notes, Pages publication, production hash verification, and direct local DMG installation complete. Direct Sparkle UI installation remains pending.

## Risks and dependencies

- Download completion is observable only through conservative filesystem signals. The
  per-file monitor now catches in-place writes even when a download manager preallocates
  the final size, but advisory locks are not guaranteed for every writer and a download
  paused longer than two seconds can still resemble a finalized file.
- Security-scoped bookmarks, login items, notifications, and real browser downloads require a signed installed app for authoritative manual verification.
- Replacing a Developer ID app with the ad-hoc Debug build is suitable for local iteration only and does not preserve release-signing evidence.
- Filesystem watchers report writes and lifecycle changes, not a transactional
  “download finished” event. NDM live download/pause/resume behavior remains pending.
- FSEvents is a scan trigger rather than the database authority. Rename/move inference depends on filesystem identity; copy provenance and delete-vs-move-out cannot be proven from the authorized tree alone.
- Recursive indexing increases scan work after event bursts. Incomplete scans fail closed, but large-tree latency, memory, and idle behavior need release-like measurement.
- Advisory locks are cooperative. Temporary suffixes, a retained per-file vnode
  monitor, size/modification-date quietness, and final identity revalidation are combined;
  none is a third-party download-manager completion API.
- Identity revalidation closes deterministic replacement cases, but a malicious external process racing the final path-based filesystem syscall is not fully eliminated without a future file-descriptor-relative migration implementation.

## Next actions

- Confirm the production bundle identifier, signing identity ownership, and distribution channel.
- Run the remaining release acceptance against `dist/DayDrop-1.4.0.dmg`; do not substitute the installed Debug app as release-package evidence.
- Run `ACCEPTANCE.md` signed-app checks in Safari, Chrome, Edge, and Firefox.
- Perform a focused visual pass for the compact toggle states, today-module hit targets, Settings navigation, and onboarding scrolling.
- Run a signed compatibility pass on the minimum supported macOS 13 Ventura runtime.
- Profile idle CPU and resident memory in a release-like build.
- Visually verify File Query current/unavailable/history scopes and measure initial/reconciliation scans against a large Downloads hierarchy.
