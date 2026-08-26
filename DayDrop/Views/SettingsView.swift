import SwiftUI

/// Full settings destination for DayDrop's menu-bar panel.
///
/// Operational commands live here so the primary panel can stay focused on
/// today's downloads and recent organization history.
struct SettingsView: View {
    @ObservedObject var controller: DayDropController
    @ObservedObject var updater: DayDropUpdater

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()
            settingsTabs
        }
        .frame(width: 380, height: 520)
        .dayDropPanelSurface()
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            Button {
                controller.hideSettings()
            } label: {
                Label("返回", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回主面板")
            .accessibilityHint("关闭设置")

            Text("设置")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var settingsTabs: some View {
        TabView {
            generalSettings
                .tabItem { Label("通用", systemImage: "gearshape") }

            forNowSettings
                .tabItem {
                    Label(
                        "扩展功能",
                        systemImage: "puzzlepiece.extension"
                    )
                }
        }
    }

    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "整理工具") {
                    SettingsActionRow(
                        title: "立即整理现有文件",
                        subtitle: "按文件日期整理“下载”文件夹顶层的现有文件",
                        systemImage: "wand.and.stars",
                        isEnabled: controller.hasFolderAccess
                    ) {
                        controller.organizeExistingFiles()
                    }

                    Divider()

                    SettingsActionRow(
                        title: "深度整理子文件夹…",
                        subtitle: "处理顶层和下一层文件夹，执行前会再次确认",
                        systemImage: "folder.badge.gearshape",
                        isEnabled: controller.hasFolderAccess
                    ) {
                        controller.requestDeepOrganizationConfirmation()
                    }

                    Divider()

                    SettingsActionRow(
                        title: "打开“下载”文件夹",
                        subtitle: "在访达中打开当前授权的下载文件夹",
                        systemImage: "folder",
                        isEnabled: controller.hasFolderAccess
                    ) {
                        controller.openDownloadsFolder()
                    }
                }

                SettingsSection(title: "自动化") {
                    SettingsToggleRow(
                        title: "登录时自动启动",
                        systemImage: "power",
                        accessibilityHint: "控制登录 macOS 后是否自动运行 DayDrop",
                        isOn: Binding(
                            get: { controller.launchAtLogin },
                            set: { controller.setLaunchAtLogin($0) }
                        )
                    )

                    SettingsToggleRow(
                        title: "自动检查更新",
                        systemImage: "arrow.triangle.2.circlepath",
                        accessibilityHint: "每天在线检查一次新版本；不会上传文件或文件名",
                        isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.setAutomaticallyChecksForUpdates($0) }
                        )
                    )

                    SettingsToggleRow(
                        title: "整理完成通知",
                        systemImage: "bell",
                        accessibilityHint: "控制每批文件整理完成后的系统通知",
                        isOn: Binding(
                            get: { controller.notificationsEnabled },
                            set: { controller.setNotificationsEnabled($0) }
                        )
                    )
                }

                SettingsSection(title: "下载文件夹") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text(controller.hasFolderAccess
                                ? controller.folderDisplayName
                                : "尚未授权")
                                .lineLimit(2)
                                .truncationMode(.middle)
                        } icon: {
                            Image(systemName: controller.hasFolderAccess
                                ? "folder.fill"
                                : "folder.badge.questionmark")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .help(controller.folderDisplayName)

                        Button(controller.hasFolderAccess ? "重新授权…" : "选择文件夹…") {
                            controller.chooseDownloadsFolder()
                        }
                        .controlSize(.small)
                        .accessibilityHint("选择并授权当前用户的下载文件夹")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsSection(title: "帮助") {
                    Button {
                        controller.showOnboarding()
                    } label: {
                        Label("重新打开欢迎页面", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("再次查看首次运行时的介绍与设置页面")
                }

                SettingsSection(title: "关于") {
                    HStack(spacing: 10) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("DayDrop")
                                .font(.subheadline.weight(.semibold))
                            Text(DayDropVersionInfo.current.detailedDisplay)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if let availableVersion = updater.availableVersion {
                                Text("v\(availableVersion) 可更新")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }

                        Spacer(minLength: 8)

                        Button(updater.availableVersion == nil
                            ? "检查更新…"
                            : "安装更新…") {
                            updater.checkForUpdates()
                        }
                        .controlSize(.small)
                        .disabled(!updater.canCheckForUpdates)
                        .accessibilityHint("在线检查是否有可用的 DayDrop 新版本")
                    }
                }

                if let message = controller.statusMessage, !message.isEmpty {
                    Label(message, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("状态：\(message)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var forNowSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "产品介绍") {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(ForNowIntegrationContract.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(ForNowIntegrationContract.displayName) 是一款 macOS 本地暂存工具。文件、图片、文字、链接和录音都可先放入面板，需要时再拖出到其他应用。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }

                SettingsSection(title: "连接状态") {
                    ForNowIntegrationStatusRow(
                        availability: controller.forNowIntegrationAvailability
                    )

                    Divider()

                    Button("重新检测") {
                        controller.refreshForNowIntegrationStatus()
                    }
                    .controlSize(.small)
                    .accessibilityHint(
                        "重新检查是否安装了兼容版本的\(ForNowIntegrationContract.displayName)"
                    )
                }

                SettingsSection(title: "连接搁这儿后获得的额外能力") {
                    ForNowFeatureRow(
                        title: "今日下载",
                        description: "无需打开访达，可直接把当天文件暂存到\(ForNowIntegrationContract.displayName)。",
                        systemImage: "tray.full"
                    )

                    Divider()

                    ForNowFeatureRow(
                        title: "下载文件",
                        description: "可从文件查询结果中暂存仍在下载目录内的文件。",
                        systemImage: "doc.text.magnifyingglass"
                    )

                    Divider()

                    ForNowFeatureRow(
                        title: "整理记录",
                        description: "可将仍存在的原文件或整理后文件暂存，便于继续使用。",
                        systemImage: "clock.arrow.circlepath"
                    )
                }

                SettingsSection(title: "权限与数据") {
                    Label(
                        "无需安装 Finder 扩展。DayDrop 只发送经过路径和文件身份验证的本机文件；复制、去重和保存由\(ForNowIntegrationContract.displayName)完成。",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: "了解与下载") {
                    Link(destination: ForNowIntegrationContract.homepageURL) {
                        Label("访问产品主页", systemImage: "globe")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(ForNowIntegrationContract.homepageURL.absoluteString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .onAppear {
            controller.refreshForNowIntegrationStatus()
        }
    }
}

private struct ForNowIntegrationStatusRow: View {
    let availability: ForNowIntegrationAvailability

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch availability {
        case .notInstalled: return "未检测到\(ForNowIntegrationContract.displayName)"
        case .updateRequired: return "\(ForNowIntegrationContract.displayName)需要更新"
        case .ready: return "已连接\(ForNowIntegrationContract.displayName)"
        }
    }

    private var description: String {
        switch availability {
        case .notInstalled:
            return "安装兼容版本后，可从 DayDrop 的文件条目直接暂存内容。"
        case .updateRequired:
            return "当前版本无法接收 DayDrop 发送的文件，请先更新。"
        case .ready:
            return "连接正常，可从今日下载、下载文件和整理记录直接暂存文件。"
        }
    }

    private var systemImage: String {
        switch availability {
        case .notInstalled: return "app.badge"
        case .updateRequired: return "arrow.down.app"
        case .ready: return "checkmark.circle.fill"
        }
    }
}

private struct ForNowFeatureRow: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                Color.secondary.opacity(0.065),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    let accessibilityHint: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(DayDropCompactToggleStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint(accessibilityHint)
    }
}
