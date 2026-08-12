import SwiftUI

/// Full settings destination for DayDrop's menu-bar panel.
///
/// The main panel keeps the two frequently used switches available as quick
/// controls. This view provides a discoverable settings destination and uses
/// the same controller bindings so both locations always reflect runtime state.
struct SettingsView: View {
    @ObservedObject var controller: DayDropController

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()
            settingsContent
        }
        .frame(width: 340)
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
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "通用") {
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
