import SwiftUI
import DockCore

/// Stan animacji ramienia (klasa, żeby Canvas mógł go krokować bez publikowania zmian na każdą klatkę).
final class ArmSim {
    var spring = TipSpring(pos: .zero)
    var last: Date?
    var wants = false          // czy kursor jest w zasięgu (ramię ma się wysuwać)
    var extend: CGFloat = 0    // 0 = całkiem schowane w notchu, 1 = wysunięte
    var shoulderX: CGFloat = 0 // bark przesuwa się po notchu krokami (nie płynie za kursorem)
    var patting = true         // pacanie: seria szybkich „klepnięć” w stronę kursora
    var patStart: TimeInterval = 0

    /// Początek klatki: wysuwanie/chowanie (wolne, żeby nie migało) i przesunięcie barku. Zwraca dt.
    func beginFrame(now: Date, shoulderTarget: CGFloat) -> CGFloat {
        let dt = min(0.1, last.map { CGFloat(now.timeIntervalSince($0)) } ?? 1.0 / 60)
        last = now
        extend += ((wants ? 1 : 0) - extend) * min(1, dt * (wants ? 6.5 : 3.6))
        if !wants && extend < 0.004 { extend = 0 }
        shoulderX = extend < 0.08 ? shoulderTarget : shoulderX + (shoulderTarget - shoulderX) * min(1, dt * 7)
        return dt
    }

    /// Kotek „wypacuje”: ok. 1,1 s cyklu: szybkie wyrzucenie łapki do przodu, chwila w bezruchu, powolny powrót.
    func patFactor(at t: TimeInterval) -> CGFloat {
        guard patting else { return 1 }
        let ph = ((t - patStart) / 1.15).truncatingRemainder(dividingBy: 1)
        let jab: Double
        switch ph {
        case ..<0.16: jab = ph / 0.16; case ..<0.30: jab = 1; default: let u = (ph - 0.30) / 0.70; jab = 1 - u * u * (3 - 2 * u)
        }
        return 0.66 + 0.34 * CGFloat(jab)
    }

    func step(dt: CGFloat, target: CGPoint) {
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
                let sim = state.sim
                let dt = sim.beginFrame(now: tl.date, shoulderTarget: state.shoulderX)
                let shoulder = CGPoint(x: size.width / 2 + sim.shoulderX, y: notch.height - 6)
                let k = sim.patFactor(at: tl.date.timeIntervalSinceReferenceDate)
                let target = CGPoint(x: shoulder.x + state.tipX * k, y: shoulder.y + state.tipY * k)
                if sim.extend < 0.08 { sim.spring = TipSpring(pos: CGPoint(x: shoulder.x, y: shoulder.y - 40)) }
                sim.step(dt: dt, target: target)
                let e = sim.extend
                guard e > 0 else { return }            // całkiem schowana: nic nie rysujemy
                let sc = notch.width / 220
                let hide = (1 - e * e * (3 - 2 * e)) * (100 * sc + notch.height + 40)      // cała łapka wjeżdża w notch, nic nie wystaje
                Self.draw(&ctx, shoulder: CGPoint(x: shoulder.x, y: shoulder.y - hide), tip: CGPoint(x: sim.spring.pos.x, y: sim.spring.pos.y - hide), scale: sc, notchH: notch.height - hide)
            }
        }
        .mask(alignment: .top) {
            VStack(spacing: 0) { Color.clear.frame(height: notch.height); Color.black }     // nic nad dolną krawędzią notcha
        }
        .allowsHitTesting(false)
    }

    /// Proporcje względem szerokości notcha 220 pt: ramię przy notchu 36 pt (cieńsze, 25), łokieć, dalej przedramię 64 pt, które szerzej idzie do dłoni (29 -> 36), pęk pięciu palców.
    static func draw(_ ctx: inout GraphicsContext, shoulder: CGPoint, tip target: CGPoint, scale s: CGFloat, notchH: CGFloat) {
        let r = ArmIK.solve(shoulder: shoulder, target: target, l1: 36 * s, l2: 64 * s, elbowFloor: notchH + 2)
        let w0 = 25 * s, wE = 29 * s, w1 = 36 * s
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
