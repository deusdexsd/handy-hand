import CoreGraphics
import Foundation

/// Giętkie ramię jako lina Verleta: punkty mają bezwładność, koniec jest przyciągany sprężyną do celu, do tego lekki zwis
/// i wygładzanie krzywizny. Dzięki temu ramię faluje, dobiega z opóźnieniem i „przestrzeliwuje” zamiast sztywno obracać odcinki.
public struct RopeArm: Sendable {
    public private(set) var pts: [CGPoint]
    private var prev: [CGPoint]
    public let count: Int
    public let segLen: CGFloat
    public var maxReach: CGFloat { segLen * CGFloat(count - 1) * 0.97 }

    public init(shoulder: CGPoint, count: Int = 12, length: CGFloat = 88) {
        self.count = count; segLen = length / CGFloat(count - 1)
        pts = (0..<count).map { CGPoint(x: shoulder.x, y: shoulder.y - CGFloat($0) * length / CGFloat(count - 1)) }   // start: zwinięte nad notchem
        prev = pts
    }

    public mutating func step(dt: CGFloat, shoulder: CGPoint, target: CGPoint,
                              stiffness: CGFloat = 520, damping: CGFloat = 0.93, gravity: CGFloat = 620, smoothing: CGFloat = 0.05) {
        let h = min(max(dt, 0.001), 1.0 / 30)
        var tgt = target
        let dx = tgt.x - shoulder.x, dy = tgt.y - shoulder.y, d = hypot(dx, dy)
        if d > maxReach { tgt = CGPoint(x: shoulder.x + dx / d * maxReach, y: shoulder.y + dy / d * maxReach) }
        let damp = pow(damping, h * 60)
        for i in 1..<count {
            let v = CGPoint(x: (pts[i].x - prev[i].x) * damp, y: (pts[i].y - prev[i].y) * damp)
            prev[i] = pts[i]
            let w = i == count - 1 ? 1.0 : 0.05 * CGFloat(i) / CGFloat(count)       // koniec ciągnie mocno, reszta lekko
            let ax = (tgt.x - pts[i].x) * stiffness * w, ay = (tgt.y - pts[i].y) * stiffness * w + gravity
            pts[i] = CGPoint(x: pts[i].x + v.x + ax * h * h, y: pts[i].y + v.y + ay * h * h)
        }
        if count > 2 {
            for i in 1..<(count - 1) {          // wygładzanie: kolejne punkty układają się w łuk
                pts[i].x += ((pts[i - 1].x + pts[i + 1].x) / 2 - pts[i].x) * smoothing
                pts[i].y += ((pts[i - 1].y + pts[i + 1].y) / 2 - pts[i].y) * smoothing
            }
        }
        for _ in 0..<10 {                       // stała długość członów
            pts[0] = shoulder
            for i in 0..<(count - 1) {
                let ex = pts[i + 1].x - pts[i].x, ey = pts[i + 1].y - pts[i].y, len = hypot(ex, ey)
                guard len > 1e-4 else { continue }
                let k = (len - segLen) / len
                if i == 0 { pts[1].x -= ex * k; pts[1].y -= ey * k }
                else { pts[i].x += ex * k * 0.5; pts[i].y += ey * k * 0.5; pts[i + 1].x -= ex * k * 0.5; pts[i + 1].y -= ey * k * 0.5 }
            }
        }
        pts[0] = shoulder
    }

    /// Krzywa gładka przez punkty (Catmull-Rom), do rysowania.
    public func smoothPoints(perSegment n: Int = 4) -> [CGPoint] {
        var out: [CGPoint] = []
        for i in 0..<(count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(count - 1, i + 2)]
            for s in 0..<n {
                let t = CGFloat(s) / CGFloat(n), t2 = t * t, t3 = t2 * t
                func c(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat { 0.5 * ((2 * b) + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (-a + 3 * b - 3 * cc + d) * t3) }
                out.append(CGPoint(x: c(p0.x, p1.x, p2.x, p3.x), y: c(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        out.append(pts[count - 1])
        return out
    }
}
