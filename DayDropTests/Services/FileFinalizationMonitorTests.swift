import Dispatch
import XCTest
@testable import DayDrop

final class FileFinalizationMonitorTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "DayDrop-FinalizationMonitorTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    func testWriteEventResetsMonitorQuietWindowForPreallocatedFile() throws {
        let fileURL = temporaryRoot.appendingPathComponent("large.iso")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: fileURL.path,
            contents: Data(repeating: 0, count: 4_096)
        ))
        let eventExpectation = expectation(description: "vnode write event")
        let monitor = FileFinalizationMonitor(fileURL: fileURL)
        try monitor.start(observedUptime: 0) { event in
            if !event.flags.intersection([.write, .extend, .attrib]).isEmpty {
                eventExpectation.fulfill()
            }
        }
        XCTAssertTrue(monitor.hasBeenQuiet(for: 1))

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seek(toOffset: 2_048)
        try handle.write(contentsOf: Data(repeating: 7, count: 128))
        try handle.synchronize()
        try handle.close()

        wait(for: [eventExpectation], timeout: 2)
        XCTAssertFalse(monitor.hasBeenQuiet(for: 1))
    }

    func testRenameKeepsMonitoringSameInodeAndResetsQuietWindow() throws {
        let sourceURL = temporaryRoot.appendingPathComponent("movie.tmp")
        let finalURL = temporaryRoot.appendingPathComponent("movie.mp4")
        try Data("payload".utf8).write(to: sourceURL)
        let eventExpectation = expectation(description: "vnode rename event")
        let monitor = FileFinalizationMonitor(fileURL: sourceURL)
        try monitor.start(observedUptime: 0) { event in
            if event.flags.contains(.rename) {
                eventExpectation.fulfill()
            }
        }

        try FileManager.default.moveItem(at: sourceURL, to: finalURL)

        wait(for: [eventExpectation], timeout: 2)
        XCTAssertTrue(monitor.isRunning)
        XCTAssertFalse(monitor.hasBeenQuiet(for: 1))
    }

    func testDeleteInvalidatesMonitor() throws {
        let fileURL = temporaryRoot.appendingPathComponent("partial.zip")
        try Data("partial".utf8).write(to: fileURL)
        let eventExpectation = expectation(description: "vnode delete event")
        let monitor = FileFinalizationMonitor(fileURL: fileURL)
        try monitor.start { event in
            if event.invalidatesMonitor {
                eventExpectation.fulfill()
            }
        }

        try FileManager.default.removeItem(at: fileURL)

        wait(for: [eventExpectation], timeout: 2)
        XCTAssertFalse(monitor.isRunning)
        XCTAssertFalse(monitor.hasBeenQuiet(for: 0))
    }

    func testSymlinkAndDirectoryFailClosed() throws {
        let regularFile = temporaryRoot.appendingPathComponent("outside.bin")
        let symlink = temporaryRoot.appendingPathComponent("linked.bin")
        try Data("data".utf8).write(to: regularFile)
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL: regularFile
        )

        XCTAssertThrowsError(
            try FileFinalizationMonitor(fileURL: symlink).start { _ in }
        )
        XCTAssertThrowsError(
            try FileFinalizationMonitor(fileURL: temporaryRoot).start { _ in }
        ) { error in
            guard case FileFinalizationMonitorError.notRegularFile = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
