# DayDrop Technical Baseline

## Architecture summary

The native MVP uses a SwiftUI `MenuBarExtra` with window style, an AppKit folder picker, Foundation file operations, file-descriptor-backed Dispatch sources, ServiceManagement login-item APIs, and UserNotifications. Pure date/path, eligibility, stability, and collision logic is independently tested.

Automatic discovery and the ordinary manual action remain root-only. The opt-in deep action performs one bounded expansion into immediate, non-hidden, non-package, non-symbolic-link subfolders; it skips DayDrop-owned archive roots. Pending nested candidates retain their exact file-system identity and are revalidated at a maximum depth of two before the archive engine reacquires its advisory lock and moves them.

## Components

- **App/UI:** menu-bar popover, standard-titlebar onboarding window, clickable today module, activity history, full Settings destination, current-version display, manual update action, and a shared compact toggle style.
- **Coordinator:** owns user-visible state, first-run/session baselines, retries, day changes, moves, migration, and UI refreshes.
- **Folder access:** creates and resolves a security-scoped bookmark chosen through `NSOpenPanel`.
- **Monitor:** watches the root and current-day folder without polling while idle; pending candidates use a short retry timer.
- **Archive engine:** calculates routes, rejects path traversal and symbolic-link archive components, validates volume/inode identities, holds advisory locks through file moves, and performs restartable managed-folder migrations.
- **Local stores:** managed-folder metadata and the latest 50 operation records, stored only in the app container.
- **Updater:** Sparkle 2.9.5 reads the HTTPS appcast, verifies the signed feed and release notes, validates the EdDSA-signed archive before extraction, then uses its installer XPC service to replace the sandboxed app.

## Data and control flow

Filesystem event → debounced root scan → eligibility/stability checks → route planning → collision-safe move → registry/history persistence → today-list refresh → optional batch notification.

User-driven today-folder flow: today-module click → safe target preparation → ownership-policy evaluation → managed-folder persistence when newly created → today-monitor refresh → Finder open.

Settings/onboarding flow: main panel → Settings → reopen welcome page. First-run onboarding is non-closable until completion; a later reopened window is closable and preserves existing authorization. Both quick toggles and Settings toggles bind to `DayDropController` runtime methods.

## Stack and platform

- Swift and SwiftUI/AppKit
- macOS 13 Ventura or later
- Apple Silicon and Intel (`ARCHS_STANDARD`)
- Sparkle 2.9.5, pinned through Swift Package Manager
- XcodeGen is used only to generate the checked-out Xcode project from `project.yml`.

## Security, privacy, reliability, and performance

- App Sandbox with user-selected read/write access, app-scoped bookmark entitlement, Sparkle installer mach-service exceptions, and a persistent security-scoped bookmark.
- No file-content upload. The network client entitlement is used only to retrieve the HTTPS appcast, signed release notes, and signed/notarized update package when update checks are enabled.
- Atomic local metadata writes, persisted migration intent, source/destination identity checks, ownership xattrs, source-preserving failures, collision-safe names, and an immediate pause when metadata or directory safety checks fail.
- Dispatch filesystem events keep idle CPU near zero; UI refresh after relevant events targets two seconds.
- Automatic update checks default on at a 24-hour interval and remain user-controllable in Settings; automatic installation remains off.
- [Unknown] The under-50-MB memory target and browser-specific behavior require measurement in a signed release-like build.

## Verified commands

The following workflow is exercised against the generated project:

```sh
npm run test:mac
npm run build:mac
xcodebuild -project DayDrop.xcodeproj -scheme DayDrop \
  -configuration Release -destination 'generic/platform=macOS' \
  build CODE_SIGNING_ALLOWED=NO ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO
```

For iterative installed-app testing:

```sh
npm run mac
```

This command generates and builds the arm64 Debug app, terminates DayDrop, moves the existing installed app to a recoverable timestamped Trash backup, copies the Debug app to `/Applications/DayDrop.app`, verifies its ad-hoc signature, and starts that exact installed path. It is development automation, not a release packaging or notarization command.

## Technical decisions and open questions

- `SMAppService.mainApp` is the macOS 13+ login-item API.
- Persistent Downloads access uses a security-scoped folder bookmark rather than assuming unrestricted home-directory access.
- Startup and resume capture a file-identity baseline before monitoring, so offline or paused files require explicit manual organization.
- The app is sandboxed and hardened; Downloads access is user-selected read/write only.
- The current universal DMG is timestamped with `Developer ID Application: Xueliu Shen (8NF4K823FV)`. App Store Connect `.p8` authentication was used for notarization; Apple returned `Accepted`, the ticket is stapled, and Gatekeeper reports `Notarized Developer ID` for both the DMG and contained app.
- The current `/Applications/DayDrop.app` used during development is an arm64 ad-hoc-signed Debug build installed by `npm run mac`; its successful launch does not prove Developer ID, Gatekeeper, notarization, Intel, or minimum-macOS release behavior.
- Path identities are revalidated immediately before and throughout recursive operations. A fully adversarial same-path replacement race would require a future file-descriptor-relative `openat`/`renameat` implementation; this is tracked separately from normal Downloads-folder operation.
- `npm run version:set -- <version> <build>` updates `project.yml`, both npm manifest/lock declarations, and the generated Xcode project as one rollback-protected operation; `version:check` verifies them before release.
- `npm run release:mac -- --version <version> --build <build>` requires an explicit release intent and performs version preflight, credential preflight, tests, static analysis, universal build, app/DMG version verification, entitlement/signature validation, immutable submission tracking, notarization recovery, stapling, Gatekeeper checks, mounted-content verification, and final SHA-256 generation.
- The release workflow also re-signs Sparkle's nested helpers with the same Developer ID identity, generates `Product_Site/updates/appcast.xml` with EdDSA signatures, stages the DMG/checksum, updates every homepage release reference from the project version, and runs a cross-artifact consistency check. The private update key never enters the repository or website.
- Deployment remains an explicit second step: `npm run publish:web` first revalidates local release content, deploys `Product_Site` to the `daydrop` Cloudflare Pages project, and then downloads and verifies the homepage, appcast, and complete DMG from both the immutable deployment URL and production custom domain.
- [Unknown] Mac App Store entitlements and distribution-channel automation await distribution decisions.
