import Foundation

enum ForNowIntegrationAvailability: Equatable {
    case notInstalled
    case updateRequired
    case ready(applicationURL: URL)
}

/// DayDrop 与搁这儿-ForNow之间的公开能力契约。
///
/// 不能只按 bundle id 判断：旧版搁这儿-ForNow虽然已安装，但还不能接收
/// DayDrop 发送的文件。能力版本让右键入口只在接收端确实可用时出现。
enum ForNowIntegrationContract {
    static let displayName = "搁这儿-ForNow"
    static let bundleIdentifier = "com.fornow.app"
    static let homepageURL = URL(string: "https://fornow.liveby.app")!
    static let externalFileImportInfoKey = "ForNowExternalFileImportVersion"
    static let minimumExternalFileImportVersion = 1

    static func availability(
        resolvedApplicationURL: URL?,
        resolvedBundleIdentifier: String?,
        externalFileImportVersion: Int?
    ) -> ForNowIntegrationAvailability {
        guard let resolvedApplicationURL else {
            return .notInstalled
        }
        guard resolvedApplicationURL.isFileURL,
              resolvedBundleIdentifier == bundleIdentifier,
              let externalFileImportVersion,
              externalFileImportVersion >= minimumExternalFileImportVersion
        else {
            return .updateRequired
        }
        return .ready(applicationURL: resolvedApplicationURL.standardizedFileURL)
    }

    static func normalizedFileURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { url in
            guard url.isFileURL else { return nil }
            let normalized = url.standardizedFileURL
            guard !normalized.path.isEmpty,
                  seen.insert(normalized.path).inserted
            else {
                return nil
            }
            return normalized
        }
    }
}
