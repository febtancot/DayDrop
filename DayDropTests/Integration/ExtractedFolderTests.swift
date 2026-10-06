import Darwin
import XCTest
@testable import DayDrop

final class ExtractedFolderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DayDrop-Extraction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-stores"))
        }
    }

    func testSystemReaderSupportsZIP7zRAR3AndRAR5Headers() throws {
        let reader = ArchiveManifestReader()
        for name in ["bundle.zip", "bundle.7z"] {
            let manifest = try reader.read(at: fixture(name))
            XCTAssertEqual(manifest.entries["Project.v1/Read me.txt"]?.size, 8, name)
            XCTAssertEqual(manifest.entries["Project.v1/nested/data.txt"]?.size, 9, name)
            XCTAssertEqual(manifest.rootDirectory, "Project.v1", name)
        }
        let rar3 = try reader.read(at: fixture("sample-rar3.rar"))
        XCTAssertEqual(rar3.entries["testdir/test.txt"]?.size, 16)
        let rar5 = try reader.read(at: fixture("sample-rar5.rar"))
        XCTAssertEqual(rar5.entries["helloworld.txt"]?.size, 29)
        let unicode = try reader.read(at: fixture("unicode.zip"))
        XCTAssertEqual(unicode.entries["资料/说明.txt"]?.size, 6)
    }

    func testEncryptedTraversalAndLinkArchivesFailClosed() throws {
        for name in ["encrypted.zip", "unsafe.zip", "symlink.zip", "linked.rar", "incomplete-volume.rar"] {
            XCTAssertThrowsError(try ArchiveManifestReader().read(at: fixture(name)), name)
        }
        let invalid = root.appendingPathComponent("invalid.zip")
        try Data("not a zip".utf8).write(to: invalid)
        XCTAssertThrowsError(try ArchiveManifestReader().read(at: invalid))
    }

    func testManifestRejectsAmbiguousOrUnsafePaths() {
        for path in ["../escape.txt", "/absolute.txt", "a/../../b", "C:/file", "a\\b"] {
            XCTAssertThrowsError(try ArchiveManifest(entries: [.init(path: path, isDirectory: false, size: 1)]), path)
        }
        XCTAssertThrowsError(try ArchiveManifest(entries: [
            .init(path: "file", isDirectory: false, size: 1),
            .init(path: "file", isDirectory: false, size: 2)
        ]))
        XCTAssertThrowsError(try ArchiveManifest(entries: [
            .init(path: "file", isDirectory: false, size: 1),
            .init(path: "file/nested", isDirectory: false, size: 2)
        ]))
    }

    func testStoredRootAndCollisionNamesMatchWholeContents() throws {
        let folder = try projectFolder()
        let manifest = try ArchiveManifestReader().read(at: fixture("bundle.zip"))
        let tree = try ExtractedFolderTreeScanner().scan(at: folder)
        for name in ["Project.v1", "Project.v1 2", "Project.v1 (1)", "bundle"] {
            XCTAssertTrue(manifest.matches(tree: tree, folderName: name, archiveName: "bundle.zip"), name)
        }
        for name in ["Personal", "Project.v1 backup", "Project.v1 0"] {
            XCTAssertFalse(manifest.matches(tree: tree, folderName: name, archiveName: "bundle.zip"), name)
        }
        let wrapper = root.appendingPathComponent("wrapper", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: folder, to: wrapper.appendingPathComponent("Project.v1"))
        XCTAssertTrue(manifest.matches(tree: try ExtractedFolderTreeScanner().scan(at: wrapper), folderName: "bundle", archiveName: "bundle.zip"))
    }

    func testNameAloneMissingExtraAndPartialFilesCannotMatch() throws {
        let folder = try projectFolder()
        let manifest = try ArchiveManifestReader().read(at: fixture("bundle.zip"))
        let child = folder.appendingPathComponent("nested/data.txt")
        try Data("partial".utf8).write(to: child)
        XCTAssertFalse(manifest.matches(tree: try ExtractedFolderTreeScanner().scan(at: folder), folderName: "Project.v1", archiveName: "bundle.zip"))
        try Data("contents\n".utf8).write(to: child)
        let extra = folder.appendingPathComponent("my-notes.txt")
        try Data("user content".utf8).write(to: extra)
        XCTAssertFalse(manifest.matches(tree: try ExtractedFolderTreeScanner().scan(at: folder), folderName: "Project.v1", archiveName: "bundle.zip"))
        try FileManager.default.removeItem(at: extra)
        try Data("Finder metadata".utf8).write(to: folder.appendingPathComponent(".DS_Store"))
        XCTAssertTrue(manifest.matches(tree: try ExtractedFolderTreeScanner().scan(at: folder), folderName: "Project.v1", archiveName: "bundle.zip"))
        try FileManager.default.removeItem(at: child)
        XCTAssertFalse(manifest.matches(tree: try ExtractedFolderTreeScanner().scan(at: folder), folderName: "Project.v1", archiveName: "bundle.zip"))
    }

    func testFlatArchiveRenamedByCollisionStillMatchesOriginalFolderName() async throws {
        let original = try copyArchive("flat.zip")
        let archive = root.appendingPathComponent("flat (1).zip")
        try FileManager.default.moveItem(at: original, to: archive)
        let manifest = try ArchiveManifestReader().read(at: archive)
        let folder = root.appendingPathComponent("flat", isDirectory: true)
        try materialize(Array(manifest.entries.values), in: folder)
        let matches = await ExtractedFolderRecognizer().recognize(
            folders: try FileCandidateScanner().topLevelSnapshots(in: root), archiveURLs: [archive], in: root
        )
        XCTAssertEqual(matches.count, 1)
    }

    func testArchiveOutsideAuthorizedRootCannotProvideEvidence() async throws {
        _ = try projectFolder()
        let matches = await ExtractedFolderRecognizer().recognize(
            folders: try FileCandidateScanner().topLevelSnapshots(in: root), archiveURLs: [try fixture("bundle.zip")], in: root
        )
        XCTAssertTrue(matches.isEmpty)
    }

    func testRecognizerAcceptsZIP7zAndRARDirectories() async throws {
        for name in ["bundle.zip", "bundle.7z", "sample-rar3.rar", "sample-rar5.rar"] {
            let caseRoot = root.appendingPathComponent(name + "-case", isDirectory: true)
            try FileManager.default.createDirectory(at: caseRoot, withIntermediateDirectories: true)
            let archive = try copyArchive(name, to: caseRoot)
            let manifest = try ArchiveManifestReader().read(at: archive)
            let folder = caseRoot.appendingPathComponent((name as NSString).deletingPathExtension, isDirectory: true)
            try materialize(manifest.entries.values.map { $0 }, in: folder)
            let matches = await ExtractedFolderRecognizer().recognize(
                folders: try FileCandidateScanner().topLevelSnapshots(in: caseRoot), archiveURLs: [archive], in: caseRoot
            )
            XCTAssertEqual(matches.count, 1, name)
            XCTAssertEqual(matches.values.first?.folderURL.lastPathComponent, folder.lastPathComponent)
        }
    }

    func testAlreadyOrganizedArchiveStillIdentifiesExtraction() async throws {
        let archive = try copyArchive("bundle.zip")
        let folder = try projectFolder()
        let dayFolder = root.appendingPathComponent("Day 2026-09-29", isDirectory: true)
        try FileManager.default.createDirectory(at: dayFolder, withIntermediateDirectories: true)
        try DayDropDirectoryOwnershipMarker.mark(dayFolder, dateIdentifier: "2026-09-29")
        try FileManager.default.moveItem(at: archive, to: dayFolder.appendingPathComponent("bundle.zip"))
        let managed = ManagedDayFolder(dateIdentifier: "2026-09-29", relativePath: "Day 2026-09-29", directoryIdentity: FileSystemIdentity.directoryIdentifier(at: dayFolder))
        let matches = await ExtractedFolderRecognizer().recognize(
            folders: try FileCandidateScanner().topLevelSnapshots(in: root), archiveURLs: [], managedFolders: [managed], in: root
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.values.first?.folderURL.standardizedFileURL, folder.standardizedFileURL)
    }

    func testAmbiguousArchivesAndOlderOrdinaryFoldersAreNotMoved() async throws {
        let first = try copyArchive("bundle.zip")
        let folder = try projectFolder()
        let second = root.appendingPathComponent("copy.zip")
        try FileManager.default.copyItem(at: first, to: second)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: second.path)
        let recognizer = ExtractedFolderRecognizer()
        let snapshots = try FileCandidateScanner().topLevelSnapshots(in: root)
        let ambiguous = await recognizer.recognize(folders: snapshots, archiveURLs: [first, second], in: root)
        XCTAssertTrue(ambiguous.isEmpty)
        let future = Date().addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: future, .creationDate: future], ofItemAtPath: first.path)
        let olderFolder = await recognizer.recognize(folders: snapshots, archiveURLs: [first], in: root)
        XCTAssertTrue(olderFolder.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testManagedPackageAndLinkedFoldersAreExcluded() async throws {
        let archive = try copyArchive("bundle.zip")
        let folder = try projectFolder()
        try DayDropDirectoryOwnershipMarker.mark(folder, dateIdentifier: "2026-09-29")
        let matches = await ExtractedFolderRecognizer().recognize(
            folders: try FileCandidateScanner().topLevelSnapshots(in: root), archiveURLs: [archive], in: root
        )
        XCTAssertTrue(matches.isEmpty)
        let package = root.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ExtractedFolderTreeScanner().scan(at: package))
        let plain = root.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: plain.appendingPathComponent("link"), withDestinationURL: folder)
        XCTAssertThrowsError(try ExtractedFolderTreeScanner().scan(at: plain))
    }

    func testNestedSameSizeWriteRestartsQuietWindowEvenIfMtimeIsRestored() throws {
        let folder = try projectFolder()
        let scanner = ExtractedFolderTreeScanner()
        let initial = try scanner.scan(at: folder)
        var tracker = ExtractedFolderFinalization(tree: initial, lastActivityUptime: 0)
        XCTAssertFalse(tracker.observe(initial, at: 9))
        XCTAssertTrue(tracker.observe(initial, at: 10))
        let nested = folder.appendingPathComponent("nested/data.txt")
        let oldDate = try XCTUnwrap(try nested.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        try Data("changed!\n".utf8).write(to: nested)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: nested.path)
        let changed = try scanner.scan(at: folder)
        XCTAssertNotEqual(initial, changed)
        XCTAssertFalse(tracker.observe(changed, at: 11))
        XCTAssertFalse(tracker.observe(changed, at: 20))
        XCTAssertTrue(tracker.observe(changed, at: 21))
        tracker.recordActivity(at: 22)
        XCTAssertFalse(tracker.observe(changed, at: 25))
    }

    func testWholeFolderMovePreservesContentsAndAvoidsNameCollision() async throws {
        let archive = try copyArchive("bundle.zip")
        let folder = try projectFolder()
        let evidence = try await evidence(for: folder, archive: archive)
        let today = ArchiveDay(date: Date())
        let existing = root.appendingPathComponent("Day \(today.encoded)/Project.v1", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: existing.appendingPathComponent("keep.txt"))
        let result = await ArchiveEngine().moveExtractedFolder(evidence, sourceDay: today, relativeTo: today, in: root)
        XCTAssertTrue(result.succeeded, result.errorMessage ?? "")
        XCTAssertEqual(result.destinationURL.lastPathComponent, "Project.v1 (1)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(try String(contentsOf: result.destinationURL.appendingPathComponent("nested/data.txt")), "contents\n")
        XCTAssertEqual(try String(contentsOf: existing.appendingPathComponent("keep.txt")), "existing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    func testBusyDescendantPreventsWholeFolderMove() async throws {
        let archive = try copyArchive("bundle.zip")
        let folder = try projectFolder()
        let evidence = try await evidence(for: folder, archive: archive)
        let descriptor = Darwin.open(folder.appendingPathComponent("nested/data.txt").path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { Darwin.close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        let day = ArchiveDay(date: Date())
        let result = await ArchiveEngine().moveExtractedFolder(evidence, sourceDay: day, relativeTo: day, in: root)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.destinationURL.path))
    }

    func testChangedTreeOrArchiveInvalidatesMoveEvidence() async throws {
        let archive = try copyArchive("bundle.zip")
        let folder = try projectFolder()
        let proof = try await evidence(for: folder, archive: archive)
        let newFile = folder.appendingPathComponent("later.txt")
        try Data("new file".utf8).write(to: newFile)
        let day = ArchiveDay(date: Date())
        let engine = ArchiveEngine()
        let changedTree = await engine.moveExtractedFolder(proof, sourceDay: day, relativeTo: day, in: root)
        XCTAssertFalse(changedTree.succeeded)
        try FileManager.default.removeItem(at: newFile)
        let fresh = try await evidence(for: folder, archive: archive)
        try Data("replaced archive".utf8).write(to: archive)
        let changedArchive = await engine.moveExtractedFolder(fresh, sourceDay: day, relativeTo: day, in: root)
        XCTAssertFalse(changedArchive.succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    @MainActor
    func testControllerDefersTodaysFolderAndArchivesItAfterCalendarChange() async throws {
        _ = try copyArchive("bundle.zip")
        let folder = try projectFolder()
        let suite = "DayDrop-ExtractionController-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "DayDrop.DelayedOrganizationEnabled")
        let stores = try isolatedStores()
        let clock = TestClock(date: Date())
        let controller = DayDropController(defaults: defaults, stores: stores, currentDate: { clock.date })
        defer { controller.stop() }

        await controller.startWithTestFolder(root)
        let initialHistory = try await stores.history.page()
        XCTAssertEqual(initialHistory.totalCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

        let downloadDay = ArchiveDay(date: clock.date)
        clock.date = try XCTUnwrap(DayDropCalendar.local().date(byAdding: .day, value: 1, to: clock.date))
        await controller.handleTestCalendarChange()
        let moved = await waitUntil { !FileManager.default.fileExists(atPath: folder.path) }
        XCTAssertTrue(moved, controller.statusMessage ?? "Folder did not move")
        let destination = root.appendingPathComponent("Day \(downloadDay.encoded)/Project.v1/nested/data.txt")
        XCTAssertEqual(try String(contentsOf: destination), "contents\n")
        let history = try await stores.history.page()
        XCTAssertEqual(history.records.filter { $0.fileName == "Project.v1" && $0.succeeded }.count, 1)
        XCTAssertEqual(history.records.first { $0.fileName == "Project.v1" }?.trigger, .automaticDownload)
    }

    @MainActor
    func testControllerManualDeepActionMovesExtractionIntactWhilePausedAndDelayed() async throws {
        _ = try copyArchive("bundle.zip")
        let folder = try projectFolder()
        let suite = "DayDrop-ExtractionController-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "DayDrop.IsPaused")
        defaults.set(true, forKey: "DayDrop.DelayedOrganizationEnabled")
        let stores = try isolatedStores()
        let controller = DayDropController(defaults: defaults, stores: stores)
        defer { controller.stop() }
        await controller.startWithTestFolder(root)
        let before = try await stores.history.page()
        XCTAssertEqual(before.totalCount, 0)
        controller.organizeExistingFiles(scope: .includingImmediateSubfolders)

        let moved = await waitUntil { !FileManager.default.fileExists(atPath: folder.path) }
        XCTAssertTrue(moved, controller.statusMessage ?? "Folder did not move")
        let history = try await stores.history.page()
        let folderRecord = try XCTUnwrap(history.records.first { $0.fileName == "Project.v1" })
        XCTAssertTrue(folderRecord.succeeded)
        XCTAssertEqual(folderRecord.trigger, .manualDeep)
        XCTAssertFalse(history.records.contains { $0.fileName == "Read me.txt" || $0.fileName == "data.txt" })
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: folderRecord.destinationPath).appendingPathComponent("nested/data.txt")), "contents\n")
        XCTAssertTrue(controller.isPaused)
    }

    @MainActor
    func testExtractionPreferenceDefaultsOnAndPersists() throws {
        let suite = "DayDrop-ExtractionPreference-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = DayDropController(defaults: defaults)
        XCTAssertTrue(controller.organizeExtractedFoldersEnabled)
        controller.setOrganizeExtractedFoldersEnabled(false)
        XCTAssertFalse(DayDropController(defaults: defaults).organizeExtractedFoldersEnabled)
    }

    @MainActor
    func testManualDeepActionDoesNotFlattenPartiallyExtractedFolder() async throws {
        let archive = try copyArchive("bundle.zip")
        let folder = try projectFolder()
        try FileManager.default.removeItem(at: folder.appendingPathComponent("nested/data.txt"))
        let suite = "DayDrop-PartialExtraction-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "DayDrop.IsPaused")
        let stores = try isolatedStores()
        let controller = DayDropController(defaults: defaults, stores: stores)
        defer { controller.stop() }
        await controller.startWithTestFolder(root)
        controller.organizeExistingFiles(scope: .includingImmediateSubfolders)
        let archiveMoved = await waitUntil { !FileManager.default.fileExists(atPath: archive.path) }
        XCTAssertTrue(archiveMoved)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("Read me.txt")), "read me\n")
        let records = try await stores.history.page().records
        XCTAssertFalse(records.contains { $0.fileName == "Read me.txt" || $0.fileName == "Project.v1" })
    }

    private func isolatedStores() throws -> DayDropControllerStores {
        let storage = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-stores")
        return DayDropControllerStores(
            metadata: try LocalMetadataStore(storageURL: storage.appendingPathComponent("metadata.json")),
            history: try HistoryStore(databaseURL: storage.appendingPathComponent("history.sqlite")),
            index: try DownloadsIndexStore(databaseURL: storage.appendingPathComponent("index.sqlite"))
        )
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Extraction"))
    }

    private func copyArchive(_ name: String, to directory: URL? = nil) throws -> URL {
        let destination = (directory ?? root).appendingPathComponent(name)
        try FileManager.default.copyItem(at: fixture(name), to: destination)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: destination.path)
        return destination
    }

    private func projectFolder() throws -> URL {
        let folder = root.appendingPathComponent("Project.v1", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try Data("read me\n".utf8).write(to: folder.appendingPathComponent("Read me.txt"))
        try Data("contents\n".utf8).write(to: folder.appendingPathComponent("nested/data.txt"))
        return folder
    }

    private func materialize(_ entries: [ArchiveManifestEntry], in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            let url = folder.appendingPathComponent(entry.path)
            if entry.isDirectory {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(repeating: 1, count: Int(entry.size)).write(to: url)
            }
        }
    }

    private func evidence(for folder: URL, archive: URL) async throws -> ExtractedFolderEvidence {
        let matches = await ExtractedFolderRecognizer().recognize(
            folders: try FileCandidateScanner().topLevelSnapshots(in: root), archiveURLs: [archive], in: root
        )
        return try XCTUnwrap(matches[try XCTUnwrap(FileSystemIdentity.directoryIdentifier(at: folder))])
    }
}

@MainActor
private final class TestClock {
    var date: Date
    init(date: Date) { self.date = date }
}
