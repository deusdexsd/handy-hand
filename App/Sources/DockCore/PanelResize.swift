import CoreGraphics

public struct ResizeEdges: Equatable, Sendable {
    public var left = false, right = false, top = false, bottom = false
    public init(left: Bool = false, right: Bool = false, top: Bool = false, bottom: Bool = false) {
        self.left = left; self.right = right; self.top = top; self.bottom = bottom
    }
    public var any: Bool { left || right || top || bottom }
}

/// Rozciąganie panelu myszką. `dy` > 0 = mysz w górę (współrzędne ekranu AppKit).
public enum PanelResize {
    public static let minSize = CGSize(width: 560, height: 340)

    /// Panel jest kotwiczony do krawędzi ekranu, więc przeciągać można tylko strony od niej odsunięte.
    public static func allowed(_ e: ResizeEdges, placement: NotchPlacement) -> ResizeEdges {
        var r = e
        switch placement {
        case .topCenter: r.top = false
        case .leftMiddle: r.left = false
        case .rightMiddle: r.right = false
        }
        return r
    }

    public static func newSize(start: CGSize, dx: CGFloat, dy: CGFloat, edges e: ResizeEdges,
                               placement: NotchPlacement, screen: CGSize) -> CGSize {
        let hCentered = placement == .topCenter          // wyśrodkowany poziomo: krawędź rusza się 2x wolniej niż rozmiar
        let vCentered = placement.isSide                 // boczny: wyśrodkowany względem uchwytu w pionie
        var w = start.width, h = start.height
        if e.right { w += hCentered ? 2 * dx : dx }
        if e.left { w -= hCentered ? 2 * dx : dx }
        if e.bottom { h -= vCentered ? 2 * dy : dy }
        if e.top { h += vCentered ? 2 * dy : dy }
        w = min(max(w, minSize.width), max(minSize.width, min(1600, screen.width - 32)))
        h = min(max(h, minSize.height), max(minSize.height, min(1000, screen.height - 90)))
        return CGSize(width: w.rounded(), height: h.rounded())
    }
}
