import Foundation

/// A DayDrop-owned day directory. `dateIdentifier` is deliberately stored as a
/// calendar string so its identity cannot drift when the system time zone changes.
public struct ManagedDayFolder: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let dateIdentifier: String
    public var relativePath: String
    public var directoryIdentity: String?
    public var pendingRelativePath: String?
    public var pendingDestinationIdentity: String?
    public var pendingDestinationExpectedAbsent: Bool

    public init(
        dateIdentifier: String,
        relativePath: String,
        directoryIdentity: String? = nil,
        pendingRelativePath: String? = nil,
        pendingDestinationIdentity: String? = nil,
        pendingDestinationExpectedAbsent: Bool = false
    ) {
        self.id = dateIdentifier
        self.dateIdentifier = dateIdentifier
        self.relativePath = relativePath
        self.directoryIdentity = directoryIdentity
        self.pendingRelativePath = pendingRelativePath
        self.pendingDestinationIdentity = pendingDestinationIdentity
        self.pendingDestinationExpectedAbsent = pendingDestinationExpectedAbsent
    }

    public static func isValidDateIdentifier(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10,
              bytes[4] == 45,
              bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.suffix(2)),
              (1...9999).contains(year),
              (1...12).contains(month),
              (1...31).contains(day)
        else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else {
            return false
        }

        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == year && roundTrip.month == month && roundTrip.day == day
    }

    public static func isValidRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("\0")
        else {
            return false
        }

        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case dateIdentifier
        case relativePath
        case directoryIdentity
        case pendingRelativePath
        case pendingDestinationIdentity
        case pendingDestinationExpectedAbsent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(String.self, forKey: .id)
        let dateIdentifier = try container.decode(String.self, forKey: .dateIdentifier)
        let relativePath = try container.decode(String.self, forKey: .relativePath)
        let directoryIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .directoryIdentity
        )
        let pendingRelativePath = try container.decodeIfPresent(
            String.self,
            forKey: .pendingRelativePath
        )
        let pendingDestinationIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .pendingDestinationIdentity
        )
        let pendingDestinationExpectedAbsent = try container.decodeIfPresent(
            Bool.self,
            forKey: .pendingDestinationExpectedAbsent
        ) ?? false

        guard decodedID == dateIdentifier,
              Self.isValidDateIdentifier(dateIdentifier),
              Self.isValidRelativePath(relativePath),
              directoryIdentity?.isEmpty != true,
              pendingRelativePath.map(Self.isValidRelativePath) ?? true,
              pendingDestinationIdentity?.isEmpty != true,
              pendingRelativePath != nil
                || (pendingDestinationIdentity == nil && !pendingDestinationExpectedAbsent),
              pendingRelativePath == nil
                || pendingDestinationIdentity != nil
                || pendingDestinationExpectedAbsent,
              !(pendingDestinationIdentity != nil && pendingDestinationExpectedAbsent)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .dateIdentifier,
                in: container,
                debugDescription: "Managed day folder identity, path, or pending migration is invalid."
            )
        }

        self.id = decodedID
        self.dateIdentifier = dateIdentifier
        self.relativePath = relativePath
        self.directoryIdentity = directoryIdentity
        self.pendingRelativePath = pendingRelativePath
        self.pendingDestinationIdentity = pendingDestinationIdentity
        self.pendingDestinationExpectedAbsent = pendingDestinationExpectedAbsent
    }
}

public struct OperationRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let fileName: String
    public let sourcePath: String
    public let destinationPath: String
    public let performedAt: Date
    public let succeeded: Bool
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        fileName: String,
        sourcePath: String,
        destinationPath: String,
        performedAt: Date = Date(),
        succeeded: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.performedAt = performedAt
        self.succeeded = succeeded
        self.errorMessage = errorMessage
    }
}

public enum LocalMetadataStoreError: Error, Equatable, LocalizedError {
    case invalidDateIdentifier(String)
    case invalidRelativePath(String)
    case invalidDirectoryIdentity
    case invalidPendingMigration
    case duplicateDateIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDateIdentifier(let value):
            return "Invalid managed-folder date identifier: \(value)"
        case .invalidRelativePath(let value):
            return "Invalid managed-folder relative path: \(value)"
        case .invalidDirectoryIdentity:
            return "Managed-folder directory identity is invalid."
        case .invalidPendingMigration:
            return "Managed-folder pending migration is invalid."
        case .duplicateDateIdentifier(let value):
            return "Duplicate managed-folder date identifier: \(value)"
        }
    }
}

