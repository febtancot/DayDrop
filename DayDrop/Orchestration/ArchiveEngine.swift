import Darwin
import Foundation

enum FileSystemIdentity {
    static func directoryIdentifier(at url: URL) -> String? {
        identifier(at: url, requireDirectory: true, allowSymbolicLink: false)
    }

    static func itemIdentifier(at url: URL) -> String? {
        identifier(at: url, requireDirectory: false, allowSymbolicLink: false)
    }

    static func pathEntryIdentifier(at url: URL) -> String? {
        identifier(at: url, requireDirectory: false, allowSymbolicLink: true)
    }

    private static func identifier(
        at url: URL,
        requireDirectory: Bool,
        allowSymbolicLink: Bool
    ) -> String? {
        var fileStatus = stat()
        guard lstat(url.path, &fileStatus) == 0 else { return nil }
        let itemType = fileStatus.st_mode & S_IFMT
        guard (allowSymbolicLink || itemType != S_IFLNK),
              !requireDirectory || itemType == S_IFDIR
        else {
            return nil
        }
        // `st_dev` identifies the volume and `st_ino` the item on that
        // volume. Unlike URL resource-value caching, lstat reflects the path
        // entry at the exact validation point and survives a directory rename.
        return "\(fileStatus.st_dev):\(fileStatus.st_ino)"
    }
}

enum DayDropDirectoryOwnershipMarker {
    private static let dateAttributeName = "com.liuyuhang.DayDrop.managed-date"
    private static let containerAttributeName = "com.liuyuhang.DayDrop.managed-container"

    static func mark(_ url: URL, dateIdentifier: String) throws {
        try write(Data(dateIdentifier.utf8), named: dateAttributeName, to: url)
    }

