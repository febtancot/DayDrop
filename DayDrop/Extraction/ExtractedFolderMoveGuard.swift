import Darwin
import Foundation

/// Retains cooperative locks for the entire checked tree until its atomic move.
/// Non-cooperating writers remain subject to the same filesystem-observation
/// limitation as ordinary downloads; a quiet window is not a universal completion API.
final class ExtractedFolderMoveGuard {
    static let maximumEntries = 2_048
    private var descriptors: [Int32] = []

    init(evidence: ExtractedFolderEvidence, rootURL: URL) throws {
        do {
            guard evidence.folderURL.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL,
                  FileSystemIdentity.directoryIdentifier(at: evidence.folderURL) == evidence.folderIdentity,
                  ExtractedFolderRecognizer.isSafeArchiveURL(evidence.archiveURL, in: rootURL),
                  FileSystemIdentity.itemIdentifier(at: evidence.archiveURL) == evidence.archiveIdentity,
                  ExtractionFileStamp.read(at: evidence.archiveURL) == evidence.archiveStamp,
                  try ExtractedFolderTreeScanner().scan(at: evidence.folderURL) == evidence.tree
            else { throw ArchiveManifestError.busy }

            // A finite descriptor budget prevents a large directory from
            // exhausting the process; failure preserves the source untouched.
            guard evidence.tree.entries.count <= Self.maximumEntries else { throw ArchiveManifestError.limitExceeded }
            let rootDescriptor = try hold(evidence.folderURL.path, parent: nil, expected: evidence.tree.rootStamp, isDirectory: true)
            var directoryDescriptors = ["": rootDescriptor]
            for entry in evidence.tree.entries {
                let parent = (entry.path as NSString).deletingLastPathComponent
                guard let parentDescriptor = directoryDescriptors[parent] else { throw ArchiveManifestError.unsafeOrEncrypted }
                let descriptor = try hold((entry.path as NSString).lastPathComponent, parent: parentDescriptor,
                                          expected: entry.stamp, isDirectory: entry.isDirectory)
                if entry.isDirectory { directoryDescriptors[entry.path] = descriptor }
            }
            guard try ExtractedFolderTreeScanner().scan(at: evidence.folderURL) == evidence.tree else {
                throw ArchiveManifestError.busy
            }
        } catch {
            releaseAll()
            throw error
        }
    }

    private func hold(_ path: String, parent: Int32?, expected: ExtractionFileStamp, isDirectory: Bool) throws -> Int32 {
        let flags = O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW | (isDirectory ? O_DIRECTORY : 0)
        let descriptor = parent.map { openat($0, path, flags) } ?? Darwin.open(path, flags)
        guard descriptor >= 0 else { throw ArchiveManifestError.busy }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == (isDirectory ? S_IFDIR : S_IFREG),
              ExtractionFileStamp(status) == expected,
              isDirectory || flock(descriptor, LOCK_EX | LOCK_NB) == 0
        else {
            Darwin.close(descriptor)
            throw ArchiveManifestError.busy
        }
        descriptors.append(descriptor)
        return descriptor
    }

    private func releaseAll() {
        for descriptor in descriptors {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }
        descriptors.removeAll()
    }

    deinit { releaseAll() }
}
