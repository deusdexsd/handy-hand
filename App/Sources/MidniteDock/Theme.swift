import SwiftUI
import AppKit
import DockCore

extension AccentChoice {
    var color: Color {
        switch self {
        case .system: return .accentColor
        case .graphite: return Color(nsColor: .systemGray)
        case .blue: return Color(nsColor: .systemBlue)
        case .violet: return Color(nsColor: .systemPurple)
        case .green: return Color(nsColor: .systemGreen)
        case .orange: return Color(nsColor: .systemOrange)
        }
    }
}

private struct DockAccentKey: EnvironmentKey { static let defaultValue: Color = .accentColor }
private struct SourceTintsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var dockAccent: Color { get { self[DockAccentKey.self] } set { self[DockAccentKey.self] = newValue } }
    var sourceTints: Bool { get { self[SourceTintsKey.self] } set { self[SourceTintsKey.self] = newValue } }
}

/// Natywny materiał tła (NSVisualEffectView): sam staje się pełny przy "Zmniejsz przezroczystość".
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blending; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material; v.blendingMode = blending }
}

enum Fmt {
    static func duration(_ s: Double) -> String {
        if s < 10 { return String(format: "%.1f s", s).replacingOccurrences(of: ".", with: ",") }
        let t = Int(s.rounded())
        return t >= 60 ? String(format: "%d:%02d", t / 60, t % 60) : "\(t) s"
    }
    static func clock(_ s: Double) -> String {
        let t = max(0, s)
        return String(format: "%d:%02d,%d", Int(t) / 60, Int(t) % 60, Int((t - floor(t)) * 10))
    }
}