    static func managedDateIdentifier(at url: URL) -> String? {
        guard let data = read(named: dateAttributeName, from: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func markManagedContainer(_ url: URL) throws {
        try write(Data([1]), named: containerAttributeName, to: url)
    }

    static func isManagedContainer(_ url: URL) -> Bool {
        read(named: containerAttributeName, from: url) == Data([1])
    }

    private static func write(_ data: Data, named attributeName: String, to url: URL) throws {
        let result = url.path.withCString { pathPointer in
            attributeName.withCString { namePointer in
                data.withUnsafeBytes { bytes in
                    setxattr(
                        pathPointer,
                        namePointer,
                        bytes.baseAddress,
                        data.count,
                        0,
                        0
                    )
                }
            }
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func read(named attributeName: String, from url: URL) -> Data? {
        let size = url.path.withCString { pathPointer in
            attributeName.withCString { namePointer in
                getxattr(pathPointer, namePointer, nil, 0, 0, 0)
            }
        }
        guard size > 0 else { return nil }

        var data = Data(count: size)
        let readCount = data.withUnsafeMutableBytes { bytes in
            url.path.withCString { pathPointer in
                attributeName.withCString { namePointer in
                    getxattr(
                        pathPointer,
                        namePointer,
                        bytes.baseAddress,
                        size,
                        0,
                        0
                    )
                }
            }
        }
        guard readCount == size else { return nil }
        return data
    }
}

struct ManagedFolderDescriptor: Equatable, Sendable {
    let dateIdentifier: String
    let relativePath: String
    let directoryIdentity: String?
    let pendingRelativePath: String?
    let pendingDestinationIdentity: String?
    let pendingDestinationExpectedAbsent: Bool

    init(
        dateIdentifier: String,
        relativePath: String,
        directoryIdentity: String? = nil,
        pendingRelativePath: String? = nil,
        pendingDestinationIdentity: String? = nil,
        pendingDestinationExpectedAbsent: Bool = false
    ) {
        self.dateIdentifier = dateIdentifier
        self.relativePath = relativePath
        self.directoryIdentity = directoryIdentity
        self.pendingRelativePath = pendingRelativePath
        self.pendingDestinationIdentity = pendingDestinationIdentity
        self.pendingDestinationExpectedAbsent = pendingDestinationExpectedAbsent
    }
}

struct ArchiveFileMoveResult: Equatable, Sendable {
    let sourceURL: URL
    let destinationURL: URL
    let sourceDay: ArchiveDay
    let relativeFolderPath: String
    let succeeded: Bool
    let errorMessage: String?
}

struct ArchiveFolderPreparationResult: Equatable, Sendable {
    let sourceDay: ArchiveDay
    let relativeFolderPath: String
    let folderURL: URL
    let directoryIdentity: String?
    let ownershipDateIdentifier: String?
    let wasCreated: Bool
    let succeeded: Bool
    let errorMessage: String?
}

final class ArchiveMigrationCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

enum ManagedFolderMigrationState: Equatable, Sendable {
    case unchanged
    case moved
    case sourceMissing
    case cancelled
    case failed
}

struct ManagedFolderMigrationResult: Equatable, Sendable {
    let descriptor: ManagedFolderDescriptor
    let expectedRelativePath: String
    let sourceURL: URL
    let destinationURL: URL
    let state: ManagedFolderMigrationState
    let errorMessage: String?
}

struct ArchiveFileOperations {
    var fileExists: (URL) -> Bool
    var isDirectory: (URL) -> Bool
    var createDirectory: (URL) throws -> Void
    var moveItem: (URL, URL) throws -> Void
    var removeItem: (URL) throws -> Void
    var directoryContents: (URL) throws -> [URL]
    var directoryIdentity: (URL) -> String?
    var itemIdentity: (URL) -> String?
    var pathEntryIdentity: (URL) -> String?

    static func live(fileManager: FileManager = .default) -> ArchiveFileOperations {
        ArchiveFileOperations(
            fileExists: { fileManager.fileExists(atPath: $0.path) },
            isDirectory: { url in
                guard let values = try? url.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                ) else {
                    return false
                }
                // A directory symlink inside a managed folder must be moved as
                // one link entry. Recursing through it could otherwise move
                // files that live outside the authorized Downloads hierarchy.
                return values.isDirectory == true && values.isSymbolicLink != true
            },
            createDirectory: { url in
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            },
            moveItem: { source, destination in
                try fileManager.moveItem(at: source, to: destination)
            },
            removeItem: { url in
                try fileManager.removeItem(at: url)
            },
            directoryContents: { url in
                try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: []
                )
            },
            directoryIdentity: FileSystemIdentity.directoryIdentifier(at:),
            itemIdentity: FileSystemIdentity.itemIdentifier(at:),
            pathEntryIdentity: FileSystemIdentity.pathEntryIdentifier(at:)
        )
    }
}

/// Serializes all mutating archive operations.
///
/// Moving a file on the Downloads volume preserves its metadata. Folder
/// migration uses an atomic directory move when possible and a retry-safe merge
/// only when the destination already exists.
actor ArchiveEngine {
    private let operations: ArchiveFileOperations
    private let router: ArchivePathRouter

    init(
        calendar: Calendar = DayDropCalendar.local(),
        operations: ArchiveFileOperations = .live()
    ) {
        self.router = ArchivePathRouter(calendar: calendar)
        self.operations = operations
    }

    func prepareTargetFolder(
        for sourceDay: ArchiveDay,
        relativeTo today: ArchiveDay,
        in rootURL: URL
    ) -> ArchiveFolderPreparationResult {
        let route = router.route(for: sourceDay, relativeTo: today)
        let root = rootURL.standardizedFileURL
        guard let targetFolder = safeDescendant(
            of: root,
            relativePath: route.relativePath
        ) else {
            return folderPreparationFailure(
                sourceDay: sourceDay,
                relativePath: route.relativePath,
                folderURL: root,
                message: "目标路径无效。"
            )
        }

        let existedBeforePreparation = operations.fileExists(targetFolder)
        let missingContainers = missingAncestorContainers(
            of: root,
            relativePath: route.relativePath
        )
        do {
            if existedBeforePreparation, !operations.isDirectory(targetFolder) {
                throw ArchiveEngineError.destinationIsNotDirectory(targetFolder)
            }
            try operations.createDirectory(targetFolder)
            guard let revalidatedFolder = safeDescendant(
                of: root,
                relativePath: route.relativePath
            ),
                  revalidatedFolder.standardizedFileURL
                    == targetFolder.standardizedFileURL,
                  operations.isDirectory(targetFolder)
            else {
                throw ArchiveEngineError.unsafeDestination(targetFolder)
            }
            guard let identity = operations.directoryIdentity(targetFolder) else {
                throw ArchiveEngineError.directoryIdentityUnavailable(targetFolder)
            }
            for container in missingContainers {
                try? DayDropDirectoryOwnershipMarker.markManagedContainer(container)
            }
            let ownershipDateIdentifier: String?
            if existedBeforePreparation {
                ownershipDateIdentifier = DayDropDirectoryOwnershipMarker
                    .managedDateIdentifier(at: targetFolder)
            } else {
                try DayDropDirectoryOwnershipMarker.mark(
                    targetFolder,
                    dateIdentifier: sourceDay.encoded
                )
                ownershipDateIdentifier = sourceDay.encoded
            }

            return ArchiveFolderPreparationResult(
                sourceDay: sourceDay,
                relativeFolderPath: route.relativePath,
                folderURL: targetFolder,
                directoryIdentity: identity,
                ownershipDateIdentifier: ownershipDateIdentifier,
                wasCreated: !existedBeforePreparation,
                succeeded: true,
                errorMessage: nil
            )
        } catch {
            if !existedBeforePreparation,
               operations.fileExists(targetFolder),
               (try? operations.directoryContents(targetFolder).isEmpty) == true {
                try? operations.removeItem(targetFolder)
            }
            return folderPreparationFailure(
                sourceDay: sourceDay,
                relativePath: route.relativePath,
                folderURL: targetFolder,
                message: error.localizedDescription
            )
        }
    }

    func discardPreparedTargetFolderIfEmpty(
        _ preparation: ArchiveFolderPreparationResult,
        in rootURL: URL
    ) -> Bool {
        guard preparation.succeeded,
              preparation.wasCreated,
              let expectedIdentity = preparation.directoryIdentity,
              let folderURL = safeDescendant(
                  of: rootURL.standardizedFileURL,
                  relativePath: preparation.relativeFolderPath
              ),
              folderURL.standardizedFileURL == preparation.folderURL.standardizedFileURL,
              operations.directoryIdentity(folderURL) == expectedIdentity,
              (try? operations.directoryContents(folderURL).isEmpty) == true
        else {
            return false
        }

        do {
            try operations.removeItem(folderURL)
            return true
        } catch {
            return false
        }
    }

    func moveFile(
        at sourceURL: URL,
        sourceDay: ArchiveDay,
        relativeTo today: ArchiveDay,
        in rootURL: URL,
        expectedSourceIdentity: String? = nil,
        expectedTargetDirectoryIdentity: String? = nil
    ) -> ArchiveFileMoveResult {
        let route = router.route(for: sourceDay, relativeTo: today)
        let root = rootURL.standardizedFileURL

        guard isSafeFileSource(sourceURL, inside: root, maximumDepth: 2) else {
            return ArchiveFileMoveResult(
                sourceURL: sourceURL,
                destinationURL: root,
                sourceDay: sourceDay,
                relativeFolderPath: route.relativePath,
                succeeded: false,
                errorMessage: "来源文件不在“下载”目录顶层或下一层安全路径中。"
            )
        }

        guard let targetFolder = safeDescendant(of: root, relativePath: route.relativePath) else {
            return ArchiveFileMoveResult(
                sourceURL: sourceURL,
                destinationURL: root,
                sourceDay: sourceDay,
                relativeFolderPath: route.relativePath,
                succeeded: false,
                errorMessage: "目标路径无效。"
            )
        }

        let desiredURL = targetFolder.appendingPathComponent(
            sourceURL.lastPathComponent,
            isDirectory: false
        )
        let sourceAlreadyAtDestination = sourceURL.standardizedFileURL
            == desiredURL.standardizedFileURL
        let destinationURL = sourceAlreadyAtDestination
            ? sourceURL.standardizedFileURL
            : CollisionNameResolver.availableURL(for: desiredURL) {
                operations.fileExists($0)
            }

        do {
            try operations.createDirectory(targetFolder)
            guard let revalidatedFolder = safeDescendant(
                of: root,
                relativePath: route.relativePath
            ),
                  revalidatedFolder.standardizedFileURL
                    == targetFolder.standardizedFileURL,
                  operations.isDirectory(targetFolder)
            else {
                throw ArchiveEngineError.unsafeDestination(targetFolder)
            }
            if let expectedTargetDirectoryIdentity,
               operations.directoryIdentity(targetFolder) != expectedTargetDirectoryIdentity {
                throw ArchiveEngineError.destinationIdentityChanged(targetFolder)
            }

            guard let heldLock = HeldAdvisoryFileLock(url: sourceURL) else {
                throw ArchiveEngineError.sourceIsBusy(sourceURL)
            }
            if let expectedSourceIdentity,
               operations.itemIdentity(sourceURL) != expectedSourceIdentity {
                throw ArchiveEngineError.sourceIdentityChanged(sourceURL)
            }
            if sourceAlreadyAtDestination {
                return ArchiveFileMoveResult(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    sourceDay: sourceDay,
                    relativeFolderPath: route.relativePath,
                    succeeded: true,
                    errorMessage: nil
                )
            }
            try withExtendedLifetime(heldLock) {
                try operations.moveItem(sourceURL, destinationURL)
            }
            return ArchiveFileMoveResult(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                sourceDay: sourceDay,
                relativeFolderPath: route.relativePath,
                succeeded: true,
                errorMessage: nil
            )
        } catch {
            return ArchiveFileMoveResult(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                sourceDay: sourceDay,
                relativeFolderPath: route.relativePath,
                succeeded: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    func migrateManagedFolder(
        _ descriptor: ManagedFolderDescriptor,
        relativeTo today: ArchiveDay,
        in rootURL: URL,
        cancellationToken: ArchiveMigrationCancellationToken? = nil
    ) -> ManagedFolderMigrationResult {
        let root = rootURL.standardizedFileURL
        guard let sourceDay = ArchiveDay(encoded: descriptor.dateIdentifier) else {
            return invalidMigrationResult(
                descriptor: descriptor,
                rootURL: root,
                message: "受管理目录的完整日期无效。"
            )
        }

        let routedPath = router.route(for: sourceDay, relativeTo: today).relativePath
        // A persisted intent is completed before considering a newer routing
        // boundary. This makes an interrupted merge restartable and keeps its
        // destination stable across process launches.
        let expectedPath = descriptor.pendingRelativePath ?? routedPath
        guard
            let sourceURL = safeDescendant(of: root, relativePath: descriptor.relativePath),
            let destinationURL = safeDescendant(of: root, relativePath: expectedPath)
        else {
            return invalidMigrationResult(
                descriptor: descriptor,
                rootURL: root,
                expectedPath: expectedPath,
                message: "受管理目录路径无效。"
            )
        }
        if descriptor.pendingRelativePath != nil,
           ((descriptor.pendingDestinationIdentity != nil)
                == descriptor.pendingDestinationExpectedAbsent) {
            return failedMigrationResult(
                descriptor: descriptor,
                expectedPath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                message: "目录迁移意图缺少明确的目标存在性预期。"
            )
        }
        if cancellationToken?.isCancelled == true {
            return cancelledMigrationResult(
                descriptor: descriptor,
                expectedPath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
        }

        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            guard operations.fileExists(sourceURL) else {
                return ManagedFolderMigrationResult(
                    descriptor: descriptor,
                    expectedRelativePath: expectedPath,
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    state: .sourceMissing,
                    errorMessage: nil
                )
            }
            guard operations.isDirectory(sourceURL) else {
                return failedMigrationResult(
                    descriptor: descriptor,
                    expectedPath: expectedPath,
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    message: "受管理路径不再是目录。"
                )
            }
            if let recordedIdentity = descriptor.directoryIdentity,
               operations.directoryIdentity(sourceURL) != recordedIdentity {
                return failedMigrationResult(
                    descriptor: descriptor,
                    expectedPath: expectedPath,
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    message: "受管理目录的文件系统身份已变化，已拒绝操作。"
                )
            }
            return ManagedFolderMigrationResult(
                descriptor: descriptor,
                expectedRelativePath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                state: .unchanged,
                errorMessage: nil
            )
        }

        guard descriptor.pendingRelativePath != nil else {
            return failedMigrationResult(
                descriptor: descriptor,
                expectedPath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                message: "目录迁移意图尚未持久化，已拒绝移动。"
            )
        }

        guard operations.fileExists(sourceURL) else {
            if descriptor.pendingRelativePath != nil,
               canRecoverCompletedMigration(
                   descriptor: descriptor,
                   destinationURL: destinationURL
               ) {
                return ManagedFolderMigrationResult(
                    descriptor: descriptor,
                    expectedRelativePath: expectedPath,
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    state: .moved,
                    errorMessage: nil
                )
            }
            return ManagedFolderMigrationResult(
                descriptor: descriptor,
                expectedRelativePath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                state: .sourceMissing,
                errorMessage: nil
            )
        }

        guard operations.isDirectory(sourceURL) else {
            return failedMigrationResult(
                descriptor: descriptor,
                expectedPath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                message: "受管理路径不再是目录。"
            )
        }
        guard let recordedIdentity = descriptor.directoryIdentity else {
            return failedMigrationResult(
                descriptor: descriptor,
                expectedPath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                message: "受管理目录缺少可验证的文件系统身份。"
            )
        }
        guard operations.directoryIdentity(sourceURL) == recordedIdentity else {
            return failedMigrationResult(
                descriptor: descriptor,
                expectedPath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                message: "受管理目录的文件系统身份已变化，已拒绝迁移。"
            )
        }
        guard destinationMatchesPendingExpectation(
            descriptor: descriptor,
            destinationURL: destinationURL
        ) else {
            return failedMigrationResult(
                descriptor: descriptor,
                expectedPath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                message: "迁移目标在意图保存后发生变化，已拒绝合并。"
            )
        }
        let missingDestinationContainers = missingAncestorContainers(
            of: root,
            relativePath: expectedPath
        )

        do {
            if cancellationToken?.isCancelled == true {
                throw ArchiveEngineError.cancelled
            }
            try operations.createDirectory(destinationURL.deletingLastPathComponent())

            guard let revalidatedDestination = safeDescendant(
                of: root,
                relativePath: expectedPath
            ),
                  revalidatedDestination.standardizedFileURL
                    == destinationURL.standardizedFileURL
            else {
                throw ArchiveEngineError.unsafeDestination(destinationURL)
            }
            for container in missingDestinationContainers {
                try? DayDropDirectoryOwnershipMarker.markManagedContainer(container)
            }

            guard operations.directoryIdentity(sourceURL) == recordedIdentity else {
                throw ArchiveEngineError.sourceIdentityChanged(sourceURL)
            }
            guard destinationMatchesPendingExpectation(
                descriptor: descriptor,
                destinationURL: destinationURL
            ) else {
                throw ArchiveEngineError.destinationIdentityChanged(destinationURL)
            }

            if operations.fileExists(destinationURL) {
                guard !descriptor.pendingDestinationExpectedAbsent,
                      let expectedDestinationIdentity = descriptor.pendingDestinationIdentity,
                      operations.isDirectory(destinationURL),
                      operations.directoryIdentity(destinationURL) == expectedDestinationIdentity
                else {
                    throw ArchiveEngineError.destinationIdentityChanged(destinationURL)
                }
                try mergeDirectory(
                    sourceURL,
                    into: destinationURL,
                    expectedSourceIdentity: recordedIdentity,
                    expectedDestinationIdentity: expectedDestinationIdentity,
                    cancellationToken: cancellationToken
                )
            } else {
                guard descriptor.pendingDestinationExpectedAbsent else {
                    throw ArchiveEngineError.destinationIdentityChanged(destinationURL)
                }
                if cancellationToken?.isCancelled == true {
                    throw ArchiveEngineError.cancelled
                }
                try operations.moveItem(sourceURL, destinationURL)
            }

            // Moving/merging the managed day folder is authoritative. Parent
            // cleanup is best-effort so a cleanup permission error cannot turn
            // a successful migration into an untracked on-disk state.
            try? removeEmptyAncestors(
                startingAt: sourceURL.deletingLastPathComponent(),
                stoppingBefore: root
            )

            return ManagedFolderMigrationResult(
                descriptor: descriptor,
                expectedRelativePath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                state: .moved,
                errorMessage: nil
            )
        } catch ArchiveEngineError.cancelled {
            return cancelledMigrationResult(
                descriptor: descriptor,
                expectedPath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
        } catch {
            return ManagedFolderMigrationResult(
                descriptor: descriptor,
                expectedRelativePath: expectedPath,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                state: .failed,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func mergeDirectory(
        _ sourceURL: URL,
        into destinationURL: URL,
        expectedSourceIdentity: String,
        expectedDestinationIdentity: String,
        cancellationToken: ArchiveMigrationCancellationToken?
    ) throws {
        guard operations.isDirectory(sourceURL),
              operations.directoryIdentity(sourceURL) == expectedSourceIdentity
        else {
            throw ArchiveEngineError.sourceIsNotDirectory(sourceURL)
        }
        guard operations.isDirectory(destinationURL),
              operations.directoryIdentity(destinationURL) == expectedDestinationIdentity
        else {
            throw ArchiveEngineError.destinationIsNotDirectory(destinationURL)
        }
        let children = try operations.directoryContents(sourceURL)

        for sourceChild in children {
            if cancellationToken?.isCancelled == true {
                throw ArchiveEngineError.cancelled
            }
            guard operations.directoryIdentity(sourceURL) == expectedSourceIdentity else {
                throw ArchiveEngineError.sourceIdentityChanged(sourceURL)
            }
            guard operations.directoryIdentity(destinationURL) == expectedDestinationIdentity else {
                throw ArchiveEngineError.destinationIdentityChanged(destinationURL)
            }
            guard let sourceChildIdentity = operations.pathEntryIdentity(sourceChild) else {
                throw ArchiveEngineError.sourceIdentityChanged(sourceChild)
            }
            let desiredDestination = destinationURL.appendingPathComponent(
                sourceChild.lastPathComponent,
                isDirectory: operations.isDirectory(sourceChild)
            )

            if operations.isDirectory(sourceChild),
               operations.fileExists(desiredDestination),
               operations.isDirectory(desiredDestination) {
                guard let sourceDirectoryIdentity = operations.directoryIdentity(sourceChild),
                      sourceDirectoryIdentity == sourceChildIdentity,
                      let destinationDirectoryIdentity = operations.directoryIdentity(
                          desiredDestination
                      )
                else {
                    throw ArchiveEngineError.sourceIdentityChanged(sourceChild)
                }
                try mergeDirectory(
                    sourceChild,
                    into: desiredDestination,
                    expectedSourceIdentity: sourceDirectoryIdentity,
                    expectedDestinationIdentity: destinationDirectoryIdentity,
                    cancellationToken: cancellationToken
                )
                continue
            }

            let resolvedDestination = CollisionNameResolver.availableURL(
                for: desiredDestination,
                fileExists: operations.fileExists
            )
            guard operations.pathEntryIdentity(sourceChild) == sourceChildIdentity else {
                throw ArchiveEngineError.sourceIdentityChanged(sourceChild)
            }
            if cancellationToken?.isCancelled == true {
                throw ArchiveEngineError.cancelled
            }
            try operations.moveItem(sourceChild, resolvedDestination)
        }

        guard operations.directoryIdentity(sourceURL) == expectedSourceIdentity,
              operations.directoryIdentity(destinationURL) == expectedDestinationIdentity
        else {
            throw ArchiveEngineError.sourceIdentityChanged(sourceURL)
        }
        if try operations.directoryContents(sourceURL).isEmpty {
            try operations.removeItem(sourceURL)
        }
    }

    private func removeEmptyAncestors(startingAt startURL: URL, stoppingBefore rootURL: URL) throws {
        var candidate = startURL.standardizedFileURL
        let root = rootURL.standardizedFileURL

        while candidate != root, isStrictDescendant(candidate, of: root) {
            guard operations.fileExists(candidate), operations.isDirectory(candidate) else {
                candidate.deleteLastPathComponent()
                continue
            }

            // Parent containers are removed only when DayDrop marked them at
            // creation time. An empty user-created month/year folder is left
            // untouched even if DayDrop temporarily reused it.
            guard DayDropDirectoryOwnershipMarker.isManagedContainer(candidate) else {
                break
            }

            guard try operations.directoryContents(candidate).isEmpty else {
                break
            }

            try operations.removeItem(candidate)
            candidate.deleteLastPathComponent()
        }
    }

    private func missingAncestorContainers(
        of rootURL: URL,
        relativePath: String
    ) -> [URL] {
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return [] }

        var candidate = rootURL.standardizedFileURL
        var missing: [URL] = []
        for component in components.dropLast() {
            candidate.appendPathComponent(component, isDirectory: true)
            if !operations.fileExists(candidate) {
                missing.append(candidate)
            }
        }
        return missing
    }

    private func safeDescendant(of rootURL: URL, relativePath: String) -> URL? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard
            !components.isEmpty,
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            return nil
        }

        let candidate = components.reduce(rootURL) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: true)
        }.standardizedFileURL

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isStrictDescendant(resolvedCandidate, of: resolvedRoot),
              !containsSymbolicLink(
                from: rootURL.standardizedFileURL,
                through: components.map(String.init)
              )
        else {
            return nil
        }

        return candidate
    }

    private func isSafeFileSource(
        _ sourceURL: URL,
        inside rootURL: URL,
        maximumDepth: Int
    ) -> Bool {
        let root = rootURL.standardizedFileURL
        let source = sourceURL.standardizedFileURL
        let rootComponents = root.pathComponents
        let sourceComponents = source.pathComponents
        guard sourceComponents.starts(with: rootComponents) else { return false }

        let relativeComponents = Array(sourceComponents.dropFirst(rootComponents.count))
        guard (1...maximumDepth).contains(relativeComponents.count),
              !containsSymbolicLink(from: root, through: relativeComponents)
        else {
            return false
        }

        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL
        return isStrictDescendant(resolvedSource, of: resolvedRoot)
    }

    private func containsSymbolicLink(from rootURL: URL, through components: [String]) -> Bool {
        var candidate = rootURL
        for component in components {
            candidate.appendPathComponent(component, isDirectory: true)
            guard operations.fileExists(candidate) else { continue }
            if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                return true
            }
        }
        return false
    }

    private func isStrictDescendant(_ candidateURL: URL, of rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path.hasSuffix("/")
            ? rootURL.standardizedFileURL.path
            : rootURL.standardizedFileURL.path + "/"
        return candidateURL.standardizedFileURL.path.hasPrefix(rootPath)
    }

    private func canRecoverCompletedMigration(
        descriptor: ManagedFolderDescriptor,
        destinationURL: URL
    ) -> Bool {
        guard operations.fileExists(destinationURL),
              operations.isDirectory(destinationURL),
              let currentIdentity = operations.directoryIdentity(destinationURL)
        else {
            return false
        }

        if let recordedDestinationIdentity = descriptor.pendingDestinationIdentity {
            return currentIdentity == recordedDestinationIdentity
        }
        if let recordedSourceIdentity = descriptor.directoryIdentity {
            return currentIdentity == recordedSourceIdentity
        }
        return false
    }

    private func destinationMatchesPendingExpectation(
        descriptor: ManagedFolderDescriptor,
        destinationURL: URL
    ) -> Bool {
        guard descriptor.pendingRelativePath != nil else { return true }

        if descriptor.pendingDestinationExpectedAbsent {
            return !operations.fileExists(destinationURL)
        }
        guard let expectedIdentity = descriptor.pendingDestinationIdentity else {
            return false
        }
        return operations.fileExists(destinationURL)
            && operations.isDirectory(destinationURL)
            && operations.directoryIdentity(destinationURL) == expectedIdentity
    }

    private func failedMigrationResult(
        descriptor: ManagedFolderDescriptor,
        expectedPath: String,
        sourceURL: URL,
        destinationURL: URL,
        message: String
    ) -> ManagedFolderMigrationResult {
        ManagedFolderMigrationResult(
            descriptor: descriptor,
            expectedRelativePath: expectedPath,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            state: .failed,
            errorMessage: message
        )
    }

    private func cancelledMigrationResult(
        descriptor: ManagedFolderDescriptor,
        expectedPath: String,
        sourceURL: URL,
        destinationURL: URL
    ) -> ManagedFolderMigrationResult {
        ManagedFolderMigrationResult(
            descriptor: descriptor,
            expectedRelativePath: expectedPath,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            state: .cancelled,
            errorMessage: "目录迁移已暂停。"
        )
    }

    private func folderPreparationFailure(
        sourceDay: ArchiveDay,
        relativePath: String,
        folderURL: URL,
        message: String
    ) -> ArchiveFolderPreparationResult {
        ArchiveFolderPreparationResult(
            sourceDay: sourceDay,
            relativeFolderPath: relativePath,
            folderURL: folderURL,
            directoryIdentity: nil,
            ownershipDateIdentifier: nil,
            wasCreated: false,
            succeeded: false,
            errorMessage: message
        )
    }

    private func invalidMigrationResult(
        descriptor: ManagedFolderDescriptor,
        rootURL: URL,
        expectedPath: String? = nil,
        message: String
    ) -> ManagedFolderMigrationResult {
        ManagedFolderMigrationResult(
            descriptor: descriptor,
            expectedRelativePath: expectedPath ?? descriptor.relativePath,
            sourceURL: rootURL,
            destinationURL: rootURL,
            state: .failed,
            errorMessage: message
        )
    }
}

private enum ArchiveEngineError: LocalizedError {
    case cancelled
    case destinationIsNotDirectory(URL)
    case destinationIdentityChanged(URL)
    case directoryIdentityUnavailable(URL)
    case sourceIsNotDirectory(URL)
    case sourceIdentityChanged(URL)
    case sourceIsBusy(URL)
    case unsafeDestination(URL)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "目录迁移已暂停。"
        case let .destinationIsNotDirectory(url):
            return "迁移目标不是文件夹：\(url.lastPathComponent)"
        case let .destinationIdentityChanged(url):
            return "目标目录的文件系统身份已变化：\(url.lastPathComponent)"
        case let .directoryIdentityUnavailable(url):
            return "无法验证目录的文件系统身份：\(url.lastPathComponent)"
        case let .sourceIsNotDirectory(url):
            return "迁移来源不是受管理目录：\(url.lastPathComponent)"
        case let .sourceIdentityChanged(url):
            return "受管理目录的文件系统身份已变化：\(url.lastPathComponent)"
        case let .sourceIsBusy(url):
            return "文件仍被其他进程占用：\(url.lastPathComponent)"
        case let .unsafeDestination(url):
            return "迁移目标路径不再安全：\(url.path)"
        }
    }
}

private final class HeldAdvisoryFileLock {
    private let descriptor: Int32

    init?(url: URL) {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else { return nil }

        var fileStatus = stat()
        guard fstat(descriptor, &fileStatus) == 0,
              (fileStatus.st_mode & S_IFMT) == S_IFREG,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0
        else {
            Darwin.close(descriptor)
            return nil
        }

        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}
