# DayDrop MVP Acceptance Matrix

This matrix separates deterministic automated evidence from signed-app and real-browser evidence. A passing build is not treated as proof of permissions, login-item registration, notifications, or browser behavior.

| PRD | Acceptance criterion | Planned evidence | Status |
| --- | --- | --- | --- |
| AC-01 | Safari, Chrome, Edge, and Firefox completed downloads are organized | Signed app, four real-browser downloads | Manual pending |
| AC-02 | Temporary/incomplete downloads are not moved | Temporary-suffix tests; deterministic quiet-window tests; real vnode write/rename/delete monitoring tests; advisory-lock and identity checks; live partial/paused NDM download still required | Automated strengthened; NDM manual pending |
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

## History, classification, query, and export

| ID | Acceptance criterion | Evidence | Status |
| --- | --- | --- | --- |
| HS-01 | More than 100 records remain queryable and restart-persistent | SQLite store pagination/persistence tests | Automated pass |
| HS-02 | Existing bounded JSON records import once by stable UUID | Repeated legacy-import test | Automated pass |
| HS-03 | File name/path/error search composes with outcome and file-type filters | Composed query tests | Automated pass |
| HS-04 | Common documents, media, archives, disk images, installers, code, and data classify without reading contents | Deterministic classifier tests | Automated pass |
| HS-05 | Current query exports to UTF-8 CSV and structured JSON | Filtered export tests | Automated pass |
| HS-06 | Search, filtering, paging, and export are usable in the installed menu-bar UI | Signed/ad-hoc installed-app visual and interaction pass required | Manual pending |
| HS-07 | History remains local and works with networking disabled | Source boundary plus network-disabled installed-app test | Architectural pass; manual pending |
| HS-08 | Double-clicking a history record reveals the existing result in Finder, prefers the source for a failed move, and opens the recorded directory when the item no longer exists | Bounded path-resolution tests and static SwiftUI action audit; installed-app interaction required | Automated pass; manual interaction pending |
| FI-01 | Files saved at any Downloads depth become searchable without being moved | Recursive scanner and store-query tests; installed-app nested-save test required | Automated pass; manual interaction pending |
| FI-02 | Packages are one item and symbolic links are never followed | Package/symlink recursive scanner tests | Automated pass |
| FI-03 | Rename, move, modification, new copy/discovery, and unavailable transitions reconcile transactionally | SQLite reconciliation and change-log tests | Automated pass |
| FI-04 | Copy provenance and delete-vs-move-out are not guessed; hard-link ambiguity cannot become a false move | Ambiguous identity regression test and domain/source audit | Automated boundary pass |
| FI-05 | First scan is a quiet baseline; later startup scans recover offline changes; incomplete scans preserve the prior complete index | Store baseline/restart tests and scanner fail-closed audit; process-offline manual test required | Automated/static pass; manual pending |
| FI-06 | Recursive indexing continues while automatic organization is paused and never makes nested files organization candidates | Separate monitor/control-path audit; installed-app pause test required | Architectural pass; manual pending |
| FI-07 | Current, unavailable, name/path, and file-type queries page persistently across restart | SQLite query/paging/reopen tests | Automated pass |
| FI-08 | Nested file changes generate a real recursive FSEvents callback | Temporary nested-directory integration test | Automated pass |
| DF-01 | Deep organization includes root files and files exactly one subfolder level down only after a second structure-risk confirmation | Scanner/source-depth tests, managed-root exclusion audit, SwiftUI action audit, and interactive cancel/confirm check | Automated boundary and static UI pass; interactive pending |
| UP-01 | Current version and build are visible in the menu and Settings | Bundle-version regression test and rendered Settings inspection | Automated and visual pass |
| UP-02 | Manual and daily checks use the signed official HTTPS feed without uploading file data | Live Sparkle log, online feed verification, entitlement and source audit | Live feed pass; update-install pending |
| UP-03 | Published update metadata and packages cannot be substituted by a website-only compromise | Signed appcast/release-notes/archive verification, Developer ID, notarization, extraction-before-validation setting | Cryptographic pipeline pass; end-to-end install pending |
| UP-04 | Homepage, current DMG, checksum, and latest appcast entry always publish the same version | Local preflight plus immutable Pages URL and production-domain download verification | Automated and live deployment pass |

## Current development evidence — 2026-08-13

- The 2026-08-14 source adds per-file vnode finalization monitoring and a two-second
  metadata/event quiet window. Tests cover a preallocated same-size file receiving an
  in-place write, rename continuity, deletion invalidation, symlink/directory fail-closed
  behavior, modification-time reset, and delayed-event ordering. This does not yet prove
  NDM behavior in a signed live download.

- The current source passes 103 XCTest cases with 0 failures on arm64 macOS.
- Recursive index coverage includes arbitrary nesting, hidden files, package boundaries, symbolic-link exclusion, first-scan baseline, persistent reopen, current/unavailable search, type filters, cursor paging, rename/move/modify/discover/unavailable transitions, hard-link ambiguity, and a real nested FSEvents callback.
- The recursive index UI and pause/offline flows still require installed-app interaction and visual acceptance. Automated success does not establish large-tree performance or release-package behavior.
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

## Current release-package evidence — 2026-08-14

- 106 XCTest cases passed with strict concurrency checking and source warnings treated as errors.
- `xcodebuild analyze` passed.
- Release app built as one universal Mach-O containing `arm64` and `x86_64`.
- The current-source `DayDrop-1.1.1.dmg` was mounted successfully; its Developer ID signature, hardened runtime, sandbox/bookmark/update entitlements, Sparkle helpers, AppIcon, `/Applications` shortcut, and `arm64`/`x86_64` application were verified.
- Apple notarization submission `dcb34325-26b6-4269-a52c-eeab18884b8e` returned `Accepted` with no reported issues. Stapler validation passed and Gatekeeper reports `Notarized Developer ID` for both the DMG and mounted app.
- Final SHA-256: `0c587e4af72dd2a2c3c69a4d71901a4277de15aa89e6f72da796ae6809cf7fa4`.
- The signed Appcast advertises DayDrop 1.1.1 build 6 at `https://daydrop.liveby.app/downloads/DayDrop-1.1.1.dmg`. Cloudflare Pages deployment `https://52746232.liveby-web.pages.dev` and the production custom domain were both verified by downloading the homepage, Appcast, and complete DMG and comparing version, build, URL, and SHA-256.
- Migration recovery tests cover persisted intent, exact source/destination identity, destination replacement, partial-merge resume, cancellation, symlink handling, and preservation of user-created parent folders.
- No systematic visual acceptance pass is claimed. User screenshots drove targeted fixes, but the complete state matrix still requires inspection.
