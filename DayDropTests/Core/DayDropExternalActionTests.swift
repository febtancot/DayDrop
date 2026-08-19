import XCTest
@testable import DayDrop

final class DayDropExternalActionTests: XCTestCase {
    func testParsesOpenTodayFolderAction() throws {
        let url = try XCTUnwrap(URL(string: "daydrop://open-today-folder"))

        XCTAssertEqual(DayDropExternalAction(url: url), .openTodayFolder)
    }

    func testSchemeAndHostAreCaseInsensitive() throws {
        let url = try XCTUnwrap(URL(string: "DAYDROP://OPEN-TODAY-FOLDER"))

        XCTAssertEqual(DayDropExternalAction(url: url), .openTodayFolder)
    }

    func testRejectsUnknownOrExpandedRequests() throws {
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "daydrop://downloads"))))
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "daydrop://open-today-folder/extra"))))
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "daydrop://open-today-folder?source=test"))))
        XCTAssertNil(DayDropExternalAction(url: try XCTUnwrap(URL(string: "https://open-today-folder"))))
    }
}
