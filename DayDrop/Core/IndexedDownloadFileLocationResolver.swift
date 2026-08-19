import Foundation

/// Resolves an indexed record back to the same current filesystem item without
/// allowing a stale or modified database row to escape the authorized root.
struct IndexedDownloadFileLocationResolver {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func existingItemURL(
        for file: IndexedDownloadFile,
        in rootURL: URL
    ) -> URL? {
        guard file.isPresent,
              let candidate = recordedItemURL(for: file, in: rootURL),
              let currentIdentity = FileSystemIdentity.itemIdentifier(at: candidate),
              FileSystemIdentity.identifiersMatchAtSamePath(
                  currentIdentity,
                  file.fileSystemIdentity
              )
        else {
            return nil
        }
        return candidate
    }

    func recordedItemURL(
        for file: IndexedDownloadFile,
        in rootURL: URL
    ) -> URL? {
        guard ManagedDayFolder.isValidRelativePath(file.relativePath) else { return nil }

        let root = rootURL.standardizedFileURL
        let components = file.relativePath.split(separator: "/").map(String.init)
        var parent = root
        for component in components.dropLast() {
            parent.appendPathComponent(component, isDirectory: true)
            if fileManager.fileExists(atPath: parent.path),
               FileSystemIdentity.directoryIdentifier(at: parent) == nil {
                return nil
            }
        }

        let candidate = root.appendingPathComponent(
            file.relativePath,
            isDirectory: file.isPackage
        ).standardizedFileURL
        guard isInsideAuthorizedRoot(candidate, rootURL: root) else { return nil }
        return candidate
    }

    private func isInsideAuthorizedRoot(_ candidate: URL, rootURL: URL) -> Bool {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        return resolvedCandidate.pathComponents.starts(with: root.pathComponents)
    }
}

