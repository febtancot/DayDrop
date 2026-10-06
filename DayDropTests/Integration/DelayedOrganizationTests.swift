import XCTest
@testable import DayDrop

final class DelayedOrganizationTests: XCTestCase {
    func testFreshScanAfterDayChangeArchivesUnderDownloadDay() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-DelayedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.txt")
        let content = Data("download content".utf8)
        try content.write(to: source)

        let scanner = FileCandidateScanner()
        let snapshot = try XCTUnwrap(scanner.snapshot(at: source))
        let calendar = DayDropCalendar.local()
        let policy = AutomaticOrganizationPolicy(delayed: true, calendar: calendar)
        let downloaded = try XCTUnwrap(snapshot.addedToDirectoryDate ?? snapshot.creationDate)
        XCTAssertTrue(scanner.isEligible(snapshot))
        XCTAssertNil(policy.sourceDay(for: snapshot, isBaseline: false, at: downloaded))
        XCTAssertEqual(try Data(contentsOf: source), content)

        // A fresh scanner and a startup baseline must still discover the file
        // tomorrow, without a retained in-memory pending candidate.
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: downloaded)))
        let rescanned = try XCTUnwrap(FileCandidateScanner().topLevelSnapshots(in: root).first)
        let sourceDay = try XCTUnwrap(policy.sourceDay(for: rescanned, isBaseline: true, at: nextDay))
        let result = await ArchiveEngine(calendar: calendar).moveFile(
            at: source,
            sourceDay: sourceDay,
            relativeTo: ArchiveDay(date: nextDay, calendar: calendar),
            in: root,
            expectedSourceIdentity: rescanned.identity
        )

        XCTAssertTrue(result.succeeded, result.errorMessage ?? "")
        XCTAssertEqual(result.relativeFolderPath, "Day \(ArchiveDay(date: downloaded, calendar: calendar).encoded)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: result.destinationURL), content)
    }
}
