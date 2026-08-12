import XCTest
@testable import DayDrop

final class ArchiveDayTests: XCTestCase {
    func testEncodesFullDateWithFixedWidthComponents() throws {
        let day = try XCTUnwrap(ArchiveDay(year: 2026, month: 3, day: 7))

        XCTAssertEqual(day.encoded, "2026-03-07")
        XCTAssertEqual(day.yearComponent, "2026")
        XCTAssertEqual(day.monthComponent, "03")
        XCTAssertEqual(day.monthDayComponent, "0307")
    }

    func testDecodesOnlyValidFixedWidthGregorianDates() {
        XCTAssertEqual(ArchiveDay(encoded: "2024-02-29"), ArchiveDay(year: 2024, month: 2, day: 29))
        XCTAssertNil(ArchiveDay(encoded: "2023-02-29"))
        XCTAssertNil(ArchiveDay(encoded: "2026-2-03"))
        XCTAssertNil(ArchiveDay(encoded: "2026/02/03"))
        XCTAssertNil(ArchiveDay(encoded: "+026-02-03"))
        XCTAssertNil(ArchiveDay(encoded: "not-a-date"))
    }

    func testCodableUsesSingleYYYYMMDDString() throws {
        let original = try XCTUnwrap(ArchiveDay(year: 2026, month: 8, day: 11))

        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"2026-08-11\"")
        XCTAssertEqual(try JSONDecoder().decode(ArchiveDay.self, from: data), original)
    }

    func testDateConversionUsesInjectedLocalTimeZone() throws {
        let calendar = DayDropCalendar.local(
            timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        )
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-10T16:30:00Z"))

        XCTAssertEqual(ArchiveDay(date: instant, calendar: calendar).encoded, "2026-08-11")
    }
}
