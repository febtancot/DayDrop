# DayDrop

**Downloads, day by day.**

DayDrop is a privacy-first macOS 13+ menu-bar app that waits for downloads to finish, then organizes top-level files in the user's Downloads folder by day, month, and year. Candidate files must remain quiet for two seconds under both per-file vnode monitoring and size/modification-date checks before the final lock and identity checks allow a move. A separate read-only index keeps files anywhere below Downloads searchable without moving them. An explicit deep-organization action can include files inside immediate subfolders only after a destructive-risk confirmation. File metadata, change history, and organization history stay local; the only network path is the optional Sparkle update check against DayDrop's HTTPS website.

## Current development workflow

Requirements:

- macOS with Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Node.js and npm for the convenience commands below

The normal local workflow is:

```sh
npm run mac       # build Debug, replace /Applications/DayDrop.app, and launch it
npm run build:mac # build Debug only
npm run test:mac  # generate the project and run the macOS XCTest suite
```

`npm run mac` is intentionally an install-and-run command, not just a build. It terminates the running DayDrop process, moves the previous `/Applications/DayDrop.app` into a timestamped folder under the current user's Trash, installs the arm64 ad-hoc-signed Debug build, verifies it, and launches the installed copy. The backup remains recoverable; the script does not permanently delete it.

To install a previously verified Release bundle, use `npm run install:mac -- --app /absolute/path/DayDrop.app`. The installer verifies the source signature and bundle identifier before stopping the old process, keeps a recoverable backup, and validates the copied app. Mount and verify the notarized DMG before selecting its contained app as the source.

The equivalent native commands remain available:

```sh
xcodegen generate
xcodebuild -project DayDrop.xcodeproj -scheme DayDrop \
  -destination 'platform=macOS,arch=arm64' test CODE_SIGNING_ALLOWED=NO
```

For interactive permission, notification, login-item, and browser tests, open `DayDrop.xcodeproj`, select a development team, build the `DayDrop` scheme, and run the signed app. The app asks the user to choose the standard Downloads folder and persists that consent with a security-scoped bookmark.

## Development UI snapshot

The menu-bar panel currently provides:

- A clickable **今日下载** module. Clicking its title, empty state, or file-list area creates today's managed folder when needed and opens it in Finder.
- A narrow local integration entry, `daydrop://open-today-folder`, for companion apps such as ForNow. Compatible requests may include a stable target-display ID so DayDrop can create the Finder window on the screen where the user clicked. DayDrop still owns authorization, safe folder preparation, managed-folder records, and the final Finder open; exact placement requires the user-authorized Finder automation permission and otherwise falls back to the standard open behavior.
- A reciprocal **搁这儿-ForNow** action on file rows. When a compatible build is installed, existing rows in **今日下载**, **下载文件**, and **整理记录** expose **添加到搁这儿-ForNow** in their right-click menus. Missing, moved, replaced, or out-of-root files are rejected instead of falling back to a recorded directory.
- A dedicated **扩展功能** Settings tab describing 搁这儿-ForNow, its current connection state, the additional capabilities unlocked after connection, local-data boundary, and verified product homepage `https://fornow.liveby.app`.
- Separate manual actions for safe top-level organization and opt-in deep organization. Deep organization covers the Downloads root plus files exactly one folder level below it, warns that existing grouping may be disrupted, and requires a second destructive confirmation.
- Downloads-folder access and a **文件查询** destination that defaults to a recursive current-file index, can include files no longer found under Downloads, and keeps permanent operation history as a separate scope.
- Recursive FSEvents-backed indexing detects unambiguous rename, move, modification, discovery/copy, and “moved out or deleted” changes through metadata reconciliation. Packages are one item; symbolic links are never followed; file contents are never read.
- File-type classification, search/filter, file-modification-time sorting in either direction, double-click Finder reveal, filtered operation-history CSV/JSON export, settings, pause/resume, and local status feedback. Pausing automatic organization does not pause read-only indexing.
- Compact launch-at-login and completion-notification switches with the same runtime-backed bindings in the main panel and Settings.
- A Settings destination for general controls, Downloads authorization, and reopening the welcome/setup page.
- **设置 → 通用 → 自动化 → 延迟整理** defaults off and persists across launches. When enabled, today's top-level downloads stay in place; yesterday's and older files are picked up at local midnight, wake, startup, or resume. They retain their download day, using the date added to Downloads, then creation date, then modification date. Missing or future dates wait. Pausing still stops automatic organization, while **立即整理现有文件** and the explicit deep action remain immediate.
- Version 1.4.0 adds **整理解压文件夹** (on by default): associate top-level ZIP/RAR/7z output folders with a remaining archive inside Downloads, verify their complete paths/types/sizes, wait ten quiet seconds, then archive each directory intact. Source archives already moved into DayDrop's managed folders remain usable. Ordinary, ambiguous, encrypted, multi-volume, linked, incomplete, or over-limit folders remain in place. Explicit deep organization also protects plausible incomplete extractions from being flattened. Archive manifests are read locally; folder contents are not uploaded or inspected as text.
- A shared opaque system-window surface for the main panel, File Query, and Settings. It follows macOS light/dark appearance while preventing highly translucent window materials from placing content directly over a bright desktop image.
- The current version in the menu footer and Settings, plus manual and daily automatic update checks powered by Sparkle 2. Updates require the HTTPS appcast, EdDSA signature, Developer ID signature, and Apple notarization to validate.
- A standard-titlebar onboarding window so scrolled content cannot overlap the window title or traffic-light controls.

