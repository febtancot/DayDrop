import XCTest
@testable import DayDrop

final class ExistingFileDateResolverTests: XCTestCase {
    func testCreationDateTakesPriority() throws {
        let calendar = testCalendar()
        let creation = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 4)))
        let modification = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11)))

        let day = ExistingFileDateResolver(calendar: calendar).archiveDay(
            creationDate: creation,
            modificationDate: modification
        )

        XCTAssertEqual(day?.encoded, "2024-03-04")
    }

    func testModificationDateIsFallback() throws {
        let calendar = testCalendar()
        let modification = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31)))

        let day = ExistingFileDateResolver(calendar: calendar).archiveDay(
            creationDate: nil,
            modificationDate: modification
        )

        XCTAssertEqual(day?.encoded, "2025-12-31")
    }

    func testMissingMetadataDoesNotInventADate() {
        let day = ExistingFileDateResolver(calendar: testCalendar()).archiveDay(
            creationDate: nil,
            modificationDate: nil
        )
        XCTAssertNil(day)
    }

    private func testCalendar() -> Calendar {
        DayDropCalendar.local(timeZone: TimeZone(secondsFromGMT: 8 * 60 * 60)!)
    }
}

