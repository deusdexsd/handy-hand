import AppKit
import SwiftUI
import DockCore
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = LibraryStore()
    var controller: PanelController!
    var statusItem: NSStatusItem!
    private var iconWatch: AnyCancellable?

    private func applyStatusIcon(_ icon: MenuBarIcon? = nil) {
        let ic = icon ?? store.settings.menuBarIcon
        if let sym = ic.symbol {
            statusItem.button?.image = NSImage(systemSymbolName: sym, accessibilityDescription: AppInfo.name)
        } else {
            // HA / HA jedno pod drugim: napis rysowany jako obraz-szablon (dopasowuje się do jasnego/ciemnego paska menu).
            let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .heavy), .foregroundColor: NSColor.black, .kern: 0.4]
                let s = NSAttributedString(string: "HA", attributes: attrs); let w = s.size().width
                s.draw(at: NSPoint(x: (rect.width - w) / 2, y: 9)); s.draw(at: NSPoint(x: (rect.width - w) / 2, y: 0)); return true
            }
            statusItem.button?.image = img
        }
        statusItem.button?.image?.isTemplate = true
    }
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
        if ProcessInfo.processInfo.environment["MIDNITEDOCK_LANG"] == "en" { store.data.settings.language = .en }   // podgląd wersji angielskiej (dev)
        installEditMenu()
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
        applyStatusIcon()
        iconWatch = store.$data.map(\.settings.menuBarIcon).removeDuplicates().sink { [weak self] icon in self?.applyStatusIcon(icon) }
        // Lewy klik na ikonie otwiera Ustawienia, prawy pokazuje menu (Tryb panelu, Zakończ…).
        let m = NSMenu(); m.delegate = self; statusMenu = m
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private var statusMenu: NSMenu?

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if let w = settingsWindow, w.isVisible { w.close() }      // drugi lewy klik zamyka Ustawienia
        else { showSettings() }
    }

    func applicationWillTerminate(_ n: Notification) { store.flush() }

    /// Menu główne z pozycjami „Edycja": bez niego pola tekstowe (też w oknie Ustawień) nie reagują na ⌘X/⌘C/⌘V/⌘A/⌘Z.
    /// Apka jest bez ikony w Docku, więc menu nie jest widoczne — liczą się tylko skróty klawiszowe.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); appItem.submenu = NSMenu(); main.addItem(appItem)
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: L("Edycja", "Edit"))
        edit.addItem(withTitle: L("Cofnij", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L("Ponów", "Redo"), action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Wytnij", "Cut"), action: Selector(("cut:")), keyEquivalent: "x")
        edit.addItem(withTitle: L("Kopiuj", "Copy"), action: Selector(("copy:")), keyEquivalent: "c")
        edit.addItem(withTitle: L("Wklej", "Paste"), action: Selector(("paste:")), keyEquivalent: "v")
        edit.addItem(withTitle: L("Zaznacz wszystko", "Select All"), action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let ver = NSMenuItem(title: "\(AppInfo.name) · \(L("wersja", "version")) \(AppInfo.build)", action: nil, keyEquivalent: ""); ver.isEnabled = false
        menu.addItem(ver); menu.addItem(.separator())
        menu.addItem(ClosureMenuItem((controller.expanded ? L("Ukryj panel", "Hide panel") : L("Pokaż panel", "Show panel")) + (store.settings.toggleHotkey.map { "  (\(HotKeyText.string($0)))" } ?? "")) { [weak self] in self?.controller.toggleVisible() })
        let modes = NSMenuItem(title: L("Tryb panelu", "Panel mode"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for mode in PanelMode.allCases { sub.addItem(ClosureMenuItem(mode.label, checked: store.settings.mode == mode) { [weak self] in self?.store.settings.mode = mode }) }
        modes.submenu = sub; menu.addItem(modes)
        menu.addItem(ClosureMenuItem(L("Odśwież foldery", "Refresh folders")) { [weak self] in self?.store.reindexAll() })
        menu.addItem(ClosureMenuItem(L("Otwieraj przy logowaniu", "Open at login"), checked: LoginItem.isOn) {
            if let err = LoginItem.set(!LoginItem.isOn) {
                let a = NSAlert(); a.messageText = L("Nie udało się zmienić otwierania przy logowaniu", "Couldn\u{27}t change open-at-login"); a.informativeText = err; a.runModal()
            }
        })
        menu.addItem(.separator())
        let s = ClosureMenuItem(L("Ustawienia…", "Settings…")) { [weak self] in self?.showSettings() }; s.keyEquivalent = ","
        menu.addItem(s)
        menu.addItem(.separator())
        let q = NSMenuItem(title: L("Zakończ \(AppInfo.name)", "Quit \(AppInfo.name)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(q)
    }

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 520), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = L("Ustawienia", "Settings"); w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: store))
            settingsWindow = w
                        if let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
                // Na środku ekranu, ale trochę wyżej niż środek — klik w ikonę pasku menu otwiera je i tak.
                w.setFrameOrigin(NSPoint(x: f.midX - w.frame.width / 2, y: f.midY - w.frame.height / 2 + f.height * 0.08))
            } else { w.center() }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
