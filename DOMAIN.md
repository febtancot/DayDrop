# DayDrop Domain

## Glossary

- **Archive root:** the user-authorized Downloads folder.
- **Top-level file:** a regular file directly inside the archive root; DayDrop never imports an existing folder.
- **Completion date:** the local calendar date when a new runtime download is confirmed complete.
- **Source date:** the creation date of a manually imported existing file, falling back to modification date.
- **Managed day folder:** a folder explicitly created or safely reclaimed by DayDrop, marked with its full `YYYY-MM-DD` date, and bound to a persisted filesystem identity.
- **Recent:** a source date whose natural-day distance from today is 0 through 14 inclusive.
- **Operation record:** one local success or failure entry for a file move.

## Core relationships

A file has one full source date. That date maps to one expected relative archive path. A managed day-folder record binds the full date to its current relative path, so a directory named `0811` is never interpreted without its recorded year.

## File lifecycle

1. A root-directory event reveals a previously unseen top-level file.
2. Temporary or hidden files remain ineligible.
3. Eligible files must have unchanged size across two checks and must not be exclusively locked by a cooperating process.
4. A completed runtime download receives today's local date; a manual import receives its file metadata date.
5. The file moves to the collision-safe destination and the managed-folder registry and operation history update.
6. Before a managed folder changes hierarchy, DayDrop atomically persists a migration intent with the expected destination state; startup recovery resumes or finalizes that intent without guessing from a numeric path.

## Today-folder entry behavior

Opening the **今日下载** module is a domain action, not only Finder navigation:

1. Resolve the current local calendar day and its expected `MMDD/` route.
2. Prepare the target with the same descendant, symlink, directory-identity, and ownership-marker checks used before file moves.
3. If DayDrop created the folder, persist the full-date managed-folder record before opening it.
4. If persistence fails, discard the newly prepared folder when it is still empty and identity-matched.
5. If a safe pre-existing unmarked user folder occupies today's path, open it without claiming it for whole-folder migration.
6. Refresh the today list and folder monitor, then open the prepared directory in Finder.

## Rules and invariants

- Calendar-day differences use the current macOS time zone; exactly 14 days old remains recent.
- A different year, including a future year, uses `YYYY/MM/MMDD/`.
- Only root-level regular files are imported; existing folders are not.
- A destination collision appends ` (n)` before the last extension and never overwrites.
- A failed move leaves the source in place.
- Normal scans never recursively reprocess archived content.
- Automatic migration touches only identity-bound, ownership-marked managed folders.
- A pre-existing unmarked destination may receive an individual file, but is never implicitly registered for later whole-folder migration.
- A migration target must either remain absent as recorded or retain the exact recorded identity and matching date marker.
- Only empty month/year containers explicitly marked as DayDrop-created are eligible for cleanup.
- The registry retains the full date even when the visible directory contains only month and day.
- Existing files present at app startup are excluded from automatic import unless the user explicitly requests manual organization.
- A user-triggered request to open today's folder may create an empty managed day folder, but it never moves existing root files or enables automatic organization by itself.

## Open domain questions

- [Unknown] The PRD does not define a retry expiry for files that never stabilize; the implementation should keep a bounded in-memory retry state and retry on later filesystem events.
- [Unknown] The behavior for creation dates later than modification dates is not specified; the literal creation-date-first rule is retained.
