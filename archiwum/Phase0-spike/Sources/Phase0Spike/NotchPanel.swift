import AppKit
import DockCore

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 168), // start w rozmiarze rozwiniętym: autoresizing treści liczy od tego
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar   // 25 > mainMenu 24: rysuje się też nad paskiem menu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Trzy tryby: hover (zwinięty, rozwija po najechaniu), followApp (rozwinięty, gdy aktywna wybrana apka), pinned.
@MainActor
final class NotchPanelController: NSObject {
    enum Mode: String, CaseIterable, Identifiable {
        case hover = "Najechanie"
        case followApp = "Podążaj za apką"
        case pinned = "Przypięty"
        var id: String { rawValue }
    }

    let panel = NotchPanel()
    var watchedBundleIDs: Set<String> = ["com.apple.FinalCut"]
    var mode: Mode = .hover { didSet { Log.write("TRYB -> \(mode.rawValue)"); apply(animated: true) } }

    private let expandedSize = CGSize(width: 440, height: 168)
    private let content = NSView()
    private let visual = NSVisualEffectView()
    private let pill = NSView()
    private var hovering = false
    private var dragging = false
    private var frontmostWatched = false
    private var collapseWork: DispatchWorkItem?
    private(set) var isExpanded = false
    private(set) var lastScreenNote = ""

    init(tiles: [DragTileView]) {
        super.init()
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 16
        visual.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // tylko dolne rogi: "wisi" z notcha
        visual.layer?.masksToBounds = true
        panel.contentView = visual

        // Treść ma stały rozmiar przypięty do góry - bez constraintów do okna,
        // inaczej autolayout wymusza minimalną wysokość i zwinięty pasek nie może mieć 8 pt.
        content.frame = NSRect(x: 16, y: expandedSize.height - 12 - (expandedSize.height - 26),
                               width: expandedSize.width - 32, height: expandedSize.height - 26)
        content.autoresizingMask = [.minYMargin]
        let stack = NSStackView(views: tiles)
        stack.orientation = .horizontal; stack.spacing = 14; stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "MidniteDock · Faza 0 — przeciągnij kafel do Final Cut Pro")
        title.font = .systemFont(ofSize: 11, weight: .semibold); title.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title); content.addSubview(stack)
        visual.addSubview(content)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            title.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
        pill.layer?.cornerRadius = 2
        pill.frame = NSRect(x: 0, y: 0, width: 60, height: 4)
        visual.addSubview(pill)

        tiles.forEach { t in t.onDragState = { [weak self] on in self?.dragging = on; self?.apply(animated: true) } }

        // Hover przez monitor ruchu myszy (bez Accessibility) zamiast NSTrackingArea na 8-punktowym okienku.
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
            MainActor.assumeIsolated { self?.updateHover() }
            return e
        }

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        frontmostWatched = isWatched(NSWorkspace.shared.frontmostApplication)
    }

    func show() { panel.orderFrontRegardless(); apply(animated: false) }

    // MARK: ekran i geometria
    static func metrics(_ s: NSScreen) -> ScreenMetrics {
        ScreenMetrics(frame: s.frame, visibleFrame: s.visibleFrame, safeAreaTop: s.safeAreaInsets.top,
                      auxiliaryTopLeft: s.auxiliaryTopLeftArea, auxiliaryTopRight: s.auxiliaryTopRightArea)
    }

    private func targetMetrics() -> ScreenMetrics? {
        NotchGeometry.preferredScreen(NSScreen.screens.map(Self.metrics), mouse: NSEvent.mouseLocation)
    }

    private func targetFrame() -> NSRect {
        guard let m = targetMetrics() else { return panel.frame }
        let notch = NotchGeometry.notchRect(m)
        let collapsedW = (notch?.width ?? 180) + 40
        let size = isExpanded ? expandedSize : CGSize(width: collapsedW, height: 8)
        lastScreenNote = notch != nil ? "notch \(Int(notch!.width))×\(Int(notch!.height)) pt" : "brak notcha (pod paskiem menu)"
        return NotchGeometry.panelFrame(size: size, on: m)
    }

    // MARK: logika trybów
    private func shouldExpand() -> Bool {
        switch mode {
        case .pinned: return true
        case .followApp: return frontmostWatched || hovering || dragging
        case .hover: return hovering || dragging
        }
    }

    func apply(animated: Bool) {
        let want = shouldExpand()
        if want != isExpanded { Log.write("panel \(want ? "ROZWINIĘTY" : "zwinięty") (tryb \(mode.rawValue), hover=\(hovering), drag=\(dragging), apka watched=\(frontmostWatched))") }
        isExpanded = want
        let frame = targetFrame()
        pill.frame = NSRect(x: (frame.width - 60) / 2, y: 2, width: 60, height: 4)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.28 : 0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
            content.animator().alphaValue = isExpanded ? 1 : 0
            pill.animator().alphaValue = isExpanded ? 0 : 1
        }
    }

    /// Strefa reakcji: rozwinięty = panel + margines; zwinięty = pasek + wszystko nad nim do krawędzi ekranu
    /// (pasek menu / okolice notcha), żeby nie trzeba było trafiać w 8 punktów.
    private func hotZone() -> NSRect {
        var zone = panel.frame.insetBy(dx: -10, dy: -10)
        // Zawsze sięgamy do góry ekranu (pasek menu / okolice notcha) - inaczej po rozwinięciu
        // panel odjeżdża w dół spod kursora i natychmiast się zwija (migotanie).
        if let m = targetMetrics() {
            zone.size.height += max(0, m.frame.maxY - zone.maxY)
        }
        if !isExpanded { zone.origin.y = panel.frame.minY - 6; zone.size.height += 6 }
        return zone
    }

    private func updateHover() {
        let zone = hotZone()
        let inside = zone.contains(NSEvent.mouseLocation)
        if inside != hovering { Log.write("hover: mysz=\(NSEvent.mouseLocation) strefa=\(zone) panel=\(panel.frame) inside=\(inside)") }
        guard inside != hovering || (!inside && collapseWork == nil && hovering) else { return }
        if inside {
            collapseWork?.cancel(); collapseWork = nil
            hovering = true
            apply(animated: true)
        } else if collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.collapseWork = nil; self?.hovering = false; self?.apply(animated: true)
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func isWatched(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return watchedBundleIDs.contains(id)
    }

    @objc private func appActivated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        Log.write("aktywna apka -> \(app?.localizedName ?? "?") [\(app?.bundleIdentifier ?? "?")]")
        frontmostWatched = isWatched(app)
        apply(animated: true)
    }

    @objc private func screensChanged() {
        Log.write("zmiana konfiguracji ekranów -> przeliczam pozycję")
        apply(animated: false)
    }
}
