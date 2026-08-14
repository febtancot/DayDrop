import SwiftUI

/// Unified local search for the current Downloads inventory and DayDrop's
/// permanent organization history.
struct RecentActivityView: View {
    @ObservedObject var controller: DayDropController

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()
            scopePicker
            Divider()
            queryControls
            Divider()
            results
        }
        .frame(width: 480)
        .frame(minHeight: 520, idealHeight: 640, maxHeight: 740)
        .background(.background)
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            Button {
                controller.hideRecentActivity()
            } label: {
                Label("返回", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回主面板")
            .accessibilityHint("关闭文件查询")

            Text("文件查询")
                .font(.headline)

            Spacer()

            if controller.libraryQueryScope == .files,
               controller.isReconcilingDownloadsIndex {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在扫描下载文件夹")
            }

            Text("\(queryCount) 条")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("当前查询共 \(queryCount) 条")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var scopePicker: some View {
        Picker(
            "查询范围",
            selection: Binding(
                get: { controller.libraryQueryScope },
                set: { controller.setLibraryQueryScope($0) }
            )
        ) {
            ForEach(LibraryQueryScope.allCases, id: \.self) { scope in
                Text(scope.displayName).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var queryControls: some View {
        VStack(spacing: 10) {
            searchField
            switch controller.libraryQueryScope {
            case .files:
                indexedFileFilters
                Label(
                    "只读索引整个下载目录；暂停自动整理不会暂停索引。",
                    systemImage: "magnifyingglass.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .operations:
                historyFilters
                Label("双击任一记录可在访达中显示文件", systemImage: "cursorarrow.click.2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                controller.libraryQueryScope == .files
                    ? "搜索下载目录中的文件名或路径"
                    : "搜索整理记录中的文件名、路径或失败原因",
                text: Binding(
                    get: { searchText },
                    set: { updateSearchText($0) }
                )
            )
            .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    updateSearchText("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索文字")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var indexedFileFilters: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(DownloadFilePresenceFilter.allCases, id: \.self) { presence in
                    Button(presence.displayName) {
                        controller.setIndexedFilePresence(presence)
                    }
                }
            } label: {
                Label(controller.indexedFileFilter.presence.displayName, systemImage: "externaldrive")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            categoryMenu(
                selected: controller.indexedFileFilter.category,
                onSelect: controller.setIndexedFileCategory
            )

            Spacer()

            if controller.indexedFileFilter != .current {
                Button("重置") {
                    controller.clearIndexedFileFilters()
                }
                .controlSize(.small)
            }
        }
    }

    private var historyFilters: some View {
        HStack(spacing: 8) {
            Picker(
                "结果",
                selection: Binding(
                    get: { controller.historyFilter.outcome },
                    set: { controller.setHistoryOutcome($0) }
                )
            ) {
                ForEach(HistoryOutcomeFilter.allCases, id: \.self) { outcome in
                    Text(outcome.displayName).tag(outcome)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 190)

            categoryMenu(
                selected: controller.historyFilter.category,
                onSelect: controller.setHistoryCategory
            )

            Spacer(minLength: 4)

            Menu {
                Button("导出 CSV…") { controller.exportHistory(.csv) }
                Button("导出 JSON…") { controller.exportHistory(.json) }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(controller.historyTotalCount == 0)
            .accessibilityHint("导出当前整理记录查询")
        }
    }

    private func categoryMenu(
        selected: HistoryFileCategory?,
        onSelect: @escaping (HistoryFileCategory?) -> Void
    ) -> some View {
        Menu {
            Button("全部类型") { onSelect(nil) }
            Divider()
            ForEach(HistoryFileCategory.allCases, id: \.self) { category in
                Button {
                    onSelect(category)
                } label: {
                    Label(category.displayName, systemImage: category.systemImage)
                }
            }
        } label: {
            Label(
                selected?.displayName ?? "文件类型",
                systemImage: selected?.systemImage ?? "line.3.horizontal.decrease.circle"
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var results: some View {
        switch controller.libraryQueryScope {
        case .files:
            indexedFileResults
        case .operations:
            historyResults
        }
    }

    @ViewBuilder
    private var indexedFileResults: some View {
        if let errorMessage = controller.downloadsIndexErrorMessage {
            errorState(
                title: "无法读取下载文件索引",
                message: errorMessage
            )
        } else if controller.indexedFiles.isEmpty && !controller.isLoadingIndexedFiles {
            emptyState(
                symbol: "doc.text.magnifyingglass",
                title: controller.indexedFileFilter == .current ? "没有可查询的文件" : "没有匹配文件",
                message: controller.indexedFileFilter == .current
                    ? "授权后，DayDrop 会在后台建立下载目录的只读文件索引。"
                    : "没有符合当前搜索和筛选条件的文件。",
                onReset: indexedFileResetAction
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(controller.indexedFiles, id: \.id) { file in
                        IndexedFileCard(file: file) {
                            controller.revealIndexedFile(file)
                        }
                        .onAppear {
                            if file.id == controller.indexedFiles.last?.id {
                                controller.loadMoreIndexedFiles()
                            }
                        }
                    }
                    if controller.isLoadingIndexedFiles {
                        ProgressView().controlSize(.small).padding(.vertical, 12)
                    }
                }
                .padding(14)
            }
            .accessibilityLabel("下载文件查询结果列表")
        }
    }

    @ViewBuilder
    private var historyResults: some View {
        if let errorMessage = controller.historyErrorMessage {
            errorState(title: "无法读取整理记录", message: errorMessage)
        } else if controller.historyOperations.isEmpty && !controller.isLoadingHistory {
            emptyState(
                symbol: "clock.arrow.circlepath",
                title: "还没有整理记录",
                message: controller.historyFilter == .all
                    ? "文件整理成功或失败后，记录会永久保存在这台 Mac 上。"
                    : "没有符合当前搜索和筛选条件的记录。",
                onReset: historyResetAction
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(controller.historyOperations, id: \.id) { record in
                        OperationRecordCard(record: record) {
                            controller.revealHistoryRecord(record)
                        }
                        .onAppear {
                            if record.id == controller.historyOperations.last?.id {
                                controller.loadMoreHistory()
                            }
                        }
                    }
                    if controller.isLoadingHistory {
                        ProgressView().controlSize(.small).padding(.vertical, 12)
                    }
                }
                .padding(14)
            }
            .accessibilityLabel("整理记录查询结果列表")
        }
    }

    private func emptyState(
        symbol: String,
        title: String,
        message: String,
        onReset: (() -> Void)?
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let onReset {
                Button("清除筛选条件", action: onReset).controlSize(.small)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func errorState(title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var searchText: String {
        switch controller.libraryQueryScope {
        case .files: return controller.indexedFileFilter.searchText
        case .operations: return controller.historyFilter.searchText
        }
    }

    private func updateSearchText(_ value: String) {
        switch controller.libraryQueryScope {
        case .files: controller.updateIndexedFileSearchText(value)
        case .operations: controller.updateHistorySearchText(value)
        }
    }

    private var queryCount: Int {
        switch controller.libraryQueryScope {
        case .files: return controller.indexedFileQueryCount
        case .operations: return controller.historyTotalCount
        }
    }

    private var indexedFileResetAction: (() -> Void)? {
        guard controller.indexedFileFilter != .current else { return nil }
        return { controller.clearIndexedFileFilters() }
    }

    private var historyResetAction: (() -> Void)? {
        guard controller.historyFilter != .all else { return nil }
        return { controller.clearHistoryFilters() }
    }
}

private struct IndexedFileCard: View {
    let file: IndexedDownloadFile
    let onRevealInFinder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    file.isPresent ? "当前存在" : "已移出或删除",
                    systemImage: file.isPresent ? "checkmark.circle.fill" : "questionmark.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(file.isPresent ? Color.green : Color.secondary)

                Text(file.fileName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.fileName)
                Spacer(minLength: 8)
                Label(file.fileCategory.displayName, systemImage: file.fileCategory.systemImage)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(file.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(file.relativePath)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if let size = file.size {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file))
                }
                if let modificationDate = file.modificationDate {
                    Text("修改于 \(modificationDate.formatted(date: .abbreviated, time: .shortened))")
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded(onRevealInFinder))
        .help("双击在访达中显示文件或最后记录位置")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(file.fileName)，\(file.fileCategory.displayName)，\(file.isPresent ? "当前存在" : "已移出或删除")")
        .accessibilityHint("双击或执行“在访达中显示”可打开文件位置")
        .accessibilityAction(named: Text("在访达中显示"), onRevealInFinder)
    }
}

private struct OperationRecordCard: View {
    let record: OperationRecord
    let onRevealInFinder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    record.succeeded ? "成功" : "失败",
                    systemImage: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(record.succeeded ? Color.green : Color.red)

                Text(record.fileName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(record.fileName)
                Spacer(minLength: 8)
                Text(record.performedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Label(record.fileCategory.displayName, systemImage: record.fileCategory.systemImage)
                Text(record.trigger.displayName)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                PathRow(label: "原位置", path: record.sourcePath)
                PathRow(label: "目标位置", path: record.destinationPath)
            }

            if !record.succeeded, let errorMessage = record.errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded(onRevealInFinder))
        .help("双击在访达中显示文件")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(record.fileName)，\(record.fileCategory.displayName)，\(record.succeeded ? "整理成功" : "整理失败")")
        .accessibilityHint("双击或执行“在访达中显示”可打开文件所在位置")
        .accessibilityAction(named: Text("在访达中显示"), onRevealInFinder)
    }
}

private struct PathRow: View {
    let label: String
    let path: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(path)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)：\(path)")
    }
}
