import AppKit
import Combine
import Foundation

enum DayDropRuntime {
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

struct TodayFileItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let completedAt: Date
}

enum ArchiveTargetOwnershipDecision: Equatable {
    case manage
    case repairMarkerAndManage
    case claimAndManage
    case leaveUnmanaged
    case reject(String)
}

enum ArchiveTargetOwnershipPolicy {
    static func evaluate(
        preparation: ArchiveFolderPreparationResult,
        existingFolder: ManagedDayFolder?,
        dateIdentifier: String
    ) -> ArchiveTargetOwnershipDecision {
        if let existingFolder {
            guard existingFolder.relativePath == preparation.relativeFolderPath,
                  existingFolder.directoryIdentity == preparation.directoryIdentity,
                  existingFolder.pendingRelativePath == nil
            else {
                return .reject("同一日期已有其他受管理目录或未完成迁移，已拒绝覆盖记录。")
            }

            if preparation.ownershipDateIdentifier == dateIdentifier {
                return .manage
            }
            if preparation.ownershipDateIdentifier == nil {
                return .repairMarkerAndManage
            }
            return .reject("目标日期目录的所有权标记与受管理记录不一致。")
        }

        if preparation.wasCreated
            || preparation.ownershipDateIdentifier == dateIdentifier {
            return .claimAndManage
        }
        if preparation.ownershipDateIdentifier != nil {
            return .reject("目标目录属于另一个日期，已拒绝移动。")
        }
        return .leaveUnmanaged
    }
}

@MainActor
final class DayDropController: ObservableObject {
    static let shared = DayDropController()

    @Published private(set) var isPaused: Bool
    @Published private(set) var hasFolderAccess = false
    @Published private(set) var folderDisplayName = "下载"
    @Published private(set) var todayFiles: [TodayFileItem] = []
    @Published private(set) var recentOperations: [OperationRecord] = []
    @Published private(set) var launchAtLogin = false
    @Published private(set) var notificationsEnabled: Bool
    @Published private(set) var statusMessage: String?
    @Published private(set) var isShowingRecentActivity = false
    @Published private(set) var isShowingSettings = false

    private enum DefaultsKey {
        static let onboardingCompleted = "DayDrop.OnboardingCompleted"
        static let paused = "DayDrop.IsPaused"
        static let notificationsEnabled = "DayDrop.NotificationsEnabled"
    }

    private enum CandidateOrigin {
        case runtimeDownload
        case manualExistingFile
    }

    private struct PendingCandidate {
        var snapshot: TopLevelFileSnapshot
        var stability = FileSizeStabilityTracker()
        var origin: CandidateOrigin
        var failureCount = 0
        var nextMoveAttempt = Date.distantPast
        var nextStabilityObservation = Date.distantPast
    }

    var onOnboardingCompleted: (() -> Void)?
    var onShowOnboarding: (() -> Void)?

    var onboardingCompleted: Bool {
        defaults.bool(forKey: DefaultsKey.onboardingCompleted)
    }

    private let defaults: UserDefaults
    private let bookmarkStore: DownloadsBookmarkStore
    private let metadataStore: LocalMetadataStore?
    private let loginItemService: LoginItemService
    private let notificationService: BatchNotificationService
    private let archiveEngine: ArchiveEngine
    private let scanner: FileCandidateScanner
    private let fileManager: FileManager

    private var folderAccess: SecurityScopedFolderAccess?
    private var downloadsURL: URL?
    private var rootMonitor: DirectoryEventMonitor?
    private var todayMonitor: DirectoryEventMonitor?
    private var todayMonitorURL: URL?
    private var baselineIdentities: Set<String> = []
    private var pendingCandidates: [String: PendingCandidate] = [:]
    private var processingIdentities: Set<String> = []
    private var retryTask: Task<Void, Never>?
    private var rootDebounceTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var notificationObservers: [NSObjectProtocol] = []
    private var hasStarted = false
    private var scanInProgress = false
    private var scanRequested = false
    private var migrationInProgress = false
    private var migrationCancellationToken: ArchiveMigrationCancellationToken?
    private var blockingFailureRequiresRestart = false

    private init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.bookmarkStore = DownloadsBookmarkStore(defaults: defaults)
        self.loginItemService = LoginItemService()
        self.notificationService = BatchNotificationService()
        self.archiveEngine = ArchiveEngine()
        self.scanner = FileCandidateScanner(fileManager: fileManager)
        self.isPaused = defaults.bool(forKey: DefaultsKey.paused)
        self.notificationsEnabled = defaults.bool(forKey: DefaultsKey.notificationsEnabled)

        if DayDropRuntime.isRunningUnitTests {
            self.metadataStore = nil
        } else {
            do {
                self.metadataStore = try LocalMetadataStore()
            } catch {
                self.metadataStore = nil
                self.isPaused = true
                defaults.set(true, forKey: DefaultsKey.paused)
                self.statusMessage = "本地记录存储不可用：\(error.localizedDescription)"
            }
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        if let metadataStore {
            recentOperations = await metadataStore.loadOperationRecords()
        }

        switch loginItemService.state {
        case .enabled:
            launchAtLogin = true
        case .requiresApproval:
            launchAtLogin = true
            statusMessage = "登录启动需要在“系统设置”中批准。"
        case .disabled, .unavailable:
            launchAtLogin = false
        }

        if notificationsEnabled {
            let status = await notificationService.authorizationStatus()
            if status != .authorized && status != .provisional {
                notificationsEnabled = false
                defaults.set(false, forKey: DefaultsKey.notificationsEnabled)
            }
        }

        restoreFolderAuthorization()
        installCalendarObservers()
        scheduleMidnightRefresh()

        guard hasFolderAccess else { return }
        captureCurrentFilesAsBaseline()

        if !isPaused, onboardingCompleted, metadataStore != nil {
            await migrateManagedFolders()
            startRootMonitor()
        }
        refreshTodayFilesNow()
    }

