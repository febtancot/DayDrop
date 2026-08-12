import XCTest
@testable import DayDrop

final class FileSizeStabilityTrackerTests: XCTestCase {
    func testRequiresTwoConsecutiveEqualSamples() {
        var tracker = FileSizeStabilityTracker()

        XCTAssertEqual(tracker.state, .awaitingFirstSample)
        XCTAssertEqual(tracker.observe(size: 1_024), .needsAnotherSample)
        XCTAssertEqual(tracker.state, .awaitingMatchingSample(previousSize: 1_024))
        XCTAssertFalse(tracker.isStable)

        XCTAssertEqual(tracker.observe(size: 1_024), .stable)
        XCTAssertEqual(tracker.state, .stable(size: 1_024))
        XCTAssertTrue(tracker.isStable)
    }

    func testChangingSizeRestartsTheTwoSampleRequirement() {
        var tracker = FileSizeStabilityTracker()

        XCTAssertEqual(tracker.observe(size: 100), .needsAnotherSample)
        XCTAssertEqual(tracker.observe(size: 200), .needsAnotherSample)
        XCTAssertEqual(tracker.state, .awaitingMatchingSample(previousSize: 200))
        XCTAssertEqual(tracker.observe(size: 200), .stable)
    }

    func testStableFileBecomesUnstableWhenSizeChanges() {
        var tracker = FileSizeStabilityTracker()
        _ = tracker.observe(size: 10)
        _ = tracker.observe(size: 10)

        XCTAssertEqual(tracker.observe(size: 11), .needsAnotherSample)
        XCTAssertFalse(tracker.isStable)
        XCTAssertEqual(tracker.observe(size: 11), .stable)
    }

    func testResetDiscardsPreviousSample() {
        var tracker = FileSizeStabilityTracker()
        _ = tracker.observe(size: 0)

        tracker.reset()

        XCTAssertEqual(tracker.state, .awaitingFirstSample)
        XCTAssertEqual(tracker.observe(size: 0), .needsAnotherSample)
    }
}
