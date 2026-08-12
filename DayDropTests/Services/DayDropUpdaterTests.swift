import Foundation
import XCTest
@testable import DayDrop

final class DayDropUpdaterTests: XCTestCase {
    func testCurrentVersionUsesReleaseConfiguration() {
        let version = DayDropVersionInfo.current

        XCTAssertEqual(version.shortVersion, "1.0.2")
        XCTAssertEqual(version.build, "3")
        XCTAssertEqual(version.compactDisplay, "v1.0.2")
        XCTAssertEqual(version.detailedDisplay, "版本 1.0.2（构建 3）")
    }
}
