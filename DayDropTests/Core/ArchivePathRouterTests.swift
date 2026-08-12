import XCTest
@testable import DayDrop

final class ArchivePathRouterTests: XCTestCase {
    private var calendar: Calendar!
    private var router: ArchivePathRouter!

    override func setUpWithError() throws {
        calendar = DayDropCalendar.local(
            timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        )
        router = ArchivePathRouter(calendar: calendar)
    }

    override func tearDown() {
        router = nil
        calendar = nil
    }

    func testTodayRoutesToShallowMonthDayFolder() throws {
        let today = try date(2026, 8, 11, hour: 23)

        let route = router.route(for: try date(2026, 8, 11, hour: 1), relativeTo: today)

        XCTAssertEqual(route.hierarchy, .recentDay)
        XCTAssertEqual(route.pathComponents, ["0811"])
        XCTAssertEqual(route.relativePath, "0811")
        XCTAssertEqual(route.sourceDay.encoded, "2026-08-11")
    }

    func testExactlyFourteenNaturalDaysOldRemainsRecent() throws {
        let route = router.route(
            for: try date(2026, 7, 28, hour: 1),
            relativeTo: try date(2026, 8, 11, hour: 23)
        )

        XCTAssertEqual(route.hierarchy, .recentDay)
        XCTAssertEqual(route.relativePath, "0728")
    }

    func testFifteenNaturalDaysOldMovesUnderMonth() throws {
        let route = router.route(
            for: try date(2026, 7, 27),
            relativeTo: try date(2026, 8, 11)
        )

        XCTAssertEqual(route.hierarchy, .monthAndDay)
        XCTAssertEqual(route.pathComponents, ["07", "0727"])
        XCTAssertEqual(route.relativePath, "07/0727")
    }

    func testDifferentPastYearUsesYearMonthDayEvenWhenOnlyOneNaturalDayAway() throws {
        let route = router.route(
            for: try date(2025, 12, 31),
            relativeTo: try date(2026, 1, 1)
        )

        XCTAssertEqual(route.hierarchy, .yearMonthAndDay)
        XCTAssertEqual(route.relativePath, "2025/12/1231")
    }

    func testFutureYearUsesItsOwnYearHierarchy() throws {
        let route = router.route(
            for: try date(2027, 1, 2),
            relativeTo: try date(2026, 8, 11)
        )

        XCTAssertEqual(route.hierarchy, .yearMonthAndDay)
        XCTAssertEqual(route.relativePath, "2027/01/0102")
    }

    func testNaturalDaysAreNotElapsedTwentyFourHourPeriodsAcrossDST() throws {
        let losAngelesCalendar = DayDropCalendar.local(
            timeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        )
        let dstRouter = ArchivePathRouter(calendar: losAngelesCalendar)
        calendar = losAngelesCalendar

        let route = dstRouter.route(
            for: try date(2026, 3, 8, hour: 0),
            relativeTo: try date(2026, 3, 22, hour: 23)
        )

        XCTAssertEqual(route.hierarchy, .recentDay)
        XCTAssertEqual(route.relativePath, "0308")
    }

    func testSameYearFutureDateUsesAbsoluteNaturalDayDistance() throws {
        let route = router.route(
            for: try date(2026, 8, 20),
            relativeTo: try date(2026, 8, 11)
        )

        XCTAssertEqual(route.hierarchy, .recentDay)
        XCTAssertEqual(route.relativePath, "0820")
    }

    func testStoredFullDayCanBeReroutedWhenItAges() throws {
        let storedDay = try XCTUnwrap(ArchiveDay(encoded: "2026-08-11"))
        let fifteenDaysLater = try XCTUnwrap(ArchiveDay(encoded: "2026-08-26"))

        let route = router.route(for: storedDay, relativeTo: fifteenDaysLater)

        XCTAssertEqual(route.hierarchy, .monthAndDay)
        XCTAssertEqual(route.relativePath, "08/0811")
        XCTAssertEqual(route.sourceDay, storedDay)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        try XCTUnwrap(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
        )
    }
}
