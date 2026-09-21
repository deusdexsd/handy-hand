import AppKit
import SwiftUI
import Carbon.HIToolbox
import DockCore

@MainActor
final class SpikeModel: ObservableObject {
    @Published var log: [String] = []
    @Published var mode: NotchPanelController.Mode = .hover
    @Published var variant: DragVariant = .fileURL
    @Published var pasteKind: PasteKind = .xmlLower
    @Published var selectedIndex = 0
    @Published var screenNote = ""
    var selected: ProbeAsset { TestMedia.assets[selectedIndex] }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = SpikeModel()
    var controller: NotchPanelController!
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.sink = { [model] line in Task { @MainActor in model.log.append(line) } }
        Log.write("=== MidniteDock Faza 0 start ===")
        do { try TestMedia.ensure() } catch { Log.write("BŁĄD generowania mediów: \(error)") }
        logScreens()

        let tiles = TestMedia.assets.enumerated().map { idx, a in
            DragTileView(asset: a, variant: { [model] in model.variant }, onSelect: { [model] _ in model.selectedIndex = idx })
        }
        controller = NotchPanelController(tiles: tiles)
        controller.show()
        model.screenNote = controller.lastScreenNote

        registerHotkeys()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MidniteDock · Faza 0 (kod dowodowy)"
        window.contentView = NSHostingView(rootView: SpikeView(model: model, delegate: self))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func logScreens() {
        for s in NSScreen.screens {
            let m = NotchPanelController.metrics(s)
            Log.write("EKRAN \(s.localizedName): frame=\(s.frame) safeTop=\(s.safeAreaInsets.top) auxL=\(s.auxiliaryTopLeftArea.map { "\($0)" } ?? "nil") auxR=\(s.auxiliaryTopRightArea.map { "\($0)" } ?? "nil") notch=\(m.hasNotch) scale=\(s.backingScaleFactor)")
        }
    }

    func registerHotkeys() {
        let mods = cmdKey | optionKey | controlKey
        let hk = HotkeyCenter.shared
        hk.register(id: 1, keyCode: kVK_ANSI_1, modifiers: mods) { [self] in
            Actions.putOnPasteboard(model.selected, kind: model.pasteKind)
        }
        hk.register(id: 2, keyCode: kVK_ANSI_2, modifiers: mods) { [self] in
            let files = Actions.writeFCPXMLFiles(); _ = files
            let single = Actions.outDir.appendingPathComponent("hotkey-\(model.selected.name).fcpxml")
            try? FCPXMLBuilder.eventImport(eventName: "MidniteDock Probe", assets: [model.selected]).write(to: single, atomically: true, encoding: .utf8)
            Actions.importIntoFCP(single)
        }
        hk.register(id: 3, keyCode: kVK_ANSI_3, modifiers: mods) { [self] in
            model.selectedIndex = (model.selectedIndex + 1) % TestMedia.assets.count
            Log.write("wybrany element -> \(model.selected.name)")
        }
        for (id, key, v) in [(5, kVK_ANSI_5, DragVariant.fileURL), (6, kVK_ANSI_6, .promise), (7, kVK_ANSI_7, .both)] {
            hk.register(id: UInt32(id), keyCode: key, modifiers: mods) { [self] in
                model.variant = v
                Log.write("wariant dragu -> \(v.rawValue)")
            }
        }
        for (id, key, k) in [(8, kVK_ANSI_8, PasteKind.fileURL), (9, kVK_ANSI_9, .xmlLower), (10, kVK_ANSI_0, .all)] {
            hk.register(id: UInt32(id), keyCode: key, modifiers: mods) { [self] in
                model.pasteKind = k
                Log.write("rodzaj schowka -> \(k.rawValue)")
            }
        }
        hk.register(id: 4, keyCode: kVK_ANSI_4, modifiers: mods) { [self] in
            model.mode = model.mode == .pinned ? .hover : .pinned
            controller.mode = model.mode
        }
    }
}

struct SpikeView: View {
    @ObservedObject var model: SpikeModel
    let delegate: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("1–2 · Panel przy notchu i tryby") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Tryb", selection: $model.mode) {
                        ForEach(NotchPanelController.Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.mode) { _, new in delegate.controller.mode = new }
                    HStack {
                        Button("Dowód z-order (panel vs FCP)") { Log.write("Z-ORDER:\n" + WindowProbe.report()) }
                        Button("Zrzut ekranów") { delegate.logScreens(); model.screenNote = delegate.controller.lastScreenNote }
                    }
                    Text("Pozycja: \(model.screenNote)").font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }
            GroupBox("3 · Drag z panelu do FCP") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Wariant", selection: $model.variant) { ForEach(DragVariant.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    Text("Kafle są w panelu pod notchem (najedź / tryb Przypięty). Wybrany: \(model.selected.name)")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }
            GroupBox("4 · FCPXML (import zdarzenia / compound)") {
                HStack {
                    Button("Zapisz pliki FCPXML") { Actions.writeFCPXMLFiles() }
                    Button("Importuj: zdarzenie") { Actions.importIntoFCP(Actions.writeFCPXMLFiles().event) }
                    Button("Importuj: compound") { Actions.importIntoFCP(Actions.writeFCPXMLFiles().compound) }
                }.padding(6)
            }
            GroupBox("5 · Hotkeye ⌃⌥⌘ + 1…4 i schowek") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1 = wybrany → schowek · 2 = wybrany → import FCPXML · 3 = następny element · 4 = przypnij/odepnij")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Schowek", selection: $model.pasteKind) { ForEach(PasteKind.allCases) { Text($0.rawValue).tag($0) } }
                    HStack {
                        Button("Wrzuć wybrany na schowek") { Actions.putOnPasteboard(model.selected, kind: model.pasteKind) }
                        Button("Zrzuć schowek (np. po ⌘C w FCP)") { Actions.dumpPasteboard() }
                    }
                }.padding(6)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.log.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled).id("end")
                }
                .background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: model.log.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
        }.padding(16)
    }
}
