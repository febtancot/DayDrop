import AppKit

/// 访达使用以主屏左上角为原点、y 轴向下的窗口坐标；AppKit 的屏幕坐标则以
/// 主屏左下角为原点、y 轴向上。这里集中完成转换，避免多屏上下排列时落错屏幕。
struct FinderWindowPlacement: Equatable {
    let bounds: CGRect

    static func centered(
        in targetVisibleFrame: CGRect,
        primaryScreenFrame: CGRect
    ) -> FinderWindowPlacement? {
        guard targetVisibleFrame.width >= 240,
              targetVisibleFrame.height >= 200
        else {
            return nil
        }

        let horizontalMargin = min(48, targetVisibleFrame.width * 0.08)
        let verticalMargin = min(48, targetVisibleFrame.height * 0.08)
        let width = min(1_000, targetVisibleFrame.width - horizontalMargin * 2)
        let height = min(700, targetVisibleFrame.height - verticalMargin * 2)
        guard width > 0, height > 0 else { return nil }

        let appKitX = targetVisibleFrame.midX - width / 2
        let appKitTopY = targetVisibleFrame.midY + height / 2
        let finderY = primaryScreenFrame.maxY - appKitTopY
        return FinderWindowPlacement(
            bounds: CGRect(
                x: appKitX.rounded(),
                y: finderY.rounded(),
                width: width.rounded(),
                height: height.rounded()
            )
        )
    }

    var appleScriptList: String {
        let left = Int(bounds.minX)
        let top = Int(bounds.minY)
        let right = Int(bounds.maxX)
        let bottom = Int(bounds.maxY)
        return "{\(left), \(top), \(right), \(bottom)}"
    }
}

@MainActor
enum FinderFolderPresenter {
    enum Result: Equatable {
        case positioned
        case openedNormally
        case openedWithoutRequestedPosition
        case failed
    }

    static func open(_ folderURL: URL, targetDisplayID: String?) -> Result {
        guard let targetDisplayID else {
            return NSWorkspace.shared.open(folderURL) ? .openedNormally : .failed
        }

        let screens = NSScreen.screens
        guard let targetScreen = screens.first(where: {
            DayDropDisplayIdentity.identifier(for: $0) == targetDisplayID
        }),
        let primaryScreen = screens.first(where: { $0.frame.origin == .zero })
            ?? screens.first,
        let placement = FinderWindowPlacement.centered(
            in: targetScreen.visibleFrame,
            primaryScreenFrame: primaryScreen.frame
        ) else {
            return fallbackOpen(folderURL)
        }

        guard let script = NSAppleScript(
            source: appleScriptSource(
                folderPath: folderURL.path,
                placement: placement
            )
        ) else {
            return fallbackOpen(folderURL)
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else {
            return fallbackOpen(folderURL)
        }
        return .positioned
    }

    nonisolated static func appleScriptSource(
        folderPath: String,
        placement: FinderWindowPlacement
    ) -> String {
        let literal = appleScriptStringLiteral(folderPath)
        return """
        tell application id "com.apple.finder"
            activate
            set targetFolder to (POSIX file \(literal) as alias)
            set targetWindow to make new Finder window to targetFolder
            set bounds of targetWindow to \(placement.appleScriptList)
        end tell
        """
    }

    private static func fallbackOpen(_ folderURL: URL) -> Result {
        NSWorkspace.shared.open(folderURL)
            ? .openedWithoutRequestedPosition
            : .failed
    }

    nonisolated private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