/// Serializes all mutations and replaces one JSON snapshot atomically, ensuring a
/// failed write never partially updates the in-memory or on-disk state.
public actor LocalMetadataStore {
    private struct PersistedState: Codable {
        var schemaVersion: Int
        var managedFolders: [ManagedDayFolder]
        var operationRecords: [OperationRecord]

        static let empty = PersistedState(
            schemaVersion: 1,
            managedFolders: [],
            operationRecords: []
        )
    }

    public static let defaultMaximumOperationRecords = 50

    private let storageURL: URL
    private let maximumOperationRecords: Int
    private let fileManager: FileManager
    private var state: PersistedState

    public init(
        storageURL: URL,
        maximumOperationRecords: Int = LocalMetadataStore.defaultMaximumOperationRecords,
        fileManager: FileManager = .default
    ) throws {
        self.storageURL = storageURL.standardizedFileURL
        self.maximumOperationRecords = max(1, maximumOperationRecords)
        self.fileManager = fileManager

        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: storageURL.path) {
            let data = try Data(contentsOf: storageURL, options: [.mappedIfSafe])
            let decoder = JSONDecoder()
            let decodedState = try decoder.decode(PersistedState.self, from: data)
            self.state = Self.normalized(decodedState, limit: self.maximumOperationRecords)
        } else {
            self.state = .empty
        }
    }

    public init(
        maximumOperationRecords: Int = LocalMetadataStore.defaultMaximumOperationRecords,
        fileManager: FileManager = .default
    ) throws {
        let storageURL = try Self.defaultStorageURL(fileManager: fileManager)
        try self.init(
            storageURL: storageURL,
            maximumOperationRecords: maximumOperationRecords,
            fileManager: fileManager
        )
    }

    public static func defaultStorageURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let containerName = Bundle.main.bundleIdentifier ?? "com.liuyuhang.DayDrop"
        return applicationSupport
            .appendingPathComponent(containerName, isDirectory: true)
            .appendingPathComponent("daydrop-local-metadata.json", isDirectory: false)
    }

    public func loadManagedFolders() -> [ManagedDayFolder] {
        state.managedFolders.sorted { lhs, rhs in
            lhs.dateIdentifier < rhs.dateIdentifier
        }
    }

    public func upsertManagedFolder(_ folder: ManagedDayFolder) throws {
        try Self.validate(folder)
        var candidate = state

        if let index = candidate.managedFolders.firstIndex(where: { $0.id == folder.id }) {
            candidate.managedFolders[index] = folder
        } else {
            candidate.managedFolders.append(folder)
        }

        try commit(candidate)
    }

    public func replaceManagedFolders(_ folders: [ManagedDayFolder]) throws {
        try folders.forEach(Self.validate)
        let identifiers = folders.map(\.id)
        guard Set(identifiers).count == identifiers.count else {
            let duplicate = Dictionary(grouping: identifiers, by: { $0 })
                .first(where: { $0.value.count > 1 })?.key ?? "unknown"
            throw LocalMetadataStoreError.duplicateDateIdentifier(duplicate)
        }

        var candidate = state
        candidate.managedFolders = folders
        try commit(candidate)
    }

    public func removeManagedFolder(id: String) throws {
        var candidate = state
        candidate.managedFolders.removeAll { $0.id == id }
        guard candidate.managedFolders != state.managedFolders else {
            return
        }
        try commit(candidate)
    }

    public func removeManagedFolder(dateIdentifier: String) throws {
        try removeManagedFolder(id: dateIdentifier)
    }

    /// Returns newest records first.
    public func loadOperationRecords() -> [OperationRecord] {
        state.operationRecords
    }

    /// Convenience alias for coordinators that use the shorter domain term.
    public func loadOperations() -> [OperationRecord] {
        loadOperationRecords()
    }

    public func appendOperationRecord(_ record: OperationRecord) throws {
        try appendOperationRecords([record])
    }

    public func appendOperationRecords(_ records: [OperationRecord]) throws {
        guard !records.isEmpty else {
            return
        }

        var candidate = state
        candidate.operationRecords.append(contentsOf: records)
        candidate.operationRecords = Self.mostRecent(
            candidate.operationRecords,
            limit: maximumOperationRecords
        )
        try commit(candidate)
    }

    public func clearOperationRecords() throws {
        guard !state.operationRecords.isEmpty else {
            return
        }

        var candidate = state
        candidate.operationRecords = []
        try commit(candidate)
    }

    private func commit(_ candidate: PersistedState) throws {
        let normalized = Self.normalized(candidate, limit: maximumOperationRecords)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(normalized)
        try data.write(to: storageURL, options: [.atomic])
        state = normalized
    }

    private static func validate(_ folder: ManagedDayFolder) throws {
        guard folder.id == folder.dateIdentifier,
              ManagedDayFolder.isValidDateIdentifier(folder.dateIdentifier)
        else {
            throw LocalMetadataStoreError.invalidDateIdentifier(folder.dateIdentifier)
        }
        guard ManagedDayFolder.isValidRelativePath(folder.relativePath) else {
            throw LocalMetadataStoreError.invalidRelativePath(folder.relativePath)
        }
        guard folder.directoryIdentity?.isEmpty != true,
              folder.pendingDestinationIdentity?.isEmpty != true
        else {
            throw LocalMetadataStoreError.invalidDirectoryIdentity
        }
        guard folder.pendingRelativePath.map(ManagedDayFolder.isValidRelativePath) ?? true,
              folder.pendingRelativePath != nil
                || (folder.pendingDestinationIdentity == nil
                    && !folder.pendingDestinationExpectedAbsent),
              folder.pendingRelativePath == nil
                || folder.pendingDestinationIdentity != nil
                || folder.pendingDestinationExpectedAbsent,
              !(folder.pendingDestinationIdentity != nil
                && folder.pendingDestinationExpectedAbsent)
        else {
            throw LocalMetadataStoreError.invalidPendingMigration
        }
    }

    private static func normalized(_ state: PersistedState, limit: Int) -> PersistedState {
        PersistedState(
            schemaVersion: state.schemaVersion,
            managedFolders: state.managedFolders.sorted { $0.dateIdentifier < $1.dateIdentifier },
            operationRecords: mostRecent(state.operationRecords, limit: limit)
        )
    }

    private static func mostRecent(_ records: [OperationRecord], limit: Int) -> [OperationRecord] {
        Array(records.sorted { lhs, rhs in
            if lhs.performedAt == rhs.performedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.performedAt > rhs.performedAt
        }.prefix(limit))
    }
}
