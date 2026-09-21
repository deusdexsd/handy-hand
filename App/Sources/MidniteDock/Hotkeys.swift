import Carbon.HIToolbox
import AppKit
import DockCore

/// Globalny skrót przez Carbon RegisterEventHotKey: działa, gdy na wierzchu jest inna aplikacja (np. FCP),
/// i nie wymaga żadnych uprawnień (Accessibility / Input Monitoring).
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    private var handler: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var installed = false
    private(set) var lastStatus: OSStatus = noErr

    /// Rejestruje (albo zastępuje) skrót; nil = wyłączony. Zwraca false, gdy system odmówił (np. skrót zajęty).
    @discardableResult
    func set(_ spec: HotKeySpec?, handler: @escaping () -> Void) -> Bool {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        self.handler = handler
        guard let spec else { lastStatus = noErr; return true }
        installHandlerOnce()
        var r: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4C415031), id: 1)      // 'LAP1'
        lastStatus = RegisterEventHotKey(spec.keyCode, spec.modifiers, id, GetApplicationEventTarget(), 0, &r)
        if lastStatus == noErr { ref = r }
        return lastStatus == noErr
    }

    fileprivate func fire() { handler?() }

    private func installHandlerOnce() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotkeyCenter.shared.fire() } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

enum HotKeyText {
    /// „⌃⌥⌘L” z kodu klawisza i modyfikatorów.
    static func string(_ s: HotKeySpec) -> String {
        var t = ""
        if s.modifiers & HotKeySpec.control != 0 { t += "⌃" }
        if s.modifiers & HotKeySpec.option != 0 { t += "⌥" }
        if s.modifiers & HotKeySpec.shift != 0 { t += "⇧" }
        if s.modifiers & HotKeySpec.cmd != 0 { t += "⌘" }
        return t + keyName(s.keyCode)
    }

    static func carbon(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.control) { m |= HotKeySpec.control }
        if f.contains(.option) { m |= HotKeySpec.option }
        if f.contains(.shift) { m |= HotKeySpec.shift }
        if f.contains(.command) { m |= HotKeySpec.cmd }
        return m
    }

    private static func keyName(_ code: UInt32) -> String {
        let special: [UInt32: String] = [49: "Spacja", 36: "Enter", 48: "Tab", 51: "⌫", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                          122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let n = special[code] { return n }
        let letters: [UInt32: String] = [0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
                                          18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0", 27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`"]
        return letters[code] ?? "klawisz \(code)"
    }
}
