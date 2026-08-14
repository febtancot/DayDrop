import AppKit
import SwiftUI

@main
struct DayDropApp: App {
    @NSApplicationDelegateAdaptor(DayDropAppDelegate.self) private var appDelegate
    @StateObject private var controller = DayDropController.shared
    @StateObject private var updater = DayDropUpdater()

    var body: some Scene {
        MenuBarExtra {
            if controller.isShowingSettings {
                SettingsView(controller: controller, updater: updater)
            } else if controller.isShowingRecentActivity {
                RecentActivityView(controller: controller)
            } else {
                MenuBarView(controller: controller)
            }
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .opacity(controller.isPaused ? 0.55 : 1)
                .accessibilityLabel(
                    updater.availableVersion.map { "DayDrop，版本 \($0) 可更新" }
                        ?? (controller.isPaused ? "DayDrop，已暂停" : "DayDrop")
                )
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class DayDropAppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?
    private var isShowingDeepOrganizationConfirmation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !DayDropRuntime.isRunningUnitTests else { return }
        NSApp.setActivationPolicy(.accessory)

        let controller = DayDropController.shared
        controller.onOnboardingCompleted = { [weak self] in
            self?.closeOnboarding()
        }
        controller.onShowOnboarding = { [weak self, weak controller] in
            guard let controller else { return }
            self?.presentOnboarding(
                controller: controller,
                requiresCompletion: false
            )
        }
        controller.onRequestDeepOrganizationConfirmation = { [weak self, weak controller] in
            guard let self, let controller else { return }
            // A MenuBarExtra window is transient and is dismissed as soon as
            // it loses focus. Defer until the button event has completed, then
            // present an application-modal AppKit alert that owns its window.
            DispatchQueue.main.async { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.presentDeepOrganizationConfirmation(controller: controller)
            }
        }

        Task {
            await controller.start()
            if !controller.onboardingCompleted {
                presentOnboarding(
                    controller: controller,
                    requiresCompletion: true
                )
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !DayDropRuntime.isRunningUnitTests else { return }
        DayDropController.shared.stop()
    }

    private func presentOnboarding(
        controller: DayDropController,
        requiresCompletion: Bool
    ) {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: OnboardingView(controller: controller))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "欢迎使用 DayDrop"
        // DayDrop has no Dock icon. Until onboarding is completed, allowing this
        // window to close or minimize would leave no reliable way to finish setup.
        // `closeOnboarding()` can still dismiss it programmatically after the
        // user confirms their choices.
        window.styleMask = requiresCompletion
            ? [.titled]
            : [.titled, .closable, .miniaturizable]
        // Keep the scroll view below the standard title bar. A transparent,
        // full-size content view lets scrolled text pass behind the traffic
        // light controls and window title, making both layers overlap.
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 540, height: 590))
        window.minSize = NSSize(width: 500, height: 520)
        window.center()
        onboardingWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    private func presentDeepOrganizationConfirmation(
        controller: DayDropController
    ) {
        guard !isShowingDeepOrganizationConfirmation else { return }
        isShowingDeepOrganizationConfirmation = true
        defer { isShowingDeepOrganizationConfirmation = false }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "深度整理会改变现有文件夹结构"
        alert.informativeText = "DayDrop 将移动“下载”目录顶层及下一层文件夹中的文件。原有分类和文件夹结构可能被破坏，且无法自动撤销。确认继续吗？"

        // Cancellation is the safe default. The destructive action requires a
        // deliberate click and cannot be triggered by pressing Return.
        let cancelButton = alert.addButton(withTitle: "取消")
        cancelButton.keyEquivalent = "\r"
        let confirmButton = alert.addButton(withTitle: "仍要深度整理")
        confirmButton.hasDestructiveAction = true
        confirmButton.keyEquivalent = ""

        alert.window.level = .floating
        alert.window.collectionBehavior.insert(.canJoinAllSpaces)
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertSecondButtonReturn else { return }
        controller.organizeExistingFiles(scope: .includingImmediateSubfolders)
    }
}
