import XCTest
@testable import DayDrop

final class DownloadsIndexStoreTests: XCTestCase {
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
        modifiedAt: Date = Date(timeIntervalSince1970: 100)
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
