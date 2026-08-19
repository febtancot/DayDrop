import Foundation

/// Revalidates a current "Today" row before an item-level action uses it.
struct TodayFileLocationResolver {
    func existingItemURL(
        for file: TodayFileItem,
        in rootURL: URL
    ) -> URL? {
        let candidate = URL(fileURLWithPath: file.id).standardizedFileURL
        guard candidate.isFileURL,
              candidate.lastPathComponent == file.name,
              isInsideAuthorizedRoot(candidate, rootURL: rootURL),
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

    private func isInsideAuthorizedRoot(_ candidate: URL, rootURL: URL) -> Bool {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        return resolvedCandidate.pathComponents.starts(with: root.pathComponents)
    }
}

