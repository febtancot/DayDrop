---
title: DayDrop development progress knowledge base
created: 2026-08-12
source_type: conversation-code-and-tests
content_type: knowledge-base
status: current
tags:
  - source/user-conversation
  - source/current-workspace
  - content/knowledge-base
  - domain/daydrop
  - workflow/macos-development
  - stage/mvp-iteration
  - component/menu-bar-ui
  - component/archive-engine
  - artifact/progress-overview
  - status/current
related_raw_inputs:
  - ../raw/2026-08-12-current-development-progress.md
---

# DayDrop development progress knowledge base

## Executive summary

DayDrop's native macOS MVP is implemented and the current source passes 70 tests. The 2026-08-12 iteration added a dedicated Settings destination, a safely reopenable onboarding window, an interactive **今日下载** module that creates and opens today's managed folder, compact runtime-backed toggles, and npm automation that installs the Debug build into `/Applications` with a recoverable backup.

The installed development build and the distribution artifact are different evidence lanes. `/Applications/DayDrop.app` is currently an arm64 ad-hoc-signed Debug build. `dist/DayDrop-1.0.0.dmg` is a fresh universal Developer ID package containing the latest UI changes; Apple notarization returned `Accepted`, its ticket is stapled, and Gatekeeper reports `Notarized Developer ID`.

## Current user workflow

1. DayDrop starts from the menu bar and restores the security-scoped Downloads authorization.
2. **今日下载** shows today's files. Clicking its title, empty state, or list prepares today's managed folder if necessary and opens it in Finder.
3. The main panel offers manual organization, Downloads-folder access, recent history, Settings, pause/resume, and compact quick settings.
4. Settings mirrors the real login-launch and notification controls, supports Downloads reauthorization, and can reopen the welcome page.
5. Reopened onboarding preserves current authorization and does not organize existing files unless the user explicitly opts in and completes the action.

## Implementation and evidence map

| Area | Current implementation | Evidence | Remaining gate |
| --- | --- | --- | --- |
| Archive routing and migration | Full-date identity-bound routing and recovery | Unit/integration tests | Real filesystem/browser matrix |
| Today module | Safe create, persist, monitor, and Finder open | Source audit, successful build, and archive-engine tests | Dedicated Finder/UI automation and empty/populated visual inspection |
| Settings | Shared controller-backed launch and notification state | Build/tests and installed Debug run | Signed permission/login-item verification |
| Onboarding | First-run required window; later closable window; standard title bar | Build/tests and targeted source correction | Full scroll/resize/minimum-OS visual pass |
| Development install | Build, terminate, Trash backup, copy, signature verify, launch | Successful `npm run mac` runs | Backup retention policy |
| Distribution | Current-source universal Developer ID DMG with stapled Apple ticket | 70 tests, static analysis, signature/architecture/entitlement checks, notarization `Accepted` with zero issues, Gatekeeper `Notarized Developer ID` | Signed browser/permission/visual/minimum-OS/performance acceptance |

## Primary knowledge documents

- `PRODUCT.md`: scope, user outcomes, and current interaction model.
- `DOMAIN.md`: archive invariants and today-folder creation semantics.
- `TECH.md`: architecture, security boundaries, and build/install workflows.
- `PROJECT.md`: delivery status, milestones, risks, and next actions.
- `ACCEPTANCE.md`: separated automated, installed-development, signed-app, visual, and release evidence.
- `IMPROVEMENT.md`: prioritized follow-up work.

## Immediate next version

1. Complete a visual state matrix covering the main panel, compact toggles, empty and populated today lists, Settings, and scrolled/resized onboarding.
2. Run signed installed-app tests for folder authorization denial/recovery, login-item approval, notifications, and Safari/Chrome/Edge/Firefox downloads.
3. Validate the notarized package on the minimum macOS 13 runtime and representative Intel hardware.
4. Profile release-build idle CPU and resident memory before the final distribution decision.
