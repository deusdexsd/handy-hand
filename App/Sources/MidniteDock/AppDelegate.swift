import AppKit
import SwiftUI
import DockCore
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = LibraryStore()
    var controller: PanelController!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    private var hotkeyWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ n: Notification) {
        if let dev = ProcessInfo.processInfo.environment["MIDNITEDOCK_DEV_MEDIA"], store.sources.isEmpty {
            let d = URL(fileURLWithPath: dev)
            store.addSource(url: d.appendingPathComponent("SFX"), kind: .folder)
            store.addSource(url: d.appendingPathComponent("SFX Backup"), kind: .folder)
            store.addSource(url: d.appendingPathComponent("B-roll"), kind: .folder)
            store.addSource(url: d.appendingPathComponent("Zdjecia"), kind: .folder)
            store.addSource(url: d.appendingPathComponent("DevLibrary.fcpbundle"), kind: .fcpLibrary)
        }
        store.openSettings = { [weak self] in self?.showSettings() }
        controller = PanelController(store: store)
        controller.show()

        if let dir = ProcessInfo.processInfo.environment["MIDNITEDOCK_SHOTS"] {
            Task { @MainActor in await SnapshotRunner.run(dir: dir, controller: self.controller, store: self.store, delegate: self) }
        }

        if ProcessInfo.processInfo.environment["MIDNITEDOCK_SELFTEST"] != nil {
            Task { @MainActor in await SelfTest.run(controller: self.controller, store: self.store) }
        }

        // globalny skrót pokaż/ukryj panel (zmiana w Ustawieniach przerejestrowuje go od razu)
        hotkeyWatch = store.$data.map(\.settings.toggleHotkey).removeDuplicates().sink { [weak self] spec in
            let ok = HotkeyCenter.shared.set(spec) { self?.controller.toggleVisible() }
            if ProcessInfo.processInfo.environment["MIDNITEDOCK_SELFTEST"] != nil { print("SELF hotkey: \(spec.map(HotKeyText.string) ?? "wyłączony") zarejestrowany=\(ok) status=\(HotkeyCenter.shared.lastStatus)") }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: AppInfo.name)
        statusItem.button?.image?.isTemplate = true
        let m = NSMenu(); m.delegate = self
        statusItem.menu = m
    }

    func applicationWillTerminate(_ n: Notification) { store.flush() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let ver = NSMenuItem(title: "\(AppInfo.name) · wersja \(AppInfo.build)", action: nil, keyEquivalent: ""); ver.isEnabled = false
        menu.addItem(ver); menu.addItem(.separator())
        menu.addItem(ClosureMenuItem((controller.expanded ? "Ukryj panel" : "Pokaż panel") + (store.settings.toggleHotkey.map { "  (\(HotKeyText.string($0)))" } ?? "")) { [weak self] in self?.controller.toggleVisible() })
        let modes = NSMenuItem(title: "Tryb panelu", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for mode in PanelMode.allCases { sub.addItem(ClosureMenuItem(mode.label, checked: store.settings.mode == mode) { [weak self] in self?.store.settings.mode = mode }) }
        modes.submenu = sub; menu.addItem(modes)
        menu.addItem(ClosureMenuItem("Odśwież foldery") { [weak self] in self?.store.reindexAll() })
        menu.addItem(.separator())
        let s = ClosureMenuItem("Ustawienia…") { [weak self] in self?.showSettings() }; s.keyEquivalent = ","
        menu.addItem(s)
        menu.addItem(.separator())
        let q = NSMenuItem(title: "Zakończ \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(q)
    }

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 520), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Ustawienia"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: store))
            w.center(); settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
