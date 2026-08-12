import Darwin
import XCTest
@testable import DayDrop

final class ArchiveEngineTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-ArchiveEngineTests-\(UUID().uuidString)", isDirectory: true)
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

    func testMoveUsesRouteAndPreservesBothCollidingFiles() async throws {
        let firstSource = temporaryRoot.appendingPathComponent("report.pdf")
        try Data("first".utf8).write(to: firstSource)

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let sourceDay = ArchiveDay(year: 2026, month: 8, day: 11)!
        let today = ArchiveDay(year: 2026, month: 8, day: 11)!

        let firstResult = await engine.moveFile(
            at: firstSource,
            sourceDay: sourceDay,
            relativeTo: today,
            in: temporaryRoot
        )
        XCTAssertTrue(firstResult.succeeded)
        XCTAssertEqual(firstResult.destinationURL.lastPathComponent, "report.pdf")

        let secondSource = temporaryRoot.appendingPathComponent("report.pdf")
        try Data("second".utf8).write(to: secondSource)
        let secondResult = await engine.moveFile(
            at: secondSource,
            sourceDay: sourceDay,
            relativeTo: today,
            in: temporaryRoot
        )

        XCTAssertTrue(secondResult.succeeded)
        XCTAssertEqual(secondResult.destinationURL.lastPathComponent, "report (1).pdf")
        XCTAssertEqual(try String(contentsOf: firstResult.destinationURL), "first")
        XCTAssertEqual(try String(contentsOf: secondResult.destinationURL), "second")
    }

    func testMoveFailureLeavesSourceUntouched() async throws {
        let sourceURL = temporaryRoot.appendingPathComponent("keep-me.zip")
        try Data("source".utf8).write(to: sourceURL)

        var operations = ArchiveFileOperations.live()
        operations.moveItem = { _, _ in throw InjectedFailure.move }
        let engine = ArchiveEngine(calendar: fixedCalendar(), operations: operations)

        let result = await engine.moveFile(
            at: sourceURL,
            sourceDay: ArchiveDay(year: 2026, month: 8, day: 11)!,
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(try String(contentsOf: sourceURL), "source")
    }

    func testMigrationRenamesLegacyDayFolderIntoPrefixedMonthHierarchy() async throws {
        let sourceFolder = temporaryRoot.appendingPathComponent("0727", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try DayDropDirectoryOwnershipMarker.mark(
            sourceFolder,
            dateIdentifier: "2026-07-27"
        )
        try Data("payload".utf8).write(to: sourceFolder.appendingPathComponent("archive.zip"))

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(
                dateIdentifier: "2026-07-27",
                relativePath: "0727",
                directoryIdentity: try XCTUnwrap(
                    FileSystemIdentity.directoryIdentifier(at: sourceFolder)
                ),
                pendingRelativePath: "Month 2026-07/Day 2026-07-27",
                pendingDestinationExpectedAbsent: true
            ),
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot
        )

        XCTAssertEqual(result.state, .moved)
        XCTAssertEqual(
            result.expectedRelativePath,
            "Month 2026-07/Day 2026-07-27"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFolder.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: temporaryRoot.appendingPathComponent(
                "Month 2026-07/Day 2026-07-27/archive.zip"
            ).path
        ))
        XCTAssertEqual(
            DayDropDirectoryOwnershipMarker.managedDateIdentifier(
                at: temporaryRoot.appendingPathComponent(
                    "Month 2026-07/Day 2026-07-27",
                    isDirectory: true
                )
            ),
            "2026-07-27"
        )
    }

    func testMigrationMergesDestinationWithoutOverwritingCollision() async throws {
        let sourceFolder = temporaryRoot.appendingPathComponent("0727", isDirectory: true)
        let destinationFolder = temporaryRoot.appendingPathComponent(
            "Month 2026-07/Day 2026-07-27",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: sourceFolder.appendingPathComponent("report.pdf"))
        try Data("old".utf8).write(to: destinationFolder.appendingPathComponent("report.pdf"))

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(
                dateIdentifier: "2026-07-27",
                relativePath: "0727",
                directoryIdentity: try XCTUnwrap(
                    FileSystemIdentity.directoryIdentifier(at: sourceFolder)
                ),
                pendingRelativePath: "Month 2026-07/Day 2026-07-27",
                pendingDestinationIdentity: try XCTUnwrap(
                    FileSystemIdentity.directoryIdentifier(at: destinationFolder)
                )
            ),
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot
        )

        XCTAssertEqual(result.state, .moved)
        XCTAssertEqual(
            try String(contentsOf: destinationFolder.appendingPathComponent("report.pdf")),
            "old"
        )
        XCTAssertEqual(
            try String(contentsOf: destinationFolder.appendingPathComponent("report (1).pdf")),
            "new"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFolder.path))
    }

    func testMigrationMovesMonthlyFolderUnderYearAndRemovesEmptyMonthContainer() async throws {
        let sourceFolder = temporaryRoot.appendingPathComponent("07/0727", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try DayDropDirectoryOwnershipMarker.markManagedContainer(
            sourceFolder.deletingLastPathComponent()
        )
        try Data("payload".utf8).write(to: sourceFolder.appendingPathComponent("archive.zip"))

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(
                dateIdentifier: "2025-07-27",
                relativePath: "07/0727",
                directoryIdentity: try XCTUnwrap(
                    FileSystemIdentity.directoryIdentifier(at: sourceFolder)
                ),
                pendingRelativePath: "Year 2025/Month 2025-07/Day 2025-07-27",
                pendingDestinationExpectedAbsent: true
            ),
            relativeTo: ArchiveDay(year: 2026, month: 1, day: 1)!,
            in: temporaryRoot
        )

        XCTAssertEqual(result.state, .moved)
        XCTAssertEqual(
            result.expectedRelativePath,
            "Year 2025/Month 2025-07/Day 2025-07-27"
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: temporaryRoot.appendingPathComponent(
                "Year 2025/Month 2025-07/Day 2025-07-27/archive.zip"
            ).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: temporaryRoot.appendingPathComponent("07").path
        ))
    }

    func testMigrationPreservesUnmarkedEmptyUserParentContainer() async throws {
        let sourceFolder = temporaryRoot.appendingPathComponent("07/0727", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: sourceFolder.appendingPathComponent("archive.zip"))
        let sourceIdentity = try XCTUnwrap(
            FileSystemIdentity.directoryIdentifier(at: sourceFolder)
        )

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(
                dateIdentifier: "2025-07-27",
                relativePath: "07/0727",
                directoryIdentity: sourceIdentity,
                pendingRelativePath: "Year 2025/Month 2025-07/Day 2025-07-27",
                pendingDestinationExpectedAbsent: true
            ),
            relativeTo: ArchiveDay(year: 2026, month: 1, day: 1)!,
            in: temporaryRoot
        )

        XCTAssertEqual(result.state, .moved)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: temporaryRoot.appendingPathComponent("07").path,
            isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testMigrationRejectsEscapingRegistryPath() async {
        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(dateIdentifier: "2026-07-27", relativePath: "../Elsewhere"),
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot
        )

        XCTAssertEqual(result.state, .failed)
        XCTAssertNotNil(result.errorMessage)
    }

    func testMoveRejectsSymbolicLinkArchiveComponent() async throws {
        let outsideFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-Outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideFolder) }
        try FileManager.default.createSymbolicLink(
            at: temporaryRoot.appendingPathComponent("Day 2026-08-11"),
            withDestinationURL: outsideFolder
        )
        let sourceURL = temporaryRoot.appendingPathComponent("stay.pdf")
        try Data("source".utf8).write(to: sourceURL)

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.moveFile(
            at: sourceURL,
            sourceDay: ArchiveDay(year: 2026, month: 8, day: 11)!,
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: outsideFolder.path)).isEmpty)
    }

    func testMigrationMergeDoesNotTraverseDirectorySymbolicLink() async throws {
        let outsideFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-Outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideFolder) }
        let outsideFile = outsideFolder.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outsideFile)

        let sourceFolder = temporaryRoot.appendingPathComponent("0727", isDirectory: true)
        let destinationFolder = temporaryRoot.appendingPathComponent("07/0727", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: destinationFolder.appendingPathComponent("linked", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: sourceFolder.appendingPathComponent("linked"),
            withDestinationURL: outsideFolder
        )

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(
                dateIdentifier: "2026-07-27",
                relativePath: "0727",
                directoryIdentity: try XCTUnwrap(
                    FileSystemIdentity.directoryIdentifier(at: sourceFolder)
                ),
                pendingRelativePath: "07/0727",
                pendingDestinationIdentity: try XCTUnwrap(
                    FileSystemIdentity.directoryIdentifier(at: destinationFolder)
                )
            ),
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot
        )

        XCTAssertEqual(result.state, .moved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path))
        let movedLink = destinationFolder.appendingPathComponent("linked (1)")
        let values = try movedLink.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertEqual(values.isSymbolicLink, true)
    }

    func testMigrationRejectsDirectoryReplacementWithSamePath() async throws {
        let sourceFolder = temporaryRoot.appendingPathComponent("0727", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let recordedIdentity = try XCTUnwrap(
            FileSystemIdentity.directoryIdentifier(at: sourceFolder)
        )
        try FileManager.default.moveItem(
            at: sourceFolder,
            to: temporaryRoot.appendingPathComponent("displaced-0727", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try Data("user".utf8).write(to: sourceFolder.appendingPathComponent("user.txt"))

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(
                dateIdentifier: "2026-07-27",
                relativePath: "0727",
                directoryIdentity: recordedIdentity,
                pendingRelativePath: "07/0727",
                pendingDestinationExpectedAbsent: true
            ),
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot
        )

        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sourceFolder.appendingPathComponent("user.txt").path
        ))
    }

    func testPendingWholeMoveRecoversWhenOnlyMatchingDestinationRemains() async throws {
        let sourceFolder = temporaryRoot.appendingPathComponent("0727", isDirectory: true)
        let destinationFolder = temporaryRoot.appendingPathComponent("07/0727", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: sourceFolder.appendingPathComponent("archive.zip"))
        let sourceIdentity = try XCTUnwrap(
            FileSystemIdentity.directoryIdentifier(at: sourceFolder)
        )
        try FileManager.default.createDirectory(
            at: destinationFolder.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: sourceFolder, to: destinationFolder)

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(
                dateIdentifier: "2026-07-27",
                relativePath: "0727",
                directoryIdentity: sourceIdentity,
                pendingRelativePath: "07/0727",
                pendingDestinationExpectedAbsent: true
            ),
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot
        )

        XCTAssertEqual(result.state, .moved)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destinationFolder.appendingPathComponent("archive.zip").path
        ))
    }

    func testPendingMergeRejectsDestinationIdentityReplacement() async throws {
        let sourceFolder = temporaryRoot.appendingPathComponent("0727", isDirectory: true)
        let destinationFolder = temporaryRoot.appendingPathComponent("07/0727", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: sourceFolder.appendingPathComponent("source.txt"))
        let sourceIdentity = try XCTUnwrap(
            FileSystemIdentity.directoryIdentifier(at: sourceFolder)
        )
        let recordedDestinationIdentity = try XCTUnwrap(
            FileSystemIdentity.directoryIdentifier(at: destinationFolder)
        )
        try FileManager.default.moveItem(
            at: destinationFolder,
            to: temporaryRoot.appendingPathComponent("displaced-destination", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(
            to: destinationFolder.appendingPathComponent("replacement.txt")
        )

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(
                dateIdentifier: "2026-07-27",
                relativePath: "0727",
                directoryIdentity: sourceIdentity,
                pendingRelativePath: "07/0727",
                pendingDestinationIdentity: recordedDestinationIdentity
            ),
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot
        )

        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sourceFolder.appendingPathComponent("source.txt").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destinationFolder.appendingPathComponent("replacement.txt").path
        ))
    }

    func testPendingAbsentDestinationRejectsDirectoryThatAppearedLater() async throws {
        let sourceFolder = temporaryRoot.appendingPathComponent("0727", isDirectory: true)
        let destinationFolder = temporaryRoot.appendingPathComponent("07/0727", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let sourceIdentity = try XCTUnwrap(
            FileSystemIdentity.directoryIdentifier(at: sourceFolder)
        )
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(
                dateIdentifier: "2026-07-27",
                relativePath: "0727",
                directoryIdentity: sourceIdentity,
                pendingRelativePath: "07/0727",
                pendingDestinationExpectedAbsent: true
            ),
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot
        )

        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFolder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationFolder.path))
    }

    func testPreparingTargetDistinguishesNewAndPreexistingDirectory() async throws {
        let engine = ArchiveEngine(calendar: fixedCalendar())
        let day = ArchiveDay(year: 2026, month: 8, day: 11)!

        let first = await engine.prepareTargetFolder(
            for: day,
            relativeTo: day,
            in: temporaryRoot
        )
        let second = await engine.prepareTargetFolder(
            for: day,
            relativeTo: day,
            in: temporaryRoot
        )

        XCTAssertTrue(first.succeeded)
        XCTAssertTrue(first.wasCreated)
        XCTAssertFalse(second.wasCreated)
        XCTAssertEqual(first.directoryIdentity, second.directoryIdentity)
        XCTAssertEqual(first.ownershipDateIdentifier, day.encoded)
        XCTAssertEqual(second.ownershipDateIdentifier, day.encoded)
    }

    func testPreparingPreexistingUserDirectoryDoesNotClaimOwnership() async throws {
        let userFolder = temporaryRoot.appendingPathComponent(
            "Day 2026-08-12",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        let engine = ArchiveEngine(calendar: fixedCalendar())
        let day = ArchiveDay(year: 2026, month: 8, day: 12)!

        let preparation = await engine.prepareTargetFolder(
            for: day,
            relativeTo: day,
            in: temporaryRoot
        )

        XCTAssertTrue(preparation.succeeded)
        XCTAssertFalse(preparation.wasCreated)
        XCTAssertNil(preparation.ownershipDateIdentifier)
    }

    func testMoveReacquiresAndHoldsAdvisoryLockAtEngineBoundary() async throws {
        let sourceURL = temporaryRoot.appendingPathComponent("locked-at-move.zip")
        try Data("payload".utf8).write(to: sourceURL)
        let descriptor = Darwin.open(sourceURL.path, O_RDONLY | O_NONBLOCK)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { Darwin.close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        defer { flock(descriptor, LOCK_UN) }

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let day = ArchiveDay(year: 2026, month: 8, day: 11)!
        let result = await engine.moveFile(
            at: sourceURL,
            sourceDay: day,
            relativeTo: day,
            in: temporaryRoot,
            expectedSourceIdentity: try XCTUnwrap(
                FileSystemIdentity.itemIdentifier(at: sourceURL)
            )
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testMoveRejectsSourcePathReplacementAfterSnapshot() async throws {
        let sourceURL = temporaryRoot.appendingPathComponent("replace-me.zip")
        try Data("original".utf8).write(to: sourceURL)
        let recordedIdentity = try XCTUnwrap(
            FileSystemIdentity.itemIdentifier(at: sourceURL)
        )
        try FileManager.default.moveItem(
            at: sourceURL,
            to: temporaryRoot.appendingPathComponent("displaced-source.zip")
        )
        try Data("replacement".utf8).write(to: sourceURL)
        let replacementIdentity = try XCTUnwrap(
            FileSystemIdentity.itemIdentifier(at: sourceURL)
        )
        XCTAssertNotEqual(recordedIdentity, replacementIdentity)

        let engine = ArchiveEngine(calendar: fixedCalendar())
        let day = ArchiveDay(year: 2026, month: 8, day: 11)!
        let preparation = await engine.prepareTargetFolder(
            for: day,
            relativeTo: day,
            in: temporaryRoot
        )
        let result = await engine.moveFile(
            at: sourceURL,
            sourceDay: day,
            relativeTo: day,
            in: temporaryRoot,
            expectedSourceIdentity: recordedIdentity,
            expectedTargetDirectoryIdentity: preparation.directoryIdentity
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(try String(contentsOf: sourceURL), "replacement")
    }

    func testMoveRejectsPreparedTargetDirectoryReplacement() async throws {
        let sourceURL = temporaryRoot.appendingPathComponent("stay-at-root.zip")
        try Data("payload".utf8).write(to: sourceURL)
        let sourceIdentity = try XCTUnwrap(
            FileSystemIdentity.itemIdentifier(at: sourceURL)
        )
        let engine = ArchiveEngine(calendar: fixedCalendar())
        let day = ArchiveDay(year: 2026, month: 8, day: 11)!
        let preparation = await engine.prepareTargetFolder(
            for: day,
            relativeTo: day,
            in: temporaryRoot
        )
        try FileManager.default.moveItem(
            at: preparation.folderURL,
            to: temporaryRoot.appendingPathComponent("displaced-target", isDirectory: true)
        )
        try FileManager.default.createDirectory(
            at: preparation.folderURL,
            withIntermediateDirectories: true
        )

        let result = await engine.moveFile(
            at: sourceURL,
            sourceDay: day,
            relativeTo: day,
            in: temporaryRoot,
            expectedSourceIdentity: sourceIdentity,
            expectedTargetDirectoryIdentity: preparation.directoryIdentity
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testCancellationStopsRetrySafeMergeBetweenChildren() async throws {
        let sourceFolder = temporaryRoot.appendingPathComponent("0727", isDirectory: true)
        let destinationFolder = temporaryRoot.appendingPathComponent("07/0727", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: sourceFolder.appendingPathComponent("one.txt"))
        try Data("two".utf8).write(to: sourceFolder.appendingPathComponent("two.txt"))

        let cancellationToken = ArchiveMigrationCancellationToken()
        var operations = ArchiveFileOperations.live()
        operations.moveItem = { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
            cancellationToken.cancel()
        }
        let sourceIdentity = try XCTUnwrap(
            FileSystemIdentity.directoryIdentifier(at: sourceFolder)
        )
        let destinationIdentity = try XCTUnwrap(
            FileSystemIdentity.directoryIdentifier(at: destinationFolder)
        )
        let engine = ArchiveEngine(calendar: fixedCalendar(), operations: operations)

        let result = await engine.migrateManagedFolder(
            ManagedFolderDescriptor(
                dateIdentifier: "2026-07-27",
                relativePath: "0727",
                directoryIdentity: sourceIdentity,
                pendingRelativePath: "07/0727",
                pendingDestinationIdentity: destinationIdentity
            ),
            relativeTo: ArchiveDay(year: 2026, month: 8, day: 11)!,
            in: temporaryRoot,
            cancellationToken: cancellationToken
        )

        XCTAssertEqual(result.state, .cancelled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sourceFolder.path).count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destinationFolder.path).count, 1)
    }

    private func fixedCalendar() -> Calendar {
        DayDropCalendar.local(timeZone: TimeZone(secondsFromGMT: 8 * 60 * 60)!)
    }
}

private enum InjectedFailure: Error {
    case move
}
