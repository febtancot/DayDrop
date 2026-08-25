import Foundation

/// DayDrop 对其他本机应用公开的窄范围动作。
///
/// URL 只负责请求动作；下载目录授权、今日目录创建和受管记录仍由
/// `DayDropController.openTodayFolder()` 按既有安全规则执行。
enum DayDropExternalAction: Hashable {
    case openTodayFolder(targetDisplayID: String?)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "daydrop",
              url.host?.lowercased() == "open-today-folder",
              url.path.isEmpty,
              url.fragment == nil
        else {
            return nil
        }

        guard url.query != nil else {
            self = .openTodayFolder(targetDisplayID: nil)
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "display-id",
              let displayID = queryItems[0].value,
              Self.isValidDisplayID(displayID)
        else {
            return nil
        }
        self = .openTodayFolder(targetDisplayID: displayID)
    }

    private static func isValidDisplayID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}
