import SwiftUI
import AppKit
import DockCore

/// Przezroczysta warstwa AppKit nad kaflem: natychmiastowy feedback na pointer-down,
/// klik, natywny drag plików (file URL, jak w Finderze), menu kontekstowe i hover.
struct DragOverlay: NSViewRepresentable {
    var paths: () -> [String]
    var previewName: () -> String
    var isVideo: Bool
    var passThrough: CGRect = .zero            // obszar (np. gwiazdka), który ma dostać zdarzenia myszy
    var onDown: (_ shift: Bool, _ command: Bool) -> Void
    var onPress: (Bool) -> Void
    var onClick: (_ command: Bool, _ shift: Bool) -> Void
    var onDrag: (Bool) -> Void
    var onHover: (Bool) -> Void
    var menu: () -> NSMenu?

    func makeNSView(context: Context) -> OverlayView { OverlayView() }
    func updateNSView(_ v: OverlayView, context: Context) {
        v.cfg = self
    }

    final class OverlayView: NSView, NSDraggingSource {
        var cfg: DragOverlay?
        private var down: NSPoint = .zero
        private var pressed = false
        private var dragging = false

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let c = cfg else { return super.hitTest(point) }
            let local = convert(point, from: superview)
            return c.passThrough.contains(local) ? nil : super.hitTest(point)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { cfg?.onHover(true) }
        override func mouseExited(with event: NSEvent) { cfg?.onHover(false) }

        override func mouseDown(with event: NSEvent) {
            down = event.locationInWindow; pressed = true; dragging = false
            let m = event.modifierFlags
            cfg?.onDown(m.contains(.shift), m.contains(.command)); cfg?.onPress(true)         // feedback na wciśnięcie, nie na puszczenie
        }

        override func mouseUp(with event: NSEvent) {
            defer { pressed = false; cfg?.onPress(false) }
            guard pressed, !dragging else { return }
            let m = event.modifierFlags
            cfg?.onClick(m.contains(.command), m.contains(.shift))
        }

        override func mouseDragged(with event: NSEvent) {
            guard pressed, !dragging, let c = cfg,
                  hypot(event.locationInWindow.x - down.x, event.locationInWindow.y - down.y) > 4 else { return }
            dragging = true
            cfg?.onPress(false)
            let paths = c.paths()
            guard !paths.isEmpty else { return }
            let img = DragImage.make(name: c.previewName(), count: paths.count, video: c.isVideo)
            let start = convert(event.locationInWindow, from: nil)
            // Obraz trzyma się kursora 1:1 z offsetem od miejsca chwycenia.
            let items: [NSDraggingItem] = paths.enumerated().map { i, p in
                let it = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: p) as NSURL)
                let off = CGFloat(min(i, 3)) * 4
                it.setDraggingFrame(NSRect(x: start.x - img.size.width / 2 + off, y: start.y - img.size.height / 2 - off,
                                           width: img.size.width, height: img.size.height), contents: i == 0 ? img : NSImage())
                return it
            }
            cfg?.onDrag(true)
            let session = beginDraggingSession(with: items, event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        override func rightMouseDown(with event: NSEvent) {
            let m = event.modifierFlags
            cfg?.onDown(m.contains(.shift), m.contains(.command))
            if let menu = cfg?.menu() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        }

        func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { [.copy, .generic, .link] }
        func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
            dragging = false; pressed = false
            cfg?.onDrag(false)
        }
    }
}

enum DragImage {
    static func make(name: String, count: Int, video: Bool) -> NSImage {
        let title = count > 1 ? "\(count) pliki" : name
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]
        let tw = min(200, (title as NSString).size(withAttributes: attrs).width)
        let size = NSSize(width: tw + 44, height: 32)
        return NSImage(size: size, flipped: false) { r in
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9).fill()
            NSColor.separatorColor.setStroke()
            let b = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9); b.lineWidth = 0.5; b.stroke()
            if let ic = NSImage(systemSymbolName: video ? "film" : "waveform", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) {
                ic.isTemplate = true
                let t = NSImage(size: ic.size, flipped: false) { rr in ic.draw(in: rr); NSColor.secondaryLabelColor.set(); rr.fill(using: .sourceAtop); return true }
                t.draw(at: NSPoint(x: 10, y: (r.height - ic.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
            }
            (title as NSString).draw(in: NSRect(x: 30, y: 8, width: tw + 6, height: 16), withAttributes: attrs)
            return true
        }
    }
}

/// Element menu z domknięciem zamiast target/selector.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, checked: Bool = false, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}
