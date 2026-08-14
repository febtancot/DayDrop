import Foundation

struct DownloadFileSnapshot: Equatable, Sendable {
    let fileSystemIdentity: String
    let relativePath: String
    let fileName: String
    let size: UInt64?
    let creationDate: Date?
    let modificationDate: Date?
    let fileCategory: HistoryFileCategory
    let isPackage: Bool
}

enum DownloadsFileScannerError: Error, LocalizedError {
    case unableToEnumerate(URL)
    case incompleteScan(URL, String)

    var errorDescription: String? {
        switch self {
        case .unableToEnumerate(let url):
            return "无法递归扫描下载目录：\(url.path)"
        case .incompleteScan(let url, let message):
            return "下载目录扫描未完成（\(url.path)）：\(message)"
        }
    }
}

/// Builds a read-only inventory of every file below the authorized Downloads root.
/// Packages are indexed as one item, and symbolic links are never followed.
struct DownloadsFileScanner {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func snapshots(in rootURL: URL) throws -> [DownloadFileSnapshot] {
        let root = rootURL.standardizedFileURL
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isPackageKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        var enumerationFailure: (URL, Error)?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                enumerationFailure = (url, error)
                return false
            }
        ) else {
            throw DownloadsFileScannerError.unableToEnumerate(root)
        }

        var results: [DownloadFileSnapshot] = []
        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: Set(keys))
            } catch {
                throw DownloadsFileScannerError.incompleteScan(
                    url,
                    error.localizedDescription
                )
            }

            if values.isSymbolicLink == true {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let isPackage = values.isPackage == true
            if values.isDirectory == true && !isPackage {
                continue
            }
            guard values.isRegularFile == true || isPackage else {
                continue
            }
            guard let identity = FileSystemIdentity.itemIdentifier(at: url),
                  let relativePath = Self.relativePath(of: url, below: root)
            else {
                throw DownloadsFileScannerError.incompleteScan(
                    url,
                    "无法验证文件身份或相对路径。"
                )
            }

            let fileSize = values.fileSize.flatMap { $0 >= 0 ? UInt64($0) : nil }
            results.append(DownloadFileSnapshot(
                fileSystemIdentity: identity,
                relativePath: relativePath,
                fileName: url.lastPathComponent,
                size: fileSize,
                creationDate: values.creationDate,
                modificationDate: values.contentModificationDate,
                fileCategory: FileTypeClassifier.category(forFileName: url.lastPathComponent),
                isPackage: isPackage
            ))
        }

        if let (url, error) = enumerationFailure {
            throw DownloadsFileScannerError.incompleteScan(url, error.localizedDescription)
        }

        return results.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private static func relativePath(of itemURL: URL, below rootURL: URL) -> String? {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let itemComponents = itemURL.standardizedFileURL.pathComponents
        guard itemComponents.count > rootComponents.count,
              itemComponents.starts(with: rootComponents)
        else {
            return nil
        }
        let relative = itemComponents.dropFirst(rootComponents.count).joined(separator: "/")
        return ManagedDayFolder.isValidRelativePath(relative) ? relative : nil
    }
}
