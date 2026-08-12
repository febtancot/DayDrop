import XCTest
@testable import DayDrop

final class ArchiveTargetOwnershipPolicyTests: XCTestCase {
    private let day = ArchiveDay(encoded: "2026-08-11")!

    func testMatchingManagedFolderRemainsManaged() {
        let preparation = makePreparation(
            ownershipDateIdentifier: day.encoded
        )
        let existing = ManagedDayFolder(
            dateIdentifier: day.encoded,
            relativePath: preparation.relativeFolderPath,
            directoryIdentity: preparation.directoryIdentity
        )

        XCTAssertEqual(
            ArchiveTargetOwnershipPolicy.evaluate(
                preparation: preparation,
                existingFolder: existing,
                dateIdentifier: day.encoded
            ),
            .manage
        )
    }

    func testCreatedFolderCannotOverwriteExistingFolderForSameDate() {
        let preparation = makePreparation(
            relativePath: "Month 2026-08/Day 2026-08-11",
            identity: "new-target",
            ownershipDateIdentifier: day.encoded,
            wasCreated: true
        )
        let existing = ManagedDayFolder(
            dateIdentifier: day.encoded,
            relativePath: "0811",
            directoryIdentity: "old-target",
            pendingRelativePath: "Month 2026-08/Day 2026-08-11",
            pendingDestinationExpectedAbsent: true
        )

        let decision = ArchiveTargetOwnershipPolicy.evaluate(
            preparation: preparation,
            existingFolder: existing,
            dateIdentifier: day.encoded
        )

        guard case .reject = decision else {
            return XCTFail("An existing same-date record must never be overwritten.")
        }
    }

    func testNewlyCreatedFolderCanBeClaimedWhenNoRecordExists() {
        let preparation = makePreparation(
            ownershipDateIdentifier: day.encoded,
            wasCreated: true
        )

        XCTAssertEqual(
            ArchiveTargetOwnershipPolicy.evaluate(
                preparation: preparation,
                existingFolder: nil,
                dateIdentifier: day.encoded
            ),
            .claimAndManage
        )
    }

    func testPreexistingUnmarkedFolderStaysUnmanaged() {
        let preparation = makePreparation(ownershipDateIdentifier: nil)

        XCTAssertEqual(
            ArchiveTargetOwnershipPolicy.evaluate(
                preparation: preparation,
                existingFolder: nil,
                dateIdentifier: day.encoded
            ),
            .leaveUnmanaged
        )
    }

    func testPreexistingFolderMarkedForSameDateCanBeReclaimed() {
        let preparation = makePreparation(
            ownershipDateIdentifier: day.encoded
        )

        XCTAssertEqual(
            ArchiveTargetOwnershipPolicy.evaluate(
                preparation: preparation,
                existingFolder: nil,
                dateIdentifier: day.encoded
            ),
            .claimAndManage
        )
    }

    func testFolderMarkedForAnotherDateIsRejected() {
        let preparation = makePreparation(
            ownershipDateIdentifier: "2026-08-10"
        )

        let decision = ArchiveTargetOwnershipPolicy.evaluate(
            preparation: preparation,
            existingFolder: nil,
            dateIdentifier: day.encoded
        )

        guard case .reject = decision else {
            return XCTFail("A folder owned by another date must be rejected.")
        }
    }

    func testMissingMarkerOnMatchingRecordRequestsMarkerRepair() {
        let preparation = makePreparation(ownershipDateIdentifier: nil)
        let existing = ManagedDayFolder(
            dateIdentifier: day.encoded,
            relativePath: preparation.relativeFolderPath,
            directoryIdentity: preparation.directoryIdentity
        )

        XCTAssertEqual(
            ArchiveTargetOwnershipPolicy.evaluate(
                preparation: preparation,
                existingFolder: existing,
                dateIdentifier: day.encoded
            ),
            .repairMarkerAndManage
        )
    }

    private func makePreparation(
        relativePath: String = "Day 2026-08-11",
        identity: String = "device:inode",
        ownershipDateIdentifier: String?,
        wasCreated: Bool = false
    ) -> ArchiveFolderPreparationResult {
        ArchiveFolderPreparationResult(
            sourceDay: day,
            relativeFolderPath: relativePath,
            folderURL: URL(fileURLWithPath: "/tmp/DayDropTests/\(relativePath)"),
            directoryIdentity: identity,
            ownershipDateIdentifier: ownershipDateIdentifier,
            wasCreated: wasCreated,
            succeeded: true,
            errorMessage: nil
        )
    }
}
