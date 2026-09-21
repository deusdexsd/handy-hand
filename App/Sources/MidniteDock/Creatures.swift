import SwiftUI
import DockCore

/// Stan symulacji ramienia (klasa, żeby Canvas mógł ją krokować bez publikowania zmian na każdą klatkę).
final class ArmSim {
    var rope = RopeArm(shoulder: .zero)
    var last: Date?
    func advance(now: Date, shoulder: CGPoint, target: CGPoint) {
        let dt = last.map { CGFloat(now.timeIntervalSince($0)) } ?? 1.0 / 60
        last = now
        let steps = max(1, min(3, Int((dt * 60).rounded(.up))))
        for _ in 0..<steps { rope.step(dt: dt / CGFloat(steps), shoulder: shoulder, target: target) }
    }
}

/// Giętka łapka wychodząca ze szczeliny pod notchem: lina z fizyką (bezwładność, sprężyste dobieganie, zwis),
/// zwężająca się od barku do łapki. Rysowana tylko poniżej dolnej krawędzi notcha; gdy jest schowana, symulacja stoi.
struct CreatureLayer: View {
    let notch: CGSize
    @ObservedObject var state: PanelState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !state.armActive)) { tl in
            Canvas { ctx, size in
                let shoulder = CGPoint(x: size.width / 2 + state.shoulderX, y: notch.height - 6)
                let target = CGPoint(x: shoulder.x + state.tipX, y: shoulder.y + state.tipY)
                if state.sim.last == nil { state.sim.rope = RopeArm(shoulder: shoulder, length: 0.44 * notch.width) }
                state.sim.advance(now: tl.date, shoulder: shoulder, target: target)
                Self.draw(&ctx, state.sim.rope, scale: notch.width / 220)
            }
        }
        .mask(alignment: .top) {
            VStack(spacing: 0) { Color.clear.frame(height: notch.height); Color.black }     // nic nad dolną krawędzią notcha
        }
        .allowsHitTesting(false)
    }

    /// Proporcje jak w filmie referencyjnym (skala względem szerokości notcha 220 pt): gruba, lekko zwężająca się trąba
    /// (31 -> 23 pt) i pęk pięciu okrągłych palców na końcu, bez osobnej poduszki.
    static func draw(_ ctx: inout GraphicsContext, _ rope: RopeArm, scale s: CGFloat) {
        let pts = rope.smoothPoints(perSegment: 4)
        let n = pts.count
        guard n > 6 else { return }
        let w0 = 31 * s, w1 = 23 * s
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0..<n {
            let a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
            let tx = b.x - a.x, ty = b.y - a.y, l = max(0.001, hypot(tx, ty))
            let t = CGFloat(i) / CGFloat(n - 1)
            let w = (w0 + (w1 - w0) * t) / 2
            left.append(CGPoint(x: pts[i].x - ty / l * w, y: pts[i].y + tx / l * w))
            right.append(CGPoint(x: pts[i].x + ty / l * w, y: pts[i].y - tx / l * w))
        }
        var p = Path(); p.move(to: left[0])
        left.dropFirst().forEach { p.addLine(to: $0) }
        right.reversed().forEach { p.addLine(to: $0) }
        p.closeSubpath()
        ctx.fill(p, with: .color(.black))
        // łapka: koniec ramienia zaokrąglony + wachlarz pięciu palców wokół końca
        let tip = pts[n - 1], from = pts[n * 2 / 3]
        let dl = max(0.001, hypot(tip.x - from.x, tip.y - from.y)), ux = (tip.x - from.x) / dl, uy = (tip.y - from.y) / dl
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - w1 / 2, y: tip.y - w1 / 2, width: w1, height: w1)), with: .color(.black))
        let ring = w1 / 2 + 1.5 * s, r = 0.36 * w1
        for a in [-78.0, -40.0, 0.0, 40.0, 78.0] {
            let rad = a * .pi / 180
            let tx = ux * cos(rad) - uy * sin(rad), ty = ux * sin(rad) + uy * cos(rad)
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x + tx * ring - r, y: tip.y + ty * ring - r, width: 2 * r, height: 2 * r)), with: .color(.black))
        }
    }
}