    func stop() {
        rootDebounceTask?.cancel()
        retryTask?.cancel()
        midnightTask?.cancel()
        rootMonitor?.stop()
        todayMonitor?.stop()
        migrationCancellationToken?.cancel()
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
        folderAccess?.stop()
        folderAccess = nil
        hasStarted = false
    }

    func togglePaused() {
        if isPaused, metadataStore == nil || blockingFailureRequiresRestart {
            statusMessage = "DayDrop 检测到需要处理的存储或目录安全问题，请解决后重新启动。"
            return
        }
        isPaused.toggle()
        defaults.set(isPaused, forKey: DefaultsKey.paused)

        if isPaused {
            migrationCancellationToken?.cancel()
            rootMonitor?.stop()
            rootMonitor = nil
            pendingCandidates = pendingCandidates.filter { $0.value.origin == .manualExistingFile }
            statusMessage = "自动整理已暂停。"
            scheduleRetryIfNeeded()
        } else {
            guard hasFolderAccess else {
                statusMessage = "请先授权“下载”文件夹。"
                return
            }
            captureCurrentFilesAsBaseline()
            startRootMonitor()
            statusMessage = "自动整理已开启。"
            Task {
                await migrateManagedFolders()
            }
        }
    }

    func chooseDownloadsFolder() {
        let panel = NSOpenPanel()
        panel.title = "授权 DayDrop 访问“下载”文件夹"
        panel.message = "请选择当前用户的“下载”文件夹。DayDrop 只整理其中的顶层文件。"
        panel.prompt = "授权"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            if !hasFolderAccess {
                statusMessage = "未授权文件夹，DayDrop 不会整理任何文件。"
            }
            return
        }
        let selectionScopeStarted = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if selectionScopeStarted {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }

        guard isStandardDownloadsFolder(selectedURL) else {
            statusMessage = "请选择当前用户的“下载”文件夹。"
            return
        }

