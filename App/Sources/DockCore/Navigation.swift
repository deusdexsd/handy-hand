import Foundation

/// Nawigacja strzałkami po siatce (jak w Finderze): bez zawijania, w dół z niepełnego wiersza idzie na ostatni element.
public enum GridNavigation {
    public enum Direction: Sendable { case up, down, left, right }

    public static func move(from index: Int?, count: Int, columns: Int, _ dir: Direction) -> Int? {
        guard count > 0 else { return nil }
        guard let i = index, (0..<count).contains(i) else { return 0 }     // brak zaznaczenia: pierwszy element
        let cols = max(1, columns)
        switch dir {
        case .left: return max(0, i - 1)
        case .right: return min(count - 1, i + 1)
        case .up: return i - cols >= 0 ? i - cols : i
        case .down:
            if i + cols <= count - 1 { return i + cols }
            return (i / cols) < ((count - 1) / cols) ? count - 1 : i
        }
    }

    /// Ile kolumn zmieści adaptacyjna siatka (minimalna szerokość kafla + odstępy), tak jak liczy ją SwiftUI.
    public static func columns(width: Double, minItem: Double = 148, spacing: Double = 10, padding: Double = 20) -> Int {
        max(1, Int(floor((width - padding + spacing) / (minItem + spacing))))
    }
}

/// Podziałka czasu pod waveformem: "ładny" odstęp znaczników dla danej skali.
public enum ScaleTicks {
    public static func step(forScale s: Double, maxTicks: Int = 6) -> Double {
        let candidates: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        return candidates.first { s / $0 <= Double(maxTicks) } ?? 600
    }
}
