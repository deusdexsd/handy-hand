import AppKit
import SwiftUI
import Combine
import DockCore

enum PanelKey { case space, up, down, left, right, enter, escape, digit(Int, shift: Bool) }

final class DockPanel: NSPanel {
    var onKey: ((PanelKey) -> Bool)?
    var allowsKey = true
    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false; backgroundColor = .clear; hasShadow = true; isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// Klawisze przechwytujemy przed SwiftUI (ScrollView sam by je zjadł), ale nie wtedy, gdy trwa pisanie w polu tekstowym.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !(firstResponder is NSTextView),
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let k = Self.key(event), onKey?(k) == true { return }
        super.sendEvent(event)
    }

    static func key(_ e: NSEvent) -> PanelKey? {
        switch e.keyCode {
        case 49: return .space
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        case 36, 76: return .enter
        case 53: return .escape
        default:
            let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6]
            return digits[e.keyCode].map { .digit($0, shift: e.modifierFlags.contains(.shift)) }
        }
    }
}

/// Uchwyt: wirtualny notch (czarna wysepka) albo cienka pigułka pod prawdziwym notchem.
struct HandleView: View {
    let showsCap: Bool
    let atBottom: Bool
    let expanded: Bool
    let isPlaying: Bool
    @ObservedObject var state: PanelState
    let glowColor: Color
    var realNotch = false
    var anchorSize = CGSize(width: 200, height: 32)      // rozmiar notcha / wysepki w środku przezroczystego okna
    var side = 0                                         // -1 lewa krawędź, 1 prawa, 0 góra
    var effect: NotchEffect = .glow

