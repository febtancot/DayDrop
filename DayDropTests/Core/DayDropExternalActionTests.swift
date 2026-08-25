import XCTest
@testable import DayDrop

final class DayDropExternalActionTests: XCTestCase {
    func testParsesOpenTodayFolderAction() throws {
        let url = try XCTUnwrap(URL(string: "daydrop://open-today-folder"))

        XCTAssertEqual(
            DayDropExternalAction(url: url),
            .openTodayFolder(targetDisplayID: nil)
        )
    }

    func testSchemeAndHostAreCaseInsensitive() throws {
        let url = try XCTUnwrap(URL(string: "DAYDROP://OPEN-TODAY-FOLDER"))

        XCTAssertEqual(
            DayDropExternalAction(url: url),
            .openTodayFolder(targetDisplayID: nil)
        )
    }

    func testParsesTargetDisplayIdentity() throws {
        let url = try XCTUnwrap(
            URL(string: "daydrop://open-today-folder?display-id=86A6C293-6A3B-4C70-9F3C-17D8A03479E2")
        )

        XCTAssertEqual(
            DayDropExternalAction(url: url),
            .openTodayFolder(targetDisplayID: "86A6C293-6A3B-4C70-9F3C-17D8A03479E2")
        )
    }

    func testRejectsUnknownOrExpandedRequests() throws {
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "daydrop://downloads"))))
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "daydrop://open-today-folder/extra"))))
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "daydrop://open-today-folder?source=test"))))
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "daydrop://open-today-folder?display-id="))))
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "daydrop://open-today-folder?display-id=screen%20one"))))
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "daydrop://open-today-folder?display-id=one&display-id=two"))))
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "https://open-today-folder"))))
    }
}
