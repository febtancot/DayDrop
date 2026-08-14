# DayDrop Domain

## Glossary

- **Archive root:** the user-authorized Downloads folder.
- **Top-level file:** a regular file directly inside the archive root; DayDrop never imports an existing folder.
- **Completion date:** the local calendar date when a new runtime download is confirmed complete.
- **Source date:** the creation date of a manually imported existing file, falling back to modification date.
- **Managed day folder:** a folder explicitly created or safely reclaimed by DayDrop, marked with its full `YYYY-MM-DD` date, and bound to a persisted filesystem identity.
- **Recent:** a source date whose natural-day distance from today is 0 through 14 inclusive.
- **Operation record:** one permanent local success or failure entry for a file move or managed-folder migration, including its deterministic file-type category and trigger.
- **Indexed download file:** one metadata-only record for a regular file or package anywhere under Downloads, including filesystem identity, relative path, type, size, dates, first/last seen time, and current availability.
- **File change:** a reconciliation result: discovered, renamed, moved, modified, or unavailable. “Unavailable” means only that the item is no longer found under the authorized Downloads root; it does not claim deletion.

## Core relationships

A file has one full source date. That date maps to one expected relative archive path. A managed day-folder record binds the full date to its current relative path. Visible folder names use `Day`, `Month`, and `Year` prefixes plus complete ISO-style dates so their meaning remains clear outside the hierarchy.

## File lifecycle

1. A root-directory event reveals a previously unseen top-level file.
2. Temporary or hidden files remain ineligible.
3. DayDrop opens an event-only descriptor for the candidate inode. Writes, extension,
   attribute changes, rename, deletion, or revocation restart or invalidate finalization.
4. File size and modification time must remain unchanged for two seconds while the
   descriptor monitor is also quiet. Failure to start or retain the monitor fails closed.
5. Immediately before moving, DayDrop revalidates path identity and metadata and must
   acquire an advisory lock. A completed runtime download receives today's local date;
   a manual import receives its file metadata date.
6. The file moves to the collision-safe destination and the managed-folder registry and operation history update.
7. Before a managed folder changes hierarchy, DayDrop atomically persists a migration intent with the expected destination state; startup recovery resumes or finalizes that intent without guessing from a numeric path.
8. During the readable-name upgrade, an unregistered legacy numeric folder may
   be recovered only when a persisted successful operation still points to an
   existing file inside it and the operation date resolves the old route to one
   unambiguous full date. The folder then receives the normal ownership marker
   and follows the same restartable migration path.

## Read-only index lifecycle

1. Start recursive FSEvents monitoring before a startup or reauthorization scan so changes during the scan cause a follow-up reconciliation.
2. The first successful scan establishes the current baseline without claiming that every existing file was newly created.
3. Later scans match an exact path and filesystem identity first. A unique remaining identity on both sides can then establish a rename or move.
4. A new identity is discovered; a matched identity with changed size, modification date, type, or package state is modified.
5. An unmatched previously present identity becomes unavailable. DayDrop does not guess whether the user deleted it or moved it outside Downloads.
6. Packages are indexed as single items. Symbolic links are ignored and never followed.
7. Any enumeration or metadata-read failure aborts reconciliation, preserving the last complete index until a later scan succeeds.

## Today-folder entry behavior

Opening the **今日下载** module is a domain action, not only Finder navigation:

1. Resolve the current local calendar day and its expected `Day YYYY-MM-DD/` route.
2. Prepare the target with the same descendant, symlink, directory-identity, and ownership-marker checks used before file moves.
3. If DayDrop created the folder, persist the full-date managed-folder record before opening it.
4. If persistence fails, discard the newly prepared folder when it is still empty and identity-matched.
5. If a safe pre-existing unmarked user folder occupies today's path, open it without claiming it for whole-folder migration.
6. Refresh the today list and folder monitor, then open the prepared directory in Finder.

## Rules and invariants

- Calendar-day differences use the current macOS time zone; exactly 14 days old remains recent.
- A different year, including a future year, uses
  `Year YYYY/Month YYYY-MM/Day YYYY-MM-DD/`.
- A same-year date older than 14 natural days uses
  `Month YYYY-MM/Day YYYY-MM-DD/`; a recent date remains a shallow
  `Day YYYY-MM-DD/` folder.
- Only root-level regular files are imported; existing folders are not.
- A destination collision appends ` (n)` before the last extension and never overwrites.
- A failed move leaves the source in place.
- Operation history is retained locally without an automatic age or count limit. Search, filtering, and export never change or delete downloaded files.
- The recursive file index and its change log are retained locally without reading file contents. Indexing never makes a file eligible for automatic or manual organization.
- Pausing automatic organization stops automatic moves but does not pause the read-only index.
- A copy is recorded as a newly discovered identity; DayDrop does not claim which existing file was its source.
- Same-parent path changes are called renames and cross-parent path changes are called moves only when one remaining old item and one remaining new item share a unique filesystem identity. Ambiguous hard-link cases remain separate discoveries/unavailable records.
- File-type classification uses only the file name extension and system type declaration; it does not read file contents and does not affect archive routing.
- Organization scans never recursively reprocess archived content. Read-only search indexing intentionally includes DayDrop archive folders so the query surface covers the complete Downloads hierarchy.
- Automatic migration touches only identity-bound, ownership-marked managed folders.
- A pre-existing unmarked destination may receive an individual file, but is
  never registered from its name alone. The readable-name upgrade may recover
  it only from unambiguous persisted operation evidence as described above.
- A migration target must either remain absent as recorded or retain the exact recorded identity and matching date marker.
- Only empty month/year containers explicitly marked as DayDrop-created are eligible for cleanup.
- The registry retains the full date even when the visible directory contains only month and day.
- Existing files present at app startup are excluded from automatic import unless the user explicitly requests manual organization.
- Filesystem quietness is evidence that writes have stopped, not a universal download
  completion protocol. A non-cooperating writer may pause longer than the quiet window;
  real download-manager compatibility remains an independent acceptance requirement.
- A user-triggered request to open today's folder may create an empty managed day folder, but it never moves existing root files or enables automatic organization by itself.

## Open domain questions

- [Unknown] The PRD does not define a retry expiry for files that never stabilize; the implementation should keep a bounded in-memory retry state and retry on later filesystem events.
- [Unknown] The behavior for creation dates later than modification dates is not specified; the literal creation-date-first rule is retained.
