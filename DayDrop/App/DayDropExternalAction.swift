import Foundation

/// DayDrop 对其他本机应用公开的窄范围动作。
///
/// URL 只负责请求动作；下载目录授权、今日目录创建和受管记录仍由
/// `DayDropController.openTodayFolder()` 按既有安全规则执行。
enum DayDropExternalAction: Hashable {
    case openTodayFolder

    init?(url: URL) {
        guard url.scheme?.lowercased() == "daydrop",
              url.host?.lowercased() == "open-today-folder",
              url.path.isEmpty,
              url.query == nil,
              url.fragment == nil
        else {
            return nil
        }
        self = .openTodayFolder
    }
}
