import XCTest
@testable import DayDrop

final class CollisionNameResolverTests: XCTestCase {
    func testReturnsOriginalNameWhenItIsAvailable() {
        XCTAssertEqual(
            CollisionNameResolver.availableName(for: "report.pdf", isTaken: { _ in false }),
            "report.pdf"
        )
    }

    func testAppendsFirstAvailableNumberBeforeExtension() {
        let occupied: Set<String> = ["report.pdf", "report (1).pdf"]

        let result = CollisionNameResolver.availableName(for: "report.pdf") {
            occupied.contains($0)
        }

        XCTAssertEqual(result, "report (2).pdf")
    }

    func testHandlesFileWithoutExtension() {
        let occupied: Set<String> = ["README", "README (1)", "README (2)"]

        let result = CollisionNameResolver.availableName(for: "README") {
            occupied.contains($0)
        }

        XCTAssertEqual(result, "README (3)")
    }

    func testInsertsNumberBeforeOnlyTheFinalExtension() {
        let occupied: Set<String> = ["backup.tar.gz"]

        let result = CollisionNameResolver.availableName(for: "backup.tar.gz") {
            occupied.contains($0)
        }

        XCTAssertEqual(result, "backup.tar (1).gz")
    }

    func testAvailableURLChecksCandidatesInTheSameDirectory() {
        let desiredURL = URL(fileURLWithPath: "/Downloads/0811/report.pdf")
        let occupied: Set<String> = ["report.pdf", "report (1).pdf"]

        let result = CollisionNameResolver.availableURL(for: desiredURL) {
            occupied.contains($0.lastPathComponent)
        }

        XCTAssertEqual(result.path, "/Downloads/0811/report (2).pdf")
    }
}
