import SwiftUI
import AppKit

/// 弹窗主视图:搜索框 + 置顶/最近两段列表 + 底部快捷键提示。
///
/// 性能要点:
/// - 行(`ClipRow`)是独立 View,悬停高亮用**行内** `@State`,因此滚动时鼠标划过不会触发整表重渲染。
/// - 图片只渲染 `store.thumbnail` 生成的小缩略图,避免每帧缩放原图。
/// - 列表用 `LazyVStack`,仅可见行被实例化。
struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    let onChoose: (ClipboardItem) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedID: UUID?

    // MARK: 过滤 / 排序(仅在输入 / 选中 / 历史变化时求值,滚动不触发)

    private var matched: [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.items }
        return store.items.filter { match($0, q) }
    }
    private var pinnedItems: [ClipboardItem] { matched.filter { $0.pinned } }
    private var recentItems: [ClipboardItem] { matched.filter { !$0.pinned } }
    private var ordered: [ClipboardItem] { pinnedItems + recentItems }

    private func match(_ item: ClipboardItem, _ q: String) -> Bool {
        if item.previewText.lowercased().contains(q) { return true }
        if let t = item.text, t.lowercased().contains(q) { return true }
        if let app = item.sourceApp, app.lowercased().contains(q) { return true }
        if let files = item.fileURLs, files.contains(where: { $0.lowercased().contains(q) }) { return true }
        return false
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            SearchField(
                text: $query,
                onMoveUp: { move(-1) },
                onMoveDown: { move(1) },
                onEnter: { chooseSelected() },
                onCancel: { onClose() },
                onDelete: { deleteSelected() }
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().opacity(0.5)

            if store.items.isEmpty {
                emptyState(symbol: "clipboard", text: "暂无剪贴板历史\n复制点东西试试")
            } else if ordered.isEmpty {
                emptyState(symbol: "magnifyingglass", text: "没有匹配「\(query)」的记录")
            } else {
                listView
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 400, height: 520)
        .background(VisualEffectBlur(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear { selectedID = ordered.first?.id }
        .onChange(of: query, perform: { _ in selectedID = ordered.first?.id })
    }

    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !pinnedItems.isEmpty {
                        sectionHeader("置顶")
                        ForEach(pinnedItems) { rowView($0) }
                    }
                    if !recentItems.isEmpty {
                        if !pinnedItems.isEmpty { sectionHeader("最近") }
                        ForEach(recentItems) { rowView($0) }
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedID, perform: { id in
                guard let id = id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            })
        }
    }

    private func rowView(_ item: ClipboardItem) -> some View {
        ClipRow(
            item: item,
            isSelected: item.id == selectedID,
            thumbnail: item.kind == .image ? store.thumbnail(for: item) : nil,
            relativeTime: Self.relativeTime(item.date),
            onChoose: { onChoose(item) },
            onTogglePin: { store.togglePin(item) },
            onDelete: { store.delete(item); fixSelectionAfterDelete() }
        )
        .id(item.id)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyState(symbol: String, text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.45))
            Text(text)
                .multilineTextAlignment(.center)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            hint("↑↓", "选择")
            hint("↵", "粘贴")
            hint("⌫", "删除")
            hint("esc", "关闭")
            Spacer()
            Text("\(store.items.count) 条")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
    }

    // MARK: 键盘导航 / 删除

    private func move(_ delta: Int) {
        let ids = ordered.map { $0.id }
        guard !ids.isEmpty else { selectedID = nil; return }
        guard let cur = selectedID, let idx = ids.firstIndex(of: cur) else {
            selectedID = ids.first
            return
        }
        let next = max(0, min(ids.count - 1, idx + delta))
        selectedID = ids[next]
    }

    private func chooseSelected() {
        if let id = selectedID, let item = ordered.first(where: { $0.id == id }) {
            onChoose(item)
        } else if let first = ordered.first {
            onChoose(first)
        }
    }

    /// 删除当前选中项,并把选中态落到原位置的下一项(若删的是最后一项则落到上一项)。
    private func deleteSelected() {
        guard let id = selectedID, let idx = ordered.firstIndex(where: { $0.id == id }) else { return }
        store.delete(ordered[idx])
        let now = ordered
        selectedID = now.isEmpty ? nil : now[min(idx, now.count - 1)].id
    }

    /// 右键菜单删除后,如果选中项已不存在,把选中态归到第一项。
    private func fixSelectionAfterDelete() {
        if let id = selectedID, ordered.contains(where: { $0.id == id }) { return }
        selectedID = ordered.first?.id
    }

    // MARK: 工具

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeTime(_ date: Date) -> String {
        relFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 单行(独立 View,悬停状态行内管理)

private struct ClipRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let thumbnail: NSImage?
    let relativeTime: String
    let onChoose: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 11) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                Text(item.previewText)
                    .lineLimit(1)
                    .font(.system(size: 13))
                HStack(spacing: 5) {
                    if let app = item.sourceApp, !app.isEmpty {
                        Text(app)
                        Text("·").opacity(0.5)
                    }
                    Text(relativeTime)
                }
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.20)
                      : (hovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { onChoose() }
        .onHover { hovered = $0 }
        .contextMenu {
            Button(item.pinned ? "取消置顶" : "置顶") { onTogglePin() }
            Button("复制 / 粘贴") { onChoose() }
            Divider()
            Button("删除", role: .destructive) { onDelete() }
        }
    }

    @ViewBuilder
    private var badge: some View {
        Group {
            if item.kind == .image, let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    tint.opacity(0.16)
                    Image(systemName: item.symbolName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(tint)
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var tint: Color {
        switch item.kind {
        case .text: return .blue
        case .image: return .green
        case .file: return .orange
        }
    }
}

// MARK: - 半透明背景(vibrancy)

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

// MARK: - 自定义搜索框(拦截方向键 / 回车 / esc / 删除)

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onEnter: () -> Void
    var onCancel: () -> Void
    var onDelete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "搜索剪贴板历史…"
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.controlSize = .large
        field.font = .systemFont(ofSize: 14)
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        // 视图刚建立时尝试抢占焦点(此时面板通常已经/即将成为 key)
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp(); return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown(); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onEnter(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel(); return true
            case #selector(NSResponder.deleteBackward(_:)):
                // 搜索框为空时,⌫ 删除选中项;否则正常删字符
                if parent.text.isEmpty { parent.onDelete(); return true }
                return false
            case #selector(NSResponder.deleteForward(_:)):
                parent.onDelete(); return true
            default:
                return false
            }
        }
    }
}
