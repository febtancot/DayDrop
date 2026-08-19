import XCTest
@testable import DayDrop

final class TodayFileLocationResolverTests: XCTestCase {
    func testResolvesSameCurrentFileInsideAuthorizedRoot() throws {
        let root = try makeDirectory(prefix: "DayDrop-TodayRoot")
        let fileURL = root.appendingPathComponent("report.pdf")
        try Data("report".utf8).write(to: fileURL)
        let identity = try XCTUnwrap(FileSystemIdentity.itemIdentifier(at: fileURL))

        XCTAssertEqual(
            TodayFileLocationResolver().existingItemURL(
                for: makeItem(url: fileURL, identity: identity),
                in: root
            ),
            fileURL.standardizedFileURL
        )
    }

    func testRejectsReplacedOrOutsideFile() throws {
        let root = try makeDirectory(prefix: "DayDrop-TodayRoot")
        let outside = try makeDirectory(prefix: "DayDrop-TodayOutside")
        let fileURL = outside.appendingPathComponent("report.pdf")
        try Data("report".utf8).write(to: fileURL)
        let identity = try XCTUnwrap(FileSystemIdentity.itemIdentifier(at: fileURL))

        XCTAssertNil(
            TodayFileLocationResolver().existingItemURL(
                for: makeItem(url: fileURL, identity: identity),
                in: root
            )
        )

        let inside = root.appendingPathComponent("inside.pdf")
        try Data("inside".utf8).write(to: inside)
        XCTAssertNil(
            TodayFileLocationResolver().existingItemURL(
                for: makeItem(url: inside, identity: "v2:stale:1"),
                in: root
            )
        )
    }

    func testRejectsSymlink() throws {
        let root = try makeDirectory(prefix: "DayDrop-TodayRoot")
        let outside = try makeDirectory(prefix: "DayDrop-TodayOutside")
        let target = outside.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: target)
        let link = root.appendingPathComponent("secret.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let targetIdentity = try XCTUnwrap(FileSystemIdentity.itemIdentifier(at: target))

        XCTAssertNil(
            TodayFileLocationResolver().existingItemURL(
                for: makeItem(url: link, identity: targetIdentity),
                in: root
            )
        )
    }

    private func makeItem(url: URL, identity: String) -> TodayFileItem {
        TodayFileItem(
            id: url.standardizedFileURL.path,
            name: url.lastPathComponent,
            completedAt: Date(),
            fileSystemIdentity: identity
        )
    }

    private func makeDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

