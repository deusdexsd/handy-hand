import CoreGraphics
import Foundation

/// Giętkie ramię jako lina Verleta. Kształt spoczynkowy to łuk łokcia (parabola o długości równej długości ramienia),
/// a bezwładność i sprężyste przyciąganie do tego łuku dają falowanie i „przestrzeliwanie” w ruchu.
/// Bez grawitacji: zwis dawał odgięcie końca łapki do góry.
public struct RopeArm: Sendable {
    public private(set) var pts: [CGPoint]
    private var prev: [CGPoint]
    public let count: Int
    public let segLen: CGFloat
    public var length: CGFloat { segLen * CGFloat(count - 1) }
    public var maxReach: CGFloat { length * 0.97 }

    public init(shoulder: CGPoint, count: Int = 12, length: CGFloat = 76) {
        self.count = count; segLen = length / CGFloat(count - 1)
        pts = (0..<count).map { CGPoint(x: shoulder.x, y: shoulder.y - CGFloat($0) * length / CGFloat(count - 1)) }   // start: zwinięte nad notchem
        prev = pts
    }

    /// Wypukłość łuku dla danej odległości: L ≈ d + 8b²/(3d) => b = sqrt(3d(L-d)/8). Blisko celu ramię się zgina, daleko prostuje.
    public func bow(forDistance d: CGFloat) -> CGFloat { min(0.5 * length, sqrt(max(0, 3 * d * max(0, length - d) / 8))) }

    public mutating func step(dt: CGFloat, shoulder: CGPoint, target: CGPoint,
                              tipStiffness: CGFloat = 520, arcStiffness: CGFloat = 170, damping: CGFloat = 0.92) {
        let h = min(max(dt, 0.001), 1.0 / 30)
        var tgt = target
        var dx = tgt.x - shoulder.x, dy = tgt.y - shoulder.y
        var d = max(1, hypot(dx, dy))
        if d > maxReach { tgt = CGPoint(x: shoulder.x + dx / d * maxReach, y: shoulder.y + dy / d * maxReach); dx = tgt.x - shoulder.x; dy = tgt.y - shoulder.y; d = maxReach }
        let ux = dx / d, uy = dy / d
        var perp = CGPoint(x: -uy, y: ux)
        if perp.y > 0 || (abs(perp.y) < 0.001 && perp.x > 0) { perp = CGPoint(x: -perp.x, y: -perp.y) }      // łokieć w górę
        let b = bow(forDistance: d)
        let damp = pow(damping, h * 60)
        for i in 1..<count {
            let t = CGFloat(i) / CGFloat(count - 1)
            let off = b * sin(.pi * t) * sin(.pi * t)      // zerowe nachylenie przy barku: ramię wychodzi prosto, bez „wargi” na krawędzi notcha
            let vk = min(1, t / 0.4), kk = vk * vk                                  // pierwsze człony schodzą prosto w dół z notcha, wygięcie dopiero dalej
            let want = CGPoint(x: shoulder.x + (dx * t + perp.x * off) * kk, y: shoulder.y + dy * t + perp.y * off * kk)
            let v = CGPoint(x: (pts[i].x - prev[i].x) * damp, y: (pts[i].y - prev[i].y) * damp)
            prev[i] = pts[i]
            let k = i == count - 1 ? tipStiffness : arcStiffness
            pts[i] = CGPoint(x: pts[i].x + v.x + (want.x - pts[i].x) * k * h * h, y: pts[i].y + v.y + (want.y - pts[i].y) * k * h * h)
        }
        for i in 1..<(count - 1) {              // lekkie wygładzanie: bez załamań i „guzków” na ramieniu
            pts[i].x += ((pts[i - 1].x + pts[i + 1].x) / 2 - pts[i].x) * 0.12
            pts[i].y += ((pts[i - 1].y + pts[i + 1].y) / 2 - pts[i].y) * 0.12
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
