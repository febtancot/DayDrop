import Foundation
import XCTest
@testable import DayDrop

final class LocalMetadataStoreTests: XCTestCase {
    func testPrefixedManagedFolderPathPersists() async throws {
        let storageURL = try makeStorageURL()
        let store = try LocalMetadataStore(storageURL: storageURL)
        let folder = ManagedDayFolder(
            dateIdentifier: "2025-03-21",
            relativePath: "Year 2025/Month 2025-03/Day 2025-03-21"
        )

        try await store.upsertManagedFolder(folder)

        let reopenedStore = try LocalMetadataStore(storageURL: storageURL)
        let reopenedFolders = await reopenedStore.loadManagedFolders()
        XCTAssertEqual(reopenedFolders, [folder])
    }

    func testManagedFoldersPersistUpsertAndRemoveByStableDateIdentity() async throws {
        let storageURL = try makeStorageURL()
        let store = try LocalMetadataStore(storageURL: storageURL)

        try await store.upsertManagedFolder(
            ManagedDayFolder(dateIdentifier: "2026-08-11", relativePath: "0811")
        )
        try await store.upsertManagedFolder(
            ManagedDayFolder(dateIdentifier: "2025-03-21", relativePath: "2025/03/0321")
        )
        try await store.upsertManagedFolder(
            ManagedDayFolder(dateIdentifier: "2026-08-11", relativePath: "08/0811")
        )

        let reopenedStore = try LocalMetadataStore(storageURL: storageURL)
        var folders = await reopenedStore.loadManagedFolders()
        XCTAssertEqual(
            folders,
            [
                ManagedDayFolder(dateIdentifier: "2025-03-21", relativePath: "2025/03/0321"),
                ManagedDayFolder(dateIdentifier: "2026-08-11", relativePath: "08/0811")
            ]
        )

        try await reopenedStore.removeManagedFolder(dateIdentifier: "2025-03-21")
        folders = await reopenedStore.loadManagedFolders()
        XCTAssertEqual(
            folders,
            [ManagedDayFolder(dateIdentifier: "2026-08-11", relativePath: "08/0811")]
        )
    }

    func testInvalidManagedFolderDoesNotMutatePersistedSnapshot() async throws {
        let storageURL = try makeStorageURL()
        let store = try LocalMetadataStore(storageURL: storageURL)
        let valid = ManagedDayFolder(dateIdentifier: "2024-02-29", relativePath: "2024/02/0229")
        try await store.upsertManagedFolder(valid)
        let before = try Data(contentsOf: storageURL)

        do {
            try await store.upsertManagedFolder(
                ManagedDayFolder(dateIdentifier: "2023-02-29", relativePath: "02/0229")
            )
            XCTFail("An invalid calendar date should be rejected.")
        } catch let error as LocalMetadataStoreError {
            XCTAssertEqual(error, .invalidDateIdentifier("2023-02-29"))
        }

        do {
            try await store.upsertManagedFolder(
                ManagedDayFolder(dateIdentifier: "2026-08-11", relativePath: "../0811")
            )
            XCTFail("A path traversal should be rejected.")
        } catch let error as LocalMetadataStoreError {
            XCTAssertEqual(error, .invalidRelativePath("../0811"))
        }

        let foldersAfterInvalidMutations = await store.loadManagedFolders()
        XCTAssertEqual(foldersAfterInvalidMutations, [valid])
        XCTAssertEqual(try Data(contentsOf: storageURL), before)
    }

    func testOperationRecordsPreserveSuccessAndFailureAndKeepNewestFifty() async throws {
        let storageURL = try makeStorageURL()
        let store = try LocalMetadataStore(storageURL: storageURL)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<80 {
                group.addTask {
                    let succeeded = index.isMultiple(of: 2)
                    let record = OperationRecord(
                        fileName: "file-\(index).zip",
                        sourcePath: "/Downloads/file-\(index).zip",
                        destinationPath: "/Downloads/0811/file-\(index).zip",
                        performedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                        succeeded: succeeded,
                        errorMessage: succeeded ? nil : "move failed"
                    )
                    try await store.appendOperationRecord(record)
                }
            }
            try await group.waitForAll()
        }

