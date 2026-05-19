import SwiftUI

public struct ClipboardHistoryView: View {
    @ObservedObject private var model: CompanionModel
    private let onSelect: (ClipboardHistoryItem) -> Void
    private let onClose: () -> Void
    private let onRequestDetail: (ClipboardHistoryItem?) -> Void
    @State private var selectedID: ClipboardHistoryItem.ID?
    @State private var hoverTask: Task<Void, Never>?

    public init(
        model: CompanionModel,
        onSelect: @escaping (ClipboardHistoryItem) -> Void,
        onClose: @escaping () -> Void,
        onRequestDetail: @escaping (ClipboardHistoryItem?) -> Void = { _ in }
    ) {
        self.model = model
        self.onSelect = onSelect
        self.onClose = onClose
        self.onRequestDetail = onRequestDetail
    }

    public var body: some View {
        content
            .padding(12)
            .frame(width: 170)
            .fixedSize(horizontal: false, vertical: true)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        .onDisappear {
            hoverTask?.cancel()
        }
        .onExitCommand {
            onClose()
        }
        .onMoveCommand { direction in
            moveSelection(direction)
        }
        .onSubmit {
            selectCurrentItem()
        }
    }

    private var content: some View {
        Group {
            if visibleItems.isEmpty {
                Text("暂无文本")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36)
            } else {
                VStack(spacing: 3) {
                    ForEach(visibleItems) { item in
                        ClipboardHistoryRow(
                            item: item,
                            isSelected: selectedID == item.id
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onTapGesture {
                            onSelect(item)
                        }
                        .onHover { hovering in
                            hoverTask?.cancel()
                            if hovering {
                                selectedID = item.id
                                let capturedItem = item
                                hoverTask = Task {
                                    try? await Task.sleep(nanoseconds: 350_000_000)
                                    guard !Task.isCancelled else { return }
                                    onRequestDetail(capturedItem)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var visibleItems: [ClipboardHistoryItem] {
        Array(model.clipboardHistory.prefix(5))
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in items.firstIndex { $0.id == id } } ?? -1
        switch direction {
        case .down:
            selectedID = items[min(currentIndex + 1, items.count - 1)].id
        case .up:
            selectedID = items[max(currentIndex - 1, 0)].id
        default:
            break
        }
    }

    private func selectCurrentItem() {
        guard let selectedID, let item = visibleItems.first(where: { $0.id == selectedID }) else {
            return
        }
        onSelect(item)
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(previewText)
                .font(.system(.callout, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .glassEffect(.regular)
                    .tint(.purple.opacity(0.18))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var previewText: String {
        item.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
