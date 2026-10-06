import SQLite3
import XCTest
@testable import DayDrop

final class DownloadsIndexStoreTests: XCTestCase {
    func testDuplicateScanEntriesDoNotPersistDuplicateCurrentPaths() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)
        let file = snapshot(identity: "1:99", path: "report.txt", size: 10)
        let first = try await store.reconcile([file, file])
        XCTAssertEqual(first.indexedFileCount, 1)
        let page = try await store.page()
        XCTAssertEqual(page.totalCount, 1)
        // A restart used to trap when rebuilding the path dictionary.
        let restarted = try DownloadsIndexStore(databaseURL: databaseURL)
        let second = try await restarted.reconcile([file])
        XCTAssertEqual(second.changeCount, 0)
    }

    func testExistingDuplicatePathsRecoverOnRestartWithoutDeletingHistory() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)
        _ = try await store.reconcile([])
        let file = snapshot(identity: "1:99", path: "report.txt", size: 10)
        _ = try await store.reconcile([file])
        let originalPage = try await store.page()
        let original = try XCTUnwrap(originalPage.records.first)
        let originalChanges = try await store.changes()
        try duplicateCurrentRecord(original.id, in: databaseURL)

        let restarted = try DownloadsIndexStore(databaseURL: databaseURL)
        let summary = try await restarted.reconcile([file])
        let current = try await restarted.page()
        let all = try await restarted.page(filter: DownloadFileFilter(presence: .all))
        let changes = try await restarted.changes()
        XCTAssertEqual(summary.indexedFileCount, 1)
        XCTAssertEqual(summary.unavailable, 1)
        XCTAssertEqual(current.records.map(\.id), [original.id])
        XCTAssertEqual(all.totalCount, 2)
        XCTAssertTrue(Set(originalChanges.map(\.id)).isSubset(of: Set(changes.map(\.id))))
        let repeated = try await restarted.reconcile([file])
        XCTAssertEqual(repeated.changeCount, 0)
    }

    func testConflictingScanPreservesLastCompleteIndexAndHistory() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)
        let file = snapshot(identity: "1:99", path: "report.txt", size: 10)
        _ = try await store.reconcile([file])
        let originalPage = try await store.page()
        let originalChanges = try await store.changes()

        for conflicting in [
            snapshot(identity: "1:100", path: "report.txt", size: 10),
            snapshot(identity: "1:99", path: "report.txt", size: 20)
        ] {
            do {
                _ = try await store.reconcile([file, conflicting])
                XCTFail("An inconsistent scan must be rejected")
            } catch DownloadsIndexStoreError.conflictingSnapshots {
                // The controller catches this recoverable error and continues startup.
            }
            let currentPage = try await store.page()
            let changes = try await store.changes()
            XCTAssertEqual(currentPage, originalPage)
            XCTAssertEqual(changes, originalChanges)
        }
    }

    func testDuplicateRecoveryDoesNotInventMoveToNewHardLink() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)
        let file = snapshot(identity: "1:99", path: "report.txt", size: 10)
        _ = try await store.reconcile([file])
        let page = try await store.page()
        let original = try XCTUnwrap(page.records.first)
        try duplicateCurrentRecord(original.id, in: databaseURL)

        let hardLink = snapshot(identity: "1:99", path: "link.txt", size: 10)
        let summary = try await store.reconcile([file, hardLink])
        let current = try await store.page()
        XCTAssertEqual(summary.indexedFileCount, 2)
        XCTAssertEqual(summary.discovered, 1)
        XCTAssertEqual(summary.unavailable, 1)
        XCTAssertEqual(summary.renamed, 0)
        XCTAssertEqual(summary.moved, 0)
        XCTAssertEqual(Set(current.records.map(\.relativePath)), ["report.txt", "link.txt"])
    }

    func testSamePathReplacementRecoversFromDuplicateOldRows() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)
        _ = try await store.reconcile([snapshot(identity: "1:99", path: "report.txt", size: 10)])
        let page = try await store.page()
        try duplicateCurrentRecord(try XCTUnwrap(page.records.first).id, in: databaseURL)

        let replacement = snapshot(identity: "1:100", path: "report.txt", size: 20)
        let summary = try await store.reconcile([replacement])
        let current = try await store.page()
        let all = try await store.page(filter: DownloadFileFilter(presence: .all))
        XCTAssertEqual(summary.discovered, 1)
        XCTAssertEqual(summary.unavailable, 2)
        XCTAssertEqual(current.records.map(\.fileSystemIdentity), ["1:100"])
        XCTAssertEqual(all.totalCount, 3)
        let repeated = try await store.reconcile([replacement])
        XCTAssertEqual(repeated.changeCount, 0)
    }

    func testCanonicallyEquivalentDuplicatePathsAreCoalesced() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)
        let composed = snapshot(identity: "1:99", path: "caf\u{00E9}.txt", size: 10)
        let decomposed = snapshot(identity: "1:99", path: "cafe\u{0301}.txt", size: 10)
        let summary = try await store.reconcile([composed, decomposed])
        XCTAssertEqual(summary.indexedFileCount, 1)
        let repeated = try await store.reconcile([decomposed])
        XCTAssertEqual(repeated.changeCount, 0)
    }

    private func duplicateCurrentRecord(_ id: UUID, in databaseURL: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let sql = """
            INSERT INTO indexed_files
            SELECT '\(UUID().uuidString)', file_system_identity, relative_path, file_name,
                   size, creation_date, modification_date, file_category, classifier_version,
                   is_package, first_seen_at + 1, last_seen_at, is_present, unavailable_since
            FROM indexed_files WHERE id = '\(id.uuidString)';
            """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }

    func testReconciliationRecordsRenameMoveModifyCopyAndUnavailable() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)
        let start = Date(timeIntervalSince1970: 1_000)

        let original = snapshot(
            identity: "1:10",
            path: "draft.txt",
            size: 10,
            modifiedAt: start
        )
        let baseline = try await store.reconcile([original], observedAt: start)
        XCTAssertEqual(baseline.indexedFileCount, 1)
        XCTAssertEqual(baseline.changeCount, 0)
        let baselineChanges = try await store.changes()
        XCTAssertTrue(baselineChanges.isEmpty)

        let renamed = snapshot(
            identity: "1:10",
            path: "final.txt",
            size: 10,
            modifiedAt: start
        )
        let renameSummary = try await store.reconcile(
            [renamed],
            observedAt: start.addingTimeInterval(1)
        )
        XCTAssertEqual(renameSummary.renamed, 1)

        let moved = snapshot(
            identity: "1:10",
            path: "Project/final.txt",
            size: 10,
            modifiedAt: start
        )
        let moveSummary = try await store.reconcile(
            [moved],
            observedAt: start.addingTimeInterval(2)
        )
        XCTAssertEqual(moveSummary.moved, 1)

        let modified = snapshot(
            identity: "1:10",
            path: "Project/final.txt",
            size: 25,
            modifiedAt: start.addingTimeInterval(3)
        )
        let modifySummary = try await store.reconcile(
            [modified],
            observedAt: start.addingTimeInterval(3)
        )
        XCTAssertEqual(modifySummary.modified, 1)

        let copied = snapshot(
            identity: "1:11",
            path: "Project/final copy.txt",
            size: 25,
            modifiedAt: start.addingTimeInterval(3)
        )
        let copySummary = try await store.reconcile(
            [modified, copied],
            observedAt: start.addingTimeInterval(4)
        )
        XCTAssertEqual(copySummary.discovered, 1)

        let unavailableSummary = try await store.reconcile(
            [copied],
            observedAt: start.addingTimeInterval(5)
        )
        XCTAssertEqual(unavailableSummary.unavailable, 1)

        let changes = try await store.changes()
        XCTAssertEqual(changes.map(\.kind), [
            .unavailable, .discovered, .modified, .moved, .renamed
        ])
        XCTAssertEqual(changes.last?.oldRelativePath, "draft.txt")
        XCTAssertEqual(changes.last?.newRelativePath, "final.txt")

        let currentPage = try await store.page()
        XCTAssertEqual(currentPage.records.map(\.relativePath), ["Project/final copy.txt"])
        let missingPage = try await store.page(
            filter: DownloadFileFilter(presence: .unavailable)
        )
        XCTAssertEqual(missingPage.records.map(\.relativePath), ["Project/final.txt"])
    }

    func testSearchCategoryPagingAndRestartPersistence() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let observedAt = Date(timeIntervalSince1970: 2_000)

        do {
            let store = try DownloadsIndexStore(databaseURL: databaseURL)
            let snapshots = [
                snapshot(identity: "1:1", path: "Docs/report.pdf", size: 1),
                snapshot(identity: "1:2", path: "Images/report.png", size: 2),
                snapshot(identity: "1:3", path: "Data/table.csv", size: 3)
            ]
            _ = try await store.reconcile(snapshots, observedAt: observedAt)

            var filter = DownloadFileFilter.current
            filter.searchText = "report"
            let reportPage = try await store.page(filter: filter, limit: 1)
            XCTAssertEqual(reportPage.totalCount, 2)
            XCTAssertEqual(reportPage.records.count, 1)
            XCTAssertNotNil(reportPage.nextCursor)

            let secondPage = try await store.page(
                filter: filter,
                after: reportPage.nextCursor,
                limit: 1
            )
            XCTAssertEqual(secondPage.records.count, 1)
            XCTAssertNotEqual(reportPage.records.first?.id, secondPage.records.first?.id)

            filter.searchText = ""
            filter.category = .data
            let dataPage = try await store.page(filter: filter)
            XCTAssertEqual(dataPage.records.map(\.relativePath), ["Data/table.csv"])
        }

        let reopened = try DownloadsIndexStore(databaseURL: databaseURL)
        let page = try await reopened.page()
        XCTAssertEqual(page.totalCount, 3)
        let changes = try await reopened.changes()
        XCTAssertTrue(changes.isEmpty)
    }

    func testModificationDateSortSupportsBothDirectionsPagingAndUnknownDates() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)
        let baseDate = Date(timeIntervalSince1970: 10_000)
        _ = try await store.reconcile([
            snapshot(
                identity: "1:31",
                path: "oldest.txt",
                size: 1,
                modifiedAt: baseDate
            ),
            snapshot(
                identity: "1:32",
                path: "middle.txt",
                size: 1,
                modifiedAt: baseDate.addingTimeInterval(100)
            ),
            snapshot(
                identity: "1:33",
                path: "newest.txt",
                size: 1,
                modifiedAt: baseDate.addingTimeInterval(200)
            ),
            snapshot(identity: "1:34", path: "unknown.txt", size: 1, modifiedAt: nil)
        ])

        var newestFirst = DownloadFileFilter.current
        newestFirst.modificationSortOrder = .newestFirst
        let descendingPaths = try await allPaths(
            in: store,
            filter: newestFirst,
            pageSize: 2
        )
        XCTAssertEqual(descendingPaths, [
            "newest.txt", "middle.txt", "oldest.txt", "unknown.txt"
        ])

        var oldestFirst = DownloadFileFilter.current
        oldestFirst.modificationSortOrder = .oldestFirst
        let ascendingPaths = try await allPaths(
            in: store,
            filter: oldestFirst,
            pageSize: 2
        )
        XCTAssertEqual(ascendingPaths, [
            "oldest.txt", "middle.txt", "newest.txt", "unknown.txt"
        ])
    }

    func testModificationDateSortPaginatesStablyAcrossTiesAndUnknownDates() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)
        let tiedDate = Date(timeIntervalSince1970: 20_000)
        _ = try await store.reconcile([
            snapshot(identity: "1:41", path: "tie-a.txt", size: 1, modifiedAt: tiedDate),
            snapshot(identity: "1:42", path: "tie-b.txt", size: 1, modifiedAt: tiedDate),
            snapshot(identity: "1:43", path: "unknown-a.txt", size: 1, modifiedAt: nil),
            snapshot(identity: "1:44", path: "unknown-b.txt", size: 1, modifiedAt: nil)
        ])

        for order in DownloadFileModificationSortOrder.allCases {
            var filter = DownloadFileFilter.current
            filter.modificationSortOrder = order
            let unpaged = try await store.page(filter: filter, limit: 100).records
            let paged = try await allRecords(in: store, filter: filter, pageSize: 1)

            XCTAssertEqual(paged.map(\.id), unpaged.map(\.id))
            XCTAssertEqual(Set(paged.map(\.id)).count, 4)
            XCTAssertEqual(paged.map(\.modificationDate), [tiedDate, tiedDate, nil, nil])
        }
    }

    func testAmbiguousHardLinkIdentityDoesNotBecomeFalseMove() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)
        let first = snapshot(identity: "1:20", path: "one.txt", size: 1)
        let second = snapshot(identity: "1:20", path: "two.txt", size: 1)
        _ = try await store.reconcile([first, second])

        let third = snapshot(identity: "1:20", path: "three.txt", size: 1)
        let summary = try await store.reconcile([first, second, third])

        XCTAssertEqual(summary.discovered, 1)
        XCTAssertEqual(summary.moved, 0)
        XCTAssertEqual(summary.renamed, 0)
    }

    func testReconciliationUpgradesLegacyIdentityWithoutFalseFileChanges() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try DownloadsIndexStore(databaseURL: databaseURL)

        _ = try await store.reconcile([
            snapshot(identity: "16777233:42", path: "report.pdf", size: 10)
        ])
        let summary = try await store.reconcile([
            snapshot(
                identity: "v2:32f37f71-c7f5-4d82-9835-222fc9d36b11:42",
                path: "report.pdf",
                size: 10
            )
        ])

        XCTAssertEqual(summary.indexedFileCount, 1)
        XCTAssertEqual(summary.changeCount, 0)
        let changes = try await store.changes()
        let page = try await store.page()
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(
            page.records.first?.fileSystemIdentity,
            "v2:32f37f71-c7f5-4d82-9835-222fc9d36b11:42"
        )
    }

    private func snapshot(
        identity: String,
        path: String,
        size: UInt64,
        modifiedAt: Date? = Date(timeIntervalSince1970: 100)
    ) -> DownloadFileSnapshot {
        DownloadFileSnapshot(
            fileSystemIdentity: identity,
            relativePath: path,
            fileName: (path as NSString).lastPathComponent,
            size: size,
            creationDate: Date(timeIntervalSince1970: 50),
            modificationDate: modifiedAt,
            fileCategory: FileTypeClassifier.category(forFileName: path),
            isPackage: false
        )
    }

    private func allPaths(
        in store: DownloadsIndexStore,
        filter: DownloadFileFilter,
        pageSize: Int
    ) async throws -> [String] {
        try await allRecords(in: store, filter: filter, pageSize: pageSize)
            .map(\.relativePath)
    }

    private func allRecords(
        in store: DownloadsIndexStore,
        filter: DownloadFileFilter,
        pageSize: Int
    ) async throws -> [IndexedDownloadFile] {
        var records: [IndexedDownloadFile] = []
        var cursor: DownloadFileCursor?
        repeat {
            let page = try await store.page(filter: filter, after: cursor, limit: pageSize)
            records.append(contentsOf: page.records)
            cursor = page.nextCursor
        } while cursor != nil
        return records
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-IndexStore-\(UUID().uuidString)")
            .appendingPathComponent("index.sqlite")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

private extension DownloadFileFilter {
    init(presence: DownloadFilePresenceFilter) {
        self.init()
        self.presence = presence
    }
}
