import SwiftUI
import DockCore

/// Stan animacji ramienia (klasa, żeby Canvas mógł go krokować bez publikowania zmian na każdą klatkę).
final class ArmSim {
    var spring = TipSpring(pos: .zero)
    var last: Date?
    func advance(now: Date, target: CGPoint) {
        let dt = last.map { CGFloat(now.timeIntervalSince($0)) } ?? 1.0 / 60
        last = now
        let steps = max(1, min(3, Int((dt * 60).rounded(.up))))
        for _ in 0..<steps { spring.step(dt: dt / CGFloat(steps), target: target) }
    }
}

/// Łapka wychodząca ze szczeliny pod notchem: SZTYWNE ramię, łokieć tuż przy notchu, przedramię celuje w kursor
/// i kończy się pękiem palców skierowanym w tę samą stronę. Giętkość to tylko lekkie sprężyste dobieganie (ok. 15%).
/// Rysowana tylko poniżej dolnej krawędzi notcha; gdy jest schowana, animacja stoi.
struct CreatureLayer: View {
    let notch: CGSize
    @ObservedObject var state: PanelState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !state.armActive)) { tl in
            Canvas { ctx, size in
                let shoulder = CGPoint(x: size.width / 2 + state.shoulderX, y: notch.height - 6)
                let target = CGPoint(x: shoulder.x + state.tipX, y: shoulder.y + state.tipY)
                if state.sim.last == nil { state.sim.spring = TipSpring(pos: CGPoint(x: shoulder.x, y: shoulder.y - 40)) }
                state.sim.advance(now: tl.date, target: target)
                Self.draw(&ctx, shoulder: shoulder, tip: state.sim.spring.pos, scale: notch.width / 220, notchH: notch.height)
            }
        }
        .mask(alignment: .top) {
            VStack(spacing: 0) { Color.clear.frame(height: notch.height); Color.black }     // nic nad dolną krawędzią notcha
        }
        .allowsHitTesting(false)
    }

    /// Proporcje względem szerokości notcha 220 pt: człon przy notchu 22, przedramię 75, grubość 31 -> 25 pt, pęk pięciu palców.
    static func draw(_ ctx: inout GraphicsContext, shoulder: CGPoint, tip target: CGPoint, scale s: CGFloat, notchH: CGFloat) {
        let r = ArmIK.solve(shoulder: shoulder, target: target, l1: 22 * s, l2: 75 * s, elbowFloor: notchH + 2)
        let w0 = 31 * s, wE = 29 * s, w1 = 25 * s
        func limb(_ a: CGPoint, _ b: CGPoint, _ wa: CGFloat, _ wb: CGFloat) {
            let dx = b.x - a.x, dy = b.y - a.y, l = max(0.001, hypot(dx, dy)), nx = -dy / l, ny = dx / l
            var p = Path()
            p.move(to: CGPoint(x: a.x + nx * wa / 2, y: a.y + ny * wa / 2)); p.addLine(to: CGPoint(x: b.x + nx * wb / 2, y: b.y + ny * wb / 2))
            p.addLine(to: CGPoint(x: b.x - nx * wb / 2, y: b.y - ny * wb / 2)); p.addLine(to: CGPoint(x: a.x - nx * wa / 2, y: a.y - ny * wa / 2)); p.closeSubpath()
            ctx.fill(p, with: .color(.black))
            ctx.fill(Path(ellipseIn: CGRect(x: a.x - wa / 2, y: a.y - wa / 2, width: wa, height: wa)), with: .color(.black))
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - wb / 2, y: b.y - wb / 2, width: wb, height: wb)), with: .color(.black))
        }
        limb(shoulder, r.elbow, w0, wE)
        limb(r.elbow, r.tip, wE, w1)
        // łapka: pęk pięciu palców wokół końca przedramienia, skierowany tak jak ono, czyli w stronę kursora
        let dl = max(0.001, hypot(r.tip.x - r.elbow.x, r.tip.y - r.elbow.y)), ux = (r.tip.x - r.elbow.x) / dl, uy = (r.tip.y - r.elbow.y) / dl
        let ring = w1 / 2 + 4 * s, tr = 0.27 * w1
        for a in [-70.0, -35.0, 0.0, 35.0, 70.0] {
            let rad = a * .pi / 180
            let tx = ux * cos(rad) - uy * sin(rad), ty = ux * sin(rad) + uy * cos(rad)
            ctx.fill(Path(ellipseIn: CGRect(x: r.tip.x + tx * ring - tr, y: r.tip.y + ty * ring - tr, width: 2 * tr, height: 2 * tr)), with: .color(.black))
        }
    }
}
