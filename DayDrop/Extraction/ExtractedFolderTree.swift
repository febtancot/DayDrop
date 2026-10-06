import Darwin
import Foundation

struct ExtractionFileStamp: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ status: stat) {
        device = status.st_dev
        inode = status.st_ino
        size = status.st_size
        modifiedSeconds = Int64(status.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(status.st_mtimespec.tv_nsec)
        changedSeconds = Int64(status.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(status.st_ctimespec.tv_nsec)
    }

    static func read(at url: URL) -> ExtractionFileStamp? {
        var status = stat()
        guard lstat(url.path, &status) == 0,
              status.st_mode & S_IFMT != S_IFLNK else { return nil }
        return ExtractionFileStamp(status)
    }
}

struct ExtractedFolderTreeEntry: Equatable, Sendable {
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let stamp: ExtractionFileStamp
}

struct ExtractedFolderTree: Equatable, Sendable {
    let rootStamp: ExtractionFileStamp
    let entries: [ExtractedFolderTreeEntry]
}

struct ExtractedFolderTreeScanner: Sendable {
    let maximumEntries = 10_000

    func scan(at root: URL) throws -> ExtractedFolderTree {
        var rootStatus = stat()
        guard lstat(root.path, &rootStatus) == 0, rootStatus.st_mode & S_IFMT == S_IFDIR,
              (try? root.resourceValues(forKeys: [.isPackageKey]))?.isPackage == false,
              DayDropDirectoryOwnershipMarker.managedDateIdentifier(at: root) == nil,
              !DayDropDirectoryOwnershipMarker.isManagedContainer(root)
        else { throw ArchiveManifestError.unsafeOrEncrypted }
        let rootStamp = ExtractionFileStamp(rootStatus)
        var entries: [ExtractedFolderTreeEntry] = []
        var seenPaths: Set<String> = []
        var expandedSize: UInt64 = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        let rootDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard rootDescriptor >= 0 else { throw ArchiveManifestError.busy }
        defer { Darwin.close(rootDescriptor) }

        func visit(_ descriptor: Int32, prefix: String, expected: ExtractionFileStamp) throws {
            var before = stat()
            guard fstat(descriptor, &before) == 0, ExtractionFileStamp(before) == expected else { throw ArchiveManifestError.busy }
            let duplicate = dup(descriptor)
            guard duplicate >= 0 else { throw ArchiveManifestError.busy }
            guard let stream = fdopendir(duplicate) else {
                Darwin.close(duplicate)
                throw ArchiveManifestError.busy
            }
            defer { closedir(stream) }
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    guard errno == 0 else { throw ArchiveManifestError.busy }
                    break
                }
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw ArchiveManifestError.limitExceeded }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(validatingUTF8: $0) }
                }
                guard let name else { throw ArchiveManifestError.unsafeOrEncrypted }
                if name == "." || name == ".." { continue }
                guard entries.count < maximumEntries else { throw ArchiveManifestError.limitExceeded }
                let path = try ArchiveManifest.normalizedPath(prefix + name)
                guard seenPaths.insert(path).inserted else { throw ArchiveManifestError.busy }
                var status = stat()
                guard fstatat(descriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0,
                      status.st_dev == rootStatus.st_dev else { throw ArchiveManifestError.busy }
                let type = status.st_mode & S_IFMT
                guard type == S_IFDIR || (type == S_IFREG && status.st_nlink == 1), status.st_size >= 0 else {
                    throw ArchiveManifestError.unsafeOrEncrypted
                }
                let size = type == S_IFREG ? UInt64(status.st_size) : 0
                expandedSize += size
                guard expandedSize <= 20 * 1_024 * 1_024 * 1_024 else { throw ArchiveManifestError.limitExceeded }
                entries.append(ExtractedFolderTreeEntry(path: path, isDirectory: type == S_IFDIR, size: size, stamp: ExtractionFileStamp(status)))
                if type == S_IFDIR {
                    let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                    guard child >= 0 else { throw ArchiveManifestError.busy }
                    defer { Darwin.close(child) }
                    try visit(child, prefix: path + "/", expected: ExtractionFileStamp(status))
                }
            }
            var after = stat()
            guard fstat(descriptor, &after) == 0, ExtractionFileStamp(after) == expected else { throw ArchiveManifestError.busy }
        }
        try visit(rootDescriptor, prefix: "", expected: rootStamp)
        guard ExtractionFileStamp.read(at: root) == rootStamp else { throw ArchiveManifestError.busy }
        return ExtractedFolderTree(rootStamp: rootStamp, entries: entries.sorted { $0.path < $1.path })
    }
}

struct ExtractedFolderFinalization: Sendable {
    static let quietInterval: TimeInterval = 10
    var tree: ExtractedFolderTree
    var lastActivityUptime: TimeInterval

    mutating func observe(_ tree: ExtractedFolderTree, at uptime: TimeInterval) -> Bool {
        if self.tree != tree {
            self.tree = tree
            lastActivityUptime = uptime
            return false
        }
        return uptime - lastActivityUptime >= Self.quietInterval
    }

    mutating func recordActivity(at uptime: TimeInterval) {
        lastActivityUptime = max(lastActivityUptime, uptime)
    }
}
