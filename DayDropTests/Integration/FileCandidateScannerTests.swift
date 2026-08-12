import Darwin
import XCTest
@testable import DayDrop

final class FileCandidateScannerTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-ScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    func testTopLevelScanReturnsMetadataWithoutRecursing() throws {
        let topLevelFile = temporaryRoot.appendingPathComponent("complete.pdf")
        try Data(repeating: 7, count: 12).write(to: topLevelFile)
        let folder = temporaryRoot.appendingPathComponent("existing-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: folder.appendingPathComponent("nested.txt"))

        let scanner = FileCandidateScanner()
        let snapshots = try scanner.topLevelSnapshots(in: temporaryRoot)

        XCTAssertEqual(Set(snapshots.map(\.fileName)), ["complete.pdf", "existing-folder"])
        let file = try XCTUnwrap(snapshots.first { $0.fileName == "complete.pdf" })
        XCTAssertEqual(file.size, 12)
        XCTAssertTrue(scanner.isEligible(file))
        let directory = try XCTUnwrap(snapshots.first { $0.fileName == "existing-folder" })
        XCTAssertFalse(scanner.isEligible(directory))
    }

    func testTemporarySuffixRemainsIneligibleAtScannerBoundary() throws {
        let partial = temporaryRoot.appendingPathComponent("video.mp4.crdownload")
        try Data("partial".utf8).write(to: partial)

        let scanner = FileCandidateScanner()
        let snapshot = try XCTUnwrap(scanner.snapshot(at: partial))

        XCTAssertFalse(scanner.isEligible(snapshot))
    }

    func testExclusiveAdvisoryLockDefersCandidate() throws {
        let fileURL = temporaryRoot.appendingPathComponent("locked.zip")
        try Data("download".utf8).write(to: fileURL)
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_NONBLOCK)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { Darwin.close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        defer { flock(descriptor, LOCK_UN) }

        let scanner = FileCandidateScanner()
        XCTAssertFalse(scanner.canAcquireExclusiveAdvisoryLock(on: fileURL))
    }

    func testSymbolicLinkIsNeverAnEligibleTopLevelFile() throws {
        let externalFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-External-\(UUID().uuidString).txt")
        try Data("outside".utf8).write(to: externalFile)
        defer { try? FileManager.default.removeItem(at: externalFile) }
        let linkURL = temporaryRoot.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: externalFile)

        let scanner = FileCandidateScanner()
        let snapshot = try XCTUnwrap(scanner.snapshot(at: linkURL))

        XCTAssertTrue(snapshot.isSymbolicLink)
        XCTAssertFalse(scanner.isEligible(snapshot))
        XCTAssertFalse(scanner.canAcquireExclusiveAdvisoryLock(on: linkURL))
    }
}
