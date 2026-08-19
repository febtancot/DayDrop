import XCTest
@testable import DayDrop

final class IndexedDownloadFileLocationResolverTests: XCTestCase {
    func testResolvesCurrentItemWithMatchingIdentity() throws {
        let root = try makeRoot()
        let folder = root.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("report.pdf")
        try Data("report".utf8).write(to: fileURL)
        let identity = try XCTUnwrap(FileSystemIdentity.itemIdentifier(at: fileURL))

        let resolved = IndexedDownloadFileLocationResolver().existingItemURL(
            for: makeFile(path: "Docs/report.pdf", identity: identity),
            in: root
        )

        XCTAssertEqual(resolved, fileURL.standardizedFileURL)
    }

    func testRejectsUnavailableOrReplacedItem() throws {
        let root = try makeRoot()
        let fileURL = root.appendingPathComponent("report.pdf")
        try Data("report".utf8).write(to: fileURL)

        XCTAssertNil(
            IndexedDownloadFileLocationResolver().existingItemURL(
                for: makeFile(path: "report.pdf", identity: "v2:other:1", isPresent: false),
                in: root
            )
        )
        XCTAssertNil(
            IndexedDownloadFileLocationResolver().existingItemURL(
                for: makeFile(path: "report.pdf", identity: "v2:other:1"),
                in: root
            )
        )
    }

    func testRejectsSymlinkEscape() throws {
        let root = try makeRoot()
        let outside = try makeRoot(prefix: "DayDrop-IndexedOutside")
        let outsideFile = outside.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: outsideFile)
        let link = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let identity = try XCTUnwrap(FileSystemIdentity.itemIdentifier(at: outsideFile))

        XCTAssertNil(
            IndexedDownloadFileLocationResolver().existingItemURL(
                for: makeFile(path: "linked/secret.txt", identity: identity),
                in: root
            )
        )
    }

    private func makeRoot(prefix: String = "DayDrop-IndexedLocation") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeFile(
        path: String,
        identity: String,
        isPresent: Bool = true
    ) -> IndexedDownloadFile {
        IndexedDownloadFile(
            id: UUID(),
            fileSystemIdentity: identity,
            relativePath: path,
            fileName: (path as NSString).lastPathComponent,
            size: 1,
            creationDate: nil,
            modificationDate: nil,
            fileCategory: .document,
            isPackage: false,
            firstSeenAt: Date(),
            lastSeenAt: Date(),
            isPresent: isPresent,
            unavailableSince: isPresent ? nil : Date()
        )
    }
}

