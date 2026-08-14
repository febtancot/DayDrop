import Foundation
import XCTest
@testable import DayDrop

final class DownloadsTreeEventMonitorTests: XCTestCase {
    func testNestedFileWriteTriggersRecursiveEvent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-FSEvents-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Level1/Level2", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let expectation = expectation(description: "nested FSEvent")
        let recorder = DownloadsTreeEventRecorder(
            expectedPathSuffix: "Level1/Level2/new.txt",
            expectation: expectation
        )
        let monitor = DownloadsTreeEventMonitor(
            rootURL: root,
            latency: 0.05,
            callbackQueue: DispatchQueue(label: "com.liuyuhang.DayDropTests.fsevents")
        )
        try monitor.start { event in
            recorder.record(event)
        }
        defer { monitor.stop() }

        try Data("nested".utf8).write(to: nested.appendingPathComponent("new.txt"))
        wait(for: [expectation], timeout: 5)

        XCTAssertTrue(recorder.didObserveExpectedPath)
        XCTAssertGreaterThan(recorder.latestEventID, 0)
    }
}

private final class DownloadsTreeEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let expectedPathSuffix: String
    private let expectation: XCTestExpectation
    private var fulfilled = false
    private var storedLatestEventID: FSEventStreamEventId = 0

    init(expectedPathSuffix: String, expectation: XCTestExpectation) {
        self.expectedPathSuffix = expectedPathSuffix
        self.expectation = expectation
    }

    var didObserveExpectedPath: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fulfilled
    }

    var latestEventID: FSEventStreamEventId {
        lock.lock()
        defer { lock.unlock() }
        return storedLatestEventID
    }

    func record(_ event: DownloadsTreeChangeEvent) {
        lock.lock()
        storedLatestEventID = max(storedLatestEventID, event.latestEventID)
        let shouldFulfill = !fulfilled && event.paths.contains {
            $0.hasSuffix(expectedPathSuffix)
        }
        if shouldFulfill { fulfilled = true }
        lock.unlock()
        if shouldFulfill { expectation.fulfill() }
    }
}
