# DayDrop MVP Acceptance Matrix

This matrix separates deterministic automated evidence from signed-app and real-browser evidence. A passing build is not treated as proof of permissions, login-item registration, notifications, or browser behavior.

| PRD | Acceptance criterion | Planned evidence | Status |
| --- | --- | --- | --- |
| AC-01 | Safari, Chrome, Edge, and Firefox completed downloads are organized | Signed app, four real-browser downloads | Manual pending |
| AC-02 | Temporary/incomplete downloads are not moved | Suffix, stability, advisory-lock tests; live partial download still required | Automated pass; manual pending |
| AC-03 | 0–14 natural days route to `MMDD/` | Boundary and DST unit tests | Automated pass |
| AC-04 | This-year files older than 14 days route to `MM/MMDD/` | Day-15 unit and integration tests | Automated pass |
| AC-05 | Other-year files route to `YYYY/MM/MMDD/` | Past/future-year unit tests | Automated pass |
| AC-06 | Managed folders migrate after 14 days and across years | Whole-folder and merge integration tests | Automated pass |
| AC-07 | Existing files use creation date, then modification date | Resolver unit tests | Automated pass |
| AC-08 | Existing destinations are reused | Temporary-directory move/merge tests | Automated pass |
| AC-09 | Same-name files are preserved with a sequence suffix | Unit and integration tests | Automated pass |
| AC-10 | Move failure preserves the source | Injected failing-mover integration test | Automated pass |
| AC-11 | Pause stops automatic organization immediately | Monitor stop and code-path audit; interactive race check required | Manual pending |
| AC-12 | Menu-bar panel shows all of today's files | SwiftUI build/type checks; source audit of today-folder create/open path; visual fixture inspection required | Static integration pass; visual/manual pending |
| AC-13 | Today's list refreshes after changes | Real Dispatch-source event test; signed-app two-second timing required | Automated pass; manual timing pending |
| AC-14 | Denied folder permission cannot be bypassed | Bookmark/entitlement checks; signed denial flow required | Automated boundary pass; manual pending |
| AC-15 | All functionality works offline | No network client/entitlement; network-disabled run required | Static pass; manual pending |

## Current development evidence — 2026-08-12

- The current source passes 70 XCTest cases with 0 failures on arm64 macOS.
- `npm run mac` successfully builds, terminates the prior process, moves the previous installed app into a recoverable Trash backup, installs `/Applications/DayDrop.app`, verifies its ad-hoc signature, and launches the installed path.
- Source inspection confirms that the today-module action uses archive target preparation, ownership evaluation, managed-folder persistence, rollback of an empty newly created folder on persistence failure, today-monitor refresh, and Finder open. A dedicated Finder/UI automation test has not yet been added.
- Main-panel and Settings toggles share the same runtime-backed controller methods and compact visual style.
- The onboarding window now uses a standard non-transparent title bar, preventing its ScrollView content from entering the title/traffic-light region by construction.
- These checks do not establish visual polish, VoiceOver quality, Developer ID behavior, Intel compatibility of the Debug build, minimum-macOS compatibility, or public-release readiness.

## Current release-package evidence — 2026-08-12

- 70 XCTest cases passed with strict concurrency checking and source warnings treated as errors.
- `xcodebuild analyze` passed.
- Release app built as one universal Mach-O containing `arm64` and `x86_64`.
- Ad-hoc signature verification passed with App Sandbox, app-scoped bookmarks, and user-selected read/write entitlements.
- The current-source `DayDrop-1.0.0.dmg` was mounted successfully; its Developer ID signature, hardened runtime, three sandbox/bookmark entitlements, 10 AppIcon renditions, `/Applications` shortcut, and `arm64`/`x86_64` application were verified.
- Apple notarization submission `b24c5365-e6be-427c-8b63-80f7d107a0e5` returned `Accepted` with zero reported issues. Stapler validation passed and Gatekeeper reports `Notarized Developer ID` for the DMG and contained app.
- Migration recovery tests cover persisted intent, exact source/destination identity, destination replacement, partial-merge resume, cancellation, symlink handling, and preservation of user-created parent folders.
- No systematic visual acceptance pass is claimed. User screenshots drove targeted fixes, but the complete state matrix still requires inspection.
