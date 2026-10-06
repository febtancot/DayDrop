import Foundation

struct ExtractedFolderEvidence: Equatable, Sendable {
    let folderURL: URL
    let folderIdentity: String
    let archiveURL: URL
    let archiveIdentity: String
    let archiveStamp: ExtractionFileStamp
    let tree: ExtractedFolderTree
}

struct ExtractionRecognition: Sendable {
    let matchedFolders: [String: ExtractedFolderEvidence]
    let protectedFolderIdentities: Set<String>

    static let empty = ExtractionRecognition(matchedFolders: [:], protectedFolderIdentities: [])
}

/// A matching archive is evidence of an extraction-shaped folder, not a claim
/// that macOS exposes the process which created that directory.
actor ExtractedFolderRecognizer {
    private struct CachedManifest {
        let stamp: ExtractionFileStamp
        let manifest: ArchiveManifest?
    }

    private var cache: [String: CachedManifest] = [:]

    func recognize(
        folders: [TopLevelFileSnapshot],
        archiveURLs: [URL],
        managedFolders: [ManagedDayFolder] = [],
        in rootURL: URL
    ) -> [String: ExtractedFolderEvidence] {
        scan(folders: folders, archiveURLs: archiveURLs, managedFolders: managedFolders, in: rootURL).matchedFolders
    }

    func scan(
        folders: [TopLevelFileSnapshot],
        archiveURLs: [URL],
        managedFolders: [ManagedDayFolder] = [],
        in rootURL: URL
    ) -> ExtractionRecognition {
        let scanner = FileCandidateScanner()
        let folders = folders.filter(Self.isCandidateFolder)
        guard !folders.isEmpty else { return .empty }
        var protectedFolders: Set<String> = []
        var candidateURLs = archiveURLs
        // Source archives can already have been moved by DayDrop. Read only
        // identity-bound managed day folders, never descend into arbitrary folders.
        for folder in managedFolders.prefix(512) {
            guard ManagedDayFolder.isValidRelativePath(folder.relativePath), folder.pendingRelativePath == nil else { continue }
            let url = rootURL.appendingPathComponent(folder.relativePath)
            guard Self.isSafeArchiveURL(url, in: rootURL),
                  FileSystemIdentity.directoryIdentifier(at: url) == folder.directoryIdentity,
                  DayDropDirectoryOwnershipMarker.managedDateIdentifier(at: url) == folder.dateIdentifier
            else { continue }
            candidateURLs += ((try? scanner.topLevelSnapshots(in: url)) ?? []).filter {
                scanner.isEligible($0) && ArchiveManifestReader.supportedExtensions.contains($0.url.pathExtension.lowercased())
            }.map(\.url)
            if candidateURLs.count >= 1_024 { break }
        }
        var archives: [(TopLevelFileSnapshot, ExtractionFileStamp, ArchiveManifest)] = []
        var seen: Set<String> = []
        for url in candidateURLs {
            if seen.count >= 512 { break }
            guard Self.isSafeArchiveURL(url, in: rootURL),
                  let snapshot = scanner.snapshot(at: url), scanner.isEligible(snapshot),
                  ArchiveManifestReader.supportedExtensions.contains(url.pathExtension.lowercased()),
                  seen.insert(snapshot.identity).inserted,
                  let stamp = ExtractionFileStamp.read(at: url)
            else { continue }
            for folder in folders {
                if let folderDate = folder.addedToDirectoryDate ?? folder.creationDate,
                   let archiveDate = snapshot.creationDate ?? snapshot.addedToDirectoryDate,
                   folderDate >= archiveDate,
                   ArchiveManifest.archiveStemAliases(snapshot.fileName).contains(where: {
                       ArchiveManifest.matchesOutputName(folder.fileName, base: $0)
                   }) {
                    protectedFolders.insert(folder.identity)
                }
            }
            let manifest: ArchiveManifest?
            if let cached = cache[snapshot.identity], cached.stamp == stamp {
                manifest = cached.manifest
            } else {
                do {
                    manifest = try ArchiveManifestReader().read(at: url)
                } catch ArchiveManifestError.busy {
                    continue
                } catch {
                    manifest = nil
                }
                guard ExtractionFileStamp.read(at: url) == stamp else { continue }
                // Busy/unsupported/encrypted files never yield partial evidence.
                cache[snapshot.identity] = CachedManifest(stamp: stamp, manifest: manifest)
            }
            if let manifest,
               folders.contains(where: { manifest.canMatchName($0.fileName, archiveName: snapshot.fileName) }) {
                archives.append((snapshot, stamp, manifest))
            }
            if cache.values.reduce(0, { $0 + ($1.manifest?.entries.count ?? 0) }) > 100_000 { cache.removeAll() }
        }
        cache = cache.filter { seen.contains($0.key) }

        var result: [String: ExtractedFolderEvidence] = [:]
        for folder in folders {
            guard folder.url.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL,
                  let folderDate = folder.addedToDirectoryDate ?? folder.creationDate
            else { continue }
            let plausibleArchives = archives.filter { archive, _, manifest in
                // A pre-existing project later zipped under the same name must
                // not become an automatic folder candidate merely by matching.
                guard let archiveDate = archive.creationDate ?? archive.addedToDirectoryDate,
                      folderDate >= archiveDate,
                      manifest.canMatchName(folder.fileName, archiveName: archive.fileName)
                else { return false }
                return true
            }
            if !plausibleArchives.isEmpty { protectedFolders.insert(folder.identity) }
            guard !plausibleArchives.isEmpty,
                  let tree = try? ExtractedFolderTreeScanner().scan(at: folder.url),
                  tree.entries.count <= ExtractedFolderMoveGuard.maximumEntries
            else { continue }
            let matches = plausibleArchives.filter { archive, _, manifest in
                manifest.matches(tree: tree, folderName: folder.fileName, archiveName: archive.fileName)
            }
            // Multiple plausible sources are intentionally left for the user.
            guard matches.count == 1, let (archive, stamp, _) = matches.first else { continue }
            result[folder.identity] = ExtractedFolderEvidence(
                folderURL: folder.url, folderIdentity: folder.identity,
                archiveURL: archive.url, archiveIdentity: archive.identity,
                archiveStamp: stamp, tree: tree
            )
        }
        return ExtractionRecognition(matchedFolders: result, protectedFolderIdentities: protectedFolders)
    }

    static func isCandidateFolder(_ snapshot: TopLevelFileSnapshot) -> Bool {
        snapshot.isDirectory && !snapshot.isPackage && !snapshot.isHidden && !snapshot.isSymbolicLink
            && !snapshot.fileName.hasPrefix(".")
            && DownloadCandidatePolicy().isEligible(fileName: snapshot.fileName, isHidden: false, isDirectory: false)
            && DayDropDirectoryOwnershipMarker.managedDateIdentifier(at: snapshot.url) == nil
            && !DayDropDirectoryOwnershipMarker.isManagedContainer(snapshot.url)
    }

    static func isSafeArchiveURL(_ url: URL, in rootURL: URL) -> Bool {
        let root = rootURL.standardizedFileURL
        let candidate = url.standardizedFileURL
        let parts = candidate.pathComponents
        guard parts.starts(with: root.pathComponents), parts.count > root.pathComponents.count else { return false }
        var parent = candidate.deletingLastPathComponent()
        while parent != root {
            guard FileSystemIdentity.directoryIdentifier(at: parent) != nil else { return false }
            parent.deleteLastPathComponent()
        }
        return FileSystemIdentity.itemIdentifier(at: candidate) != nil
    }
}
