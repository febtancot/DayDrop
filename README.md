# DayDrop

**Downloads, day by day.**

DayDrop is a privacy-first macOS 13+ menu-bar app that waits for downloads to finish, then organizes top-level files in the user's Downloads folder by day, month, and year. File organization and history stay local; the only network path is the optional Sparkle update check against DayDrop's HTTPS website.

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
- The current version in the menu footer and Settings, plus manual and daily automatic update checks powered by Sparkle 2. Updates require the HTTPS appcast, EdDSA signature, Developer ID signature, and Apple notarization to validate.
- A standard-titlebar onboarding window so scrolled content cannot overlap the window title or traffic-light controls.

## Distribution artifact status

`dist/DayDrop-1.0.1.dmg` is the current 2026-08-12 distribution artifact. It contains the latest universal `DayDrop.app` and an `/Applications` installation shortcut. The app and DMG are timestamped with the installed Developer ID identity; Apple notarization returned `Accepted`, the ticket is stapled, and Gatekeeper reports `Notarized Developer ID`. Its SHA-256 is `f26edc3cb9f8ebb54a12471e44354cee7e2a98235eb55e49046597b972b72c32`. Browser, permission, login-item, notification, visual, minimum-OS, and performance acceptance remain separate release gates.

The source is now version 1.0.2 (build 3). It adds in-app version display and Sparkle updates, but it has not yet replaced the published 1.0.1 DMG. `npm run release:mac` generates the notarized DMG and a signed website appcast; `npm run appcast:mac` can regenerate the feed for an already notarized artifact. The Sparkle private key is stored in the local login Keychain under `com.liuyuhang.DayDrop`; only the public key is embedded in the app.

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
