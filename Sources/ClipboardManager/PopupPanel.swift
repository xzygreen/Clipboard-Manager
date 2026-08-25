import AppKit
import SwiftUI

/// 承载历史列表 SwiftUI 视图的浮动面板。
///
/// 无边框 + 透明背景,圆角与半透明由 SwiftUI 内容(`VisualEffectBlur` + 圆角裁剪)负责,
/// 窗口本身负责阴影与定位。唤出时激活本 App 并成为 key(搜索框可输入、方向键可用);
/// 选中或关闭后 `orderOut` 并 `NSApp.hide`,把焦点交还上一个 App,用户随即 ⌘V 粘贴。
final class PopupPanel: NSPanel {

    private let store: HistoryStore

    /// 选中某条时的处理(由 AppDelegate 注入:写回剪贴板 +(可选)自动粘贴)。
    var chooseHandler: ((ClipboardItem) -> Void)?

    /// 唤出面板前的前台 App,用于关闭后把焦点/粘贴交还给它。
    private(set) var previousApp: NSRunningApplication?

    init(store: HistoryStore) {
        self.store = store
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    // 无边框窗口必须显式允许成为 key,否则搜索框无法输入。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: 显示 / 隐藏

    func toggle() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        // 记录唤出前的前台 App(用于关闭后交还焦点 / 自动粘贴目标)
        let front = NSWorkspace.shared.frontmostApplication
        if front != NSRunningApplication.current { previousApp = front }

        // 每次重建视图 → 重置搜索词与选中项,并触发搜索框重新抢焦点
        let root = HistoryView(
            store: store,
            onChoose: { [weak self] item in self?.chooseHandler?(item) },
            onClose: { [weak self] in self?.hidePanel() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 520)
        contentView = hosting

        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        orderOut(nil)
        // 让出激活状态,焦点回到此前的前台 App
        NSApp.hide(nil)
    }

    /// 收起面板并把焦点交还给唤出前的前台 App(供自动粘贴前调用)。
    func dismissReturningFocus() {
        orderOut(nil)
        if let prev = previousApp, prev != NSRunningApplication.current {
            prev.activate(options: [.activateIgnoringOtherApps])
        } else {
            NSApp.hide(nil)
        }
    }

    // MARK: 定位(鼠标所在屏幕的上方居中)

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = frame.size
        let originX = visible.midX - size.width / 2
        let topMargin = visible.height * 0.12
        let originY = visible.maxY - size.height - topMargin
        setFrameOrigin(NSPoint(x: originX, y: max(visible.minY, originY)))
    }
}