        let records = await store.loadOperationRecords()
        XCTAssertEqual(records.count, 50)
        XCTAssertEqual(records.first?.performedAt, Date(timeIntervalSince1970: 79))
        XCTAssertEqual(records.last?.performedAt, Date(timeIntervalSince1970: 30))
        XCTAssertTrue(records.contains { !$0.succeeded && $0.errorMessage == "move failed" })
        XCTAssertTrue(records.contains { $0.succeeded && $0.errorMessage == nil })

        let reopenedStore = try LocalMetadataStore(storageURL: storageURL)
        let reopenedRecords = await reopenedStore.loadOperationRecords()
        XCTAssertEqual(reopenedRecords, records)
    }

    func testReplaceManagedFoldersRejectsDuplicateDateIdentity() async throws {
        let store = try LocalMetadataStore(storageURL: try makeStorageURL())
        let duplicates = [
            ManagedDayFolder(dateIdentifier: "2026-08-11", relativePath: "0811"),
            ManagedDayFolder(dateIdentifier: "2026-08-11", relativePath: "08/0811")
        ]

        do {
            try await store.replaceManagedFolders(duplicates)
            XCTFail("Duplicate date identities should be rejected.")
        } catch let error as LocalMetadataStoreError {
            XCTAssertEqual(error, .duplicateDateIdentifier("2026-08-11"))
        }

        let folders = await store.loadManagedFolders()
        XCTAssertEqual(folders, [])
    }

    func testPendingMigrationPersistsAndFinalizesInOneSnapshotReplacement() async throws {
        let storageURL = try makeStorageURL()
        let store = try LocalMetadataStore(storageURL: storageURL)
        let pending = ManagedDayFolder(
            dateIdentifier: "2026-07-27",
            relativePath: "0727",
            directoryIdentity: "volume:source",
            pendingRelativePath: "07/0727",
            pendingDestinationIdentity: "volume:destination"
        )
        try await store.upsertManagedFolder(pending)

        let reopenedPendingStore = try LocalMetadataStore(storageURL: storageURL)
        let reopenedPendingFolders = await reopenedPendingStore.loadManagedFolders()
        XCTAssertEqual(reopenedPendingFolders, [pending])

        let finalized = ManagedDayFolder(
            dateIdentifier: "2026-07-27",
            relativePath: "07/0727",
            directoryIdentity: "volume:destination"
        )
        try await reopenedPendingStore.upsertManagedFolder(finalized)

        let reopenedFinalStore = try LocalMetadataStore(storageURL: storageURL)
        let reopenedFinalFolders = await reopenedFinalStore.loadManagedFolders()
        XCTAssertEqual(reopenedFinalFolders, [finalized])
    }

    func testPendingDestinationIdentityRequiresPendingPath() async throws {
        let store = try LocalMetadataStore(storageURL: try makeStorageURL())

        do {
            try await store.upsertManagedFolder(
                ManagedDayFolder(
                    dateIdentifier: "2026-08-11",
                    relativePath: "0811",
                    directoryIdentity: "volume:source",
                    pendingDestinationIdentity: "volume:destination"
                )
            )
            XCTFail("A destination identity without a pending path should be rejected.")
        } catch let error as LocalMetadataStoreError {
            XCTAssertEqual(error, .invalidPendingMigration)
        }

        do {
            try await store.upsertManagedFolder(
                ManagedDayFolder(
                    dateIdentifier: "2026-08-11",
                    relativePath: "0811",
                    directoryIdentity: "volume:source",
                    pendingRelativePath: "08/0811"
                )
            )
            XCTFail("A pending path should declare whether its destination exists.")
        } catch let error as LocalMetadataStoreError {
            XCTAssertEqual(error, .invalidPendingMigration)
        }
    }

    private func makeStorageURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayDropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("metadata.json")
    }
}
