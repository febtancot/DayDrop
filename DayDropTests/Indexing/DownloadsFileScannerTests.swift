import XCTest
@testable import DayDrop

final class DownloadsFileScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-RecursiveScanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    func testRecursiveScanIncludesEveryDepthAndHiddenFile() throws {
        let nested = root
            .appendingPathComponent("Project", isDirectory: true)
            .appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("top".utf8).write(to: root.appendingPathComponent("top.pdf"))
        try Data("nested".utf8).write(to: nested.appendingPathComponent("photo.png"))
        try Data("hidden".utf8).write(to: nested.appendingPathComponent(".notes.txt"))

        let snapshots = try DownloadsFileScanner().snapshots(in: root)

        XCTAssertEqual(Set(snapshots.map(\.relativePath)), [
            "top.pdf",
            "Project/Assets/photo.png",
            "Project/Assets/.notes.txt"
        ])
        XCTAssertEqual(
            snapshots.first { $0.fileName == "photo.png" }?.fileCategory,
            .image
        )
    }

    func testPackageIsOneItemAndSymbolicLinksAreIgnored() throws {
        let package = root.appendingPathComponent("Example.app", isDirectory: true)
        let packageContents = package.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: packageContents, withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: packageContents.appendingPathComponent("payload"))

        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDrop-Outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("outside".utf8).write(to: outside.appendingPathComponent("outside.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Linked", isDirectory: true),
            withDestinationURL: outside
        )

        let snapshots = try DownloadsFileScanner().snapshots(in: root)

        XCTAssertEqual(snapshots.map(\.relativePath), ["Example.app"])
        XCTAssertEqual(snapshots.first?.isPackage, true)
        XCTAssertEqual(snapshots.first?.fileCategory, .application)
    }
}
