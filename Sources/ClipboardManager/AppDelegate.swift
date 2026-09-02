import AppKit
import ServiceManagement

/// 总装配:状态栏图标、全局快捷键、剪贴板监听、弹窗、右键菜单。
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var panel: PopupPanel!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!

    /// 选中后是否自动粘贴(默认开;需「辅助功能」权限)。
    private var autoPasteEnabled: Bool =
        (UserDefaults.standard.object(forKey: "autoPasteEnabled") as? Bool) ?? true
    private var didPromptAX = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = HistoryStore()

        monitor = ClipboardMonitor(store: store)
        // 我们写回剪贴板后,让监听器把当前状态当作已知,避免回环
        store.pasteboardWriteHook = { [weak monitor] in monitor?.acknowledgeCurrentState() }
        monitor.start()

        panel = PopupPanel(store: store)
        panel.chooseHandler = { [weak self] item in self?.handleChoose(item) }

        // 全局快捷键 ⌘⇧V
        do {
            hotKey = try HotKey { [weak self] in self?.panel.toggle() }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.presentError(error.localizedDescription)
            }
        }

        setupStatusItem()

        // 开启了自动粘贴但还没授权 → 启动时申请一次「辅助功能」权限
        if autoPasteEnabled && !AutoPaster.isTrusted() {
            AutoPaster.requestPermission()
        }

        // 隐藏调试开关:塞入样例数据并立即弹出面板(仅供截图/可视化验证)
        if CommandLine.arguments.contains("--debug-show") {
            seedSampleData()
            panel.hidesOnDeactivate = false   // 调试时不随失焦隐藏,便于截图
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.panel.showPanel()
            }
        }
    }

    // MARK: 选中处理(复制 +(可选)自动粘贴)

    private func handleChoose(_ item: ClipboardItem) {
        guard store.copyToPasteboard(item) else {
            panel.hidePanel()
            presentError("该条目的原始内容已不可用，系统剪贴板未被修改。")
            return
        }

        guard autoPasteEnabled else {
            panel.hidePanel()
            return
        }

        guard AutoPaster.isTrusted() else {
            panel.dismissReturningFocus()
            promptAccessibilityIfNeeded()
            return
        }

        guard let target = panel.previousApp,
              !target.isTerminated,
              target != NSRunningApplication.current else {
            panel.hidePanel()
            return
        }
        panel.dismissReturningFocus()
        AutoPaster.paste(whenActive: target)
    }

    private func promptAccessibilityIfNeeded() {
        AutoPaster.requestPermission()   // 触发系统「辅助功能」提示
        guard !didPromptAX else { return }
        didPromptAX = true

        let alert = NSAlert()
        alert.messageText = "需要「辅助功能」权限才能自动粘贴"
        alert.informativeText = "内容已复制到剪贴板。要让选中后自动粘贴生效,请在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 ClipboardManager,然后重试。\n\n(也可以在菜单里关闭「选中后自动粘贴」,改为手动 ⌘V。)"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 仅 --debug-show 使用:制造几条不同类型的样例记录。
    private func seedSampleData() {
        store.add(.text("https://github.com/anthropics/anthropic-sdk-swift"), sourceApp: "Safari")
        store.add(.files(["/Users/green/Desktop/季度报告.pdf"]), sourceApp: "访达")
        store.add(.text("func quickSort<T: Comparable>(_ a: [T]) -> [T] { ... }"), sourceApp: "Xcode")
        store.add(.text("会议纪要:周四 10:00 与设计团队同步剪贴板管理器的交互细节,确认快捷键与置顶逻辑。"), sourceApp: "备忘录")
        store.add(.text("brew install --cask clipboard-manager"), sourceApp: "终端")
        store.add(.text("置顶的常用文本片段"), sourceApp: "备忘录")
        if let pin = store.items.first(where: { $0.text == "置顶的常用文本片段" }) {
            store.togglePin(pin)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: 状态栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "剪贴板历史")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "剪贴板历史(⌘⇧V)"
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRight {
            showMenu()
        } else {
            panel.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        menu.addItem(withTitle: "打开历史    ⌘⇧V",
                     action: #selector(openHistory), keyEquivalent: "")

        menu.addItem(.separator())

        let pasteItem = NSMenuItem(title: "选中后自动粘贴",
                                   action: #selector(toggleAutoPaste),
                                   keyEquivalent: "")
        pasteItem.state = autoPasteEnabled ? .on : .off
        menu.addItem(pasteItem)

        let launchItem = NSMenuItem(title: "开机时启动",
                                    action: #selector(toggleLaunchAtLogin),
                                    keyEquivalent: "")
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(withTitle: "清空历史…",
                     action: #selector(clearHistory), keyEquivalent: "")

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出剪贴板历史",
                     action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.action != nil { item.target = self }

        // 临时挂上菜单；等 menuDidClose 再解绑，避免状态栏按钮残留高亮吞掉下次左键。
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard statusItem.menu === menu else { return }
        statusItem.menu = nil
        statusItem.button?.highlight(false)
    }

    // MARK: 菜单动作

    @objc private func openHistory() {
        panel.showPanel()
    }

    @objc private func toggleAutoPaste() {
        autoPasteEnabled.toggle()
        UserDefaults.standard.set(autoPasteEnabled, forKey: "autoPasteEnabled")
        if autoPasteEnabled && !AutoPaster.isTrusted() {
            promptAccessibilityIfNeeded()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            presentError("无法设置开机启动:\(error.localizedDescription)\n(未签名/未放入 /Applications 时此功能可能不可用)")
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空全部剪贴板历史?"
        alert.informativeText = "此操作不可撤销,包含已置顶的条目。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
