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
            settingsContent
        }
        .frame(width: 380, height: 520)
        .background(.background)
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

    private var settingsContent: some View {
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
