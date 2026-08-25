import CoreGraphics
import XCTest
@testable import DayDrop

final class FinderWindowPlacementTests: XCTestCase {
    func testCentersFinderWindowOnDisplayAboveAndRightOfPrimaryScreen() throws {
        let primary = CGRect(x: 0, y: 0, width: 1_800, height: 1_169)
        let external = CGRect(x: 2_116, y: 1_169, width: 1_920, height: 1_080)

        let placement = try XCTUnwrap(
            FinderWindowPlacement.centered(
                in: external,
                primaryScreenFrame: primary
            )
        )

        XCTAssertEqual(placement.bounds, CGRect(x: 2_576, y: -890, width: 1_000, height: 700))
        XCTAssertEqual(placement.appleScriptList, "{2576, -890, 3576, -190}")
    }

    func testWindowSizeIsClampedInsideSmallerDisplay() throws {
        let primary = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let visible = CGRect(x: -800, y: 100, width: 800, height: 600)

        let placement = try XCTUnwrap(
            FinderWindowPlacement.centered(
                in: visible,
                primaryScreenFrame: primary
            )
        )

        XCTAssertEqual(placement.bounds.width, 704)
        XCTAssertEqual(placement.bounds.height, 504)
        XCTAssertGreaterThanOrEqual(placement.bounds.minX, visible.minX)
        XCTAssertLessThanOrEqual(placement.bounds.maxX, visible.maxX)
    }

    func testRejectsDisplayTooSmallForUsableFinderWindow() {
        XCTAssertNil(
            FinderWindowPlacement.centered(
                in: CGRect(x: 0, y: 0, width: 200, height: 150),
                primaryScreenFrame: CGRect(x: 0, y: 0, width: 1_800, height: 1_169)
            )
        )
    }

    func testAppleScriptEscapesFolderPath() throws {
        let placement = try XCTUnwrap(
            FinderWindowPlacement.centered(
                in: CGRect(x: 0, y: 0, width: 1_800, height: 1_100),
                primaryScreenFrame: CGRect(x: 0, y: 0, width: 1_800, height: 1_169)
            )
        )
        let script = FinderFolderPresenter.appleScriptSource(
            folderPath: "/tmp/a\"b\\c",
            placement: placement
        )

        XCTAssertTrue(script.contains("POSIX file \"/tmp/a\\\"b\\\\c\""))
        XCTAssertTrue(script.contains("set bounds of targetWindow to"))
    }
}
