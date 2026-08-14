import XCTest
@testable import DayDrop

final class FileFinalizationTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testRequiresWholeQuietIntervalBeforeFinalization() {
        var tracker = FileFinalizationTracker(
            size: 1_024,
            modificationDate: start,
            observedUptime: 1_000,
            quietInterval: 2
        )

        XCTAssertEqual(
            tracker.observe(
                size: 1_024,
                modificationDate: start,
                atUptime: 1_001.99
            ),
            .settling
        )
        XCTAssertEqual(
            tracker.observe(
                size: 1_024,
                modificationDate: start,
                atUptime: 1_002
            ),
            .quiet
        )
    }

    func testModificationChangeResetsPreallocatedFileEvenWhenSizeIsConstant() {
        var tracker = FileFinalizationTracker(
            size: 10_000,
            modificationDate: start,
            observedUptime: 1_000,
            quietInterval: 2
        )
        let writeDate = start.addingTimeInterval(4)

        XCTAssertEqual(
            tracker.observe(
                size: 10_000,
                modificationDate: writeDate,
                atUptime: 1_004
            ),
            .settling
        )
        XCTAssertEqual(
            tracker.observe(
                size: 10_000,
                modificationDate: writeDate,
                atUptime: 1_005.99
            ),
            .settling
        )
        XCTAssertEqual(
            tracker.observe(
                size: 10_000,
                modificationDate: writeDate,
                atUptime: 1_006
            ),
            .quiet
        )
    }

    func testFilesystemEventResetsQuietWindowWhenMetadataIsUnchanged() {
        var tracker = FileFinalizationTracker(
            size: 2_048,
            modificationDate: start,
            observedUptime: 1_000,
            quietInterval: 2
        )
        tracker.recordFilesystemActivity(atUptime: 1_004)

        XCTAssertEqual(
            tracker.observe(
                size: 2_048,
                modificationDate: start,
                atUptime: 1_005.99
            ),
            .settling
        )
        XCTAssertEqual(
            tracker.observe(
                size: 2_048,
                modificationDate: start,
                atUptime: 1_006
            ),
            .quiet
        )
    }

    func testOlderDelayedEventCannotMoveActivityBackward() {
        var tracker = FileFinalizationTracker(
            size: 1,
            modificationDate: start,
            observedUptime: 1_010,
            quietInterval: 2
        )

        tracker.recordFilesystemActivity(atUptime: 1_000)

        XCTAssertEqual(tracker.lastActivityUptime, 1_010)
    }
}
