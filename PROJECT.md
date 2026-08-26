# DayDrop Delivery State

## Current status

The PRD v1.1 MVP, recursive read-only Downloads indexing, restart-stable managed-folder identity, a two-second finalization quiet window, reliable persistent update reminders, target-display Finder opening, and an opaque appearance-aware menu-bar surface are implemented and shipped in DayDrop 1.2.2 (build 10). The release pipeline passed 129 tests on macOS 27, strict warnings-as-errors compilation, static analysis, universal build, Developer ID signing, Apple notarization, stapling, Gatekeeper checks, signed Appcast generation, Cloudflare Pages publication, and production package consistency verification. Installed 1.2.2 visual inspection, signed real-browser, permission-denial, login-item, notification, Sparkle updater installation, index UI, broader visual, minimum-OS, and large-tree performance acceptance remain open.

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

Complete visual and signed real-Mac acceptance against the notarized distribution artifact.

## Milestones

1. Native project and tested date/path core — complete.
2. Authorization, monitoring, move/migration engine, history, and notifications — implemented.
3. Menu-bar and first-run UI — implemented and iterated from user screenshots; systematic visual/VoiceOver/minimum-OS acceptance remains pending.
4. Automated verification — current source passes 129 tests, strict concurrency/warnings-as-errors compilation, Release static analysis, and an `arm64` + `x86_64` universal Release build. The 1.2.2 artifact adds the shared opaque menu-bar surface while preserving the existing authorization, organization, indexing, and Finder flows.
5. Development installation — `npm run mac` builds, safely replaces `/Applications/DayDrop.app`, verifies, and launches the arm64 Debug app; complete.
6. Distribution packaging — DayDrop 1.2.2 universal Developer ID DMG, `.p8` notarization, stapling, Gatekeeper verification, signed Sparkle feed, Cloudflare Pages publication, and production download consistency verification complete; direct 1.2.2 installation and Sparkle updater installation remain pending.

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
- Run the remaining release acceptance against `dist/DayDrop-1.2.2.dmg`; do not substitute the installed Debug app as release-package evidence.
- Run `ACCEPTANCE.md` signed-app checks in Safari, Chrome, Edge, and Firefox.
- Perform a focused visual pass for the compact toggle states, today-module hit targets, Settings navigation, and onboarding scrolling.
- Run a signed compatibility pass on the minimum supported macOS 13 Ventura runtime.
- Profile idle CPU and resident memory in a release-like build.
- Visually verify File Query current/unavailable/history scopes and measure initial/reconciliation scans against a large Downloads hierarchy.
