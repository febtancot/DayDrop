import Foundation

enum HistoryRecordLocationResolution: Equatable, Sendable {
    case revealItem(URL)
    case openRecordedDirectory(URL)
}

/// Resolves a persisted history path without allowing a modified record to
/// navigate outside the currently authorized Downloads root.
struct HistoryRecordLocationResolver {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func resolve(
        record: OperationRecord,
        in rootURL: URL
    ) -> HistoryRecordLocationResolution? {
        let candidates = candidateURLs(for: record, in: rootURL)

        for candidate in candidates {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
                continue
            }
            return isDirectory.boolValue
                ? .openRecordedDirectory(candidate)
                : .revealItem(candidate)
        }

        // The file may have been renamed, moved again, or deleted after the
        // operation. In that case, open the closest recorded parent that still
        // exists, preferring the destination for a successful operation and
        // the source for a failed operation.
        for candidate in candidates {
            var parent = candidate.deletingLastPathComponent()
            while isInsideAuthorizedRoot(parent, rootURL: rootURL) {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    return .openRecordedDirectory(parent)
                }
                guard parent.standardizedFileURL != rootURL.standardizedFileURL else { break }
                parent.deleteLastPathComponent()
            }
        }
        return nil
    }

    /// Returns only the recorded item itself. Unlike `resolve`, this never
    /// falls back to a parent directory, so callers cannot accidentally send
    /// an unrelated folder when the recorded file has moved or been deleted.
    func existingItemURL(
        record: OperationRecord,
        in rootURL: URL
    ) -> URL? {
        candidateURLs(for: record, in: rootURL).first { candidate in
            fileManager.fileExists(atPath: candidate.path)
                && FileSystemIdentity.itemIdentifier(at: candidate) != nil
        }
    }

    private func candidateURLs(for record: OperationRecord, in rootURL: URL) -> [URL] {
        let paths = record.succeeded
            ? [record.destinationPath, record.sourcePath]
            : [record.sourcePath, record.destinationPath]
        var seen: Set<String> = []

        return paths.compactMap { path in
            guard !path.isEmpty else { return nil }
            let candidate: URL
            if NSString(string: path).isAbsolutePath {
                candidate = URL(fileURLWithPath: path)
            } else {
                candidate = rootURL.appendingPathComponent(path)
            }
            let standardized = candidate.standardizedFileURL
            guard isInsideAuthorizedRoot(standardized, rootURL: rootURL),
                  seen.insert(standardized.path).inserted
            else {
                return nil
            }
            return standardized
        }
    }

    private func isInsideAuthorizedRoot(_ candidate: URL, rootURL: URL) -> Bool {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        let candidateComponents = resolvedCandidate.pathComponents
        return candidateComponents.starts(with: rootComponents)
    }
}
