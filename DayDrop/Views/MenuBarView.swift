import SwiftUI

/// DayDrop's primary menu-bar panel.
///
/// The controller owns all persistent and runtime state. This view intentionally
/// routes setting changes back through controller methods so the UI never drifts
/// away from the actual monitor, login item, or notification configuration.
struct MenuBarView: View {
    @ObservedObject var controller: DayDropController

    private let panelWidth: CGFloat = 380

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
            recentActivityAction
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

            HStack(spacing: 6) {
                Button {
                    controller.showSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("打开整理、文件夹、自动化与更新设置")

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
                .frame(maxWidth: .infinity, minHeight: 200)
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
                            TodayFileRow(
                                file: file,
                                showsForNowAction: controller.isForNowIntegrationReady,
                                canAddToForNow: { controller.canAddTodayFileToForNow(file) },
                                onAddToForNow: { controller.addTodayFileToForNow(file) },
                                onRevealInFinder: { controller.revealTodayFile(file) }
                            )

                            if file.id != sortedTodayFiles.last?.id {
                                Divider()
                                    .padding(.leading, 27)
                            }
                        }
                    }
                }
                .frame(height: 240)
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

    private var recentActivityAction: some View {
        VStack(spacing: 0) {
            MenuActionRow(
                title: "文件查询",
                systemImage: "doc.text.magnifyingglass",
                badge: controller.indexedFileCount == 0 ? nil : "\(controller.indexedFileCount)",
                accessibilityHint: "搜索下载目录中的当前文件或查看完整整理记录"
            ) {
                controller.showRecentActivity()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
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

            Text(DayDropVersionInfo.current.compactDisplay)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .accessibilityLabel(DayDropVersionInfo.current.detailedDisplay)

            Button {
                controller.quit()
            } label: {
                Label("退出", systemImage: "power")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color.red)
                    .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.red.opacity(0.28), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出 DayDrop")
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
    let showsForNowAction: Bool
    let canAddToForNow: () -> Bool
    let onAddToForNow: () -> Void
    let onRevealInFinder: () -> Void

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
        .contextMenu {
            if showsForNowAction {
                Button(action: onAddToForNow) {
                    Label(
                        "添加到\(ForNowIntegrationContract.displayName)",
                        systemImage: "tray.and.arrow.down"
                    )
                }
                .disabled(!canAddToForNow())
                Divider()
            }
            Button(action: onRevealInFinder) {
                Label("在访达中显示", systemImage: "folder")
            }
        }
        .help(file.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name)，完成于 \(file.completedAt.formatted(date: .omitted, time: .shortened))")
        .accessibilityAction(named: Text("在访达中显示"), onRevealInFinder)
        .todayForNowAccessibilityAction(
            isAvailable: showsForNowAction,
            action: onAddToForNow
        )
    }
}

private extension View {
    @ViewBuilder
    func todayForNowAccessibilityAction(
        isAvailable: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isAvailable {
            accessibilityAction(
                named: Text("添加到\(ForNowIntegrationContract.displayName)"),
                action
            )
        } else {
            self
        }
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
