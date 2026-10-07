import Carbon
import Foundation

/// 全局快捷键（Carbon RegisterEventHotKey —— 无需任何权限）。
///
/// ⌃⌥⌘B  立即休息
/// ⌃⌥⌘P  暂停 / 恢复
public final class HotKeyCenter {

    public static let shared = HotKeyCenter()

    public var onBreakNow: (() -> Void)?
    public var onTogglePause: (() -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []

    private static let signature: OSType = 0x49524953 // 'IRIS'

    public static var breakNowDescription: String { "⌃⌥⌘B" }
    public static var togglePauseDescription: String { "⌃⌥⌘P" }

    private init() {}

    public func register() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            guard status == noErr else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.dispatch(id: hkID.id)
            return noErr
        }

        let installStatus = InstallEventHandler(GetApplicationEventTarget(),
                                                callback,
                                                1,
                                                &eventType,
                                                Unmanaged.passUnretained(self).toOpaque(),
                                                &handlerRef)
        guard installStatus == noErr else { return }

        registerKey(keyCode: UInt32(kVK_ANSI_B), id: 1)
        registerKey(keyCode: UInt32(kVK_ANSI_P), id: 2)
    }

    public func unregister() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private func registerKey(keyCode: UInt32, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: HotKeyCenter.signature, id: id)
        var ref: EventHotKeyRef?
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        }
    }

    /// Carbon 事件回调发生在主线程。
    private func dispatch(id: UInt32) {
        switch id {
        case 1: onBreakNow?()
        case 2: onTogglePause?()
        default: break
        }
    }
}
