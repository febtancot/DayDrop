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

struct DayDropPendingUpdateInfo: Codable, Equatable, Sendable {
    let displayVersion: String
    let build: String
}

final class DayDropPendingUpdateStore {
    static let defaultKey = "DayDrop.PendingUpdate"

    private let defaults: UserDefaults
    private let key: String
    private let versionComparator: SUStandardVersionComparator

    init(
        defaults: UserDefaults = .standard,
        key: String = DayDropPendingUpdateStore.defaultKey,
        versionComparator: SUStandardVersionComparator = .default
    ) {
        self.defaults = defaults
        self.key = key
        self.versionComparator = versionComparator
    }

    func record(displayVersion: String, build: String) {
        let pendingUpdate = DayDropPendingUpdateInfo(
            displayVersion: displayVersion,
            build: build
        )
        guard let data = try? JSONEncoder().encode(pendingUpdate) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func pendingUpdate(newerThan currentBuild: String) -> DayDropPendingUpdateInfo? {
        guard
            let data = defaults.data(forKey: key),
            let pendingUpdate = try? JSONDecoder().decode(DayDropPendingUpdateInfo.self, from: data)
        else {
            clear()
            return nil
        }

        guard versionComparator.compareVersion(
            pendingUpdate.build,
            toVersion: currentBuild
        ) == .orderedDescending else {
            clear()
            return nil
        }

        return pendingUpdate
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
final class DayDropUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var availableVersion: String?

    private let pendingUpdateStore: DayDropPendingUpdateStore
    private var updaterController: SPUStandardUpdaterController!

    init(
        startingUpdater: Bool = !DayDropRuntime.isRunningUnitTests,
        defaults: UserDefaults = .standard,
        currentVersionInfo: DayDropVersionInfo = .current
    ) {
        pendingUpdateStore = DayDropPendingUpdateStore(defaults: defaults)
        super.init()
        availableVersion = pendingUpdateStore
            .pendingUpdate(newerThan: currentVersionInfo.build)?
            .displayVersion

        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: self,
            userDriverDelegate: nil
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

    private func recordAvailableUpdate(_ update: SUAppcastItem) {
        pendingUpdateStore.record(
            displayVersion: update.displayVersionString,
            build: update.versionString
        )
        availableVersion = update.displayVersionString
    }

    private func clearAvailableUpdate() {
        pendingUpdateStore.clear()
        availableVersion = nil
    }
}

extension DayDropUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordAvailableUpdate(item)
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if choice == .skip {
            clearAvailableUpdate()
        }
    }
}
