import Foundation
import SQLite3

enum HistoryOutcomeFilter: String, CaseIterable, Sendable {
    case all
    case succeeded
    case failed

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .succeeded: return "成功"
        case .failed: return "失败"
        }
    }
}

struct HistoryFilter: Equatable, Sendable {
    var searchText = ""
    var outcome: HistoryOutcomeFilter = .all
    var category: HistoryFileCategory?

    static let all = HistoryFilter()
}

struct HistoryCursor: Equatable, Sendable {
    let performedAt: Date
    let id: UUID
}

struct HistoryPage: Equatable, Sendable {
    let records: [OperationRecord]
    let nextCursor: HistoryCursor?
    let totalCount: Int
}

enum HistoryExportFormat: String, CaseIterable, Sendable {
    case csv
    case json

    var fileExtension: String { rawValue }
    var displayName: String { rawValue.uppercased() }
}

enum HistoryStoreError: Error, LocalizedError {
    case openDatabase(String)
    case execute(String)
    case prepare(String)
    case bind(String)
    case step(String)
    case invalidRecord
    case unsupportedSchema(Int32)

    var errorDescription: String? {
        switch self {
        case .openDatabase(let message): return "无法打开整理历史数据库：\(message)"
        case .execute(let message): return "无法更新整理历史数据库：\(message)"
        case .prepare(let message): return "无法准备整理历史查询：\(message)"
        case .bind(let message): return "无法绑定整理历史查询参数：\(message)"
        case .step(let message): return "无法读取或写入整理历史：\(message)"
        case .invalidRecord: return "整理历史中包含无法解析的记录。"
        case .unsupportedSchema(let version):
            return "整理历史数据库版本 \(version) 高于当前应用支持的版本。"
        }
    }
}

