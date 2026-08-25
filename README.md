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
- File-type classification, search/filter, double-click Finder reveal, filtered operation-history CSV/JSON export, settings, pause/resume, and local status feedback. Pausing automatic organization does not pause read-only indexing.
- Compact launch-at-login and completion-notification switches with the same runtime-backed bindings in the main panel and Settings.
- A Settings destination for general controls, Downloads authorization, and reopening the welcome/setup page.
- The current version in the menu footer and Settings, plus manual and daily automatic update checks powered by Sparkle 2. Updates require the HTTPS appcast, EdDSA signature, Developer ID signature, and Apple notarization to validate.
- A standard-titlebar onboarding window so scrolled content cannot overlap the window title or traffic-light controls.

## Distribution artifact status

`dist/DayDrop-1.2.1.dmg` is the current 2026-08-26 distribution artifact. It contains the universal `DayDrop.app` and an `/Applications` installation shortcut. The app and DMG are timestamped with the installed Developer ID identity; Apple notarization submission `ee3c0335-c67f-4093-b164-7538ffe0ccf1` returned `Accepted` with no reported issues, the ticket is stapled, and Gatekeeper reports `Notarized Developer ID`. Its SHA-256 is `bcc20f2ff25fa81ce8402a9b967f039ec3b6fe3a25333ca68fd625da5f112dda`. A three-display installed Debug run opened the managed-day Finder window on the Mi Monitor after an actual ForNow capsule click and on the Studio Display through the same target-display contract; WindowServer bounds confirmed both physical-screen placements. The permission-denied path, display unplug/replug behavior, DayDrop-row-to-ForNow context menu, Settings visual inspection, login item, notification, broader visual, minimum-OS, and large-tree performance remain separate acceptance gates.

Version 1.2.1 (build 9) lets compatible callers attach a stable target-display ID to `daydrop://open-today-folder`. DayDrop preserves its Downloads authorization and safe folder preparation, then positions a new Finder window on the requested display when Finder automation is available; a stale display ID or denied automation permission falls back to the standard open behavior. `npm run release:mac` generates the notarized DMG, signed appcast, website checksum, and current-version homepage content, but intentionally does not deploy. `npm run appcast:mac` can regenerate the website release content for an already notarized artifact. The Sparkle private key is stored in the local login Keychain under `com.liuyuhang.DayDrop`; only the public key is embedded in the app.

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
