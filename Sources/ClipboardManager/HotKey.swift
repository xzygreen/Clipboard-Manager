import Carbon
import Foundation

enum HotKeyError: LocalizedError {
    case installHandler(OSStatus)
    case register(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandler(let status):
            return "安装全局快捷键处理器失败（\(status)）"
        case .register(let status):
            return "注册 ⌘⇧V 失败，可能已被其他应用占用（\(status)）"
        }
    }
}

/// 通过 Carbon `RegisterEventHotKey` 注册一个无需辅助功能权限的全局快捷键。
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    init(
        keyCode: UInt32 = UInt32(kVK_ANSI_V),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey),
        handler: @escaping () -> Void
    ) throws {
        self.handler = handler
        try register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { owner.handler() }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        guard handlerStatus == noErr else {
            throw HotKeyError.installHandler(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            throw HotKeyError.register(registerStatus)
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
