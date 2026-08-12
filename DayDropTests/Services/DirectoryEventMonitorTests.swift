import Foundation
import XCTest
@testable import DayDrop

final class DirectoryEventMonitorTests: XCTestCase {
    func testWriteDeliversDirectoryChangeEvent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDropMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let expectation = expectation(description: "directory write event")
        let recorder = DirectoryEventRecorder(expectation: expectation)
        let callbackQueue = DispatchQueue(label: "com.liuyuhang.DayDropTests.monitor-callback")
        let monitor = DirectoryEventMonitor(
            directoryURL: directory,
            callbackQueue: callbackQueue
        )
        try monitor.start { event in
            recorder.record(event)
        }
        defer { monitor.stop() }

        try Data("new file".utf8).write(to: directory.appendingPathComponent("download.txt"))
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(recorder.lastEvent?.directoryURL, directory.standardizedFileURL)
        XCTAssertFalse(recorder.lastEvent?.flags.isEmpty ?? true)
    }

    func testStartRearmAndStopMaintainConsistentRunningState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDropMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let monitor = DirectoryEventMonitor(directoryURL: directory)
        try monitor.start { _ in }
        XCTAssertTrue(monitor.isRunning)

        try monitor.rearm()
        XCTAssertTrue(monitor.isRunning)

        monitor.stop()
        XCTAssertFalse(monitor.isRunning)

        XCTAssertThrowsError(try monitor.rearm()) { error in
            guard case DirectoryEventMonitorError.notStarted = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStartingWithAFileURLIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDropMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("not-a-directory")
        XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        let monitor = DirectoryEventMonitor(directoryURL: fileURL)

        XCTAssertThrowsError(try monitor.start { _ in }) { error in
            guard case DirectoryEventMonitorError.notDirectory = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(monitor.isRunning)
    }
}

private final class DirectoryEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let expectation: XCTestExpectation
    private var storedEvent: DirectoryChangeEvent?

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    var lastEvent: DirectoryChangeEvent? {
        lock.lock()
        defer { lock.unlock() }
        return storedEvent
    }

    func record(_ event: DirectoryChangeEvent) {
        lock.lock()
        let isFirst = storedEvent == nil
        storedEvent = event
        lock.unlock()

        if isFirst {
            expectation.fulfill()
        }
    }
}