/// Unbounded, local-only history storage. Managed-folder control state remains
/// in `LocalMetadataStore`; this database owns queryable operation history.
actor HistoryStore {
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
            throw HistoryStoreError.openDatabase(message)
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
        try self.init(databaseURL: Self.defaultDatabaseURL(fileManager: fileManager), fileManager: fileManager)
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
            .appendingPathComponent("daydrop-history.sqlite", isDirectory: false)
    }

    func importLegacyRecords(_ records: [OperationRecord]) throws {
        guard !records.isEmpty else { return }
        try transaction {
            for record in records {
                var legacyRecord = record
                if record.trigger != .legacyImport {
                    legacyRecord = OperationRecord(
                        id: record.id,
                        fileName: record.fileName,
                        sourcePath: record.sourcePath,
                        destinationPath: record.destinationPath,
                        performedAt: record.performedAt,
                        succeeded: record.succeeded,
                        errorMessage: record.errorMessage,
                        fileCategory: record.fileCategory,
                        trigger: .legacyImport,
                        operationKind: record.operationKind
                    )
                }
                try insert(legacyRecord, ignoreExisting: true)
            }
        }
    }

    func append(_ record: OperationRecord) throws {
        try insert(record, ignoreExisting: false)
    }

    func append(_ records: [OperationRecord]) throws {
        guard !records.isEmpty else { return }
        try transaction {
            for record in records {
                try insert(record, ignoreExisting: false)
            }
        }
    }

    func page(
        filter: HistoryFilter = .all,
        after cursor: HistoryCursor? = nil,
        limit: Int = HistoryStore.defaultPageSize
    ) throws -> HistoryPage {
        let safeLimit = min(max(limit, 1), 500)
        let totalCount = try count(filter: filter)
        let query = Self.selectSQL(filter: filter, cursor: cursor, includeLimit: true)
        let statement = try prepare(query.sql)
        defer { sqlite3_finalize(statement) }
        try bind(query.bindings + [.integer(Int64(safeLimit + 1))], to: statement)

        var records: [OperationRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw HistoryStoreError.step(lastErrorMessage) }
            records.append(try decodeRecord(from: statement))
        }

        let hasMore = records.count > safeLimit
        if hasMore { records.removeLast() }
        let nextCursor = hasMore ? records.last.map {
            HistoryCursor(performedAt: $0.performedAt, id: $0.id)
        } : nil
        return HistoryPage(records: records, nextCursor: nextCursor, totalCount: totalCount)
    }

    func count(filter: HistoryFilter = .all) throws -> Int {
        let query = Self.countSQL(filter: filter)
        let statement = try prepare(query.sql)
        defer { sqlite3_finalize(statement) }
        try bind(query.bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw HistoryStoreError.step(lastErrorMessage)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func export(
        filter: HistoryFilter,
        to destinationURL: URL,
        format: HistoryExportFormat,
        fileManager: FileManager = .default
    ) throws -> Int {
        let query = Self.selectSQL(filter: filter, cursor: nil, includeLimit: false)
        let statement = try prepare(query.sql)
        defer { sqlite3_finalize(statement) }
        try bind(query.bindings, to: statement)

        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("DayDrop-History-\(UUID().uuidString).\(format.fileExtension)")
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: temporaryURL)
        else {
            throw HistoryStoreError.execute("无法创建临时导出文件。")
        }
        defer {
            try? handle.close()
            try? fileManager.removeItem(at: temporaryURL)
        }

        if format == .csv {
            try handle.write(contentsOf: Data([0xEF, 0xBB, 0xBF]))
            try write(
                "ID,文件名,原位置,目标位置,整理时间,结果,文件类型,整理方式,操作类型,失败原因\n",
                to: handle
            )
        } else {
            try write("[\n", to: handle)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var exportedCount = 0
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw HistoryStoreError.step(lastErrorMessage) }
            let record = try decodeRecord(from: statement)
            if format == .csv {
                let values = [
                    record.id.uuidString,
                    record.fileName,
                    record.sourcePath,
                    record.destinationPath,
                    ISO8601DateFormatter().string(from: record.performedAt),
                    record.succeeded ? "成功" : "失败",
                    record.fileCategory.displayName,
                    record.trigger.displayName,
                    record.operationKind.rawValue,
                    record.errorMessage ?? ""
                ]
                try write(values.map(Self.csvField).joined(separator: ",") + "\n", to: handle)
            } else {
                if exportedCount > 0 { try write(",\n", to: handle) }
                try handle.write(contentsOf: encoder.encode(record))
            }
            exportedCount += 1
        }
        if format == .json { try write("\n]\n", to: handle) }
        try handle.synchronize()
        try handle.close()

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
        return exportedCount
    }

    private func insert(_ record: OperationRecord, ignoreExisting: Bool) throws {
        let clause = ignoreExisting ? "INSERT OR IGNORE" : "INSERT OR REPLACE"
        let sql = """
        \(clause) INTO history_records (
            id, file_name, source_path, destination_path, performed_at, succeeded,
            error_message, file_category, classifier_version, trigger, operation_kind
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind([
            .text(record.id.uuidString),
            .text(record.fileName),
            .text(record.sourcePath),
            .text(record.destinationPath),
            .double(record.performedAt.timeIntervalSince1970),
            .integer(record.succeeded ? 1 : 0),
            record.errorMessage.map(Binding.text) ?? .null,
            .text(record.fileCategory.rawValue),
            .integer(Int64(FileTypeClassifier.version)),
            .text(record.trigger.rawValue),
            .text(record.operationKind.rawValue)
        ], to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw HistoryStoreError.step(lastErrorMessage)
        }
    }

    private func decodeRecord(from statement: OpaquePointer?) throws -> OperationRecord {
        guard let id = UUID(uuidString: text(at: 0, from: statement)),
              let category = HistoryFileCategory(rawValue: text(at: 7, from: statement)),
              let trigger = HistoryOperationTrigger(rawValue: text(at: 8, from: statement)),
              let operationKind = HistoryOperationKind(rawValue: text(at: 9, from: statement))
        else {
            throw HistoryStoreError.invalidRecord
        }
        return OperationRecord(
            id: id,
            fileName: text(at: 1, from: statement),
            sourcePath: text(at: 2, from: statement),
            destinationPath: text(at: 3, from: statement),
            performedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            succeeded: sqlite3_column_int(statement, 5) != 0,
            errorMessage: sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil
                : text(at: 6, from: statement),
            fileCategory: category,
            trigger: trigger,
            operationKind: operationKind
        )
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let database else { throw HistoryStoreError.openDatabase("连接已关闭。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.prepare(lastErrorMessage)
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
            guard result == SQLITE_OK else { throw HistoryStoreError.bind(lastErrorMessage) }
        }
    }

    private func transaction(_ work: () throws -> Void) throws {
        guard let database else { throw HistoryStoreError.openDatabase("连接已关闭。") }
        try Self.execute("BEGIN IMMEDIATE TRANSACTION;", in: database)
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

    private func write(_ string: String, to handle: FileHandle) throws {
        guard let data = string.data(using: .utf8) else {
            throw HistoryStoreError.execute("无法编码导出内容。")
        }
        try handle.write(contentsOf: data)
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
            throw HistoryStoreError.unsupportedSchema(currentVersion)
        }
        guard currentVersion == 0 else { return }

        try execute(
            """
            CREATE TABLE IF NOT EXISTS history_records (
                id TEXT PRIMARY KEY NOT NULL,
                file_name TEXT NOT NULL,
                source_path TEXT NOT NULL,
                destination_path TEXT NOT NULL,
                performed_at REAL NOT NULL,
                succeeded INTEGER NOT NULL CHECK (succeeded IN (0, 1)),
                error_message TEXT,
                file_category TEXT NOT NULL,
                classifier_version INTEGER NOT NULL,
                trigger TEXT NOT NULL,
                operation_kind TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS history_records_time
                ON history_records(performed_at DESC, id DESC);
            CREATE INDEX IF NOT EXISTS history_records_outcome_time
                ON history_records(succeeded, performed_at DESC);
            CREATE INDEX IF NOT EXISTS history_records_category_time
                ON history_records(file_category, performed_at DESC);
            PRAGMA user_version = 1;
            """,
            in: database
        )
    }

    private static func userVersion(in database: OpaquePointer) throws -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.prepare(message(from: database))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw HistoryStoreError.step(message(from: database))
        }
        return sqlite3_column_int(statement, 0)
    }

    private static func selectSQL(
        filter: HistoryFilter,
        cursor: HistoryCursor?,
        includeLimit: Bool
    ) -> (sql: String, bindings: [Binding]) {
        let predicate = predicateSQL(filter: filter, cursor: cursor)
        let limit = includeLimit ? " LIMIT ?" : ""
        return (
            """
            SELECT id, file_name, source_path, destination_path, performed_at, succeeded,
                   error_message, file_category, trigger, operation_kind
            FROM history_records
            \(predicate.sql)
            ORDER BY performed_at DESC, id DESC\(limit);
            """,
            predicate.bindings
        )
    }

    private static func countSQL(filter: HistoryFilter) -> (sql: String, bindings: [Binding]) {
        let predicate = predicateSQL(filter: filter, cursor: nil)
        return ("SELECT COUNT(*) FROM history_records \(predicate.sql);", predicate.bindings)
    }

    private static func predicateSQL(
        filter: HistoryFilter,
        cursor: HistoryCursor?
    ) -> (sql: String, bindings: [Binding]) {
        var clauses: [String] = []
        var bindings: [Binding] = []
        let normalizedSearch = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedSearch.isEmpty {
            let pattern = "%\(escapeLike(normalizedSearch.lowercased()))%"
            clauses.append(
                "(LOWER(file_name) LIKE ? ESCAPE '\\' OR LOWER(source_path) LIKE ? ESCAPE '\\' OR LOWER(destination_path) LIKE ? ESCAPE '\\' OR LOWER(COALESCE(error_message, '')) LIKE ? ESCAPE '\\')"
            )
            bindings.append(contentsOf: Array(repeating: .text(pattern), count: 4))
        }
        switch filter.outcome {
        case .all: break
        case .succeeded:
            clauses.append("succeeded = 1")
        case .failed:
            clauses.append("succeeded = 0")
        }
        if let category = filter.category {
            clauses.append("file_category = ?")
            bindings.append(.text(category.rawValue))
        }
        if let cursor {
            clauses.append("(performed_at < ? OR (performed_at = ? AND id < ?))")
            bindings.append(.double(cursor.performedAt.timeIntervalSince1970))
            bindings.append(.double(cursor.performedAt.timeIntervalSince1970))
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

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func execute(_ sql: String, in database: OpaquePointer) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? message(from: database)
            sqlite3_free(errorPointer)
            throw HistoryStoreError.execute(message)
        }
    }

    private static func message(from database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return "未知错误" }
        return String(cString: message)
    }
}
