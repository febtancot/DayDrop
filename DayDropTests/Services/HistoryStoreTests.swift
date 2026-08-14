import Foundation
import XCTest
@testable import DayDrop

final class HistoryStoreTests: XCTestCase {
    func testHistoryPermanentlyKeepsMoreThanLegacyLimitAndPaginatesWithoutDuplicates() async throws {
        let store = try makeStore()
        for index in 0..<130 {
            try await store.append(makeRecord(index: index))
        }

        let firstPage = try await store.page(limit: 50)
        XCTAssertEqual(firstPage.totalCount, 130)
        XCTAssertEqual(firstPage.records.count, 50)
        XCTAssertNotNil(firstPage.nextCursor)

        let secondPage = try await store.page(after: firstPage.nextCursor, limit: 50)
        XCTAssertEqual(secondPage.records.count, 50)
        XCTAssertTrue(Set(firstPage.records.map(\.id)).isDisjoint(with: secondPage.records.map(\.id)))

        let thirdPage = try await store.page(after: secondPage.nextCursor, limit: 50)
        XCTAssertEqual(thirdPage.records.count, 30)
        XCTAssertNil(thirdPage.nextCursor)
        let totalCount = try await store.count()
        XCTAssertEqual(totalCount, 130)
    }

    func testSearchCategoryAndOutcomeFiltersCompose() async throws {
        let store = try makeStore()
        try await store.append(
            OperationRecord(
                fileName: "Quarterly Report.pdf",
                sourcePath: "/Downloads/Quarterly Report.pdf",
                destinationPath: "/Downloads/Day 2026-08-12/Quarterly Report.pdf",
                performedAt: Date(timeIntervalSince1970: 30),
                succeeded: true,
                trigger: .automaticDownload
            )
        )
        try await store.append(
            OperationRecord(
                fileName: "Quarterly Data.csv",
                sourcePath: "/Downloads/Quarterly Data.csv",
                destinationPath: "/Downloads/Quarterly Data.csv",
                performedAt: Date(timeIntervalSince1970: 20),
                succeeded: false,
                errorMessage: "permission denied",
                trigger: .manualTopLevel
            )
        )
        try await store.append(
            OperationRecord(
                fileName: "photo.png",
                sourcePath: "/Downloads/photo.png",
                destinationPath: "/Downloads/Day 2026-08-12/photo.png",
                performedAt: Date(timeIntervalSince1970: 10),
                succeeded: true,
                trigger: .automaticDownload
            )
        )

        let documentPage = try await store.page(
            filter: HistoryFilter(
                searchText: "quarterly",
                outcome: .succeeded,
                category: .document
            )
        )
        XCTAssertEqual(documentPage.records.map(\.fileName), ["Quarterly Report.pdf"])

        let failurePage = try await store.page(
            filter: HistoryFilter(searchText: "permission", outcome: .failed)
        )
        XCTAssertEqual(failurePage.records.map(\.fileName), ["Quarterly Data.csv"])
    }

    func testLegacyImportIsIdempotentAndPreservesIdentifier() async throws {
        let store = try makeStore()
        let record = makeRecord(index: 1)

        try await store.importLegacyRecords([record])
        try await store.importLegacyRecords([record])

        let page = try await store.page()
        XCTAssertEqual(page.totalCount, 1)
        XCTAssertEqual(page.records.first?.id, record.id)
        XCTAssertEqual(page.records.first?.trigger, .legacyImport)
    }

    func testExportsCurrentFilterAsCSVAndJSON() async throws {
        let store = try makeStore()
        try await store.append(makeRecord(index: 1, succeeded: true, fileName: "image.png"))
        try await store.append(makeRecord(index: 2, succeeded: false, fileName: "notes.txt"))

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-HistoryExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: exportDirectory) }

        let csvURL = exportDirectory.appendingPathComponent("success.csv")
        let csvCount = try await store.export(
            filter: HistoryFilter(outcome: .succeeded),
            to: csvURL,
            format: .csv
        )
        XCTAssertEqual(csvCount, 1)
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("image.png"))
        XCTAssertFalse(csv.contains("notes.txt"))

        let jsonURL = exportDirectory.appendingPathComponent("all.json")
        let jsonCount = try await store.export(filter: .all, to: jsonURL, format: .json)
        XCTAssertEqual(jsonCount, 2)
        let decoded = try JSONDecoder.iso8601.decode(
            [OperationRecord].self,
            from: Data(contentsOf: jsonURL)
        )
        XCTAssertEqual(Set(decoded.map(\.fileName)), ["image.png", "notes.txt"])
    }

    private func makeStore() throws -> HistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try HistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite"))
    }

    private func makeRecord(
        index: Int,
        succeeded: Bool? = nil,
        fileName: String? = nil
    ) -> OperationRecord {
        let resolvedName = fileName ?? "file-\(index).zip"
        return OperationRecord(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            fileName: resolvedName,
            sourcePath: "/Downloads/\(resolvedName)",
            destinationPath: "/Downloads/Day 2026-08-12/\(resolvedName)",
            performedAt: Date(timeIntervalSince1970: TimeInterval(index)),
            succeeded: succeeded ?? index.isMultiple(of: 2),
            errorMessage: (succeeded ?? index.isMultiple(of: 2)) ? nil : "move failed",
            trigger: .automaticDownload
        )
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
