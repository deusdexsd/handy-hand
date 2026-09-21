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
                if state.sim.last == nil { state.sim.rope = RopeArm(shoulder: shoulder) }
                state.sim.advance(now: tl.date, shoulder: shoulder, target: target)
                Self.draw(&ctx, state.sim.rope)
            }
        }
        .mask(alignment: .top) {
            VStack(spacing: 0) { Color.clear.frame(height: notch.height); Color.black }     // nic nad dolną krawędzią notcha
        }
        .allowsHitTesting(false)
    }

    static func draw(_ ctx: inout GraphicsContext, _ rope: RopeArm) {
        let pts = rope.smoothPoints(perSegment: 4)
        let n = pts.count
        guard n > 6 else { return }
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0..<n {
            let a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
            let tx = b.x - a.x, ty = b.y - a.y, l = max(0.001, hypot(tx, ty))
            let t = CGFloat(i) / CGFloat(n - 1)
            let w = (23 - 9 * t) / 2                                       // grubo przy barku, węziej przy łapce
            left.append(CGPoint(x: pts[i].x - ty / l * w, y: pts[i].y + tx / l * w))
            right.append(CGPoint(x: pts[i].x + ty / l * w, y: pts[i].y - tx / l * w))
        }
        var p = Path(); p.move(to: left[0])
        left.dropFirst().forEach { p.addLine(to: $0) }
        right.reversed().forEach { p.addLine(to: $0) }
        p.closeSubpath()
        ctx.fill(p, with: .color(.black))
        // łapka: pękata poduszka i cztery palce od strony końca ramienia
        let tip = pts[n - 1], from = pts[n - 5]
        let dl = max(0.001, hypot(tip.x - from.x, tip.y - from.y)), ux = (tip.x - from.x) / dl, uy = (tip.y - from.y) / dl
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 12.5, y: tip.y - 12.5, width: 25, height: 25)), with: .color(.black))
        for a in [-52.0, -18.0, 18.0, 52.0] {
            let r = a * .pi / 180
            let tx = ux * cos(r) - uy * sin(r), ty = ux * sin(r) + uy * cos(r)
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x + tx * 13 - 5.8, y: tip.y + ty * 13 - 5.8, width: 11.6, height: 11.6)), with: .color(.black))
        }
    }
}
