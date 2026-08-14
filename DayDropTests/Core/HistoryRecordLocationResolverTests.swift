import Foundation
import XCTest
@testable import DayDrop

final class HistoryRecordLocationResolverTests: XCTestCase {
    func testSuccessfulRecordRevealsExistingDestination() throws {
        let root = try makeRoot()
        let source = root.appendingPathComponent("report.pdf")
        let destinationFolder = root.appendingPathComponent("Day 2026-08-13", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let destination = destinationFolder.appendingPathComponent("report.pdf")
        try Data("report".utf8).write(to: destination)

        let resolution = HistoryRecordLocationResolver().resolve(
            record: makeRecord(source: source, destination: destination, succeeded: true),
            in: root
        )

        XCTAssertEqual(resolution, .revealItem(destination.standardizedFileURL))
    }

    func testFailedRecordPrefersExistingSource() throws {
        let root = try makeRoot()
        let source = root.appendingPathComponent("archive.zip")
        let destination = root.appendingPathComponent("Day 2026-08-13/archive.zip")
        try Data("archive".utf8).write(to: source)

        let resolution = HistoryRecordLocationResolver().resolve(
            record: makeRecord(source: source, destination: destination, succeeded: false),
            in: root
        )

        XCTAssertEqual(resolution, .revealItem(source.standardizedFileURL))
    }

    func testMissingFileOpensRecordedDestinationDirectory() throws {
        let root = try makeRoot()
        let destinationFolder = root.appendingPathComponent("Day 2026-08-13", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let record = makeRecord(
            source: root.appendingPathComponent("missing.pdf"),
            destination: destinationFolder.appendingPathComponent("missing.pdf"),
            succeeded: true
        )

        let resolution = HistoryRecordLocationResolver().resolve(record: record, in: root)

        XCTAssertEqual(
            resolution,
            .openRecordedDirectory(destinationFolder.standardizedFileURL)
        )
    }

    func testRelativeLegacyPathResolvesWithinAuthorizedRoot() throws {
        let root = try makeRoot()
        let folder = root.appendingPathComponent("Day 2026-08-13", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("photo.png")
        try Data("image".utf8).write(to: file)
        let record = OperationRecord(
            fileName: "photo.png",
            sourcePath: "photo.png",
            destinationPath: "Day 2026-08-13/photo.png",
            succeeded: true
        )

        let resolution = HistoryRecordLocationResolver().resolve(record: record, in: root)

        XCTAssertEqual(resolution, .revealItem(file.standardizedFileURL))
    }

    func testPathOutsideAuthorizedRootIsRejected() throws {
        let root = try makeRoot()
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-Outside-\(UUID().uuidString).txt")
        try Data("outside".utf8).write(to: outside)
        addTeardownBlock { try? FileManager.default.removeItem(at: outside) }
        let record = makeRecord(source: outside, destination: outside, succeeded: true)

        XCTAssertNil(HistoryRecordLocationResolver().resolve(record: record, in: root))
    }

    func testSymlinkCannotEscapeAuthorizedRoot() throws {
        let root = try makeRoot()
        let outsideFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-OutsideFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        let outsideFile = outsideFolder.appendingPathComponent("secret.txt")
        try Data("outside".utf8).write(to: outsideFile)
        addTeardownBlock { try? FileManager.default.removeItem(at: outsideFolder) }

        let link = root.appendingPathComponent("linked-folder", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFolder)
        let escapedPath = link.appendingPathComponent("secret.txt")
        let record = makeRecord(
            source: escapedPath,
            destination: escapedPath,
            succeeded: true
        )

        XCTAssertNil(HistoryRecordLocationResolver().resolve(record: record, in: root))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-HistoryLocationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeRecord(
        source: URL,
        destination: URL,
        succeeded: Bool
    ) -> OperationRecord {
        OperationRecord(
            fileName: destination.lastPathComponent,
            sourcePath: source.path,
            destinationPath: destination.path,
            succeeded: succeeded,
            errorMessage: succeeded ? nil : "move failed"
        )
    }
}