    var body: some View {
        let glow = expanded || effect != .glow ? 0 : state.glow
        ZStack(alignment: .top) {
            if realNotch {
                // Prawdziwy notch: w spoczynku nic. Poświata wychodzi zza czarnego kształtu równego notchowi
                // (nad fizycznym notchem nie ma pikseli, więc sam kształt jest niewidoczny).
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                    .fill(Color.black).frame(width: anchorSize.width - 2, height: anchorSize.height)
                    .shadow(color: glowColor.opacity(0.95 * glow), radius: 8 + 22 * glow)
                    .shadow(color: glowColor.opacity(0.65 * glow), radius: 3 + 6 * glow)
                    .animation(.easeOut(duration: 0.18), value: glow)
            } else if showsCap {
                let shape = UnevenRoundedRectangle(topLeadingRadius: side == 1 ? 12 : 0, bottomLeadingRadius: side == 1 || side == 0 ? 12 : 0,
                                                   bottomTrailingRadius: side == -1 || side == 0 ? 12 : 0, topTrailingRadius: side == -1 ? 12 : 0, style: .continuous)
                ZStack {
                    shape.fill(Color.black)
                    RadialGradient(colors: [glowColor.opacity(0.55 * glow), .clear], center: side == -1 ? .leading : (side == 1 ? .trailing : .bottom), startRadius: 0, endRadius: 110).clipShape(shape)
                    shape.strokeBorder(glowColor.opacity(0.8 * glow), lineWidth: 1)
                    Image(systemName: "pawprint.fill").font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(expanded || isPlaying ? 0.55 : 0.22 + 0.5 * glow))
                }
                .frame(width: anchorSize.width, height: anchorSize.height)
                .animation(.easeOut(duration: 0.16), value: glow)
            } else {
                Capsule().fill(Color.white.opacity(expanded ? 0 : 0.55)).frame(height: 4).padding(.horizontal, 20)
            }
            if effect == .paw && !expanded && side == 0 && (realNotch || showsCap) {
                CreatureLayer(notch: anchorSize, state: state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

@MainActor
final class PanelController: NSObject {
    let store: LibraryStore
    let state = PanelState()
    private let handle = DockPanel(size: CGSize(width: 200, height: 32))
    private let body: DockPanel
    var bodyPanel: DockPanel { body }
    var bodyContentView: NSView? { body.contentView }
    private var hovering = false
    private var frontmostWatched = false
    private var collapseWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()
    private(set) var expanded = false

    init(store: LibraryStore) {
        self.store = store
        body = DockPanel(size: CGSize(width: store.settings.expandedWidth, height: store.settings.expandedHeight))
        super.init()
        handle.ignoresMouseEvents = true
        handle.hasShadow = false
        body.contentView = NSHostingView(rootView: DockRootView(store: store, panel: state))
        body.onKey = { [weak self] k in self?.handleKey(k) ?? false }
        rebuildHandle()

        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in MainActor.assumeIsolated { self?.updateHover() } }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in MainActor.assumeIsolated { self?.updateHover() }; return e }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        frontmostWatched = isWatched(NSWorkspace.shared.frontmostApplication)

        // Zmiany ustawień (tryb, pozycja, rozmiar, wirtualny notch) przeliczają układ na żywo.
        store.$data.map(\.settings).removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.settingsChanged() } }.store(in: &bag)
        store.$dragging.removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.apply(animated: true) } }.store(in: &bag)
        store.$prompt.sink { [weak self] p in DispatchQueue.main.async { if p != nil { self?.body.makeKey() }; self?.apply(animated: true) } }.store(in: &bag)
        store.$notice.sink { [weak self] _ in DispatchQueue.main.async { self?.apply(animated: true) } }.store(in: &bag)
        store.previewer.$isPlaying.removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildHandle() } }.store(in: &bag)
    }

    // MARK: geometria
    private func metrics() -> ScreenMetrics? {
        let all = NSScreen.screens.map { s in ScreenMetrics(frame: s.frame, visibleFrame: s.visibleFrame, safeAreaTop: s.safeAreaInsets.top,
                                                            auxiliaryTopLeft: s.auxiliaryTopLeftArea, auxiliaryTopRight: s.auxiliaryTopRightArea) }
        return NotchGeometry.preferredScreen(all, mouse: NSEvent.mouseLocation)
    }

    private func frames() -> (handle: CGRect, body: CGRect, cap: Bool, bottom: Bool, glowRect: CGRect, realNotch: Bool)? {
        guard let m = metrics() else { return nil }
        let s = store.settings
        let bodySize = CGSize(width: s.expandedWidth, height: s.expandedHeight)
        if s.placement.isSide {      // uchwyt na lewej/prawej krawędzi, panel obok niego
            let sf = NotchGeometry.sideFrames(m, placement: s.placement, position: s.sidePosition, bodySize: bodySize)
            return (sf.handle, sf.body, true, false, sf.handle, false)
        }
        let realNotchStyle = m.hasNotch                                           // prawdziwy notch: bez wirtualnej wysepki i bez pigułki
        let l = NotchGeometry.layout(m, placement: .topCenter, mode: realNotchStyle ? .never : s.virtualNotch, windowWidth: bodySize.width)
        var hw = l.capSize.width, hh = l.capSize.height
        if !l.showsCap { hw = l.capSize.width + 40; hh = 8 }
        var bodyFrame = NotchGeometry.windowFrame(size: bodySize, layout: l, on: m)
        let hx = max(m.frame.minX, min(l.horizontalAnchor - hw / 2, m.frame.maxX - hw))
        if realNotchStyle, let n = NotchGeometry.notchRect(m) {
            bodyFrame.origin.y = n.minY - bodySize.height                          // panel wisi tuż pod notchem
            return (NotchGeometry.windowAround(n, side: 90, below: 150, screen: m.frame), bodyFrame, false, false, n, true)
        }
        let anchor: CGRect
        if l.showsCap { anchor = CGRect(x: hx, y: m.frame.maxY - hh, width: hw, height: hh); bodyFrame.origin.y = anchor.minY - 6 - bodySize.height }
        else { let top = l.windowTopY ?? m.frame.maxY; anchor = CGRect(x: hx, y: top - hh, width: hw, height: hh); bodyFrame.origin.y = top - bodySize.height }
        // Przezroczyste okno wokół wysepki na poświatę i łapkę (klikanie przechodzi przez nie).
        let win = l.showsCap ? NotchGeometry.windowAround(anchor, side: 90, below: 150, screen: m.frame) : anchor
        return (win, bodyFrame, l.showsCap, false, anchor, false)
    }

    /// Na bocznych krawędziach łapka nie działa (tylko poświata).
    private var activeEffect: NotchEffect {
        let e = store.settings.notchEffect
        return store.settings.placement.isSide && e == .paw ? .glow : e
    }

    private func rebuildHandle() {
        guard let f = frames() else { return }
        handle.contentView = NSHostingView(rootView: HandleView(showsCap: f.cap, atBottom: f.bottom, expanded: expanded, isPlaying: store.previewer.isPlaying, state: state, glowColor: Self.glowColor(store.settings.glowColor), realNotch: f.realNotch, anchorSize: f.glowRect.size, side: store.settings.placement == .leftMiddle ? -1 : (store.settings.placement == .rightMiddle ? 1 : 0), effect: activeEffect))
        handle.setFrame(f.handle, display: true)
        state.atBottom = f.bottom
    }

    func show() { handle.orderFrontRegardless(); apply(animated: false) }
    func toggleVisible() { if expanded { forceCollapse() } else { pinnedOnce = true; apply(animated: true) } }
    private var pinnedOnce = false
    private func forceCollapse() { pinnedOnce = false; hovering = false; apply(animated: true) }

    // MARK: tryby
    private func shouldExpand() -> Bool {
        if pinnedOnce { return true }
        switch store.settings.mode {
        case .pinned: return true
        case .followApp: return frontmostWatched || hovering || store.holdsPanelOpen
        case .hover: return hovering || store.holdsPanelOpen
        }
    }

    private var handleKey = ""
    private func settingsChanged() {
        let s = store.settings
        let key = "\(s.placement.rawValue)|\(s.virtualNotch.rawValue)|\(s.glowColor.rawValue)|\(s.notchEffect.rawValue)"
        if key != handleKey { handleKey = key; rebuildHandle() }      // rozmiar panelu zmienia się w trakcie rozciągania: uchwytu nie przebudowujemy
        apply(animated: false)
    }

    func apply(animated: Bool) {
        let want = shouldExpand()
        guard let f = frames() else { return }
        handle.setFrame(f.handle, display: true)
        body.setFrame(f.body, display: true)
        state.atBottom = f.bottom
        if want != expanded {
            expanded = want
            hideWork?.cancel()
            if want {
                body.orderFrontRegardless()
                state.expanded = true
            } else {
                state.expanded = false
                let w = DispatchWorkItem { [weak self] in
                    guard let self, !self.expanded else { return }
                    self.body.orderOut(nil)
                }
                hideWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0), execute: w)
            }
            rebuildHandle()
        }
    }

    // MARK: klawiatura
    private func handleKey(_ k: PanelKey) -> Bool {
        guard store.prompt == nil, store.notice == nil else { return false }     // pytanie na wierzchu: klawisze dla niego
        switch k {
        case .space:
            // Jak Quick Look w Finderze: spacja na obrazie/wideo powiększa podgląd (i zamyka go), na dźwięku odtwarza.
            if let p = store.primary, p.kind != .audio { store.data.settings.bigMediaPreview.toggle(); return true }
            store.previewer.toggle(); return store.previewer.item != nil
        case .digit(let n, let shift): return store.quickKey(n, shift: shift)
        case .up: store.moveSelection(.up); return true
        case .down: store.moveSelection(.down); return true
        case .left: store.moveSelection(.left); return true
        case .right: store.moveSelection(.right); return true
        case .enter: store.renameSelected(); return store.selection.count == 1     // jak w Finderze: Enter = zmiana nazwy
        case .escape: return false
        }
    }

    func debugKey(_ k: PanelKey) -> Bool { handleKey(k) }

    /// Strefa reakcji: uchwyt razem z krawędzią ekranu za nim; po rozwinięciu także cały panel.
    private func hotZone() -> NSRect {
        guard let f = frames(), let m = metrics() else { return .zero }
        var z = f.glowRect.insetBy(dx: -12, dy: -8)
        switch store.settings.placement {      // strefa sięga do krawędzi ekranu, przy której siedzi uchwyt
        case .leftMiddle: z.size.width += z.minX - m.frame.minX; z.origin.x = m.frame.minX
        case .rightMiddle: z.size.width += max(0, m.frame.maxX - z.maxX)
        case .topCenter: z.size.height += max(0, m.frame.maxY - z.maxY)
        }
        if expanded { z = z.union(f.body.insetBy(dx: -10, dy: -10)) }
        return z
    }

    func debugSetHovering(_ on: Bool) {
        if on { hovering = true; collapseWork?.cancel(); collapseWork = nil; apply(animated: true) }
        else { hovering = false; pinnedOnce = false; apply(animated: true) }
    }

    static func glowColor(_ g: GlowChoice) -> Color {
        switch g { case .violet: Color(red: 0.72, green: 0.48, blue: 1.0); case .teal: Color(red: 0.36, green: 0.88, blue: 0.82); case .blue: Color(red: 0.36, green: 0.55, blue: 1.0) }
    }

    var debugMouse: CGPoint?
    func debugUpdateEffect() { updateGlow() }
    func debugGlowRect() -> CGRect? { frames()?.glowRect }
    func handleSnapshot() -> NSImage? {
        guard let v = handle.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep); let img = NSImage(size: v.bounds.size); img.addRepresentation(rep); return img
    }

    /// Efekt przy notchu: poświata albo łapka reagują na odległość kursora (duże pole: ok. 140 pt od notcha).
    private func updateGlow() {
        let effect = activeEffect
        guard effect != .none, !expanded, let f = frames() else { resetEffect(); return }
        let h = f.glowRect
        let p = debugMouse ?? NSEvent.mouseLocation
        let dx = max(h.minX - p.x, 0, p.x - h.maxX), dy = max(h.minY - p.y, 0, p.y - h.maxY)
        let g = NotchGlow.intensity(distance: hypot(dx, dy), radius: effect == .paw ? 105 : 140)
        switch effect {
        case .glow: if abs(g - state.glow) > 0.02 { state.glow = g }
        case .paw:
            guard g > 0.02 else { if state.tipY > -30 { retractArm() }; return }
            // dłoń celuje w kursor: kierunek z barku, zasięg rośnie, im bliżej jest kursor
            let vx = p.x - h.midX, vy = max(14, h.minY - p.y)
            let dist = hypot(vx, vy), reach = min(h.width * 0.42, max(h.width * 0.16, dist * 0.7)) * (0.55 + 0.45 * g)
            state.armActive = true
            state.shoulderX = max(-45, min(45, vx * 0.1))
            state.tipX = vx / dist * reach; state.tipY = vy / dist * reach
        case .none: break
        }
    }

    private func retractArm() {
        state.tipX = 0; state.tipY = -60; state.shoulderX = 0
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if state.tipY < -30 { state.armActive = false; state.sim.last = nil }      // schowana: zatrzymujemy symulację
        }
    }

    private func resetEffect() {
        if state.glow != 0 { state.glow = 0 }
        if state.tipY > -30 { retractArm() }
    }


    private func updateHover() {
        updateGlow()
        let inside = hotZone().contains(NSEvent.mouseLocation)
        if inside {
            collapseWork?.cancel(); collapseWork = nil
            if !hovering { hovering = true; apply(animated: true) }
        } else if hovering, collapseWork == nil {
            let w = DispatchWorkItem { [weak self] in self?.collapseWork = nil; self?.hovering = false; self?.pinnedOnce = false; self?.apply(animated: true) }
            collapseWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
        }
    }

    private func isWatched(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return store.settings.watchedBundleIDs.contains(id)
    }

    @objc private func appActivated(_ n: Notification) {
        frontmostWatched = isWatched(n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        apply(animated: true)
    }

    @objc private func screensChanged() { rebuildHandle(); apply(animated: false) }
}

