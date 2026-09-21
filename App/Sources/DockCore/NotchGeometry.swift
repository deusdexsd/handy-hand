import CoreGraphics

/// Migawka parametrów ekranu (współrzędne globalne AppKit, początek w lewym dolnym rogu).
public struct ScreenMetrics: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeft: CGRect?
    public var auxiliaryTopRight: CGRect?

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat = 0,
                auxiliaryTopLeft: CGRect? = nil, auxiliaryTopRight: CGRect? = nil) {
        self.frame = frame; self.visibleFrame = visibleFrame; self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft; self.auxiliaryTopRight = auxiliaryTopRight
    }

    public var hasNotch: Bool { safeAreaTop > 0 && auxiliaryTopLeft != nil && auxiliaryTopRight != nil }
}

/// Jak ma wyglądać "czapka" (notch prawdziwy lub narysowany) nad panelem.
public struct NotchLayout: Equatable, Sendable {
    public var showsCap: Bool       // czy rysujemy własną czarną wysepkę
    public var capSize: CGSize      // rozmiar wysepki (szerokość prawdziwego notcha, gdy jest)
    public var atBottom: Bool
    public var horizontalAnchor: CGFloat   // środek wysepki w osi X (globalnie)
    public var windowTopY: CGFloat?        // górna krawędź okna (gdy panel wisi od góry)
    public var windowBottomY: CGFloat?     // dolna krawędź okna (gdy panel rośnie od dołu)
}

public enum NotchGeometry {
    public static let defaultVirtualCap = CGSize(width: 200, height: 32)

    public static func notchRect(_ m: ScreenMetrics) -> CGRect? {
        guard m.hasNotch, let l = m.auxiliaryTopLeft, let r = m.auxiliaryTopRight else { return nil }
        return CGRect(x: l.maxX, y: m.frame.maxY - m.safeAreaTop, width: r.minX - l.maxX, height: m.safeAreaTop)
    }

    public static func wantsVirtualCap(_ m: ScreenMetrics, mode: VirtualNotchMode, placement: NotchPlacement) -> Bool {
        if placement != .topCenter { return true }   // poza notchem zawsze potrzebna własna wysepka
        switch mode {
        case .always: return true
        case .never: return false
        case .auto: return !m.hasNotch
        }
    }

    public static func layout(_ m: ScreenMetrics, placement: NotchPlacement, mode: VirtualNotchMode,
                              windowWidth: CGFloat, margin: CGFloat = 16) -> NotchLayout {
        let cap = wantsVirtualCap(m, mode: mode, placement: placement)
        let real = notchRect(m)
        let capSize = (placement == .topCenter ? real.map { CGSize(width: $0.width, height: $0.height) } : nil) ?? defaultVirtualCap
        switch placement {
        case .topCenter:
            let x = real?.midX ?? m.frame.midX
            if cap { return NotchLayout(showsCap: true, capSize: capSize, atBottom: false, horizontalAnchor: x, windowTopY: m.frame.maxY, windowBottomY: nil) }
            let top = m.hasNotch ? m.frame.maxY - m.safeAreaTop : m.visibleFrame.maxY
            return NotchLayout(showsCap: false, capSize: capSize, atBottom: false, horizontalAnchor: x, windowTopY: top, windowBottomY: nil)
        case .topLeft:
            return NotchLayout(showsCap: true, capSize: capSize, atBottom: false, horizontalAnchor: m.frame.minX + margin + windowWidth / 2,
                               windowTopY: m.frame.maxY, windowBottomY: nil)
        case .topRight:
            return NotchLayout(showsCap: true, capSize: capSize, atBottom: false, horizontalAnchor: m.frame.maxX - margin - windowWidth / 2,
                               windowTopY: m.frame.maxY, windowBottomY: nil)
        case .bottomCenter:
            return NotchLayout(showsCap: true, capSize: capSize, atBottom: true, horizontalAnchor: m.frame.midX, windowTopY: nil, windowBottomY: m.frame.minY)
        }
    }

    public static func windowFrame(size: CGSize, layout l: NotchLayout, on m: ScreenMetrics) -> CGRect {
        var x = l.horizontalAnchor - size.width / 2
        x = max(m.frame.minX, min(x, m.frame.maxX - size.width))
        if let top = l.windowTopY { return CGRect(x: x, y: top - size.height, width: size.width, height: size.height) }
        return CGRect(x: x, y: (l.windowBottomY ?? m.frame.minY), width: size.width, height: size.height)
    }

    /// Ekran z notchem ma pierwszeństwo; potem ekran pod kursorem; potem główny.
    public static func preferredScreen(_ all: [ScreenMetrics], mouse: CGPoint?) -> ScreenMetrics? {
        if let n = all.first(where: \.hasNotch) { return n }
        if let mouse, let u = all.first(where: { $0.frame.contains(mouse) }) { return u }
        return all.first
    }
}

public enum NotchGlow {
    /// Siła podświetlenia notcha (0...1) wg odległości kursora od wysepki w punktach: pełna przy dotknięciu, zanika do `radius`.
    public static func intensity(distance: Double, radius: Double = 26) -> Double {
        guard distance < radius else { return 0 }
        let t = 1 - max(0, distance) / radius
        return t * t * (3 - 2 * t)      // smoothstep
    }
}

extension NotchGeometry {
    /// Okno uchwytu przy prawdziwym notchu: sam notch powiększony o margines na poświatę (u góry równo z krawędzią ekranu).
    public static func notchHandleFrame(_ m: ScreenMetrics, pad: CGFloat = 16) -> CGRect? {
        guard let n = notchRect(m) else { return nil }
        return CGRect(x: n.minX - pad, y: n.minY - pad, width: n.width + 2 * pad, height: n.height + pad)
    }
}
