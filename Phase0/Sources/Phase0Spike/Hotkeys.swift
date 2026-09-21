import Carbon.HIToolbox
import AppKit

/// Globalne skróty przez Carbon RegisterEventHotKey: działają, gdy frontmost jest inna apka
/// (np. FCP), i NIE wymagają uprawnień Accessibility ani Input Monitoring.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var installed = false

    func register(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        installHandlerOnce()
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4D444B31), id: id) // 'MDK1'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
        Log.write("hotkey #\(id) keyCode=\(keyCode) mods=\(modifiers) -> status \(status) (\(status == noErr ? "zarejestrowany" : "BŁĄD"))")
        refs.append(ref)
    }

    fileprivate func fire(_ id: UInt32) {
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        Log.write("HOTKEY #\(id) odpalony; frontmost = \(front)")
        handlers[id]?()
    }

    private func installHandlerOnce() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotkeyCenter.shared.fire(id) } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
