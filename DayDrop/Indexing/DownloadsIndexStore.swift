import Foundation
import SQLite3

enum DownloadFilePresenceFilter: String, CaseIterable, Sendable {
    case current
    case unavailable
    case all

    var displayName: String {
        switch self {
        case .current: return "当前文件"
        case .unavailable: return "已移出或删除"
        case .all: return "全部文件"
        }
    }
}

struct DownloadFileFilter: Equatable, Sendable {
    var searchText = ""
    var category: HistoryFileCategory?
    var presence: DownloadFilePresenceFilter = .current

    static let current = DownloadFileFilter()
}

struct DownloadFileCursor: Equatable, Sendable {
    let lastSeenAt: Date
    let id: UUID
}

struct DownloadFilePage: Equatable, Sendable {
    let records: [IndexedDownloadFile]
    let nextCursor: DownloadFileCursor?
    let totalCount: Int
}

struct IndexedDownloadFile: Equatable, Identifiable, Sendable {
    let id: UUID
    let fileSystemIdentity: String
    let relativePath: String
    let fileName: String
    let size: UInt64?
    let creationDate: Date?
    let modificationDate: Date?
    let fileCategory: HistoryFileCategory
    let isPackage: Bool
    let firstSeenAt: Date
    let lastSeenAt: Date
    let isPresent: Bool
    let unavailableSince: Date?
}

enum DownloadFileChangeKind: String, Codable, CaseIterable, Sendable {
    case discovered
    case renamed
    case moved
    case modified
    case unavailable

    var displayName: String {
        switch self {
        case .discovered: return "发现"
        case .renamed: return "重命名"
        case .moved: return "移动"
        case .modified: return "修改"
        case .unavailable: return "移出或删除"
        }
    }
}

struct DownloadFileChange: Equatable, Identifiable, Sendable {
    let id: UUID
    let fileID: UUID
    let kind: DownloadFileChangeKind
    let oldRelativePath: String?
    let newRelativePath: String?
    let observedAt: Date
}

struct DownloadIndexReconciliationSummary: Equatable, Sendable {
    let discovered: Int
    let renamed: Int
    let moved: Int
    let modified: Int
    let unavailable: Int
    let indexedFileCount: Int

    static let empty = DownloadIndexReconciliationSummary(
        discovered: 0,
        renamed: 0,
        moved: 0,
        modified: 0,
        unavailable: 0,
        indexedFileCount: 0
    )

    var changeCount: Int { discovered + renamed + moved + modified + unavailable }
}

enum DownloadsIndexStoreError: Error, LocalizedError {
    case openDatabase(String)
    case execute(String)
    case prepare(String)
    case bind(String)
    case step(String)
    case invalidRecord
    case unsupportedSchema(Int32)

    var errorDescription: String? {
        switch self {
        case .openDatabase(let message): return "无法打开下载文件索引：\(message)"
        case .execute(let message): return "无法更新下载文件索引：\(message)"
        case .prepare(let message): return "无法准备下载文件索引查询：\(message)"
        case .bind(let message): return "无法绑定下载文件索引查询：\(message)"
        case .step(let message): return "无法读取或写入下载文件索引：\(message)"
        case .invalidRecord: return "下载文件索引中包含无法解析的记录。"
        case .unsupportedSchema(let version):
            return "下载文件索引版本 \(version) 高于当前应用支持的版本。"
        }
    }
}

