import AppKit
import CoreGraphics
import ApplicationServices

/// 模拟 ⌘V 把当前剪贴板内容粘贴到前台 App,以及辅助功能(Accessibility)权限的检查/申请。
///
/// 合成按键(`CGEvent.post`)需要系统「辅助功能」授权,否则按键会被静默丢弃。
enum AutoPaster {

    /// 本进程是否已获得辅助功能授权。
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 申请授权:若未授权,弹出系统提示把本 App 加入「辅助功能」列表。
    @discardableResult
    static func requestPermission() -> Bool {
        // key 即 kAXTrustedCheckOptionPrompt 的字符串值,硬编码可避开 Unmanaged 桥接的写法差异。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 合成一次 ⌘V。
    static func paste() {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey = CGKeyCode(9)   // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
