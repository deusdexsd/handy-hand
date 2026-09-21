import CoreGraphics

/// Migawka parametrów ekranu (współrzędne globalne AppKit, początek w lewym dolnym rogu).
/// Oddzielona od NSScreen, żeby geometrię notcha dało się testować na danych syntetycznych.
public struct ScreenMetrics: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeft: CGRect?
    public var auxiliaryTopRight: CGRect?

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat = 0,
                auxiliaryTopLeft: CGRect? = nil, auxiliaryTopRight: CGRect? = nil) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }

    public var hasNotch: Bool {
        safeAreaTop > 0 && auxiliaryTopLeft != nil && auxiliaryTopRight != nil
    }
}

public enum NotchGeometry {
    /// Prostokąt notcha we współrzędnych globalnych; nil na ekranach bez notcha.
    public static func notchRect(_ m: ScreenMetrics) -> CGRect? {
        guard m.hasNotch, let l = m.auxiliaryTopLeft, let r = m.auxiliaryTopRight else { return nil }
        return CGRect(x: l.maxX, y: m.frame.maxY - m.safeAreaTop,
                      width: r.minX - l.maxX, height: m.safeAreaTop)
    }

    /// Oś, wokół której układa się panel: środek notcha albo środek ekranu.
    public static func anchorX(_ m: ScreenMetrics) -> CGFloat {
        notchRect(m)?.midX ?? m.frame.midX
    }

    /// Górna krawędź panelu: tuż pod notchem, a bez notcha - tuż pod paskiem menu.
    public static func topEdgeY(_ m: ScreenMetrics) -> CGFloat {
        m.hasNotch ? m.frame.maxY - m.safeAreaTop : m.visibleFrame.maxY
    }

    public static func panelFrame(size: CGSize, on m: ScreenMetrics, inset: CGFloat = 0) -> CGRect {
        var x = anchorX(m) - size.width / 2
        x = max(m.frame.minX + inset, min(x, m.frame.maxX - size.width - inset)) // lewa krawędź wygrywa, gdy panel szerszy niż ekran
        return CGRect(x: x, y: topEdgeY(m) - size.height, width: size.width, height: size.height)
    }

    /// Ekran z notchem ma pierwszeństwo (tam jest sens "przy notchu"); potem ekran pod kursorem; potem główny.
    public static func preferredScreen(_ all: [ScreenMetrics], mouse: CGPoint?) -> ScreenMetrics? {
        if let notched = all.first(where: \.hasNotch) { return notched }
        if let mouse, let under = all.first(where: { $0.frame.contains(mouse) }) { return under }
        return all.first
    }
}
