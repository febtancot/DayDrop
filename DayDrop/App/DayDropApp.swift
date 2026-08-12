import AppKit
import SwiftUI

@main
struct DayDropApp: App {
    @NSApplicationDelegateAdaptor(DayDropAppDelegate.self) private var appDelegate
    @StateObject private var controller = DayDropController.shared

    var body: some Scene {
        MenuBarExtra {
            if controller.isShowingSettings {
                SettingsView(controller: controller)
            } else if controller.isShowingRecentActivity {
                RecentActivityView(controller: controller)
            } else {
                MenuBarView(controller: controller)
            }
        } label: {
            Label(
                "DayDrop",
                systemImage: controller.isPaused ? "drop" : "drop.fill"
            )
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class DayDropAppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

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
}
