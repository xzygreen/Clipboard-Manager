import AppKit
import ApplicationServices
import CoreGraphics

/// 模拟 ⌘V 把当前剪贴板内容粘贴到指定 App,以及辅助功能权限的检查/申请。
enum AutoPaster {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 等指定 App 真正回到前台后再粘贴。激活失败或超时只保留已复制内容,绝不粘到别处。
    static func paste(
        whenActive target: NSRunningApplication,
        timeout: TimeInterval = 1.2,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard isTrusted(), !target.isTerminated,
              target != NSRunningApplication.current else {
            completion?(false)
            return
        }

        let deadline = Date().addingTimeInterval(timeout)
        _ = target.activate(options: [.activateIgnoringOtherApps])

        func attempt() {
            guard !target.isTerminated else {
                completion?(false)
                return
            }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                completion?(postPaste())
                return
            }
            guard Date() < deadline else {
                completion?(false)
                return
            }
            _ = target.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: attempt)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: attempt)
    }

    @discardableResult
    private static func postPaste() -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        let vKey = CGKeyCode(9)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
