# DayDrop Product

## Purpose

DayDrop is a lightweight macOS menu-bar utility that keeps the user's Downloads folder tidy by moving completed top-level downloads into date-based folders. The product promise is **“Downloads, day by day.”**

## Target users and outcomes

- macOS users who download files frequently in Safari, Chrome, Edge, or Firefox.
- People who want chronological organization without maintaining a rules engine.
- The desired outcome is a quiet, local-only Downloads folder whose recent files remain shallow and whose older files are progressively grouped by month and year.

## MVP scope

- First-run explanation, Downloads-folder authorization, login-item choice, and an explicit choice before existing files are organized.
- Event-driven monitoring of top-level files in the selected Downloads folder.
- Conservative download-completion checks and delayed retry when completion cannot be proven.
- Date routing to `MMDD/`, `MM/MMDD/`, or `YYYY/MM/MMDD/`.
- Migration of DayDrop-managed day folders as they cross the 14-day and year boundaries.
- Collision-safe moves, pause/resume, a complete interactive today list, notifications, and the latest 50 local operation records.
- A Settings destination for login launch, completion notifications, Downloads authorization, and reopening the welcome/setup page.

## Current interaction model

- The **今日下载** module is both a status surface and the Finder entry point for today's archive. Its title, empty state, and populated list area all open the same folder.
- If today's archive folder does not yet exist, the open action creates it through the normal safe archive-preparation flow, writes the full-date ownership marker, persists its managed-folder identity, refreshes the today monitor, and then opens it.
- Frequently used login-launch and notification settings remain visible as compact controls in the main panel and are mirrored in the full Settings page. Both surfaces call the same runtime methods rather than maintaining independent UI-only state.
- The welcome/setup page opens automatically before first-run completion and can later be reopened from **设置 → 帮助 → 重新打开欢迎页面**. Reopening it does not erase existing authorization or automatically opt into organizing existing files.

## Out of scope

File-type or website rules, multiple watched folders, custom date formats, AI inspection, renaming, duplicate detection, cloud sync, browser extensions, automatic deletion, and undo are not part of the MVP.

## Success criteria

The MVP is successful when the 15 acceptance criteria in the supplied PRD can be demonstrated. In particular, incomplete downloads must never be moved, collisions must never overwrite data, a failed move must preserve the source, and denied folder access must stop processing.

## Open product questions

- [Decided] The production icon uses the user-selected blue archive-drawer character stored under `Design/SelectedIcon/`.
- [Decided] Completion notifications default off until the user enables them and macOS grants authorization.
- [Verified] The current DMG uses the locally installed Developer ID identity and passed Apple notarization with a stapled ticket.
- [Unknown] Final app-name ownership, bundle identifier, and distribution channel still require confirmation.
- [Unknown] Final notification copy still requires product-owner review.
- [Unknown] Browser-by-browser real-download acceptance requires a signed app and manual testing on a real Mac.