## Distribution artifact status

`dist/DayDrop-1.4.0.dmg` is the current 2026-10-06 distribution artifact (build 12). It contains the universal `DayDrop.app` and an `/Applications` installation shortcut. Apple notarization submission `c9342ac8-7d66-4ac4-b21f-83aabb39a37b` returned `Accepted` with no reported issues. Developer ID signature checks, stapler validation, and Gatekeeper assessment passed for the DMG and mounted app. Package SHA-256: `a7bc32e23eb438bed97bc84ebf3bbe0ba58efe32fcc0e2cf46eea3cad412d229`.

Version 1.4.0 adds conservative ZIP/RAR/RAR5/7z extracted-folder recognition, ten-second tree stabilization, and intact folder moves that follow delay/pause settings. All 167 tests and Release static analysis passed with strict concurrency and source warnings treated as errors. The source archive must remain inside authorized Downloads; encrypted, multi-volume, ambiguous, unsafe, and over-limit cases remain untouched.

Cloudflare Pages `https://f7d58663.liveby-web.pages.dev` and `https://daydrop.liveby.app` passed homepage/feed version and complete-DMG hash verification. Cryptographic verification passed for the signed appcast, archive, and release notes. Browser DOM checks confirmed all current download links and no horizontal overflow at 1579 px and 390 px; this is not a screenshot-based visual acceptance pass.

The same notarized DMG was used to update `/Applications/DayDrop.app`. Installed version/build are 1.4.0/12; Developer ID/Gatekeeper checks passed, its executable hash matches the mounted package, and the installed-path process launched. The previous application was backed up under the user's Trash. Direct Sparkle UI installation, actual extraction-utility trials, real overnight/wake behavior, minimum-OS runtime compatibility, and broader signed-app acceptance remain separate checks.

`npm run release:mac` generates the notarized DMG, signed appcast, website checksum, and current-version homepage content. `npm run publish:web` explicitly deploys and verifies that prepared content. The Sparkle private key remains in the local login Keychain; only its public key is embedded in the app.

The selected app-icon master is `Design/SelectedIcon/DayDrop-AppIcon-Source-1254.png`. Xcode consumes the complete macOS icon set under `DayDrop/Resources/Assets.xcassets/AppIcon.appiconset/`.

Set and verify the intended version first. This updates `project.yml`,
`package.json`, `package-lock.json`, and the generated Xcode project together:

```sh
npm run version:set -- <next-x.y.z> <next-build>
npm run version:check -- --version <next-x.y.z> --build <next-build>
```

Then create that exact Developer ID distribution using the App Store Connect
`.p8` key configured by the local LiveBy release workflow:

```sh
npm run release:mac -- --version <next-x.y.z> --build <next-build>
```

Override `NOTARY_KEY`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER` when using another
API key. If polling is interrupted after upload, resume the same immutable DMG
without rebuilding or submitting again:

```sh
SUBMISSION_ID=<submission-uuid> npm run release:mac -- --version <next-x.y.z> --build <next-build>
```

Release parameters are mandatory and fail closed if they disagree with a source
version declaration. The built app, resumed DMG, final mounted DMG, and generated
Sparkle appcast are checked for both marketing version and build number. A new
submission must also use a build number greater than the latest Appcast entry.

Review the prepared static site, validate it without making remote changes, and
then explicitly publish it to the production Cloudflare Pages project:

```sh
npm run verify:web
npm run publish:web
```

`publish:web` deploys the complete `Product_Site` directory to Pages project
`daydrop`, then verifies the homepage version/download link, signed appcast, and
DMG SHA-256 against both the immutable deployment URL and
`https://daydrop.liveby.app`.

`Product_Site` is the complete production artifact set, including the current
DMG. Keep that DMG under version control so both the explicit Direct Upload flow
and Cloudflare's Git-triggered fallback can publish the same complete site. Push
release commits before running `publish:web`; prefix an unavoidable metadata-only
commit made after the final upload with `[CF-Pages-Skip]`, then confirm that the
canonical production deployment still passes the immutable and custom-domain
checks.

## Archive layout

```text
Downloads/
├── Day 2026-08-11/                                  # today through 14 natural days old
├── Month 2026-05/Day 2026-05-12/                    # older than 14 days, still in this year
└── Year 2025/Month 2025-03/Day 2025-03-21/          # a different year
```

The `Day`, `Month`, and `Year` prefixes make every level distinguishable in
Finder. DayDrop records the full calendar date for every folder it manages and
does not migrate user-created lookalike folders based on their names. During
upgrade, a legacy numeric folder is recovered only when a persisted successful
DayDrop operation still points to an existing file in that folder and resolves
to one unambiguous full date.

## Project references

- [PRODUCT.md](PRODUCT.md) — product purpose and boundaries
- [DOMAIN.md](DOMAIN.md) — archive rules and invariants
- [TECH.md](TECH.md) — architecture and verification commands
- [PROJECT.md](PROJECT.md) — current delivery state
- [ACCEPTANCE.md](ACCEPTANCE.md) — PRD acceptance evidence matrix
- [Development progress knowledge base](output/2026-08-12-development-progress-knowledge-base.md) — current cross-document implementation and evidence overview
- [Design/SelectedIcon](Design/SelectedIcon) — the user-selected app-icon master
- [Design/IconConcepts](Design/IconConcepts) — retained icon explorations
