import Darwin
import Foundation

struct TopLevelFileSnapshot: Equatable, Sendable {
    let url: URL
    let identity: String
    let fileName: String
    let isHidden: Bool
    let isDirectory: Bool
    let isRegularFile: Bool
    let isSymbolicLink: Bool
    let size: UInt64?
    let creationDate: Date?
    let modificationDate: Date?

    var existingFileArchiveDay: ArchiveDay? {
        ExistingFileDateResolver().archiveDay(
            creationDate: creationDate,
            modificationDate: modificationDate
        )
    }
}

struct FileCandidateScanner {
    private let fileManager: FileManager
    private let policy: DownloadCandidatePolicy

    init(
        fileManager: FileManager = .default,
        policy: DownloadCandidatePolicy = DownloadCandidatePolicy()
    ) {
        self.fileManager = fileManager
        self.policy = policy
    }

    func topLevelSnapshots(in rootURL: URL) throws -> [TopLevelFileSnapshot] {
        let keys: Set<URLResourceKey> = [
            .isHiddenKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ]

        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
        ).compactMap { snapshot(at: $0, prefetchedKeys: keys) }
    }

    func snapshot(at url: URL) -> TopLevelFileSnapshot? {
        snapshot(
            at: url,
            prefetchedKeys: [
                .isHiddenKey,
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .fileResourceIdentifierKey
            ]
        )
    }

    func isEligible(_ snapshot: TopLevelFileSnapshot) -> Bool {
        !snapshot.isSymbolicLink && snapshot.isRegularFile && policy.isEligible(
            fileName: snapshot.fileName,
            isHidden: snapshot.isHidden,
            isDirectory: snapshot.isDirectory
        )
    }

    /// Advisory locks are cooperative. A failed acquisition proves the file is
    /// currently locked; a successful acquisition is combined with suffix and
    /// size-stability checks before a move is attempted.
    func canAcquireExclusiveAdvisoryLock(on url: URL) -> Bool {
        let descriptor = open(
            url.path,
            O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            return false
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            return false
        }
        defer { flock(descriptor, LOCK_UN) }
        return true
    }

    private func snapshot(
        at url: URL,
        prefetchedKeys keys: Set<URLResourceKey>
    ) -> TopLevelFileSnapshot? {
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return nil
        }

        let identity = FileSystemIdentity.itemIdentifier(at: url)
            ?? url.standardizedFileURL.path
        let fileSize = values.fileSize.flatMap { $0 >= 0 ? UInt64($0) : nil }

        return TopLevelFileSnapshot(
            url: url,
            identity: identity,
            fileName: url.lastPathComponent,
            isHidden: values.isHidden ?? url.lastPathComponent.hasPrefix("."),
            isDirectory: values.isDirectory ?? false,
            isRegularFile: values.isRegularFile ?? false,
            isSymbolicLink: values.isSymbolicLink ?? false,
            size: fileSize,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate
        )
    }
}
