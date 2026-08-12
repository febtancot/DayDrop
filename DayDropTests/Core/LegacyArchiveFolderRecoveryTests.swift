import XCTest
@testable import DayDrop

final class LegacyArchiveFolderRecoveryTests: XCTestCase {
    private var rootURL: URL!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DayDrop-LegacyRecoveryTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        calendar = DayDropCalendar.local(
            timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        )
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        calendar = nil
    }

    func testSuccessfulOperationRecoversLegacyRecentDayFolder() throws {
        let record = try makeRecord(
            relativeFolderPath: "0811",
            fileName: "report.pdf",
            performedAt: date(2026, 8, 12)
        )

        let candidates = recovery().candidates(
            in: rootURL,
            operationRecords: [record],
            existingFolders: []
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.dateIdentifier, "2026-08-11")
        XCTAssertEqual(candidates.first?.relativePath, "0811")
        XCTAssertNotNil(candidates.first?.directoryIdentity)
    }

    func testRecoversLegacyMonthAndYearHierarchies() throws {
        let monthRecord = try makeRecord(
            relativeFolderPath: "05/0512",
            fileName: "month.pdf",
            performedAt: date(2026, 8, 12)
        )
        let yearRecord = try makeRecord(
            relativeFolderPath: "2025/03/0321",
            fileName: "year.pdf",
            performedAt: date(2026, 8, 12)
        )

        let candidates = recovery().candidates(
            in: rootURL,
            operationRecords: [monthRecord, yearRecord],
            existingFolders: []
        )

        XCTAssertEqual(
            candidates.map(\.dateIdentifier),
            ["2025-03-21", "2026-05-12"]
        )
    }

    func testNumericFolderWithoutSuccessfulExistingOperationIsIgnored() throws {
        let folder = rootURL.appendingPathComponent("0811", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missingRecord = OperationRecord(
            fileName: "missing.pdf",
            sourcePath: rootURL.appendingPathComponent("missing.pdf").path,
            destinationPath: folder.appendingPathComponent("missing.pdf").path,
            performedAt: try date(2026, 8, 12),
            succeeded: true
        )
        let failedRecord = try makeRecord(
            relativeFolderPath: "0811",
            fileName: "failed.pdf",
            performedAt: date(2026, 8, 12),
            succeeded: false
        )

        let candidates = recovery().candidates(
            in: rootURL,
            operationRecords: [missingRecord, failedRecord],
            existingFolders: []
        )

        XCTAssertEqual(candidates, [])
    }

    func testAmbiguousYearEvidenceIsIgnored() throws {
        let first = try makeRecord(
            relativeFolderPath: "0811",
            fileName: "first.pdf",
            performedAt: date(2025, 8, 12)
        )
        let second = try makeRecord(
            relativeFolderPath: "0811",
            fileName: "second.pdf",
            performedAt: date(2026, 8, 12)
        )

        let candidates = recovery().candidates(
            in: rootURL,
            operationRecords: [first, second],
            existingFolders: []
        )

        XCTAssertEqual(candidates, [])
    }

    func testExistingManagedDateIsNotRecoveredAgain() throws {
        let record = try makeRecord(
            relativeFolderPath: "0811",
            fileName: "report.pdf",
            performedAt: date(2026, 8, 12)
        )
        let existing = ManagedDayFolder(
            dateIdentifier: "2026-08-11",
            relativePath: "Day 2026-08-11",
            directoryIdentity: "existing"
        )

        let candidates = recovery().candidates(
            in: rootURL,
            operationRecords: [record],
            existingFolders: [existing]
        )

        XCTAssertEqual(candidates, [])
    }

    private func recovery() -> LegacyArchiveFolderRecovery {
        LegacyArchiveFolderRecovery(calendar: calendar)
    }

    private func makeRecord(
        relativeFolderPath: String,
        fileName: String,
        performedAt: Date,
        succeeded: Bool = true
    ) throws -> OperationRecord {
        let folder = rootURL.appendingPathComponent(
            relativeFolderPath,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(fileName)
        try Data("payload".utf8).write(to: destination)
        return OperationRecord(
            fileName: fileName,
            sourcePath: rootURL.appendingPathComponent(fileName).path,
            destinationPath: destination.path,
            performedAt: performedAt,
            succeeded: succeeded,
            errorMessage: succeeded ? nil : "failed"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        )
    }
}
