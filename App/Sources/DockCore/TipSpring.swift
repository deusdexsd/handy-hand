import CoreGraphics
import Foundation

/// Sprężyste dobieganie końcówki ramienia do celu: lekkie „przestrzelenie” (ok. 10%) zamiast giętkiej liny.
/// Ramię zostaje sztywne, a ruch ma odrobinę życia.
public struct TipSpring: Sendable {
    public var pos: CGPoint
    public var vel: CGPoint = .zero
    public init(pos: CGPoint) { self.pos = pos }

    public mutating func step(dt: CGFloat, target: CGPoint, stiffness: CGFloat = 420, damping ratio: CGFloat = 0.62) {
        let h = min(max(dt, 0.001), 1.0 / 30)
        let c = 2 * sqrt(stiffness) * ratio
        let ax = (target.x - pos.x) * stiffness - vel.x * c, ay = (target.y - pos.y) * stiffness - vel.y * c
        vel.x += ax * h; vel.y += ay * h
        pos.x += vel.x * h; pos.y += vel.y * h
    }
}