/// Persistent current-state index plus an append-only change log. The index stores
/// metadata only; it never reads file contents.
actor DownloadsIndexStore {
    static let defaultPageSize = 50

    private let databaseURL: URL
    // SQLite access remains actor-serialized. `nonisolated(unsafe)` only permits
    // `deinit` to close the non-Sendable C pointer after actor use has ended.
    nonisolated(unsafe) private var database: OpaquePointer?

    init(databaseURL: URL, fileManager: FileManager = .default) throws {
        self.databaseURL = databaseURL.standardizedFileURL
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var openedDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &openedDatabase, flags, nil) == SQLITE_OK,
              let openedDatabase
        else {
            let message = Self.message(from: openedDatabase)
            sqlite3_close(openedDatabase)
            throw DownloadsIndexStoreError.openDatabase(message)
        }
        database = openedDatabase

        do {
            try Self.execute("PRAGMA foreign_keys = ON;", in: openedDatabase)
            try Self.execute("PRAGMA journal_mode = WAL;", in: openedDatabase)
            try Self.execute("PRAGMA synchronous = NORMAL;", in: openedDatabase)
            try Self.execute("PRAGMA busy_timeout = 3000;", in: openedDatabase)
            try Self.migrate(openedDatabase)
        } catch {
            sqlite3_close(openedDatabase)
            database = nil
            throw error
        }
    }

    init(fileManager: FileManager = .default) throws {
        try self.init(
            databaseURL: Self.defaultDatabaseURL(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    deinit {
        sqlite3_close(database)
    }

    static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let containerName = Bundle.main.bundleIdentifier ?? "com.liuyuhang.DayDrop"
        return applicationSupport
            .appendingPathComponent(containerName, isDirectory: true)
            .appendingPathComponent("daydrop-download-index.sqlite", isDirectory: false)
    }

    /// The first successful scan establishes a baseline without claiming that every
    /// pre-existing file was newly created. Later scans record offline and live changes.
    func reconcile(
        _ snapshots: [DownloadFileSnapshot],
        observedAt: Date = Date()
    ) throws -> DownloadIndexReconciliationSummary {
        let shouldRecordChanges = try isInitialized()
        let current = try currentRecords()
        var unmatchedOld = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var unmatchedSnapshotIndices = Set(snapshots.indices)
        var matches: [(IndexedDownloadFile, DownloadFileSnapshot)] = []

        // Exact path + identity matches are unambiguous, including hard links.
        let oldByPath = Dictionary(uniqueKeysWithValues: current.map { ($0.relativePath, $0) })
        for index in snapshots.indices {
            let snapshot = snapshots[index]
            guard let old = oldByPath[snapshot.relativePath],
                  FileSystemIdentity.identifiersMatchAtSamePath(
                      old.fileSystemIdentity,
                      snapshot.fileSystemIdentity
                  )
            else { continue }
            matches.append((old, snapshot))
            unmatchedOld.removeValue(forKey: old.id)
            unmatchedSnapshotIndices.remove(index)
        }

        // A unique remaining identity on both sides is a safe move/rename match.
        let oldGroups = Dictionary(grouping: unmatchedOld.values, by: \.fileSystemIdentity)
        let newGroups = Dictionary(grouping: unmatchedSnapshotIndices, by: {
            snapshots[$0].fileSystemIdentity
        })
        for (identity, oldRecords) in oldGroups where oldRecords.count == 1 {
            guard let newIndices = newGroups[identity], newIndices.count == 1,
                  let old = oldRecords.first,
                  let index = newIndices.first
            else { continue }
            matches.append((old, snapshots[index]))
            unmatchedOld.removeValue(forKey: old.id)
            unmatchedSnapshotIndices.remove(index)
        }

        var counts: [DownloadFileChangeKind: Int] = [:]
        try transaction {
            for (old, snapshot) in matches {
                var change: DownloadFileChangeKind?
                if old.relativePath != snapshot.relativePath {
                    change = Self.parentPath(old.relativePath) == Self.parentPath(snapshot.relativePath)
                        ? .renamed
                        : .moved
                } else if old.size != snapshot.size
                    || old.modificationDate != snapshot.modificationDate
                    || old.fileCategory != snapshot.fileCategory
                    || old.isPackage != snapshot.isPackage {
                    change = .modified
                }

                try update(old.id, with: snapshot, observedAt: observedAt)
                if shouldRecordChanges, let change {
                    try insertChange(
                        fileID: old.id,
                        kind: change,
                        oldPath: old.relativePath,
                        newPath: snapshot.relativePath,
                        observedAt: observedAt
                    )
                    counts[change, default: 0] += 1
                }
            }

            for index in unmatchedSnapshotIndices.sorted() {
                let snapshot = snapshots[index]
                let id = UUID()
                try insert(id: id, snapshot: snapshot, observedAt: observedAt)
                if shouldRecordChanges {
                    try insertChange(
                        fileID: id,
                        kind: .discovered,
                        oldPath: nil,
                        newPath: snapshot.relativePath,
                        observedAt: observedAt
                    )
                    counts[.discovered, default: 0] += 1
                }
            }

            for old in unmatchedOld.values {
                try markUnavailable(old.id, observedAt: observedAt)
                if shouldRecordChanges {
                    try insertChange(
                        fileID: old.id,
                        kind: .unavailable,
                        oldPath: old.relativePath,
                        newPath: nil,
                        observedAt: observedAt
                    )
                    counts[.unavailable, default: 0] += 1
                }
            }

            try setInitialized()
        }

        return DownloadIndexReconciliationSummary(
            discovered: counts[.discovered, default: 0],
            renamed: counts[.renamed, default: 0],
            moved: counts[.moved, default: 0],
            modified: counts[.modified, default: 0],
            unavailable: counts[.unavailable, default: 0],
            indexedFileCount: snapshots.count
        )
    }

    func page(
        filter: DownloadFileFilter = .current,
        after cursor: DownloadFileCursor? = nil,
        limit: Int = DownloadsIndexStore.defaultPageSize
    ) throws -> DownloadFilePage {
        let safeLimit = min(max(limit, 1), 500)
        let totalCount = try count(filter: filter)
        let query = Self.selectSQL(filter: filter, cursor: cursor)
        let statement = try prepare(query.sql)
        defer { sqlite3_finalize(statement) }
        try bind(query.bindings + [.integer(Int64(safeLimit + 1))], to: statement)

        var records: [IndexedDownloadFile] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw DownloadsIndexStoreError.step(lastErrorMessage)
            }
            records.append(try decodeRecord(from: statement))
        }

        let hasMore = records.count > safeLimit
        if hasMore { records.removeLast() }
        let nextCursor = hasMore ? records.last.map {
            DownloadFileCursor(lastSeenAt: $0.lastSeenAt, id: $0.id)
        } : nil
        return DownloadFilePage(records: records, nextCursor: nextCursor, totalCount: totalCount)
    }

    func count(filter: DownloadFileFilter = .current) throws -> Int {
        let predicate = Self.predicateSQL(filter: filter, cursor: nil)
        let statement = try prepare("SELECT COUNT(*) FROM indexed_files \(predicate.sql);")
        defer { sqlite3_finalize(statement) }
        try bind(predicate.bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DownloadsIndexStoreError.step(lastErrorMessage)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func changes(limit: Int = 500) throws -> [DownloadFileChange] {
        let statement = try prepare(
            """
            SELECT id, file_id, kind, old_relative_path, new_relative_path, observed_at
            FROM file_changes ORDER BY observed_at DESC, id DESC LIMIT ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([.integer(Int64(min(max(limit, 1), 5_000)))], to: statement)
        var changes: [DownloadFileChange] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW,
                  let id = UUID(uuidString: text(at: 0, from: statement)),
                  let fileID = UUID(uuidString: text(at: 1, from: statement)),
                  let kind = DownloadFileChangeKind(rawValue: text(at: 2, from: statement))
            else {
                throw DownloadsIndexStoreError.invalidRecord
            }
            changes.append(DownloadFileChange(
                id: id,
                fileID: fileID,
                kind: kind,
                oldRelativePath: optionalText(at: 3, from: statement),
                newRelativePath: optionalText(at: 4, from: statement),
                observedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            ))
        }
        return changes
    }

    private func currentRecords() throws -> [IndexedDownloadFile] {
        let statement = try prepare(
            """
            SELECT id, file_system_identity, relative_path, file_name, size,
                   creation_date, modification_date, file_category, is_package,
                   first_seen_at, last_seen_at, is_present, unavailable_since
            FROM indexed_files WHERE is_present = 1;
            """
        )
        defer { sqlite3_finalize(statement) }
        var records: [IndexedDownloadFile] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw DownloadsIndexStoreError.step(lastErrorMessage)
            }
            records.append(try decodeRecord(from: statement))
        }
        return records
    }

    private func insert(id: UUID, snapshot: DownloadFileSnapshot, observedAt: Date) throws {
        let statement = try prepare(
            """
            INSERT INTO indexed_files (
                id, file_system_identity, relative_path, file_name, size,
                creation_date, modification_date, file_category, classifier_version,
                is_package, first_seen_at, last_seen_at, is_present, unavailable_since
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, NULL);
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(Self.bindings(id: id, snapshot: snapshot, observedAt: observedAt), to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DownloadsIndexStoreError.step(lastErrorMessage)
        }
    }

    private func update(
        _ id: UUID,
        with snapshot: DownloadFileSnapshot,
        observedAt: Date
    ) throws {
        let statement = try prepare(
            """
            UPDATE indexed_files SET
                file_system_identity = ?, relative_path = ?, file_name = ?, size = ?,
                creation_date = ?, modification_date = ?, file_category = ?,
                classifier_version = ?, is_package = ?, last_seen_at = ?,
                is_present = 1, unavailable_since = NULL
            WHERE id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([
            .text(snapshot.fileSystemIdentity),
            .text(snapshot.relativePath),
            .text(snapshot.fileName),
            snapshot.size.map { .integer(Int64(clamping: $0)) } ?? .null,
            snapshot.creationDate.map { .double($0.timeIntervalSince1970) } ?? .null,
            snapshot.modificationDate.map { .double($0.timeIntervalSince1970) } ?? .null,
            .text(snapshot.fileCategory.rawValue),
            .integer(Int64(FileTypeClassifier.version)),
            .integer(snapshot.isPackage ? 1 : 0),
            .double(observedAt.timeIntervalSince1970),
            .text(id.uuidString)
        ], to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DownloadsIndexStoreError.step(lastErrorMessage)
        }
    }

    private func markUnavailable(_ id: UUID, observedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE indexed_files SET is_present = 0, unavailable_since = ? WHERE id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([.double(observedAt.timeIntervalSince1970), .text(id.uuidString)], to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DownloadsIndexStoreError.step(lastErrorMessage)
        }
    }

    private func insertChange(
        fileID: UUID,
        kind: DownloadFileChangeKind,
        oldPath: String?,
        newPath: String?,
        observedAt: Date
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO file_changes (
                id, file_id, kind, old_relative_path, new_relative_path, observed_at
            ) VALUES (?, ?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([
            .text(UUID().uuidString),
            .text(fileID.uuidString),
            .text(kind.rawValue),
            oldPath.map(Binding.text) ?? .null,
            newPath.map(Binding.text) ?? .null,
            .double(observedAt.timeIntervalSince1970)
        ], to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DownloadsIndexStoreError.step(lastErrorMessage)
        }
    }

    private func isInitialized() throws -> Bool {
        let statement = try prepare("SELECT value FROM index_metadata WHERE key = 'initialized';")
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return false }
        guard result == SQLITE_ROW else {
            throw DownloadsIndexStoreError.step(lastErrorMessage)
        }
        return text(at: 0, from: statement) == "1"
    }

    private func setInitialized() throws {
        try Self.execute(
            "INSERT OR REPLACE INTO index_metadata (key, value) VALUES ('initialized', '1');",
            in: database
        )
    }

    private func decodeRecord(from statement: OpaquePointer?) throws -> IndexedDownloadFile {
        guard let id = UUID(uuidString: text(at: 0, from: statement)),
              let category = HistoryFileCategory(rawValue: text(at: 7, from: statement))
        else {
            throw DownloadsIndexStoreError.invalidRecord
        }
        return IndexedDownloadFile(
            id: id,
            fileSystemIdentity: text(at: 1, from: statement),
            relativePath: text(at: 2, from: statement),
            fileName: text(at: 3, from: statement),
            size: optionalInt64(at: 4, from: statement).map(UInt64.init),
            creationDate: optionalDouble(at: 5, from: statement).map(Date.init(timeIntervalSince1970:)),
            modificationDate: optionalDouble(at: 6, from: statement).map(Date.init(timeIntervalSince1970:)),
            fileCategory: category,
            isPackage: sqlite3_column_int(statement, 8) != 0,
            firstSeenAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            lastSeenAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
            isPresent: sqlite3_column_int(statement, 11) != 0,
            unavailableSince: optionalDouble(at: 12, from: statement).map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func bindings(
        id: UUID,
        snapshot: DownloadFileSnapshot,
        observedAt: Date
    ) -> [Binding] {
        [
            .text(id.uuidString),
            .text(snapshot.fileSystemIdentity),
            .text(snapshot.relativePath),
            .text(snapshot.fileName),
            snapshot.size.map { .integer(Int64(clamping: $0)) } ?? .null,
            snapshot.creationDate.map { .double($0.timeIntervalSince1970) } ?? .null,
            snapshot.modificationDate.map { .double($0.timeIntervalSince1970) } ?? .null,
            .text(snapshot.fileCategory.rawValue),
            .integer(Int64(FileTypeClassifier.version)),
            .integer(snapshot.isPackage ? 1 : 0),
            .double(observedAt.timeIntervalSince1970),
            .double(observedAt.timeIntervalSince1970)
        ]
    }

    private static func parentPath(_ relativePath: String) -> String {
        (relativePath as NSString).deletingLastPathComponent
    }

    private static func selectSQL(
        filter: DownloadFileFilter,
        cursor: DownloadFileCursor?
    ) -> (sql: String, bindings: [Binding]) {
        let predicate = predicateSQL(filter: filter, cursor: cursor)
        return (
            """
            SELECT id, file_system_identity, relative_path, file_name, size,
                   creation_date, modification_date, file_category, is_package,
                   first_seen_at, last_seen_at, is_present, unavailable_since
            FROM indexed_files \(predicate.sql)
            ORDER BY last_seen_at DESC, id DESC LIMIT ?;
            """,
            predicate.bindings
        )
    }

    private static func predicateSQL(
        filter: DownloadFileFilter,
        cursor: DownloadFileCursor?
    ) -> (sql: String, bindings: [Binding]) {
        var clauses: [String] = []
        var bindings: [Binding] = []
        let search = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            let pattern = "%\(escapeLike(search.lowercased()))%"
            clauses.append(
                "(LOWER(file_name) LIKE ? ESCAPE '\\' OR LOWER(relative_path) LIKE ? ESCAPE '\\')"
            )
            bindings.append(contentsOf: [.text(pattern), .text(pattern)])
        }
        if let category = filter.category {
            clauses.append("file_category = ?")
            bindings.append(.text(category.rawValue))
        }
        switch filter.presence {
        case .current: clauses.append("is_present = 1")
        case .unavailable: clauses.append("is_present = 0")
        case .all: break
        }
        if let cursor {
            clauses.append("(last_seen_at < ? OR (last_seen_at = ? AND id < ?))")
            bindings.append(.double(cursor.lastSeenAt.timeIntervalSince1970))
            bindings.append(.double(cursor.lastSeenAt.timeIntervalSince1970))
            bindings.append(.text(cursor.id.uuidString))
        }
        return (clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND "), bindings)
    }

    private static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DownloadsIndexStoreError.prepare(lastErrorMessage)
        }
        return statement
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer?) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else {
                throw DownloadsIndexStoreError.bind(lastErrorMessage)
            }
        }
    }

    private func transaction(_ work: () throws -> Void) throws {
        try Self.execute("BEGIN IMMEDIATE;", in: database)
        do {
            try work()
            try Self.execute("COMMIT;", in: database)
        } catch {
            try? Self.execute("ROLLBACK;", in: database)
            throw error
        }
    }

    private var lastErrorMessage: String { Self.message(from: database) }

    private func text(at index: Int32, from statement: OpaquePointer?) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalText(at index: Int32, from statement: OpaquePointer?) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : text(at: index, from: statement)
    }

    private func optionalDouble(at index: Int32, from statement: OpaquePointer?) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(statement, index)
    }

    private func optionalInt64(at index: Int32, from statement: OpaquePointer?) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(statement, index)
    }

    private enum Binding {
        case text(String)
        case double(Double)
        case integer(Int64)
        case null
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func migrate(_ database: OpaquePointer) throws {
        let currentVersion = try userVersion(in: database)
        guard currentVersion <= 1 else {
            throw DownloadsIndexStoreError.unsupportedSchema(currentVersion)
        }
        guard currentVersion == 0 else { return }
        try execute(
            """
            CREATE TABLE IF NOT EXISTS index_metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS indexed_files (
                id TEXT PRIMARY KEY NOT NULL,
                file_system_identity TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                file_name TEXT NOT NULL,
                size INTEGER,
                creation_date REAL,
                modification_date REAL,
                file_category TEXT NOT NULL,
                classifier_version INTEGER NOT NULL,
                is_package INTEGER NOT NULL CHECK (is_package IN (0, 1)),
                first_seen_at REAL NOT NULL,
                last_seen_at REAL NOT NULL,
                is_present INTEGER NOT NULL CHECK (is_present IN (0, 1)),
                unavailable_since REAL
            );
            CREATE TABLE IF NOT EXISTS file_changes (
                id TEXT PRIMARY KEY NOT NULL,
                file_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                old_relative_path TEXT,
                new_relative_path TEXT,
                observed_at REAL NOT NULL,
                FOREIGN KEY(file_id) REFERENCES indexed_files(id)
            );
            CREATE INDEX IF NOT EXISTS indexed_files_presence_time
                ON indexed_files(is_present, last_seen_at DESC, id DESC);
            CREATE INDEX IF NOT EXISTS indexed_files_category_presence
                ON indexed_files(file_category, is_present, last_seen_at DESC);
            CREATE INDEX IF NOT EXISTS indexed_files_identity
                ON indexed_files(file_system_identity, is_present);
            CREATE INDEX IF NOT EXISTS file_changes_time
                ON file_changes(observed_at DESC, id DESC);
            PRAGMA user_version = 1;
            """,
            in: database
        )
    }

    private static func userVersion(in database: OpaquePointer) throws -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            throw DownloadsIndexStoreError.prepare(message(from: database))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DownloadsIndexStoreError.step(message(from: database))
        }
        return sqlite3_column_int(statement, 0)
    }

    private static func execute(_ sql: String, in database: OpaquePointer?) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? message(from: database)
            sqlite3_free(errorPointer)
            throw DownloadsIndexStoreError.execute(message)
        }
    }

    private static func message(from database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return "未知错误" }
        return String(cString: message)
    }
}
