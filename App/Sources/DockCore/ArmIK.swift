import CoreGraphics
import Foundation

/// Ramię dwuczłonowe (bark - łokieć - dłoń): łokieć wychodzi tam, gdzie wynika z długości członów, i zgina się „do góry”.
public enum ArmIK {
    /// `elbowFloor`: najmniejsze dozwolone y łokcia (nie chowamy łokcia za krawędzią notcha).
    public static func solve(shoulder s: CGPoint, target t: CGPoint, l1: CGFloat, l2: CGFloat, elbowFloor: CGFloat? = nil) -> (elbow: CGPoint, tip: CGPoint) {
        var v = CGPoint(x: t.x - s.x, y: t.y - s.y)
        var d = hypot(v.x, v.y)
        if d < 0.001 { v = CGPoint(x: 0, y: 1); d = 1 }
        let minD = abs(l1 - l2) + 0.01, maxD = l1 + l2 - 0.01
        let dc = min(max(d, minD), maxD)
        let u = CGPoint(x: v.x / d, y: v.y / d)
        let tip = CGPoint(x: s.x + u.x * dc, y: s.y + u.y * dc)
        let a = acos(min(1, max(-1, (l1 * l1 + dc * dc - l2 * l2) / (2 * l1 * dc))))
        func rot(_ p: CGPoint, _ ang: CGFloat) -> CGPoint { CGPoint(x: p.x * cos(ang) - p.y * sin(ang), y: p.x * sin(ang) + p.y * cos(ang)) }
        let r1 = rot(u, a), r2 = rot(u, -a)
        let e1 = CGPoint(x: s.x + r1.x * l1, y: s.y + r1.y * l1), e2 = CGPoint(x: s.x + r2.x * l1, y: s.y + r2.y * l1)
        let elbow: CGPoint
        if let f = elbowFloor, min(e1.y, e2.y) < f, max(e1.y, e2.y) >= f { elbow = e1.y >= f ? e1 : e2 }   // wyższe rozwiązanie chowałoby łokieć: bierzemy niższe
        else if abs(e1.y - e2.y) > 0.5 { elbow = e1.y < e2.y ? e1 : e2 }      // łokieć w górę (mniejsze y)
        else { elbow = e1.x <= e2.x ? e1 : e2 }                            // ramię prosto w dół: stała strona, bez przeskoków
        return (elbow, tip)
    }
}
