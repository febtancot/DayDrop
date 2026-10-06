import XCTest
@testable import DayDrop

final class AutomaticOrganizationPolicyTests: XCTestCase {
    private let calendar = DayDropCalendar.local(timeZone: TimeZone(secondsFromGMT: 8 * 60 * 60)!)

    func testTodayWaitsUntilLocalMidnightRatherThanTwentyFourHours() throws {
        let downloaded = try date(2026, 9, 23, 23, 59)
        let snapshot = file(added: downloaded)
        let policy = AutomaticOrganizationPolicy(delayed: true, calendar: calendar)

        XCTAssertNil(policy.sourceDay(for: snapshot, isBaseline: false, at: downloaded))
        XCTAssertEqual(
            policy.sourceDay(for: snapshot, isBaseline: false, at: try date(2026, 9, 24))?.encoded,
            "2026-09-23"
        )
    }

    func testDownloadAtMidnightBelongsToTodayAndRemainsInPlace() throws {
        let now = try date(2026, 9, 24)
        XCTAssertNil(AutomaticOrganizationPolicy(delayed: true, calendar: calendar)
            .sourceDay(for: file(added: now), isBaseline: true, at: now))
    }

    func testStartupAndResumeBaselineDoesNotHideOverdueDownloads() throws {
        let policy = AutomaticOrganizationPolicy(delayed: true, calendar: calendar)
        let now = try date(2026, 9, 24, 10)
        for day in [20, 23] {
            XCTAssertEqual(
                policy.sourceDay(
                    for: file(added: try date(2026, 9, day)),
                    isBaseline: true,
                    at: now
                )?.encoded,
                "2026-09-\(day)"
            )
        }
        XCTAssertNil(policy.sourceDay(for: file(added: now), isBaseline: true, at: now))
    }

    func testDateAddedPreventsOldServerTimestampsFromMovingTodaysDownload() throws {
        let now = try date(2026, 9, 24, 10)
        let oldDate = try date(2024, 1, 1)
        let snapshot = file(added: now, created: oldDate, modified: oldDate)

        XCTAssertNil(AutomaticOrganizationPolicy(delayed: true, calendar: calendar)
            .sourceDay(for: snapshot, isBaseline: false, at: now))
    }

    func testCreationDateThenModificationDateFallback() throws {
        let policy = AutomaticOrganizationPolicy(delayed: true, calendar: calendar)
        let now = try date(2026, 9, 24, 10)
        let yesterday = try date(2026, 9, 23)
        XCTAssertNil(policy.sourceDay(
            for: file(created: now, modified: yesterday), isBaseline: false, at: now
        ))
        XCTAssertEqual(policy.sourceDay(
            for: file(created: yesterday), isBaseline: true, at: now
        )?.encoded, "2026-09-23")
        XCTAssertEqual(policy.sourceDay(
            for: file(modified: yesterday), isBaseline: true, at: now
        )?.encoded, "2026-09-23")
    }

    func testMissingAndFutureMetadataRemainUntouched() throws {
        let policy = AutomaticOrganizationPolicy(delayed: true, calendar: calendar)
        let now = try date(2026, 9, 24)
        XCTAssertNil(policy.sourceDay(for: file(), isBaseline: false, at: now))
        XCTAssertNil(policy.sourceDay(
            for: file(added: try date(2026, 9, 25)), isBaseline: false, at: now
        ))
    }

    func testDisabledModePreservesRuntimeOnlyDiscoveryAndCompletionDate() throws {
        let policy = AutomaticOrganizationPolicy(delayed: false, calendar: calendar)
        let now = try date(2026, 9, 24)
        let oldFile = file(added: try date(2026, 9, 20))
        XCTAssertNil(policy.sourceDay(for: oldFile, isBaseline: true, at: now))
        XCTAssertEqual(policy.sourceDay(for: oldFile, isBaseline: false, at: now)?.encoded, "2026-09-24")
        XCTAssertEqual(policy.sourceDay(for: file(), isBaseline: false, at: now)?.encoded, "2026-09-24")
    }

    func testYearRolloverRetainsOriginalDownloadDay() throws {
        XCTAssertEqual(AutomaticOrganizationPolicy(delayed: true, calendar: calendar).sourceDay(
            for: file(added: try date(2026, 12, 31, 23, 59)),
            isBaseline: true,
            at: try date(2027, 1, 1)
        )?.encoded, "2026-12-31")
    }

    func testDaylightSavingTransitionUsesCalendarBoundary() throws {
        let calendar = DayDropCalendar.local(timeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")))
        let downloaded = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0, minute: 30)))
        let nextMidnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9)))
        XCTAssertLessThan(nextMidnight.timeIntervalSince(downloaded), 24 * 60 * 60)
        XCTAssertEqual(AutomaticOrganizationPolicy(delayed: true, calendar: calendar).sourceDay(
            for: file(added: downloaded), isBaseline: true, at: nextMidnight
        )?.encoded, "2026-03-08")
    }

    @MainActor
    func testPreferenceDefaultsOffAndSurvivesControllerRecreation() throws {
        let suiteName = "DayDrop-DelayedPreferenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = DayDropController(defaults: defaults)
        XCTAssertFalse(controller.delayedOrganizationEnabled)
        controller.setDelayedOrganizationEnabled(true)
        let restarted = DayDropController(defaults: defaults)
        XCTAssertTrue(restarted.delayedOrganizationEnabled)
        restarted.setDelayedOrganizationEnabled(false)
        XCTAssertFalse(DayDropController(defaults: defaults).delayedOrganizationEnabled)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func file(added: Date? = nil, created: Date? = nil, modified: Date? = nil) -> TopLevelFileSnapshot {
        TopLevelFileSnapshot(
            url: URL(fileURLWithPath: "/Downloads/report.pdf"),
            identity: "test-file", fileName: "report.pdf", isHidden: false,
            isDirectory: false, isPackage: false, isRegularFile: true, isSymbolicLink: false,
            size: 10, creationDate: created, modificationDate: modified,
            addedToDirectoryDate: added
        )
    }
}
