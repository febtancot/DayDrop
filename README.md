# DayDrop

**Downloads, day by day.**

DayDrop is a local-only macOS 13+ menu-bar app that waits for downloads to finish, then organizes top-level files in the user's Downloads folder by day, month, and year.

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
- Manual organization, Downloads-folder access, recent operation history, settings, pause/resume, and local status feedback.
- Compact launch-at-login and completion-notification switches with the same runtime-backed bindings in the main panel and Settings.
- A Settings destination for general controls, Downloads authorization, and reopening the welcome/setup page.
- A standard-titlebar onboarding window so scrolled content cannot overlap the window title or traffic-light controls.

## Distribution artifact status

`dist/DayDrop-1.0.0.dmg` is the current 2026-08-12 distribution candidate. It contains the latest universal `DayDrop.app` and an `/Applications` installation shortcut. The app and DMG are timestamped with the installed Developer ID identity; Apple notarization returned `Accepted`, the ticket is stapled, and Gatekeeper reports `Notarized Developer ID`. Browser, permission, login-item, notification, visual, minimum-OS, and performance acceptance remain separate release gates.

The selected app-icon master is `Design/SelectedIcon/DayDrop-AppIcon-Source-1254.png`. Xcode consumes the complete macOS icon set under `DayDrop/Resources/Assets.xcassets/AppIcon.appiconset/`.

Create the complete Developer ID distribution using the App Store Connect `.p8`
key configured by the local LiveBy release workflow:

```sh
npm run release:mac
```

Override `NOTARY_KEY`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER` when using another
API key. If polling is interrupted after upload, resume the same immutable DMG
without rebuilding or submitting again:

```sh
SUBMISSION_ID=<submission-uuid> npm run release:mac
```

## Archive layout

```text
Downloads/
├── 0811/                  # today through 14 natural days old
├── 05/0512/               # older than 14 days, still in this year
└── 2025/03/0321/          # a different year
```

DayDrop records the full calendar date for every folder it manages. It does not infer a year from a numeric directory name and does not migrate user-created lookalike folders.

## Project references

- [PRODUCT.md](PRODUCT.md) — product purpose and boundaries
- [DOMAIN.md](DOMAIN.md) — archive rules and invariants
- [TECH.md](TECH.md) — architecture and verification commands
- [PROJECT.md](PROJECT.md) — current delivery state
- [ACCEPTANCE.md](ACCEPTANCE.md) — PRD acceptance evidence matrix
- [Development progress knowledge base](output/2026-08-12-development-progress-knowledge-base.md) — current cross-document implementation and evidence overview
- [Design/SelectedIcon](Design/SelectedIcon) — the user-selected app-icon master
- [Design/IconConcepts](Design/IconConcepts) — retained icon explorations
