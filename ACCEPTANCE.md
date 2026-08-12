# DayDrop MVP Acceptance Matrix

This matrix separates deterministic automated evidence from signed-app and real-browser evidence. A passing build is not treated as proof of permissions, login-item registration, notifications, or browser behavior.

| PRD | Acceptance criterion | Planned evidence | Status |
| --- | --- | --- | --- |
| AC-01 | Safari, Chrome, Edge, and Firefox completed downloads are organized | Signed app, four real-browser downloads | Manual pending |
| AC-02 | Temporary/incomplete downloads are not moved | Suffix, stability, advisory-lock tests; live partial download still required | Automated pass; manual pending |
| AC-03 | 0–14 natural days route to `Day YYYY-MM-DD/` | Boundary and DST unit tests | Automated pass |
| AC-04 | This-year files older than 14 days route to `Month YYYY-MM/Day YYYY-MM-DD/` | Day-15 unit and integration tests | Automated pass |
| AC-05 | Other-year files route to `Year YYYY/Month YYYY-MM/Day YYYY-MM-DD/` | Past/future-year unit tests | Automated pass |
| AC-06 | Managed and evidence-backed legacy folders migrate after layout, 14-day, and year changes | Whole-folder, legacy recovery, and merge integration tests | Automated pass |
| AC-07 | Existing files use creation date, then modification date | Resolver unit tests | Automated pass |
| AC-08 | Existing destinations are reused | Temporary-directory move/merge tests | Automated pass |
| AC-09 | Same-name files are preserved with a sequence suffix | Unit and integration tests | Automated pass |
| AC-10 | Move failure preserves the source | Injected failing-mover integration test | Automated pass |
| AC-11 | Pause stops automatic organization immediately | Monitor stop and code-path audit; interactive race check required | Manual pending |
| AC-12 | Menu-bar panel shows all of today's files | SwiftUI build/type checks; source audit of today-folder create/open path; visual fixture inspection required | Static integration pass; visual/manual pending |
| AC-13 | Today's list refreshes after changes | Real Dispatch-source event test; signed-app two-second timing required | Automated pass; manual timing pending |
| AC-14 | Denied folder permission cannot be bypassed | Bookmark/entitlement checks; signed denial flow required | Automated boundary pass; manual pending |
| AC-15 | File organization, history, and settings work offline; update checks fail safely without affecting organization | Network-disabled run and updater failure-isolation check required | Architectural separation pass; manual pending |
| DF-01 | Deep organization includes root files and files exactly one subfolder level down only after a second structure-risk confirmation | Scanner/source-depth tests, managed-root exclusion audit, SwiftUI action audit, and interactive cancel/confirm check | Automated boundary and static UI pass; interactive pending |
| UP-01 | Current version and build are visible in the menu and Settings | Bundle-version regression test and rendered Settings inspection | Automated and visual pass |
| UP-02 | Manual and daily checks use the signed official HTTPS feed without uploading file data | Live Sparkle log, online feed verification, entitlement and source audit | Live feed pass; update-install pending |
| UP-03 | Published update metadata and packages cannot be substituted by a website-only compromise | Signed appcast/release-notes/archive verification, Developer ID, notarization, extraction-before-validation setting | Cryptographic pipeline pass; end-to-end install pending |
| UP-04 | Homepage, current DMG, checksum, and latest appcast entry always publish the same version | Local preflight plus immutable Pages URL and production-domain download verification | Automated and live deployment pass |

## Current development evidence — 2026-08-12

- The current source passes 82 XCTest cases with 0 failures on arm64 macOS.
- Deep-organization tests cover immediate-subfolder discovery, non-recursion into deeper folders, excluded roots, safe nested-file moves, deeper-source rejection, and preservation of the source when rejected. The destructive confirmation compiles and routes only its explicit confirm action to the deep scope; an interactive cancel/confirm visual pass remains pending.
- Routing and migration tests cover the readable `Day`, `Month`, and `Year`
  prefixes, full ISO-style dates, legacy numeric managed-folder migration, and
  persistence of prefixed paths containing spaces. Legacy recovery tests also
  reject missing, failed, ambiguous, or already-managed operation evidence.
- `npm run mac` successfully builds, terminates the prior process, moves the previous installed app into a recoverable Trash backup, installs `/Applications/DayDrop.app`, verifies its ad-hoc signature, and launches the installed path.
- Source inspection confirms that the today-module action uses archive target preparation, ownership evaluation, managed-folder persistence, rollback of an empty newly created folder on persistence failure, today-monitor refresh, and Finder open. A dedicated Finder/UI automation test has not yet been added.
- Main-panel and Settings toggles share the same runtime-backed controller methods and compact visual style.
- The onboarding window now uses a standard non-transparent title bar, preventing its ScrollView content from entering the title/traffic-light region by construction.
- The 1.0.2 Settings page was rendered and inspected with the DayDrop icon, `版本 1.0.2（构建 3）`, automatic-check toggle, and manual update action visible without clipping.
- A sandboxed 1.0.2 Debug instance fetched the production appcast and logged `OK: EdDSA signature is correct for appcast`. The official feed, release notes, and historical DMGs carry DayDrop EdDSA signatures; feed XML validation and local signature verification pass.
- `npm run publish:web` published the prepared 1.0.2 site to Cloudflare Pages and verified the homepage version/link, latest appcast entry, and complete DMG SHA-256 against both the immutable deployment URL and production custom domain.
- These checks do not establish visual polish, VoiceOver quality, Developer ID behavior, Intel compatibility of the Debug build, minimum-macOS compatibility, or public-release readiness.

## Current release-package evidence — 2026-08-12

- 76 XCTest cases passed with strict concurrency checking and source warnings treated as errors.
- `xcodebuild analyze` passed.
- Release app built as one universal Mach-O containing `arm64` and `x86_64`.
- The current-source `DayDrop-1.0.2.dmg` was mounted successfully; its Developer ID signature, hardened runtime, sandbox/bookmark/update entitlements, Sparkle helpers, AppIcon, `/Applications` shortcut, and `arm64`/`x86_64` application were verified.
- Apple notarization submission `16a09fa5-6b69-4b32-ac73-781c3e00ee37` returned `Accepted`. Stapler validation passed and Gatekeeper reports `Notarized Developer ID` for the DMG.
- Final SHA-256: `99ba88fc5d27b43df71890795ca592231a398e2c907d9607832ecf45fd8e9767`.
- Migration recovery tests cover persisted intent, exact source/destination identity, destination replacement, partial-merge resume, cancellation, symlink handling, and preservation of user-created parent folders.
- No systematic visual acceptance pass is claimed. User screenshots drove targeted fixes, but the complete state matrix still requires inspection.
