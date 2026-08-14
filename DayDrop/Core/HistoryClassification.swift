import Foundation
import UniformTypeIdentifiers

public enum HistoryFileCategory: String, Codable, CaseIterable, Sendable {
    case document
    case image
    case audio
    case video
    case archive
    case diskImage = "disk_image"
    case application
    case code
    case font
    case data
    case other
    case unknown

    var displayName: String {
        switch self {
        case .document: return "文档"
        case .image: return "图片"
        case .audio: return "音频"
        case .video: return "视频"
        case .archive: return "压缩包"
        case .diskImage: return "磁盘映像"
        case .application: return "应用与安装包"
        case .code: return "代码"
        case .font: return "字体"
        case .data: return "数据"
        case .other: return "其他"
        case .unknown: return "未知"
        }
    }

    var systemImage: String {
        switch self {
        case .document: return "doc.text"
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .archive: return "archivebox"
        case .diskImage: return "opticaldiscdrive"
        case .application: return "app.dashed"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .font: return "textformat"
        case .data: return "tablecells"
        case .other: return "doc"
        case .unknown: return "questionmark.square.dashed"
        }
    }
}

public enum HistoryOperationTrigger: String, Codable, CaseIterable, Sendable {
    case automaticDownload = "automatic_download"
    case manualTopLevel = "manual_top_level"
    case manualDeep = "manual_deep"
    case scheduledMigration = "scheduled_migration"
    case legacyImport = "legacy_import"

    var displayName: String {
        switch self {
        case .automaticDownload: return "自动整理"
        case .manualTopLevel: return "手动整理"
        case .manualDeep: return "深度整理"
        case .scheduledMigration: return "目录迁移"
        case .legacyImport: return "旧版记录"
        }
    }
}

public enum HistoryOperationKind: String, Codable, Sendable {
    case fileMove = "file_move"
    case managedFolderMigration = "managed_folder_migration"
}

enum FileTypeClassifier {
    static let version = 1

    private static let diskImageExtensions: Set<String> = ["dmg", "iso", "img"]
    private static let applicationExtensions: Set<String> = ["app", "pkg", "mpkg"]
    private static let archiveExtensions: Set<String> = [
        "7z", "bz2", "gz", "rar", "tar", "tbz", "tbz2", "tgz", "txz", "xz", "zip"
    ]
    private static let codeExtensions: Set<String> = [
        "c", "cc", "cpp", "css", "go", "h", "hpp", "html", "java", "js", "jsx",
        "kt", "kts", "m", "mm", "php", "py", "rb", "rs", "sh", "sql", "swift",
        "ts", "tsx", "vue"
    ]
    private static let dataExtensions: Set<String> = [
        "csv", "geojson", "json", "jsonl", "ndjson", "parquet", "plist", "sqlite",
        "sqlite3", "tsv", "xml", "yaml", "yml"
    ]

    static func category(forFileName fileName: String) -> HistoryFileCategory {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard !fileExtension.isEmpty else { return .unknown }

        if diskImageExtensions.contains(fileExtension) { return .diskImage }
        if applicationExtensions.contains(fileExtension) { return .application }
        if archiveExtensions.contains(fileExtension) { return .archive }
        if codeExtensions.contains(fileExtension) { return .code }
        if dataExtensions.contains(fileExtension) { return .data }

        guard let type = UTType(filenameExtension: fileExtension) else {
            return .other
        }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .font) { return .font }
        if type.conforms(to: .sourceCode) { return .code }
        if type.conforms(to: .database) || type.conforms(to: .spreadsheet) { return .data }
        if type.conforms(to: .pdf)
            || type.conforms(to: .presentation)
            || type.conforms(to: .text)
            || type.conforms(to: .content) {
            return .document
        }
        return .other
    }
}

