import AppKit
import DockCore
import UniformTypeIdentifiers

enum DragVariant: String, CaseIterable, Identifiable {
    case fileURL = "Plik (file URL)"
    case promise = "File promise"
    case both = "Promise + URL"
    var id: String { rawValue }
}

/// NSFilePromiseProvider, który opcjonalnie dokłada też public.file-url,
/// żeby odbiorca mógł wybrać: wziąć plik "w miejscu" albo poprosić o kopię.
final class PromiseProvider: NSFilePromiseProvider {
    var alsoFileURL = false
    var sourceURL: URL? { userInfo as? URL }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var t = super.writableTypes(for: pasteboard)
        if alsoFileURL { t.append(.fileURL) }
        return t
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL, let u = sourceURL { return (u as NSURL).pasteboardPropertyList(forType: type) }
        return super.pasteboardPropertyList(forType: type)
    }
}

final class PromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let url: URL
    let queue = OperationQueue()
    init(url: URL) { self.url = url }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        Log.write("PROMISE: odbiorca pyta o nazwę pliku (typ \(fileType)) -> \(url.lastPathComponent)")
        return url.lastPathComponent
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo dest: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        Log.write("PROMISE: odbiorca prosi o zapis do \(dest.path)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest) // APFS clone: natychmiast, bez podwajania miejsca
            completionHandler(nil)
        } catch {
            Log.write("PROMISE: BŁĄD kopiowania \(error)")
            completionHandler(error)
        }
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { queue }
}

/// Kafel-źródło dragu. Feedback na pointer-down (nie na puszczenie), drag jak w Finderze.
final class DragTileView: NSView, NSDraggingSource {
    let asset: ProbeAsset
    private let variant: () -> DragVariant
    private let onSelect: (ProbeAsset) -> Void
    var onDragState: ((Bool) -> Void)?
    private var pressed = false { didSet { needsDisplay = true } }
    private var downPoint: NSPoint = .zero
    private var promiseDelegate: PromiseDelegate?

    init(asset: ProbeAsset, variant: @escaping () -> DragVariant, onSelect: @escaping (ProbeAsset) -> Void) {
        self.asset = asset
        self.variant = variant
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 190, height: 96))
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(asset.name), przeciągnij do Final Cut Pro")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let scale: CGFloat = pressed ? 0.97 : 1
        let r = bounds.insetBy(dx: bounds.width * (1 - scale) / 2, dy: bounds.height * (1 - scale) / 2)
        let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        (pressed ? NSColor.controlAccentColor.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.10)).setFill()
        path.fill()
        let symbol = asset.kind == .audio ? "waveform" : "film"
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 26, weight: .regular)) {
            let tinted = img.copy() as! NSImage
            tinted.lockFocus(); NSColor.labelColor.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop); tinted.unlockFocus()
            tinted.draw(at: NSPoint(x: r.midX - tinted.size.width / 2, y: r.midY - 4), from: .zero, operation: .sourceOver, fraction: 1)
        }
        let title = "\(asset.name)  ·  \(asset.seconds) s" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor]
        let sz = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.minY + 12), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        downPoint = event.locationInWindow
        onSelect(asset)
    }

    override func mouseUp(with event: NSEvent) { pressed = false }

    override func mouseDragged(with event: NSEvent) {
        guard pressed, hypot(event.locationInWindow.x - downPoint.x, event.locationInWindow.y - downPoint.y) > 4 else { return }
        pressed = false
        beginDrag(event)
    }

    private func beginDrag(_ event: NSEvent) {
        let v = variant()
        let writer: NSPasteboardWriting
        switch v {
        case .fileURL:
            writer = asset.url as NSURL
        case .promise, .both:
            let delegate = PromiseDelegate(url: asset.url)
            promiseDelegate = delegate
            let type = asset.kind == .audio ? UTType.wav.identifier : UTType.quickTimeMovie.identifier
            let p = PromiseProvider(fileType: type, delegate: delegate)
            p.userInfo = asset.url
            p.alsoFileURL = (v == .both)
            writer = p
        }
        let item = NSDraggingItem(pasteboardWriter: writer)
        let rep = bitmapImageRepForCachingDisplay(in: bounds)!
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size); img.addRepresentation(rep)
        item.setDraggingFrame(bounds, contents: img)
        onDragState?(true)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        Log.write("DRAG start: \(asset.name) jako [\(v.rawValue)]")
    }

    // MARK: NSDraggingSource
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .generic, .link]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let opName = operation.isEmpty ? "NONE (odrzucony / anulowany)"
            : [(NSDragOperation.copy, "copy"), (.generic, "generic"), (.link, "link"), (.move, "move")]
                .filter { operation.contains($0.0) }.map(\.1).joined(separator: "+")
        Log.write("DRAG koniec: \(asset.name) operacja=\(opName) w punkcie ekranu (\(Int(screenPoint.x)), \(Int(screenPoint.y)))")
        onDragState?(false)
    }
}
