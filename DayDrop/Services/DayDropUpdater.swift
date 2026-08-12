import Combine
import Foundation
import Sparkle

struct DayDropVersionInfo: Equatable, Sendable {
    let shortVersion: String
    let build: String

    init(bundle: Bundle = .main) {
        shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "未知"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "未知"
    }

    static let current = DayDropVersionInfo()

    var compactDisplay: String {
        "v\(shortVersion)"
    }

    var detailedDisplay: String {
        "版本 \(shortVersion)（构建 \(build)）"
    }
}

@MainActor
final class DayDropUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var availableVersion: String?

    private var updaterController: SPUStandardUpdaterController!

    init(startingUpdater: Bool = !DayDropRuntime.isRunningUnitTests) {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: self
        )

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)

        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

}

extension DayDropUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        if !immediateFocus {
            availableVersion = update.displayVersionString
        }
        return immediateFocus
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
