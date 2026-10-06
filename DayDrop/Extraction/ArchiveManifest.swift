import Foundation

enum ArchiveManifestError: Error, LocalizedError {
    case unreadable
    case unsafeOrEncrypted
    case limitExceeded
    case busy

    var errorDescription: String? {
        switch self {
        case .unreadable: return "无法完整读取压缩包目录清单，未移动文件夹。"
        case .unsafeOrEncrypted: return "压缩包或文件夹包含无法安全核对的加密、链接或路径，未移动文件夹。"
        case .limitExceeded: return "文件夹或压缩包超过自动检查上限，未移动文件夹。"
        case .busy: return "文件夹或对应压缩包仍在变化或被占用，稍后重试。"
        }
    }
}

struct ArchiveManifestEntry: Equatable, Sendable {
    let path: String
    let isDirectory: Bool
    let size: UInt64
}

struct ArchiveManifest: Equatable, Sendable {
    let entries: [String: ArchiveManifestEntry]
    let rootDirectory: String?

    init(entries rawEntries: [ArchiveManifestEntry]) throws {
        var entries: [String: ArchiveManifestEntry] = [:]
        var caseFoldedPaths: [String: String] = [:]
        for raw in rawEntries {
            let path = try Self.normalizedPath(raw.path)
            guard !Self.isExtractionMetadata(path) else { continue }
            let entry = ArchiveManifestEntry(path: path, isDirectory: raw.isDirectory, size: raw.isDirectory ? 0 : raw.size)
            if let existing = entries[path], existing != entry { throw ArchiveManifestError.unsafeOrEncrypted }
            let folded = path.lowercased()
            if let existing = caseFoldedPaths[folded], existing != path { throw ArchiveManifestError.unsafeOrEncrypted }
            entries[path] = entry
            caseFoldedPaths[folded] = path
        }
        guard entries.values.contains(where: { !$0.isDirectory }) else { throw ArchiveManifestError.unreadable }

        // ZIP writers may omit explicit parent-directory records.
        for entry in Array(entries.values) {
            var parts = entry.path.split(separator: "/").map(String.init)
            while parts.count > 1 {
                parts.removeLast()
                let parent = parts.joined(separator: "/")
                if let existing = entries[parent], !existing.isDirectory { throw ArchiveManifestError.unsafeOrEncrypted }
                entries[parent] = ArchiveManifestEntry(path: parent, isDirectory: true, size: 0)
            }
        }
        guard entries.count <= 10_000 else { throw ArchiveManifestError.limitExceeded }
        self.entries = entries
        let roots = Set(entries.keys.compactMap { $0.split(separator: "/").first.map(String.init) })
        self.rootDirectory = roots.count == 1 && entries[roots.first!]?.isDirectory == true ? roots.first : nil
    }

    static func normalizedPath(_ value: String) throws -> String {
        var path = value.precomposedStringWithCanonicalMapping
        while path.hasPrefix("./") { path.removeFirst(2) }
        while path.hasSuffix("/") { path.removeLast() }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              path.utf8.count <= 4_096, parts.count <= 64,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") })
        else { throw ArchiveManifestError.unsafeOrEncrypted }
        return path
    }

    static func isExtractionMetadata(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        return parts.contains("__MACOSX") || parts.last == ".DS_Store" || parts.contains(where: { $0.hasPrefix("._") })
    }

    func matches(tree: ExtractedFolderTree, folderName: String, archiveName: String) -> Bool {
        let actual = tree.entries.filter { !Self.isExtractionMetadata($0.path) }
        let actualEntries = Dictionary(uniqueKeysWithValues: actual.map {
            ($0.path, ArchiveManifestEntry(path: $0.path, isDirectory: $0.isDirectory, size: $0.isDirectory ? 0 : $0.size))
        })
        let archiveNameMatches = Self.archiveStemAliases(archiveName).contains { Self.matchesOutputName(folderName, base: $0) }
        if archiveNameMatches, entries == actualEntries { return true }

        // Some tools unpack a single stored root directly; others wrap a flat
        // archive in a directory named after the archive. Support both layouts.
        guard let root = rootDirectory,
              Self.matchesOutputName(folderName, base: root) || archiveNameMatches
        else { return false }
        let prefix = root + "/"
        let unwrapped = Dictionary(uniqueKeysWithValues: entries.values.compactMap { entry -> (String, ArchiveManifestEntry)? in
            guard entry.path.hasPrefix(prefix) else { return nil }
            let path = String(entry.path.dropFirst(prefix.count))
            return (path, ArchiveManifestEntry(path: path, isDirectory: entry.isDirectory, size: entry.size))
        })
        return unwrapped == actualEntries
    }

    func canMatchName(_ folderName: String, archiveName: String) -> Bool {
        Self.archiveStemAliases(archiveName).contains { Self.matchesOutputName(folderName, base: $0) }
            || (rootDirectory.map { Self.matchesOutputName(folderName, base: $0) } ?? false)
    }

    static func archiveStemAliases(_ archiveName: String) -> [String] {
        let stem = (archiveName as NSString).deletingPathExtension
        guard stem.hasSuffix(")"), let start = stem.range(of: " (", options: .backwards) else { return [stem] }
        let number = stem[start.upperBound..<stem.index(before: stem.endIndex)]
        guard !number.isEmpty, number.allSatisfy(\.isASCII), number.allSatisfy(\.isNumber),
              Int(number).map({ $0 > 0 }) == true else { return [stem] }
        return [stem, String(stem[..<start.lowerBound])]
    }

    static func matchesOutputName(_ folderName: String, base: String) -> Bool {
        let folder = folderName.precomposedStringWithCanonicalMapping
        let base = base.precomposedStringWithCanonicalMapping
        if folder == base { return true }
        guard folder.hasPrefix(base + " ") else { return false }
        let suffix = String(folder.dropFirst(base.count + 1))
        let number = suffix.hasPrefix("(") && suffix.hasSuffix(")")
            ? String(suffix.dropFirst().dropLast()) : suffix
        return !number.isEmpty && number.allSatisfy(\.isASCII) && number.allSatisfy(\.isNumber)
            && (Int(number).map { (1...999).contains($0) } ?? false)
    }
}

struct ArchiveManifestReader: Sendable {
    static let supportedExtensions: Set<String> = ["zip", "rar", "7z"]

    func read(at url: URL) throws -> ArchiveManifest {
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else { throw ArchiveManifestError.unreadable }
        let buffer = ManifestBuffer()
        let code = DDReadArchiveManifest(url.path, 10_000, 20 * 1_024 * 1_024 * 1_024, 5, { path, directory, size, context in
            guard let path, let context, let name = String(validatingUTF8: path) else { return 1 }
            let buffer = Unmanaged<ManifestBuffer>.fromOpaque(context).takeUnretainedValue()
            buffer.entries.append(ArchiveManifestEntry(path: name, isDirectory: directory != 0, size: UInt64(size)))
            return 0
        }, Unmanaged.passUnretained(buffer).toOpaque())
        switch code {
        case 0: return try ArchiveManifest(entries: buffer.entries)
        case 2: throw ArchiveManifestError.unsafeOrEncrypted
        case 3: throw ArchiveManifestError.limitExceeded
        case 4: throw ArchiveManifestError.busy
        default: throw ArchiveManifestError.unreadable
        }
    }
}

private final class ManifestBuffer {
    var entries: [ArchiveManifestEntry] = []
}