// MARK: sprawdzian wizualny bez uprawnień do nagrywania ekranu (tylko z MIDNITEDOCK_SHOTS)
extension PanelController {
    func snapshot(dark: Bool) -> NSImage? {
        guard let v = bodyContentView else { return nil }
        bodyPanel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        v.appearance = bodyPanel.appearance
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        let img = NSImage(size: v.bounds.size)
        img.lockFocus()
        (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()   // atrapa materiału tła
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: v.bounds.size), xRadius: 16, yRadius: 16).fill()
        rep.draw(in: NSRect(origin: .zero, size: v.bounds.size))
        img.unlockFocus()
        return img
    }
}

@MainActor
enum SnapshotRunner {
    static func save(_ img: NSImage?, _ path: String) {
        guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    static func run(dir: String, controller: PanelController, store: LibraryStore, delegate: AppDelegate) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        func shot(_ name: String, dark: Bool = true) async { await wait(1.2); save(controller.snapshot(dark: dark), "\(dir)/\(name).png") }
        func viewShot<V: View>(_ name: String, _ v: V, _ w: CGFloat, _ h: CGFloat) async {
            let hv = NSHostingView(rootView: v.frame(width: w, height: h).environment(\.colorScheme, .dark))
            hv.frame = NSRect(x: 0, y: 0, width: w, height: h)
            let win = NSWindow(contentRect: hv.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.appearance = NSAppearance(named: .darkAqua); win.contentView = hv; win.orderFrontRegardless()
            await wait(1.2); hv.layoutSubtreeIfNeeded()
            let rep = hv.bitmapImageRepForCachingDisplay(in: hv.bounds)!; hv.cacheDisplay(in: hv.bounds, to: rep)
            let img = NSImage(size: hv.bounds.size); img.lockFocus(); NSColor(white: 0.16, alpha: 1).setFill(); NSRect(origin: .zero, size: hv.bounds.size).fill()
            rep.draw(in: NSRect(origin: .zero, size: hv.bounds.size)); img.unlockFocus()
            save(img, "\(dir)/\(name).png"); win.orderOut(nil)
        }
        store.settings.mode = .pinned
        await wait(3)
        await shot("01-grid-dark")
        await shot("02-grid-light", dark: false)
        if let it = store.visible.first(where: { $0.name == "riser_tension" }) { store.click(it, command: false, shift: false); store.previewer.pause(); store.previewer.seek(to: 0.4) }
        await shot("03-selected-dark")
        if let r = store.org.durationRanges.first(where: { $0.kind == .audio && $0.maxSeconds == 1 }) { store.select(category: .duration(r.id)) }
        await shot("04-smart-short-dark")
        store.select(category: .klass(.image)); await shot("04b-images-dark")
        store.select(category: .klass(.music)); await shot("04c-music-dark")
        if let img = store.visible.first { _ = img }
        store.select(category: .klass(.image)); if let i0 = store.visible.first { store.click(i0, command: false, shift: false) }
        await shot("04d-image-selected-dark")
        if let it0 = store.visible.first { store.beginRename(it0) }
        await shot("04f-rename-prompt-dark"); store.prompt = nil
        store.select(category: .klass(.image)); store.config.viewMode = .list
        if let i1 = store.visible.first { store.click(i1, command: false, shift: false) }
        await shot("04h-images-list-small-preview-dark")
        store.data.settings.bigMediaPreview = true
        await shot("04j-images-list-big-preview-dark")
        store.data.settings.bigMediaPreview = false
        store.select(category: .klass(.video)); store.config.viewMode = .list
        if let v1 = store.visible.first { store.click(v1, command: false, shift: false); store.previewer.pause() }
        await shot("04i-video-list-inline-preview-dark")
        store.select(category: .all)
        if let i2 = store.visible.first { store.click(i2, command: false, shift: false); store.previewer.pause() }
        store.config.viewMode = .grid
        store.select(category: .klass(.sfx))
        await shot("04g-sfx-scale-dark")
        store.select(category: .all)
        store.select(category: .all); store.config.viewMode = .list
        await shot("05-list-dark")
        store.config.viewMode = .grid; store.settings.categoryLayout = .chips
        await shot("06-chips-dark")
        store.search = "whoosh"
        await shot("06b-dupes-dark")
        store.search = ""
        store.settings.categoryLayout = .sidebar; store.settings.sourceTints = true
        await shot("07-tints-dark")
        store.settings.sourceTints = false; store.search = "zzzz"
        await shot("08-no-results-dark")
        store.search = ""
        // Diagnostyka odtwarzania (wyciszone): czas ma płynąć po kliknięciu i wrócić na 0 po końcu.
        if let it = store.visible.first(where: { $0.name == "click_double" }) {
            store.click(it, command: false, shift: false)
            await wait(0.3); let t1 = store.previewer.time; let playing = store.previewer.isPlaying
            await wait(1.0)
            print("DIAG play: isPlaying po 0.3 s = \(playing), time = \(t1); po zakończeniu isPlaying = \(store.previewer.isPlaying), time = \(store.previewer.time)")
        }
        // Uchwyt (wirtualny notch) i ustawienia
        do {
            let hv = NSHostingView(rootView: HandleView(showsCap: true, atBottom: false, expanded: false, isPlaying: false, state: { let st = PanelState(); st.glow = 0.9; return st }(), glowColor: PanelController.glowColor(.violet)).frame(width: 200, height: 32))
            hv.frame = NSRect(x: 0, y: 0, width: 200, height: 32)
            let rep = hv.bitmapImageRepForCachingDisplay(in: hv.bounds)!; hv.cacheDisplay(in: hv.bounds, to: rep)
            let img = NSImage(size: hv.bounds.size); img.addRepresentation(rep); save(img, "\(dir)/09-handle.png")
        }
        func settingsShot(_ name: String, _ v: some View) async {
            let hv = NSHostingView(rootView: v.frame(width: 600, height: 470).environment(\.colorScheme, .dark))
            hv.frame = NSRect(x: 0, y: 0, width: 600, height: 470)
            let w = NSWindow(contentRect: hv.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w.appearance = NSAppearance(named: .darkAqua); w.contentView = hv; w.orderFrontRegardless()
            await wait(0.8)
            hv.layoutSubtreeIfNeeded()
            let rep = hv.bitmapImageRepForCachingDisplay(in: hv.bounds)!; hv.cacheDisplay(in: hv.bounds, to: rep)
            let img = NSImage(size: hv.bounds.size); img.lockFocus(); NSColor(white: 0.16, alpha: 1).setFill(); NSRect(origin: .zero, size: hv.bounds.size).fill()
            rep.draw(in: NSRect(origin: .zero, size: hv.bounds.size)); img.unlockFocus()
            save(img, "\(dir)/\(name).png"); w.orderOut(nil)
        }
        await viewShot("09b-handle-real-notch", HandleView(showsCap: false, atBottom: false, expanded: false, isPlaying: false, state: { let st = PanelState(); st.glow = 0.9; return st }(), glowColor: PanelController.glowColor(.violet), realNotch: true, anchorSize: CGSize(width: 220, height: 38)).frame(width: 252, height: 54).background(Color(white: 0.55)), 252, 54)
        for (name, tx, ty, sh, jump) in [("paw-settled", 30.0, 80.0, 4.0, false), ("paw-swing", 55.0, 62.0, 8.0, true), ("paw-left", -60.0, 60.0, -8.0, false)] {
            let st = PanelState(); st.armActive = true; st.tipX = tx; st.tipY = ty; st.shoulderX = sh
            let shoulder = CGPoint(x: 200 + sh, y: 38 - 6)
            st.sim.spring = TipSpring(pos: CGPoint(x: shoulder.x + (jump ? 0 : tx), y: shoulder.y + (jump ? 80 : ty)))
            if jump { for _ in 0..<7 { st.sim.spring.step(dt: 1.0 / 60, target: CGPoint(x: shoulder.x + tx, y: shoulder.y + ty)) } }    // poza „w locie”
            st.sim.last = Date().addingTimeInterval(0.0001)
            await viewShot("09c-\(name)", HandleView(showsCap: false, atBottom: false, expanded: false, isPlaying: false, state: st, glowColor: PanelController.glowColor(.violet), realNotch: true, anchorSize: CGSize(width: 220, height: 38), effect: .paw).frame(width: 400, height: 188).background(Color(white: 0.62)), 400, 188)
        }
        await settingsShot("10-set-general", GeneralTab(store: store))
        await settingsShot("11-set-sources", SourcesTab(store: store))
        await settingsShot("12-set-appearance", AppearanceTab(store: store))
        await settingsShot("13-set-durations", DurationsTab(store: store))
        await settingsShot("14-set-keywords", KeywordsTab(store: store))
        NSApp.terminate(nil)
    }
}

// MARK: autotest logiki panelu (MIDNITEDOCK_SELFTEST): bez myszy i uprawnień
extension PanelController {
    func debugState() -> String {
        let f = frames()
        return "expanded=\(expanded) bodyVisible=\(bodyPanel.isVisible) handle=\(f.map { NSStringFromRect($0.handle) } ?? "-") body=\(f.map { NSStringFromRect($0.body) } ?? "-") level=\(bodyPanel.level.rawValue)"
    }
    func debugHover(_ on: Bool) { debugSetHovering(on) }
}

@MainActor
enum SelfTest {
    static func run(controller: PanelController, store: LibraryStore) async {
        func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        await wait(1.5)
        print("SELF 1 start (tryb hover):        \(controller.debugState())")
        controller.debugHover(true); await wait(0.8)
        print("SELF 2 po najechaniu:             \(controller.debugState())")
        controller.debugHover(false); await wait(0.9)
        print("SELF 3 po odjechaniu (+0.4 s):    \(controller.debugState())")
        store.settings.mode = .pinned; await wait(0.8)
        print("SELF 4 tryb przypięty:            \(controller.debugState())")
        store.settings.mode = .followApp; await wait(0.8)
        print("SELF 5 podążaj (inna apka):       \(controller.debugState())")
        for pl in NotchPlacement.allCases {
            store.settings.placement = pl; store.settings.mode = .pinned; await wait(0.6)
            print("SELF 6 pozycja \(pl.rawValue): \(controller.debugState())")
        }
        store.settings.placement = .topCenter; store.settings.virtualNotch = .never; await wait(0.6)
        print("SELF 7 bez wirtualnego notcha:     \(controller.debugState())")
        // Duplikaty
        await wait(1.5)
        let vis = store.visible
        print("SELF 7b duplikaty: plików=\(store.items.count) widocznych w Wszystko=\(vis.count) zwiniętych=\(store.hiddenDuplicateCount) whoosh_fast kopii=\(store.copies(vis.first { $0.name == "whoosh_fast" }!)) boom_low pozycji=\(vis.filter { $0.name == "boom_low" }.count)")
        if let src = store.sources.first(where: { $0.name == "SFX Backup" }) {
            store.select(category: .source(src.id))
            print("SELF 7c folder 'SFX Backup' widzi własne kopie: \(store.visible.map(\.name).sorted())")
            store.select(category: .all)
        }
        if let wf = vis.first(where: { $0.name == "whoosh_fast" }) {
            store.toggleFavorite([wf.path])
            store.select(category: .favorites)
            print("SELF 7d ulubione grupowo: kategoria Ulubione=\(store.visible.count) (kopie w bazie: \(store.org.favorites.count))")
            store.select(category: .all)
        }
        store.data.settings.hideDuplicates = false; await wait(0.3)
        print("SELF 7e wyłączone zwijanie: widocznych=\(store.visible.count)")
        store.data.settings.hideDuplicates = true
        // Rozciąganie: zmiana rozmiaru w ustawieniach (tak działa przeciąganie krawędzi) przenosi się na okno
        store.settings.placement = .topCenter; store.settings.mode = .pinned; store.settings.virtualNotch = .auto; await wait(0.5)
        store.data.settings.expandedWidth = 900; store.data.settings.expandedHeight = 520; await wait(0.6)
        print("SELF 22 rozmiar 900x520: \(controller.debugState())")
        store.data.settings.expandedWidth = 720; store.data.settings.expandedHeight = 460; await wait(0.4)
        // Typy: SFX / muzyka / wideo / obrazy
        func n(_ c: MediaClass) -> Int { store.select(category: .klass(c)); return store.visible.count }
        print("SELF 11 typy: SFX=\(n(.sfx)) Muzyka=\(n(.music)) Wideo=\(n(.video)) Obrazy=\(n(.image)) (granica SFX = \(Int(store.org.sfxMaxSeconds)) s)")
        store.select(category: .all)
        if let song = store.items.first(where: { $0.name == "theme_calm_music" }) {
            store.setClass(.sfx, for: [song.path])
            print("SELF 12 ręczny typ: theme_calm_music (\(Int(song.duration)) s) -> \(store.mediaClass(song).label); po 'Automatycznie' -> ", terminator: "")
            store.setClass(nil, for: [song.path]); print(store.mediaClass(song).label)
        }
        store.data.org.sfxMaxSeconds = 60
        print("SELF 13 granica 60 s: SFX=\(n(.sfx)) Muzyka=\(n(.music))"); store.data.org.sfxMaxSeconds = 20; store.select(category: .all)
        if let img = store.items.first(where: { $0.kind == .image }) { print("SELF 14 obraz: \(img.name).\(img.ext) \(img.pixelWidth ?? 0)x\(img.pixelHeight ?? 0) duration=\(img.duration)") }
        // Pojedyncze pliki + zmiana nazwy na dysku
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dock-rename-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let f1 = tmp.appendingPathComponent("stary_dzwiek.wav"), f2 = tmp.appendingPathComponent("zajete.wav")
        try? DevMedia.tone(.init(name: "a", seconds: 0.5, shape: "click"), to: f1, seed: 3); try? DevMedia.tone(.init(name: "b", seconds: 0.6, shape: "click"), to: f2, seed: 4)
        store.addFiles([f1, f2]); await wait(2)
        let filesSrc = store.sources.first { $0.kind == .files }
        print("SELF 15 pojedyncze pliki: źródło=\(filesSrc?.name ?? "brak") plików=\(filesSrc?.filePaths?.count ?? 0) w indeksie=\(store.items.filter { $0.sourceID == filesSrc?.id }.count)")
        if let it = store.items.first(where: { $0.name == "stary_dzwiek" }) {
            store.toggleFavorite([it.path]); store.addTag("test", to: [it.path])
            print("SELF 16 kolizja nazwy: \(store.rename(it, to: "zajete") ?? "OK (BŁĄD: powinno odmówić)")")
            print("SELF 17 zły znak:      \(store.rename(it, to: "a/b") ?? "OK (BŁĄD: powinno odmówić)")")
            let err = store.rename(it, to: "nowa_nazwa.wav")
            await wait(0.5)
            let newItem = store.items.first { $0.name == "nowa_nazwa" }
            print("SELF 18 zmiana nazwy: błąd=\(err ?? "brak") plik na dysku: stary istnieje=\(FileManager.default.fileExists(atPath: f1.path)) nowy istnieje=\(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("nowa_nazwa.wav").path)); w bibliotece=\(newItem != nil); ulubione zachowane=\(newItem.map { store.isFavorite($0) } ?? false); tag zachowany=\(newItem.map { store.org.tags[$0.path] ?? [] } ?? []); źródło zaktualizowane=\(store.sources.first { $0.kind == .files }?.filePaths?.contains { $0.hasSuffix("nowa_nazwa.wav") } ?? false)")
            if let ni = newItem { store.removeFromLibrary(ni); print("SELF 19 usunięcie z biblioteki (plik zostaje na dysku): w indeksie=\(store.items.contains { $0.name == "nowa_nazwa" }) na dysku=\(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("nowa_nazwa.wav").path))") }
        }
        if let lib = store.items.first(where: { it in store.sources.first(where: { s in s.id == it.sourceID })?.kind == .fcpLibrary }) {
            print("SELF 20 plik z biblioteki FCP: \(store.rename(lib, to: "cokolwiek") ?? "OK (BŁĄD: powinno odmówić)")")
        }
        let dropDir = FileManager.default.temporaryDirectory.appendingPathComponent("dock-drop-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: dropDir, withIntermediateDirectories: true)
        try? DevMedia.tone(.init(name: "d", seconds: 0.4, shape: "click"), to: dropDir.appendingPathComponent("z_findera.wav"), seed: 8)
        let srcBefore = store.sources.count
        _ = store.addDropped([dropDir]); await wait(2)
        print("SELF 21 upuszczony folder: źródeł \(srcBefore) -> \(store.sources.count), nowy plik widoczny=\(store.items.contains { $0.name == "z_findera" })")
        // Klawiatura, skala waveformu, miniatury, Enter, okno podglądu
        store.settings.mode = .pinned; store.select(category: .klass(.sfx)); await wait(1.0)
        store.sortByNameForTest()
        let vis0 = store.visible
        store.click(vis0[0], command: false, shift: false)
        var seq = [vis0[0].name]
        for k in [PanelKey.right, .right, .down, .down, .up, .left] { _ = controller.debugKey(k); seq.append(store.primary?.name ?? "?") }
        print("SELF 23 strzałki (kolumny=\(store.gridColumns)): \(seq.joined(separator: " → "))")
        let sfxMax = store.visible.map(\.duration).max() ?? 0
        let sample = store.visible.first { $0.duration < 1 }!
        print("SELF 24 skala SFX: najdłuższy=\(String(format: "%.1f", sfxMax)) s, skala kafla=\(String(format: "%.1f", store.waveformScale(for: sample))) s")
        store.select(category: .klass(.music)); await wait(0.5)
        print("SELF 24b skala muzyki: \(String(format: "%.1f", store.waveformScale(for: store.visible[0]))) s (najdłuższa \(String(format: "%.1f", store.visible.map(\.duration).max() ?? 0)) s)")
        store.data.settings.waveformAutoScale = false
        print("SELF 24c skala stała: \(store.waveformScale(for: store.visible[0])) s"); store.data.settings.waveformAutoScale = true
        // .mp4 bez ścieżki wideo: miniatura ma się nie powieść RAZ, a nie w kółko
        let av = FileManager.default.temporaryDirectory.appendingPathComponent("dock-av-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: av, withIntermediateDirectories: true)
        let wavSrc = av.appendingPathComponent("s.wav"), mp4 = av.appendingPathComponent("tylko_dzwiek.mp4")
        try? DevMedia.tone(.init(name: "x", seconds: 1.5, shape: "swell"), to: wavSrc, seed: 6)
        let conv = Process(); conv.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert"); conv.arguments = [wavSrc.path, "-o", av.appendingPathComponent("t.m4a").path, "-f", "m4af", "-d", "aac"]
        try? conv.run(); conv.waitUntilExit()
        try? FileManager.default.moveItem(at: av.appendingPathComponent("t.m4a"), to: mp4)
        store.addFiles([mp4]); await wait(2)
        if let vid = store.items.first(where: { $0.name == "tylko_dzwiek" }) {
            for _ in 0..<5 { _ = store.thumbnails.image(for: vid); await wait(0.5) }
            print("SELF 25 miniatura pliku bez wideo (\(vid.kind.rawValue)): prób=\(store.thumbnails.attempts[vid.path] ?? 0), oznaczona jako nieudana=\(store.thumbnails.hasFailed(vid))")
        }
        // Enter -> zmiana nazwy
        let rf = FileManager.default.temporaryDirectory.appendingPathComponent("dock-enter-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: rf, withIntermediateDirectories: true)
        let rfile = rf.appendingPathComponent("enter_test.wav"); try? DevMedia.tone(.init(name: "e", seconds: 0.4, shape: "click"), to: rfile, seed: 12)
        store.addFiles([rfile]); await wait(2)
        store.select(category: .all)
        if let it = store.items.first(where: { $0.name == "enter_test" }) {
            store.click(it, command: false, shift: false)
            let handled = controller.debugKey(.enter)
            print("SELF 26 Enter: obsłużony=\(handled) prompt=\(store.prompt?.title ?? "brak") wartość początkowa=\(store.prompt?.initial ?? "-")")
            let keyDuringPrompt = controller.debugKey(.down)
            print("SELF 26b klawisze przy otwartym pytaniu przekazane do pola: \(!keyDuringPrompt)")
            store.prompt?.onConfirm("po_enterze"); store.prompt = nil; await wait(0.4)
            print("SELF 26c po zatwierdzeniu: plik na dysku=\(FileManager.default.fileExists(atPath: rf.appendingPathComponent("po_enterze.wav").path)) w bibliotece=\(store.items.contains { $0.name == "po_enterze" })")
        }
        if let lib = store.items.first(where: { i in store.sources.first(where: { $0.id == i.sourceID })?.kind == .fcpLibrary }) {
            store.click(lib, command: false, shift: false); _ = controller.debugKey(.enter)
            print("SELF 26d Enter na pliku z biblioteki FCP: pytanie=\(store.prompt != nil) komunikat=\(store.notice ?? "brak")"); store.notice = nil
        }
        // klawisze 1-6, Shift+cyfra, spacja
        store.select(category: .source(store.sources[0].id)); store.config.filters = .none; await wait(0.4)
        let all0 = store.visible.count
        _ = controller.debugKey(.digit(2, shift: false)); let musicOnly = store.visible.count; let qk2 = store.config.filters.klass
        _ = controller.debugKey(.digit(2, shift: false)); let cleared = store.visible.count
        _ = controller.debugKey(.digit(1, shift: false)); _ = controller.debugKey(.digit(6, shift: false))
        print("SELF 28 klawisze: wszystko=\(all0) po '2' (\(qk2?.label ?? "-"))=\(musicOnly) po drugim '2'=\(cleared) po '1' i '6' filtr=\(store.config.filters.klass?.label ?? "brak")")
        if let song = store.items.first(where: { $0.kind == .audio && $0.duration > 20 }) {
            store.select(category: .all); store.click(song, command: false, shift: false); store.previewer.pause()
            let before = store.mediaClass(song).label
            _ = controller.debugKey(.digit(1, shift: true))
            print("SELF 29 Shift+1: \(song.name) \(before) -> \(store.mediaClass(song).label); 5 = ulubione: ", terminator: "")
            _ = controller.debugKey(.digit(5, shift: false)); print(store.isFavorite(song))
            store.setClass(nil, for: [song.path]); store.toggleFavorite([song.path])
        }
        store.select(category: .klass(.image)); if let im = store.visible.first { store.click(im, command: false, shift: false) }
        _ = controller.debugKey(.space); let big1 = store.settings.bigMediaPreview
        _ = controller.debugKey(.space); let big2 = store.settings.bigMediaPreview
        print("SELF 30 spacja na obrazie: powiększony=\(big1), po drugiej spacji=\(big2)")
        // duży podgląd na dole (opcja)
        store.select(category: .klass(.image)); await wait(0.4)
        if let img = store.visible.first { store.click(img, command: false, shift: false) }
        store.data.settings.bigMediaPreview = true; await wait(0.5)
        print("SELF 27 duży podgląd na dole włączony: primary=\(store.primary?.name ?? "-") ustawienie=\(store.settings.bigMediaPreview)")
        store.data.settings.bigMediaPreview = false
        store.previewer.pause(); store.select(category: .all)
        // Łapka w prawdziwym oknie uchwytu: symulowany kursor blisko notcha, potem zrzut zawartości okna
        store.settings.mode = .hover; store.settings.placement = .topCenter; store.settings.notchEffect = .paw; await wait(0.8)
        if let gr = controller.debugGlowRect() {
            controller.debugMouse = CGPoint(x: gr.midX + 70, y: gr.minY - 75); controller.debugUpdateEffect(); await wait(1.4)
            print("SELF 31 łapka: cel=(\(Int(controller.state.tipX)),\(Int(controller.state.tipY))) aktywna=\(controller.state.armActive) koniec łapki=(\(Int(controller.state.sim.spring.pos.x)),\(Int(controller.state.sim.spring.pos.y))) okno uchwytu=\(controller.debugState().split(separator: " ")[3])")
            SnapshotRunner.save(controller.handleSnapshot(), "/tmp/lapka-live-handle.png")
            controller.debugMouse = CGPoint(x: gr.midX + 900, y: gr.minY - 900); controller.debugUpdateEffect(); await wait(2.0)
            print("SELF 31b po odjechaniu: cel Y=\(Int(controller.state.tipY)) aktywna=\(controller.state.armActive)")
            controller.debugMouse = nil
        }
        // Zapis na dysk
        store.settings.accent = .violet; store.settings.placement = .rightMiddle
        store.newCollection(name: "Testowa"); store.flush()
        let onDisk = UserDataStore(url: AppInfo.dataDir.appendingPathComponent("userdata.json")).load()
        print("SELF 8 zapis: accent=\(onDisk.settings.accent.rawValue) placement=\(onDisk.settings.placement.rawValue) kolekcje=\(onDisk.org.collections.map(\.name))")
        // Obserwowanie folderu na żywo
        let watched = FileManager.default.temporaryDirectory.appendingPathComponent("dock-live-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        store.addSource(url: watched, kind: .folder); await wait(1.5)
        let before = store.items.count
        try? DevMedia.tone(.init(name: "live_new_file", seconds: 0.7, shape: "impact"), to: watched.appendingPathComponent("live_new_file.wav"), seed: 5)
        await wait(4)
        let added = store.items.contains { $0.name == "live_new_file" }
        print("SELF 9 live: elementów przed=\(before) po=\(store.items.count) nowy plik widoczny=\(added)")
        try? FileManager.default.removeItem(at: watched.appendingPathComponent("live_new_file.wav"))
        await wait(4)
        print("SELF 10 live usunięcie: nowy plik nadal w indeksie=\(store.items.contains { $0.name == "live_new_file" })")
        exit(0)
    }
}
