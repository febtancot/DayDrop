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

    func testImmediateSubfolderScanIncludesOneLevelButNeverRecursesDeeper() throws {
        let topLevelFile = temporaryRoot.appendingPathComponent("top.pdf")
        try Data("top".utf8).write(to: topLevelFile)

        let includedFolder = temporaryRoot.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(
            at: includedFolder,
            withIntermediateDirectories: true
        )
        try Data("nested".utf8).write(
            to: includedFolder.appendingPathComponent("nested.txt")
        )
        let deeperFolder = includedFolder.appendingPathComponent("Deeper", isDirectory: true)
        try FileManager.default.createDirectory(
            at: deeperFolder,
            withIntermediateDirectories: true
        )
        try Data("too deep".utf8).write(
            to: deeperFolder.appendingPathComponent("ignored.txt")
        )

        let excludedFolder = temporaryRoot.appendingPathComponent("Managed", isDirectory: true)
        try FileManager.default.createDirectory(
            at: excludedFolder,
            withIntermediateDirectories: true
        )
        try Data("managed".utf8).write(
            to: excludedFolder.appendingPathComponent("managed.txt")
        )

        let scanner = FileCandidateScanner()
        let snapshots = try scanner.snapshotsIncludingImmediateSubfolders(
            in: temporaryRoot,
            shouldDescendInto: { $0.fileName != "Managed" }
        )
        let eligibleNames = Set(
            snapshots.filter(scanner.isEligible).map(\.fileName)
        )

        XCTAssertEqual(eligibleNames, ["top.pdf", "nested.txt"])
        XCTAssertFalse(snapshots.contains { $0.fileName == "ignored.txt" })
        XCTAssertFalse(snapshots.contains { $0.fileName == "managed.txt" })
    }

    func testSupportedSourceDepthRejectsDeeperAndSymlinkedParents() throws {
        let directFolder = temporaryRoot.appendingPathComponent("Direct", isDirectory: true)
        let deeperFolder = directFolder.appendingPathComponent("Deeper", isDirectory: true)
        try FileManager.default.createDirectory(
            at: deeperFolder,
            withIntermediateDirectories: true
        )
        let nestedFile = directFolder.appendingPathComponent("nested.txt")
        let deeperFile = deeperFolder.appendingPathComponent("ignored.txt")
        try Data("nested".utf8).write(to: nestedFile)
        try Data("deeper".utf8).write(to: deeperFile)

        let outsideFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-ScannerOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outsideFolder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outsideFolder) }
        let outsideFile = outsideFolder.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outsideFile)
        let linkedFolder = temporaryRoot.appendingPathComponent("Linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedFolder,
            withDestinationURL: outsideFolder
        )

        let scanner = FileCandidateScanner()
        XCTAssertTrue(scanner.isSupportedSourceURL(
            nestedFile,
            in: temporaryRoot,
            maximumDepth: 2
        ))
        XCTAssertFalse(scanner.isSupportedSourceURL(
            deeperFile,
            in: temporaryRoot,
            maximumDepth: 2
        ))
        XCTAssertFalse(scanner.isSupportedSourceURL(
            linkedFolder.appendingPathComponent("outside.txt"),
            in: temporaryRoot,
            maximumDepth: 2
        ))
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
