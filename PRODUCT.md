# DayDrop Product

## Purpose

DayDrop is a lightweight macOS menu-bar utility that keeps the user's Downloads folder tidy by moving completed top-level downloads into date-based folders. It also maintains a read-only, recursive local index so files saved directly into any nested Downloads subfolder remain searchable without being reorganized. Users can explicitly request a one-level deep reorganization only when they accept that existing folder grouping may be disrupted. The product promise is **“Downloads, day by day.”**

## Target users and outcomes

- macOS users who download files frequently in Safari, Chrome, Edge, or Firefox.
- People who want chronological organization without maintaining a rules engine.
- The desired outcome is a quiet, local-only Downloads folder whose recent files remain shallow and whose older files are progressively grouped by month and year.

## MVP scope

- First-run explanation, Downloads-folder authorization, login-item choice, and an explicit choice before existing files are organized.
- Event-driven monitoring of top-level files in the selected Downloads folder.
- A metadata-only recursive index of regular files and packages throughout the Downloads hierarchy. The index follows neither directory nor file symbolic links, never moves nested files, and remains active when automatic organization is paused.
- Recursive FSEvents notifications trigger debounced reconciliation scans. Startup reconciliation recovers changes made while DayDrop was not running; an incomplete scan never marks unseen items unavailable.
- File queries search names and relative paths across current files, files no longer found in Downloads, and deterministic file-type categories. Current files are the default scope.
- Persistent change detection distinguishes unambiguous rename, move, metadata modification, and newly discovered identities. A missing identity is conservatively reported as “moved out or deleted”; copies are new discoveries without an asserted source relationship.
- Conservative finalization checks: each eligible file is held through a two-second
  quiet window while a file-descriptor-backed monitor listens for writes, extension,
  attribute changes, rename, deletion, and revocation. Size and modification time must
  remain unchanged for the same window, and the advisory-lock and identity checks must
  still pass immediately before a move. A monitor that cannot start fails closed.
- A separate deep-organization action for existing files in the Downloads root and its immediate subfolders. It never recurses deeper and cannot run until the user accepts a second warning that the prior folder structure may be disrupted.
- Readable date routing to `Day YYYY-MM-DD/`, `Month YYYY-MM/Day YYYY-MM-DD/`,
  or `Year YYYY/Month YYYY-MM/Day YYYY-MM-DD/`.
- Migration of DayDrop-managed day folders as they cross the 14-day and year
  boundaries, including evidence-backed recovery and renaming of legacy
  numeric folders created or used by earlier DayDrop builds.
- Collision-safe moves, pause/resume, a complete interactive today list, notifications, and a permanent local operation history.
- A unified File Query destination for the recursive Downloads index and operation history. History search covers file names, paths, and failure reasons with success/failure and file-type filters, cursor-based paging, and CSV/JSON export of the current history query.
- Double-clicking a history record reveals the current file in Finder. If the item has since moved or been deleted, DayDrop opens the closest still-existing recorded directory and explains the fallback.
- Deterministic file-type categories based only on file metadata (`UTType` and extension). The first version does not inspect file contents or support user-defined tags.
- A Settings destination for login launch, completion notifications, automatic update checks, Downloads authorization, version information, and reopening the welcome/setup page.
- A capability-gated 搁这儿-ForNow integration on current Today rows and file-query records. DayDrop only offers item actions when Launch Services finds `com.fornow.app` and that bundle declares the supported external-file-import contract.
- A dedicated **扩展功能** Settings tab for the 搁这儿-ForNow product summary, availability state, additional connected capabilities, permission boundary, and product-homepage access.
- Manual and daily automatic checks for signed, notarized updates from the official HTTPS website; update checks never upload file names or file contents.

## Current interaction model

- The **今日下载** module is both a status surface and the Finder entry point for today's archive. Its title, empty state, and populated list area all open the same folder.
- Companion apps can request that same domain action through `daydrop://open-today-folder`. The URL does not expose a filesystem path or bypass Downloads authorization, ownership checks, or managed-folder persistence.
- When a compatible 搁这儿-ForNow build is installed, right-clicking an existing row under **今日下载**, **下载文件**, or **整理记录** offers **添加到搁这儿-ForNow**. DayDrop resolves the current item within the authorized Downloads root, refuses stale or missing records, and sends the file through the system open-document route without reading or writing the receiver's Application Support data.
- If today's archive folder does not yet exist, the open action creates it through the normal safe archive-preparation flow, writes the full-date ownership marker, persists its managed-folder identity, refreshes the today monitor, and then opens it.
- Frequently used login-launch and notification settings remain visible as compact controls in the main panel and are mirrored in the full Settings page. Both surfaces call the same runtime methods rather than maintaining independent UI-only state.
- The welcome/setup page opens automatically before first-run completion and can later be reopened from **设置 → 帮助 → 重新打开欢迎页面**. Reopening it does not erase existing authorization or automatically opt into organizing existing files.
- **立即整理现有文件** remains top-level only. **深度整理子文件夹…** is a separate destructive action; cancelling its confirmation performs no organization scan or move. Background read-only indexing is independent of both actions.

## Out of scope

File-type or website organization rules, multiple watched folders, recursive organization beyond one immediate subfolder level, custom date formats, file-content/full-text indexing, AI inspection, automatic renaming, content-based duplicate detection, cloud sync, browser extensions, automatic deletion, unattended automatic update installation, and undo are not part of the MVP.

## Success criteria

The MVP is successful when the 15 acceptance criteria in the supplied PRD can be demonstrated. In particular, incomplete downloads must never be moved, collisions must never overwrite data, a failed move must preserve the source, and denied folder access must stop processing.

## Open product questions

- [Decided] The production icon uses the user-selected blue archive-drawer character stored under `Design/SelectedIcon/`.
- [Decided] Completion notifications default off until the user enables them and macOS grants authorization.
- [Verified] The current DMG uses the locally installed Developer ID identity and passed Apple notarization with a stapled ticket.
- [Unknown] Final app-name ownership, bundle identifier, and distribution channel still require confirmation.
- [Unknown] Final notification copy still requires product-owner review.
- [Unknown] Browser-by-browser real-download acceptance requires a signed app and manual testing on a real Mac.
- [Unknown] macOS does not expose a universal “download complete” event. A download
  paused longer than the quiet window can still resemble a finalized file, so NDM and
  other download managers that write directly to their final path require live acceptance.
