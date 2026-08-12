import SwiftUI

/// First-run setup. Existing files are never organized until the user opts in
/// and presses the final confirmation button.
struct OnboardingView: View {
    @ObservedObject var controller: DayDropController

    @State private var launchAtLogin = true
    @State private var organizeExistingFiles = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    folderAccessStep
                    preferencesStep
                    privacyNote
                }
                .padding(32)
            }

            Divider()

            completionBar
        }
        .frame(minWidth: 500, idealWidth: 540, minHeight: 520, idealHeight: 590)
        .background(.background)
        .onAppear {
            launchAtLogin = controller.launchAtLogin
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("欢迎使用 DayDrop")
                        .font(.title2.weight(.bold))
                    Text("Downloads, day by day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("DayDrop 会在下载完成后，按日期自动整理“下载”文件夹。最近的文件保持在浅层目录，较早的文件会按月和年份逐步收纳。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var folderAccessStep: some View {
        SetupCard(step: "1", title: "选择“下载”文件夹") {
            VStack(alignment: .leading, spacing: 12) {
                Text("macOS 需要你明确授权。DayDrop 只会处理所选文件夹顶层的文件，不会读取文件内容。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Image(systemName: controller.hasFolderAccess ? "checkmark.circle.fill" : "folder.badge.questionmark")
                        .foregroundStyle(controller.hasFolderAccess ? Color.green : Color.secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(controller.hasFolderAccess ? "已授权" : "尚未授权")
                            .font(.subheadline.weight(.semibold))
                        if controller.hasFolderAccess {
                            Text(controller.folderDisplayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 8)

                    Button(controller.hasFolderAccess ? "重新选择…" : "选择文件夹…") {
                        controller.chooseDownloadsFolder()
                    }
                    .accessibilityLabel(controller.hasFolderAccess ? "重新选择下载文件夹" : "选择下载文件夹")
                    .accessibilityHint("打开系统文件夹选择器")
                }

                if !controller.hasFolderAccess {
                    Label("完成设置前必须授权一个文件夹。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var preferencesStep: some View {
        SetupCard(step: "2", title: "选择运行方式") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("登录时自动启动")
                            .font(.subheadline.weight(.medium))
                        Text("登录 macOS 后静默运行，并监控新的下载。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityHint("可稍后在菜单栏面板中更改")

                Divider()

                Toggle(isOn: $organizeExistingFiles) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("立即整理已有文件")
                            .font(.subheadline.weight(.medium))
                        Text("仅整理所选文件夹顶层已有的文件，并按创建日期归档。已有文件夹不会移动。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityHint("关闭时不会自动整理授权前已经存在的文件")
            }
        }
    }

    private var privacyNote: some View {
        Label {
            Text("所有整理和记录都只保存在这台 Mac 上；DayDrop 不上传文件或文件名。启用更新检查时，仅连接官方网站获取版本信息与安装包。")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var completionBar: some View {
        VStack(spacing: 8) {
            if let message = controller.statusMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("状态：\(message)")
            }

            HStack {
                if !controller.hasFolderAccess {
                    Text("请先选择文件夹")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("完成设置") {
                    controller.completeOnboarding(
                        organizeExisting: organizeExistingFiles,
                        launchAtLogin: launchAtLogin
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!controller.hasFolderAccess)
                .accessibilityHint(controller.hasFolderAccess
                    ? "保存选择并开始使用 DayDrop"
                    : "需要先授权下载文件夹")
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }
}

private struct SetupCard<Content: View>: View {
    let step: String
    let title: String
    @ViewBuilder let content: Content

    init(step: String, title: String, @ViewBuilder content: () -> Content) {
        self.step = step
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Text(step)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
            }

            content
                .padding(.leading, 31)
        }
        .padding(18)
        .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 \(step) 步：\(title)")
    }
}
