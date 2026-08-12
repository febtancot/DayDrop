import SwiftUI

/// Displays the most recent local file operations. The controller/store remains
/// responsible for enforcing the persisted 50-record limit; the view also caps
/// its presentation defensively.
struct RecentActivityView: View {
    @ObservedObject var controller: DayDropController

    private var displayedOperations: [OperationRecord] {
        Array(
            controller.recentOperations
                .sorted { $0.performedAt > $1.performedAt }
                .prefix(50)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()

            if displayedOperations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayedOperations, id: \.id) { record in
                            OperationRecordCard(record: record)
                        }
                    }
                    .padding(14)
                }
                .accessibilityLabel("最近整理记录列表")
            }
        }
        .frame(width: 420)
        .frame(minHeight: 420, idealHeight: 520, maxHeight: 620)
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
            .accessibilityHint("关闭最近整理记录")

            Text("最近整理记录")
                .font(.headline)

            Spacer()

            Text("\(displayedOperations.count) 条")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("共 \(displayedOperations.count) 条记录")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("还没有整理记录")
                .font(.headline)
            Text("文件整理成功或失败后，记录会显示在这里。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

private struct OperationRecordCard: View {
    let record: OperationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(record.succeeded ? "成功" : "失败", systemImage: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
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

            VStack(alignment: .leading, spacing: 7) {
                PathRow(label: "原位置", path: record.sourcePath)
                PathRow(label: "目标位置", path: record.destinationPath)
            }

            if !record.succeeded,
               let errorMessage = record.errorMessage,
               !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("失败原因：\(errorMessage)")
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(record.fileName)，\(record.succeeded ? "整理成功" : "整理失败")，\(record.performedAt.formatted(date: .abbreviated, time: .shortened))")
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
                .textSelection(.enabled)
                .help(path)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)：\(path)")
    }
}
