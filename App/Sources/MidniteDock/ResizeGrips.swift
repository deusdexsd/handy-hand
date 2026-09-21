import SwiftUI
import AppKit
import DockCore

/// Rozciąganie panelu myszką za krawędzie i rogi (jak okno). Rozmiar zapisuje się w ustawieniach.
/// Używa położenia myszy na ekranie, a nie gestu SwiftUI, bo okno rusza się razem z kursorem.
struct ResizeGrips: NSViewRepresentable {
    @ObservedObject var store: LibraryStore
    let atBottom: Bool

    func makeNSView(context: Context) -> GripsView { let v = GripsView(); v.configure(store: store, atBottom: atBottom); return v }
    func updateNSView(_ v: GripsView, context: Context) { v.configure(store: store, atBottom: atBottom) }

    typealias Grip = ResizeEdges

    @MainActor final class GripsView: NSView {
        private weak var store: LibraryStore?
        private var atBottom = false
        private var placement: NotchPlacement = .topCenter
        private var active: Grip?
        private var startMouse: NSPoint = .zero
        private var startSize: CGSize = .zero
        private let band: CGFloat = 6, corner: CGFloat = 18

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        func configure(store: LibraryStore, atBottom: Bool) {
            self.store = store; self.atBottom = atBottom; placement = store.settings.placement
            window?.invalidateCursorRects(for: self)
            needsLayout = true
        }

        private func allowed(_ g: Grip) -> Grip { PanelResize.allowed(g, placement: placement) }

        private func grip(at p: NSPoint) -> Grip? {
            var g = Grip(left: p.x < band, right: p.x > bounds.width - band, top: p.y < band, bottom: p.y > bounds.height - band)
            let nearX = p.x < corner || p.x > bounds.width - corner, nearY = p.y < corner || p.y > bounds.height - corner
            if nearX && nearY { g.left = p.x < corner; g.right = p.x > bounds.width - corner; g.top = p.y < corner; g.bottom = p.y > bounds.height - corner }
            g = allowed(g)
            return (g.left || g.right || g.top || g.bottom) ? g : nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            grip(at: convert(point, from: superview)) != nil ? self : nil
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self))
        }

        override func mouseMoved(with event: NSEvent) { updateCursor(convert(event.locationInWindow, from: nil)) }
        override func mouseEntered(with event: NSEvent) { updateCursor(convert(event.locationInWindow, from: nil)) }
        override func mouseExited(with event: NSEvent) { if active == nil { NSCursor.arrow.set() } }

        private func updateCursor(_ p: NSPoint) {
            guard let g = grip(at: p) else { NSCursor.arrow.set(); return }
            if (g.left || g.right) && (g.top || g.bottom) {
                if #available(macOS 15.0, *) {
                    let pos: NSCursor.FrameResizePosition = g.bottom ? (g.right ? .bottomRight : .bottomLeft) : (g.right ? .topRight : .topLeft)
                    NSCursor.frameResize(position: pos, directions: .all).set()
                } else { NSCursor.crosshair.set() }
            } else if g.left || g.right { NSCursor.resizeLeftRight.set() } else { NSCursor.resizeUpDown.set() }
        }

        override func mouseDown(with event: NSEvent) {
            guard let s = store, let g = grip(at: convert(event.locationInWindow, from: nil)) else { return }
            active = g; startMouse = NSEvent.mouseLocation
            startSize = CGSize(width: s.settings.expandedWidth, height: s.settings.expandedHeight)
            s.dragging = true      // panel nie może się zwinąć w trakcie rozciągania
        }

        override func mouseDragged(with event: NSEvent) {
            guard let s = store, let g = active else { return }
            let m = NSEvent.mouseLocation
            let screen = window?.screen?.frame.size ?? CGSize(width: 1600, height: 1000)
            let n = PanelResize.newSize(start: startSize, dx: m.x - startMouse.x, dy: m.y - startMouse.y, edges: g, placement: placement, screen: screen)
            let (w, h) = (n.width, n.height)
            s.data.settings.expandedWidth = w; s.data.settings.expandedHeight = h
        }

        override func mouseUp(with event: NSEvent) {
            active = nil; store?.dragging = false
            updateCursor(convert(event.locationInWindow, from: nil))
        }
    }
}
