import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide hotkey via the Carbon Event Manager and
/// invokes a callback when it fires. `RegisterEventHotKey` works for ordinary
/// apps and does not require Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `kVK_Space`.
    ///   - modifiers: Carbon modifier mask, e.g. `optionKey`, `cmdKey`.
    init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Route the C callback back to this instance via userData.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData else { return noErr }
                let hk = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                hk.handler()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C415345 /* 'LASE' */), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
