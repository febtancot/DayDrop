import SwiftUI

/// DayDrop's primary menu-bar panel.
///
/// The controller owns all persistent and runtime state. This view intentionally
/// routes setting changes back through controller methods so the UI never drifts
/// away from the actual monitor, login item, or notification configuration.
struct MenuBarView: View {
    @ObservedObject var controller: DayDropController

    private let panelWidth: CGFloat = 340

    private var sortedTodayFiles: [TodayFileItem] {
        controller.todayFiles.sorted { $0.completedAt > $1.completedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            accessAndStatus
            todaySection
            Divider()
            actions
            Divider()
            settings
            Divider()
            footer
        }
        .frame(width: panelWidth)
        .background(.background)
        .onAppear {
            controller.refreshTodayFilesNow()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .frame(width: 34, height: 34)

                Image(systemName: statusSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("DayDrop")
                    .font(.headline)
                Text(statusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(controller.isPaused ? "开启" : "暂停") {
                controller.togglePaused()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(controller.isPaused ? "开启自动整理" : "暂停自动整理")
            .accessibilityHint(controller.isPaused
                ? "恢复监控并整理新的已完成下载"
                : "立即停止处理新的下载文件")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var accessAndStatus: some View {
        if !controller.hasFolderAccess {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("需要访问“下载”文件夹")
                        .font(.subheadline.weight(.semibold))
                    Text("重新授权后，DayDrop 才能继续整理文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Button("授权") {
                    controller.chooseDownloadsFolder()
                }
                .controlSize(.small)
                .accessibilityLabel("重新授权下载文件夹")
            }
            .padding(12)
            .background(Color.orange.opacity(0.09))
        }

        if let message = controller.statusMessage, !message.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.secondary.opacity(0.06))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("状态：\(message)")
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日下载")
                    .font(.subheadline.weight(.semibold))
                Text("\(controller.todayFiles.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.11), in: Capsule())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                controller.openTodayFolder()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("今日下载，共 \(controller.todayFiles.count) 个文件，打开今日文件夹")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("在访达中打开今天的归档文件夹")

            if controller.todayFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("今天还没有下载文件")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 94)
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.openTodayFolder()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("今天还没有下载文件，打开今日文件夹")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("在访达中打开今天的归档文件夹")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedTodayFiles, id: \.id) { file in
                            TodayFileRow(file: file)

                            if file.id != sortedTodayFiles.last?.id {
                                Divider()
                                    .padding(.leading, 27)
                            }
                        }
                    }
                }
                .frame(minHeight: 64, maxHeight: 220)
                .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.openTodayFolder()
                }
                .accessibilityLabel("今日下载文件列表，打开今日文件夹")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("在访达中打开今天的归档文件夹")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .help("打开今日文件夹")
    }

    private var actions: some View {
        VStack(spacing: 2) {
            MenuActionRow(
                title: "立即整理现有文件",
                systemImage: "wand.and.stars",
                isEnabled: controller.hasFolderAccess,
                accessibilityHint: "按照文件创建日期整理下载文件夹顶层的现有文件"
            ) {
                controller.organizeExistingFiles()
            }

            MenuActionRow(
                title: "打开“下载”文件夹",
                systemImage: "folder",
                isEnabled: controller.hasFolderAccess,
                accessibilityHint: "在访达中打开当前授权的下载文件夹"
            ) {
                controller.openDownloadsFolder()
            }

            MenuActionRow(
                title: "最近整理记录",
                systemImage: "clock.arrow.circlepath",
                badge: controller.recentOperations.isEmpty ? nil : "\(min(controller.recentOperations.count, 50))",
                accessibilityHint: "查看最近最多五十条整理结果"
            ) {
                controller.showRecentActivity()
            }

            MenuActionRow(
                title: "设置",
                systemImage: "gearshape",
                accessibilityHint: "进入 DayDrop 设置"
            ) {
                controller.showSettings()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private var settings: some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { controller.launchAtLogin },
                set: { controller.setLaunchAtLogin($0) }
            )) {
                Label("登录时自动启动", systemImage: "power")
            }
            .toggleStyle(DayDropCompactToggleStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint("控制登录 macOS 后是否自动运行 DayDrop")

            Toggle(isOn: Binding(
                get: { controller.notificationsEnabled },
                set: { controller.setNotificationsEnabled($0) }
            )) {
                Label("整理完成通知", systemImage: "bell")
            }
            .toggleStyle(DayDropCompactToggleStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint("控制每批文件整理完成后的系统通知")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(controller.hasFolderAccess ? controller.folderDisplayName : "未授权文件夹")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(controller.folderDisplayName)

            Spacer(minLength: 8)

            Button("退出 DayDrop") {
                controller.quit()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHint("停止监控并退出应用")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var statusTitle: String {
        if !controller.hasFolderAccess { return "等待文件夹授权" }
        return controller.isPaused ? "自动整理已暂停" : "自动整理已开启"
    }

    private var statusSymbol: String {
        if !controller.hasFolderAccess { return "exclamationmark" }
        return controller.isPaused ? "pause.fill" : "checkmark"
    }

    private var statusColor: Color {
        if !controller.hasFolderAccess { return .orange }
        return controller.isPaused ? .secondary : .green
    }
}

private struct TodayFileRow: View {
    let file: TodayFileItem

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(file.name)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(file.completedAt, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .help(file.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name)，完成于 \(file.completedAt.formatted(date: .omitted, time: .shortened))")
    }
}

private struct MenuActionRow: View {
    let title: String
    let systemImage: String
    var badge: String? = nil
    var isEnabled: Bool = true
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 19)
                Text(title)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }
}