        do {
            try bookmarkStore.saveBookmark(for: selectedURL)
            try activateSavedFolderAuthorization()
            captureCurrentFilesAsBaseline()
            refreshTodayFilesNow()
            if !isPaused, onboardingCompleted {
                startRootMonitor()
                Task { await migrateManagedFolders() }
            }
            statusMessage = "已授权“下载”文件夹。"
        } catch {
            revokeFolderAccess(message: "无法保存文件夹授权：\(error.localizedDescription)")
        }
    }

    func organizeExistingFiles() {
        guard metadataStore != nil else {
            statusMessage = "本地记录存储不可用，未移动任何文件。"
            return
        }
        guard let downloadsURL, hasFolderAccess else {
            statusMessage = "请先授权“下载”文件夹。"
            return
        }

        do {
            let snapshots = try scanner.topLevelSnapshots(in: downloadsURL)
            var queued = 0

            for snapshot in snapshots where scanner.isEligible(snapshot) {
                if pendingCandidates[snapshot.identity] == nil {
                    pendingCandidates[snapshot.identity] = PendingCandidate(
                        snapshot: snapshot,
                        origin: .manualExistingFile
                    )
                    queued += 1
                }
            }

            if queued == 0 {
                statusMessage = "没有需要整理的顶层文件。"
                refreshTodayFilesNow()
                return
            }

            statusMessage = "正在确认 \(queued) 个文件是否已下载完成…"
            Task {
                await scanAndProcessCandidates(discoverAutomaticFiles: !isPaused)
            }
        } catch {
            revokeFolderAccess(
                message: "无法读取“下载”文件夹，请重新授权：\(error.localizedDescription)"
            )
        }
    }

    func openDownloadsFolder() {
        guard let downloadsURL, hasFolderAccess else {
            statusMessage = "请先授权“下载”文件夹。"
            return
        }
        NSWorkspace.shared.open(downloadsURL)
    }

    func openTodayFolder() {
        guard let downloadsURL, hasFolderAccess else {
            statusMessage = "请先授权“下载”文件夹。"
            return
        }
        guard let metadataStore else {
            statusMessage = "本地记录存储不可用，无法安全创建今日文件夹。"
            return
        }

        Task {
            let today = ArchiveDay(date: Date())
            let preparation = await archiveEngine.prepareTargetFolder(
                for: today,
                relativeTo: today,
                in: downloadsURL
            )

            guard preparation.succeeded,
                  let preparedIdentity = preparation.directoryIdentity
            else {
                statusMessage = "无法创建今日文件夹：\(preparation.errorMessage ?? "未知错误")"
                return
            }

            let existingManagedFolder = await metadataStore.loadManagedFolders()
                .first { $0.id == today.encoded }
            let decision = ArchiveTargetOwnershipPolicy.evaluate(
                preparation: preparation,
                existingFolder: existingManagedFolder,
                dateIdentifier: today.encoded
            )

            switch decision {
            case .manage, .leaveUnmanaged:
                break
            case .repairMarkerAndManage:
                do {
                    try DayDropDirectoryOwnershipMarker.mark(
                        preparation.folderURL,
                        dateIdentifier: today.encoded
                    )
                } catch {
                    statusMessage = "无法修复今日文件夹标记：\(error.localizedDescription)"
                    return
                }
            case .claimAndManage:
                let folder = ManagedDayFolder(
                    dateIdentifier: today.encoded,
                    relativePath: preparation.relativeFolderPath,
                    directoryIdentity: preparedIdentity
                )
                guard await persistManagedFolder(folder) else {
                    _ = await archiveEngine.discardPreparedTargetFolderIfEmpty(
                        preparation,
                        in: downloadsURL
                    )
                    return
                }
            case .reject(let message):
                if preparation.wasCreated {
                    _ = await archiveEngine.discardPreparedTargetFolderIfEmpty(
                        preparation,
                        in: downloadsURL
                    )
                }
                statusMessage = "无法打开今日文件夹：\(message)"
                return
            }

            refreshTodayFilesNow()
            if preparation.wasCreated {
                statusMessage = "已创建今日文件夹。"
            }
            NSWorkspace.shared.open(preparation.folderURL)
        }
    }

    func showOnboarding() {
        onShowOnboarding?()
    }

    func showRecentActivity() {
        isShowingSettings = false
        isShowingRecentActivity = true
    }

    func hideRecentActivity() {
        isShowingRecentActivity = false
    }

    func showSettings() {
        isShowingRecentActivity = false
        isShowingSettings = true
    }

    func hideSettings() {
        isShowingSettings = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
            switch loginItemService.state {
            case .enabled:
                launchAtLogin = true
                statusMessage = "已开启登录时自动启动。"
            case .requiresApproval:
                launchAtLogin = true
                statusMessage = "请在“系统设置 › 通用 › 登录项”中批准 DayDrop。"
            case .disabled:
                launchAtLogin = false
                statusMessage = "已关闭登录时自动启动。"
            case .unavailable:
                launchAtLogin = false
                statusMessage = "当前构建无法配置登录启动；请使用已签名并安装的应用重试。"
            }
        } catch {
            launchAtLogin = loginItemService.state == .enabled || loginItemService.state == .requiresApproval
            statusMessage = "登录启动设置失败：\(error.localizedDescription)"
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        if !enabled {
            notificationsEnabled = false
            defaults.set(false, forKey: DefaultsKey.notificationsEnabled)
            statusMessage = "已关闭整理完成通知。"
            return
        }

        Task {
            do {
                let granted = try await notificationService.requestAuthorization()
                notificationsEnabled = granted
                defaults.set(granted, forKey: DefaultsKey.notificationsEnabled)
                statusMessage = granted
                    ? "已开启整理完成通知。"
                    : "通知权限未获批准。"
            } catch {
                notificationsEnabled = false
                defaults.set(false, forKey: DefaultsKey.notificationsEnabled)
                statusMessage = "通知设置失败：\(error.localizedDescription)"
            }
        }
    }

    func completeOnboarding(organizeExisting: Bool, launchAtLogin: Bool) {
        guard metadataStore != nil else {
            statusMessage = "本地记录存储不可用，暂时无法完成设置。"
            return
        }
        guard hasFolderAccess else {
            statusMessage = "请先授权“下载”文件夹。"
            return
        }

        defaults.set(true, forKey: DefaultsKey.onboardingCompleted)
        setLaunchAtLogin(launchAtLogin)
        captureCurrentFilesAsBaseline()
        if !isPaused {
            startRootMonitor()
            Task { await migrateManagedFolders() }
        }
        if organizeExisting {
            organizeExistingFiles()
        }
        onOnboardingCompleted?()
    }

    func refreshTodayFilesNow() {
        guard let downloadsURL, hasFolderAccess else {
            todayFiles = []
            stopTodayMonitor()
            return
        }

        let today = ArchiveDay(date: Date())
        let todayRoute = ArchivePathRouter().route(for: today, relativeTo: today)
        guard let todayFolder = managedFolderURL(
            relativePath: todayRoute.relativePath,
            rootURL: downloadsURL
        ) else {
            todayFiles = []
            stopTodayMonitor()
            statusMessage = "今日归档路径无效。"
            return
        }
        if (try? todayFolder.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            todayFiles = []
            stopTodayMonitor()
            statusMessage = "今日归档路径是符号链接，DayDrop 不会访问该路径。"
            return
        }
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isHiddenKey,
            .addedToDirectoryDateKey,
            .creationDateKey,
            .contentModificationDateKey
        ]

        let operationDates = Dictionary(
            recentOperations
                .filter(\.succeeded)
                .map { (URL(fileURLWithPath: $0.destinationPath).standardizedFileURL.path, $0.performedAt) },
            uniquingKeysWith: max
        )

        let urls = (try? fileManager.contentsOfDirectory(
            at: todayFolder,
            includingPropertiesForKeys: keys,
            options: [.skipsSubdirectoryDescendants]
        )) ?? []

        todayFiles = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  values.isHidden != true,
                  !url.lastPathComponent.hasPrefix(".")
            else {
                return nil
            }

            let standardizedPath = url.standardizedFileURL.path
            let completedAt = operationDates[standardizedPath]
                ?? values.addedToDirectoryDate
                ?? values.contentModificationDate
                ?? values.creationDate
                ?? .distantPast
            return TodayFileItem(
                id: standardizedPath,
                name: url.lastPathComponent,
                completedAt: completedAt
            )
        }.sorted { lhs, rhs in
            if lhs.completedAt == rhs.completedAt {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.completedAt > rhs.completedAt
        }

        armTodayMonitorIfPossible(at: todayFolder)
    }

    func quit() {
        stop()
        NSApp.terminate(nil)
    }

    private func restoreFolderAuthorization() {
        guard bookmarkStore.hasSavedBookmark else {
            revokeFolderAccess(message: nil, clearBookmark: false)
            return
        }

        do {
            try activateSavedFolderAuthorization()
        } catch {
            revokeFolderAccess(message: "“下载”文件夹授权已失效，请重新授权：\(error.localizedDescription)")
        }
    }

    private func activateSavedFolderAuthorization() throws {
        let newAccess = try bookmarkStore.beginAccessingDownloadsFolder(
            rebuildIfStale: true,
            requireSecurityScope: true
        )

        guard isStandardDownloadsFolder(newAccess.url) else {
            newAccess.stop()
            throw DayDropControllerError.authorizedFolderIsNotCurrentDownloads
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: newAccess.url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            newAccess.stop()
            throw DayDropControllerError.authorizedFolderUnavailable
        }

        _ = try fileManager.contentsOfDirectory(
            at: newAccess.url,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        )

        rootMonitor?.stop()
        rootMonitor = nil
        stopTodayMonitor()
        folderAccess?.stop()
        folderAccess = newAccess
        downloadsURL = newAccess.url.standardizedFileURL
        hasFolderAccess = true
        folderDisplayName = displayPath(for: newAccess.url)
        pendingCandidates.removeAll()
        processingIdentities.removeAll()
    }

    private func revokeFolderAccess(message: String?, clearBookmark: Bool = false) {
        rootMonitor?.stop()
        rootMonitor = nil
        stopTodayMonitor()
        folderAccess?.stop()
        folderAccess = nil
        downloadsURL = nil
        hasFolderAccess = false
        todayFiles = []
        baselineIdentities = []
        pendingCandidates = [:]
        retryTask?.cancel()
        if clearBookmark {
            bookmarkStore.clearBookmark()
        }
        if let message {
            statusMessage = message
        }
    }

    private func isStandardDownloadsFolder(_ selectedURL: URL) -> Bool {
        guard let expectedURL = fileManager.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            return false
        }
        return selectedURL.standardizedFileURL.resolvingSymlinksInPath()
            == expectedURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func displayPath(for url: URL) -> String {
        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(homePath) else { return path }
        return "~" + String(path.dropFirst(homePath.count))
    }

    private func managedFolderURL(relativePath: String, rootURL: URL) -> URL? {
        guard ManagedDayFolder.isValidRelativePath(relativePath) else { return nil }
        return relativePath.split(separator: "/").reduce(rootURL) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: true)
        }.standardizedFileURL
    }

    private func captureCurrentFilesAsBaseline() {
        guard let downloadsURL else {
            baselineIdentities = []
            return
        }
        do {
            baselineIdentities = Set(
                try scanner.topLevelSnapshots(in: downloadsURL).map(\.identity)
            )
        } catch {
            revokeFolderAccess(message: "无法读取“下载”文件夹：\(error.localizedDescription)")
        }
    }

    private func startRootMonitor() {
        guard !isPaused, onboardingCompleted, hasFolderAccess, let downloadsURL else { return }
        if rootMonitor?.isRunning == true { return }

        let monitor = DirectoryEventMonitor(directoryURL: downloadsURL)
        do {
            try monitor.start { [weak self] event in
                Task { @MainActor in
                    self?.handleRootEvent(event)
                }
            }
            rootMonitor = monitor
        } catch {
            statusMessage = "无法监控“下载”文件夹：\(error.localizedDescription)"
        }
    }

    private func handleRootEvent(_ event: DirectoryChangeEvent) {
        guard !isPaused else { return }
        rootDebounceTask?.cancel()
        rootDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }

            if event.requiresRearm {
                do {
                    try self.rootMonitor?.rearm()
                } catch {
                    self.revokeFolderAccess(
                        message: "文件夹监听已中断，请重新授权：\(error.localizedDescription)"
                    )
                    return
                }
            }
            await self.scanAndProcessCandidates(discoverAutomaticFiles: true)
            self.refreshTodayFilesNow()
        }
    }

    private func scanAndProcessCandidates(discoverAutomaticFiles: Bool) async {
        guard let metadataStore, let downloadsURL, hasFolderAccess else { return }
        if scanInProgress {
            scanRequested = true
            return
        }

        scanInProgress = true
        defer {
            scanInProgress = false
            scheduleRetryIfNeeded()
            if scanRequested {
                scanRequested = false
                Task {
                    await scanAndProcessCandidates(discoverAutomaticFiles: !isPaused)
                }
            }
        }

        let snapshots: [TopLevelFileSnapshot]
        do {
            snapshots = try scanner.topLevelSnapshots(in: downloadsURL)
        } catch {
            revokeFolderAccess(
                message: "无法扫描“下载”文件夹，请重新授权：\(error.localizedDescription)"
            )
            return
        }

        let snapshotsByIdentity = Dictionary(
            snapshots.map { ($0.identity, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        for identity in pendingCandidates.keys where snapshotsByIdentity[identity] == nil {
            pendingCandidates.removeValue(forKey: identity)
            processingIdentities.remove(identity)
        }

        if discoverAutomaticFiles && !isPaused {
            for snapshot in snapshots where scanner.isEligible(snapshot) {
                guard !baselineIdentities.contains(snapshot.identity),
                      pendingCandidates[snapshot.identity] == nil
                else { continue }
                pendingCandidates[snapshot.identity] = PendingCandidate(
                    snapshot: snapshot,
                    origin: .runtimeDownload
                )
            }
        }

        var succeededCount = 0
        var failedCount = 0
        var persistenceFailed = false
        var unmanagedDestinationCount = 0

        candidateLoop: for identity in Array(pendingCandidates.keys) {
            guard !blockingFailureRequiresRestart else { break }
            guard !processingIdentities.contains(identity),
                  let latestSnapshot = snapshotsByIdentity[identity],
                  scanner.isEligible(latestSnapshot),
                  let size = latestSnapshot.size,
                  var candidate = pendingCandidates[identity]
            else { continue }

            candidate.snapshot = latestSnapshot
            let observationDate = Date()
            guard observationDate >= candidate.nextStabilityObservation else {
                pendingCandidates[identity] = candidate
                continue
            }
            let stability = candidate.stability.observe(size: size)
            candidate.nextStabilityObservation = observationDate.addingTimeInterval(1)
            pendingCandidates[identity] = candidate
            guard stability == .stable,
                  Date() >= candidate.nextMoveAttempt,
                  scanner.canAcquireExclusiveAdvisoryLock(on: latestSnapshot.url)
            else { continue }

            let processingDate = Date()
            let processingToday = ArchiveDay(date: processingDate)
            let sourceDay: ArchiveDay
            switch candidate.origin {
            case .runtimeDownload:
                sourceDay = processingToday
            case .manualExistingFile:
                guard let resolvedDay = ExistingFileDateResolver().archiveDay(
                    creationDate: latestSnapshot.creationDate,
                    modificationDate: latestSnapshot.modificationDate
                ) else {
                    let record = OperationRecord(
                        fileName: latestSnapshot.fileName,
                        sourcePath: latestSnapshot.url.path,
                        destinationPath: latestSnapshot.url.path,
                        succeeded: false,
                        errorMessage: "无法读取文件创建日期或修改日期。"
                    )
                    persistenceFailed = !(await persistOperation(record)) || persistenceFailed
                    pendingCandidates.removeValue(forKey: identity)
                    failedCount += 1
                    continue
                }
                sourceDay = resolvedDay
            }

            processingIdentities.insert(identity)
            let preparation = await archiveEngine.prepareTargetFolder(
                for: sourceDay,
                relativeTo: processingToday,
                in: downloadsURL
            )
            if case .runtimeDownload = candidate.origin, isPaused {
                _ = await archiveEngine.discardPreparedTargetFolderIfEmpty(
                    preparation,
                    in: downloadsURL
                )
                processingIdentities.remove(identity)
                continue
            }

            var ownershipError: String?
            var targetIsManaged = false
            if preparation.succeeded,
               let preparedIdentity = preparation.directoryIdentity {
                let existingManagedFolder = await metadataStore.loadManagedFolders()
                    .first { $0.id == sourceDay.encoded }

                switch ArchiveTargetOwnershipPolicy.evaluate(
                    preparation: preparation,
                    existingFolder: existingManagedFolder,
                    dateIdentifier: sourceDay.encoded
                ) {
                case .manage:
                    targetIsManaged = true
                case .repairMarkerAndManage:
                    do {
                        try DayDropDirectoryOwnershipMarker.mark(
                            preparation.folderURL,
                            dateIdentifier: sourceDay.encoded
                        )
                        targetIsManaged = true
                    } catch {
                        ownershipError = "无法写入日期目录所有权标记：\(error.localizedDescription)"
                    }
                case .claimAndManage:
                    let folder = ManagedDayFolder(
                        dateIdentifier: sourceDay.encoded,
                        relativePath: preparation.relativeFolderPath,
                        directoryIdentity: preparedIdentity
                    )
                    guard await persistManagedFolder(folder) else {
                        _ = await archiveEngine.discardPreparedTargetFolderIfEmpty(
                            preparation,
                            in: downloadsURL
                        )
                        persistenceFailed = true
                        processingIdentities.remove(identity)
                        break candidateLoop
                    }
                    targetIsManaged = true
                case .leaveUnmanaged:
                    break
                case .reject(let message):
                    ownershipError = message
                    if preparation.wasCreated {
                        _ = await archiveEngine.discardPreparedTargetFolderIfEmpty(
                            preparation,
                            in: downloadsURL
                        )
                    }
                }
            } else {
                ownershipError = preparation.errorMessage ?? "无法准备目标日期目录。"
            }

            if case .runtimeDownload = candidate.origin, isPaused {
                processingIdentities.remove(identity)
                continue
            }

            let result: ArchiveFileMoveResult
            if let ownershipError {
                result = ArchiveFileMoveResult(
                    sourceURL: latestSnapshot.url,
                    destinationURL: preparation.folderURL.appendingPathComponent(
                        latestSnapshot.fileName,
                        isDirectory: false
                    ),
                    sourceDay: sourceDay,
                    relativeFolderPath: preparation.relativeFolderPath,
                    succeeded: false,
                    errorMessage: ownershipError
                )
            } else {
                result = await archiveEngine.moveFile(
                    at: latestSnapshot.url,
                    sourceDay: sourceDay,
                    relativeTo: processingToday,
                    in: downloadsURL,
                    expectedSourceIdentity: latestSnapshot.identity,
                    expectedTargetDirectoryIdentity: preparation.directoryIdentity
                )
            }
            processingIdentities.remove(identity)

            let record = OperationRecord(
                fileName: latestSnapshot.fileName,
                sourcePath: result.sourceURL.path,
                destinationPath: result.destinationURL.path,
                succeeded: result.succeeded,
                errorMessage: result.errorMessage
            )

            if result.succeeded {
                pendingCandidates.removeValue(forKey: identity)
                baselineIdentities.insert(identity)
                succeededCount += 1
                if !targetIsManaged {
                    unmanagedDestinationCount += 1
                }
            } else {
                candidate.failureCount += 1
                let backoff = min(pow(2.0, Double(candidate.failureCount)), 60.0)
                candidate.nextMoveAttempt = Date().addingTimeInterval(backoff)
                pendingCandidates[identity] = candidate
                failedCount += 1
            }
            persistenceFailed = !(await persistOperation(record)) || persistenceFailed
        }

        if succeededCount > 0 || failedCount > 0 {
            if !persistenceFailed {
                statusMessage = batchStatus(succeeded: succeededCount, failed: failedCount)
                if unmanagedDestinationCount > 0 {
                    statusMessage? += " \(unmanagedDestinationCount) 个文件进入了已有日期目录；该目录不会自动迁移。"
                }
            }
            refreshTodayFilesNow()
            if notificationsEnabled, succeededCount > 0, !persistenceFailed {
                _ = try? await notificationService.sendBatchNotification(
                    succeededCount: succeededCount,
                    failedCount: failedCount
                )
            }
        }
    }

    private func scheduleRetryIfNeeded() {
        retryTask?.cancel()
        guard !pendingCandidates.isEmpty else {
            retryTask = nil
            return
        }

        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.scanAndProcessCandidates(discoverAutomaticFiles: !self.isPaused)
        }
    }

    private func persistOperation(_ record: OperationRecord) async -> Bool {
        guard let metadataStore else { return false }
        do {
            try await metadataStore.appendOperationRecord(record)
            recentOperations = await metadataStore.loadOperationRecords()
            return true
        } catch {
            pauseAfterBlockingFailure(
                "无法保存整理记录，自动整理已暂停：\(error.localizedDescription)"
            )
            return false
        }
    }

    private func persistManagedFolder(_ folder: ManagedDayFolder) async -> Bool {
        guard let metadataStore else { return false }
        do {
            try await metadataStore.upsertManagedFolder(folder)
            return true
        } catch {
            pauseAfterBlockingFailure(
                "无法保存受管理目录信息，自动整理已暂停：\(error.localizedDescription)"
            )
            return false
        }
    }

    private func pauseAfterBlockingFailure(_ message: String) {
        blockingFailureRequiresRestart = true
        isPaused = true
        defaults.set(true, forKey: DefaultsKey.paused)
        rootMonitor?.stop()
        rootMonitor = nil
        pendingCandidates.removeAll()
        processingIdentities.removeAll()
        retryTask?.cancel()
        migrationCancellationToken?.cancel()
        statusMessage = message
    }

    private func migrateManagedFolders() async {
        guard !migrationInProgress,
              !isPaused,
              let downloadsURL,
              let metadataStore
        else { return }

        migrationInProgress = true
        let cancellationToken = ArchiveMigrationCancellationToken()
        migrationCancellationToken = cancellationToken
        defer {
            if migrationCancellationToken === cancellationToken {
                migrationCancellationToken = nil
            }
            migrationInProgress = false
        }

        var folders = await metadataStore.loadManagedFolders()
        let legacyCandidates = LegacyArchiveFolderRecovery(fileManager: fileManager)
            .candidates(
                in: downloadsURL,
                operationRecords: await metadataStore.loadOperationRecords(),
                existingFolders: folders
            )
        for candidate in legacyCandidates {
            guard let sourceURL = managedFolderURL(
                relativePath: candidate.relativePath,
                rootURL: downloadsURL
            ),
                  FileSystemIdentity.directoryIdentifier(at: sourceURL)
                    == candidate.directoryIdentity
            else {
                continue
            }

            do {
                try DayDropDirectoryOwnershipMarker.mark(
                    sourceURL,
                    dateIdentifier: candidate.dateIdentifier
                )
                let recoveredFolder = ManagedDayFolder(
                    dateIdentifier: candidate.dateIdentifier,
                    relativePath: candidate.relativePath,
                    directoryIdentity: candidate.directoryIdentity
                )
                try await metadataStore.upsertManagedFolder(recoveredFolder)
                folders.append(recoveredFolder)
            } catch {
                pauseAfterBlockingFailure(
                    "无法升级旧版日期目录：\(error.localizedDescription)"
                )
                return
            }
        }
        let today = ArchiveDay(date: Date())
        var records: [OperationRecord] = []
        var succeededCount = 0
        var failedCount = 0
        var needsFollowUpPass = false

        let router = ArchivePathRouter()

        migrationLoop: for originalFolder in folders {
            guard !isPaused else { break }

            var folder = originalFolder
            if folder.directoryIdentity == nil {
                guard let sourceURL = managedFolderURL(
                    relativePath: folder.relativePath,
                    rootURL: downloadsURL
                ),
                      let sourceIdentity = FileSystemIdentity.directoryIdentifier(
                          at: sourceURL
                      )
                else {
                    pauseAfterBlockingFailure(
                        "旧版受管理目录缺少可验证身份，未执行迁移。"
                    )
                    break migrationLoop
                }

                folder = ManagedDayFolder(
                    dateIdentifier: folder.dateIdentifier,
                    relativePath: folder.relativePath,
                    directoryIdentity: sourceIdentity,
                    pendingRelativePath: folder.pendingRelativePath,
                    pendingDestinationIdentity: folder.pendingDestinationIdentity,
                    pendingDestinationExpectedAbsent: folder.pendingDestinationExpectedAbsent
                )
                do {
                    try await metadataStore.upsertManagedFolder(folder)
                } catch {
                    pauseAfterBlockingFailure(
                        "无法升级受管理目录身份：\(error.localizedDescription)"
                    )
                    break migrationLoop
                }
            }

            if let sourceURL = managedFolderURL(
                relativePath: folder.relativePath,
                rootURL: downloadsURL
            ),
               let currentSourceIdentity = FileSystemIdentity.directoryIdentifier(
                   at: sourceURL
               ) {
                if currentSourceIdentity != folder.directoryIdentity {
                    pauseAfterBlockingFailure(
                        "受管理目录的文件系统身份已变化，未执行迁移。"
                    )
                    break migrationLoop
                }
                let ownershipDate = DayDropDirectoryOwnershipMarker
                    .managedDateIdentifier(at: sourceURL)
                if ownershipDate == nil {
                    do {
                        try DayDropDirectoryOwnershipMarker.mark(
                            sourceURL,
                            dateIdentifier: folder.dateIdentifier
                        )
                    } catch {
                        pauseAfterBlockingFailure(
                            "无法写入受管理目录所有权标记：\(error.localizedDescription)"
                        )
                        break migrationLoop
                    }
                } else if ownershipDate != folder.dateIdentifier {
                    pauseAfterBlockingFailure(
                        "受管理目录的所有权标记已变化，未执行迁移。"
                    )
                    break migrationLoop
                }
            }

            let desiredPath: String
            if let sourceDay = ArchiveDay(encoded: folder.dateIdentifier) {
                desiredPath = router.route(for: sourceDay, relativeTo: today).relativePath
            } else {
                failedCount += 1
                records.append(OperationRecord(
                    fileName: folder.relativePath,
                    sourcePath: folder.relativePath,
                    destinationPath: folder.relativePath,
                    succeeded: false,
                    errorMessage: "受管理目录的完整日期无效。"
                ))
                continue
            }

            if folder.pendingRelativePath == nil,
               folder.relativePath != desiredPath {
                guard let destinationURL = managedFolderURL(
                    relativePath: desiredPath,
                    rootURL: downloadsURL
                ) else {
                    pauseAfterBlockingFailure("目录迁移目标路径无效，未执行迁移。")
                    break migrationLoop
                }
                let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
                let destinationIdentity = FileSystemIdentity.directoryIdentifier(
                    at: destinationURL
                )
                if destinationExists, destinationIdentity == nil {
                    pauseAfterBlockingFailure(
                        "目录迁移目标无法验证或不是普通目录，未执行迁移。"
                    )
                    break migrationLoop
                }
                if destinationExists,
                   DayDropDirectoryOwnershipMarker.managedDateIdentifier(
                       at: destinationURL
                   ) != folder.dateIdentifier {
                    pauseAfterBlockingFailure(
                        "迁移目标是未经 DayDrop 管理的已有目录；为避免移动用户文件，已拒绝合并。"
                    )
                    break migrationLoop
                }
                folder = ManagedDayFolder(
                    dateIdentifier: folder.dateIdentifier,
                    relativePath: folder.relativePath,
                    directoryIdentity: folder.directoryIdentity,
                    pendingRelativePath: desiredPath,
                    pendingDestinationIdentity: destinationIdentity,
                    pendingDestinationExpectedAbsent: !destinationExists
                )

                do {
                    // Persist the intent before any physical move. Finalizing
                    // the path, identity, and clearing these fields is one
                    // later atomic upsert.
                    try await metadataStore.upsertManagedFolder(folder)
                } catch {
                    pauseAfterBlockingFailure(
                        "无法保存目录迁移意图，未移动任何目录：\(error.localizedDescription)"
                    )
                    break migrationLoop
                }
            }

            guard !isPaused else { break migrationLoop }

            let result = await archiveEngine.migrateManagedFolder(
                ManagedFolderDescriptor(
                    dateIdentifier: folder.dateIdentifier,
                    relativePath: folder.relativePath,
                    directoryIdentity: folder.directoryIdentity,
                    pendingRelativePath: folder.pendingRelativePath,
                    pendingDestinationIdentity: folder.pendingDestinationIdentity,
                    pendingDestinationExpectedAbsent: folder.pendingDestinationExpectedAbsent
                ),
                relativeTo: today,
                in: downloadsURL,
                cancellationToken: cancellationToken
            )

            switch result.state {
            case .unchanged:
                guard let identity = FileSystemIdentity.directoryIdentifier(
                    at: result.destinationURL
                ) else {
                    failedCount += 1
                    pauseAfterBlockingFailure(
                        "无法验证受管理目录身份，自动整理已暂停。"
                    )
                    break migrationLoop
                }

                if folder.directoryIdentity != identity || folder.pendingRelativePath != nil {
                    do {
                        try await metadataStore.upsertManagedFolder(
                            ManagedDayFolder(
                                dateIdentifier: folder.dateIdentifier,
                                relativePath: result.expectedRelativePath,
                                directoryIdentity: identity
                            )
                        )
                    } catch {
                        pauseAfterBlockingFailure(
                            "无法更新受管理目录身份：\(error.localizedDescription)"
                        )
                        break migrationLoop
                    }
                }
                needsFollowUpPass = needsFollowUpPass
                    || result.expectedRelativePath != desiredPath
            case .moved:
                do {
                    guard let identity = FileSystemIdentity.directoryIdentifier(
                        at: result.destinationURL
                    ) else {
                        throw DayDropControllerError.managedFolderIdentityUnavailable
                    }
                    try await metadataStore.upsertManagedFolder(
                        ManagedDayFolder(
                            dateIdentifier: folder.dateIdentifier,
                            relativePath: result.expectedRelativePath,
                            directoryIdentity: identity
                        )
                    )
                    succeededCount += 1
                    records.append(OperationRecord(
                        fileName: result.sourceURL.lastPathComponent,
                        sourcePath: result.sourceURL.path,
                        destinationPath: result.destinationURL.path,
                        succeeded: true
                    ))
                    needsFollowUpPass = needsFollowUpPass
                        || result.expectedRelativePath != desiredPath
                } catch {
                    failedCount += 1
                    pauseAfterBlockingFailure(
                        "目录已迁移，但元数据更新失败；自动整理已暂停：\(error.localizedDescription)"
                    )
                    break migrationLoop
                }
            case .sourceMissing:
                if folder.pendingRelativePath != nil {
                    failedCount += 1
                    records.append(OperationRecord(
                        fileName: result.sourceURL.lastPathComponent,
                        sourcePath: result.sourceURL.path,
                        destinationPath: result.destinationURL.path,
                        succeeded: false,
                        errorMessage: "迁移意图仍存在，但来源与可验证目标均不可用。"
                    ))
                    pauseAfterBlockingFailure(
                        "无法安全恢复未完成的目录迁移，记录已保留并暂停自动整理。"
                    )
                    break migrationLoop
                } else {
                    // With no pending transaction, a missing identity-bound
                    // source means the user removed it. Never adopt a
                    // similarly named destination.
                    do {
                        try await metadataStore.removeManagedFolder(id: folder.id)
                    } catch {
                        pauseAfterBlockingFailure(
                            "无法更新受管理目录记录；自动整理已暂停：\(error.localizedDescription)"
                        )
                        break migrationLoop
                    }
                }
            case .cancelled:
                statusMessage = "目录迁移已暂停；恢复自动整理后会从已保存的迁移意图继续。"
                break migrationLoop
            case .failed:
                failedCount += 1
                records.append(OperationRecord(
                    fileName: result.sourceURL.lastPathComponent,
                    sourcePath: result.sourceURL.path,
                    destinationPath: result.destinationURL.path,
                    succeeded: false,
                    errorMessage: result.errorMessage
                ))
                pauseAfterBlockingFailure(
                    result.errorMessage.map {
                        "目录迁移未能安全完成，已暂停：\($0)"
                    } ?? "目录迁移未能安全完成，自动整理已暂停。"
                )
                break migrationLoop
            }

            // A pause requested while the current actor operation was in
            // flight takes effect before the next managed directory begins.
            if isPaused { break migrationLoop }
        }

        if !records.isEmpty {
            do {
                try await metadataStore.appendOperationRecords(records)
                recentOperations = await metadataStore.loadOperationRecords()
            } catch {
                pauseAfterBlockingFailure(
                    "无法保存迁移记录；自动整理已暂停：\(error.localizedDescription)"
                )
            }
        }

        if (succeededCount > 0 || failedCount > 0), !isPaused {
            statusMessage = batchStatus(succeeded: succeededCount, failed: failedCount)
            if notificationsEnabled, succeededCount > 0 {
                _ = try? await notificationService.sendBatchNotification(
                    succeededCount: succeededCount,
                    failedCount: failedCount
                )
            }
        }
        if needsFollowUpPass, !isPaused {
            Task { [weak self] in
                await self?.migrateManagedFolders()
            }
        }
        refreshTodayFilesNow()
    }

    private func batchStatus(succeeded: Int, failed: Int) -> String {
        switch (succeeded, failed) {
        case (_, 0):
            return "已整理 \(succeeded) 个项目。"
        case (0, _):
            return "\(failed) 个项目整理失败，原项目已保留。"
        default:
            return "已整理 \(succeeded) 个项目，\(failed) 个失败。"
        }
    }

    private func armTodayMonitorIfPossible(at folderURL: URL) {
        guard let values = try? folderURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ),
              values.isDirectory == true,
              values.isSymbolicLink != true
        else {
            stopTodayMonitor()
            return
        }

        if todayMonitorURL?.standardizedFileURL == folderURL.standardizedFileURL,
           todayMonitor?.isRunning == true {
            return
        }

        stopTodayMonitor()
        let monitor = DirectoryEventMonitor(directoryURL: folderURL)
        do {
            try monitor.start { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    if event.requiresRearm {
                        try? self.todayMonitor?.rearm()
                    }
                    self.refreshTodayFilesNow()
                }
            }
            todayMonitor = monitor
            todayMonitorURL = folderURL
        } catch {
            statusMessage = "今日列表监听不可用：\(error.localizedDescription)"
        }
    }

    private func stopTodayMonitor() {
        todayMonitor?.stop()
        todayMonitor = nil
        todayMonitorURL = nil
    }

    private func installCalendarObservers() {
        guard notificationObservers.isEmpty else { return }
        let names = [
            Notification.Name.NSSystemClockDidChange,
            Notification.Name.NSSystemTimeZoneDidChange,
            Notification.Name.NSCalendarDayChanged
        ]

        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.handleCalendarChange()
                }
            }
            notificationObservers.append(token)
        }
    }

    private func scheduleMidnightRefresh() {
        midnightTask?.cancel()
        let calendar = DayDropCalendar.local()
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
            ?? Date().addingTimeInterval(24 * 60 * 60)
        let interval = max(1, nextDay.timeIntervalSinceNow + 0.25)

        midnightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.handleCalendarChange()
        }
    }

    private func handleCalendarChange() async {
        refreshTodayFilesNow()
        if !isPaused {
            await migrateManagedFolders()
        }
        scheduleMidnightRefresh()
    }
}

private enum DayDropControllerError: LocalizedError {
    case authorizedFolderUnavailable
    case authorizedFolderIsNotCurrentDownloads
    case managedFolderIdentityUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizedFolderUnavailable:
            return "授权的文件夹不存在或不再是文件夹。"
        case .authorizedFolderIsNotCurrentDownloads:
            return "已保存的授权不再指向当前用户的“下载”文件夹。"
        case .managedFolderIdentityUnavailable:
            return "无法验证迁移后目录的文件系统身份。"
        }
    }
}
