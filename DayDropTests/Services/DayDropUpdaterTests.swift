import Foundation
import XCTest
@testable import DayDrop

final class DayDropUpdaterTests: XCTestCase {
    func testVersionInfoReadsBundleAndFormatsDisplays() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDropVersionFixture-\(UUID().uuidString).bundle", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.liuyuhang.DayDrop.VersionFixture",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "9.8.7",
            "CFBundleVersion": "654"
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"), options: .atomic)

        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        let version = DayDropVersionInfo(bundle: bundle)

        XCTAssertEqual(version.shortVersion, "9.8.7")
        XCTAssertEqual(version.build, "654")
        XCTAssertEqual(version.compactDisplay, "v9.8.7")
        XCTAssertEqual(version.detailedDisplay, "版本 9.8.7（构建 654）")
    }
}
