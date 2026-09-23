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

/// Układ „Pinterest”: każdy kolejny element trafia do najkrótszej kolumny. Wspólny dla rysowania i nawigacji strzałkami.
public enum MasonryLayout {
    public static let spacing = 10.0

    public static func estimatedHeight(isAudio: Bool, pixelWidth: Int?, pixelHeight: Int?, scale: Double = 1) -> Double {
        guard !isAudio, let w = pixelWidth, let h = pixelHeight, w > 0, h > 0 else { return 64 * scale }
        if isSmallImage(pixelWidth: w, pixelHeight: h) { return 70 * scale }
        return min(260, max(70, 160 * Double(h) / Double(w))) * scale
    }

    /// Obrazy mniejsze niż ~160 px (ikony) pokazujemy w naturalnym rozmiarze zamiast rozciągać.
    public static func isSmallImage(pixelWidth: Int?, pixelHeight: Int?) -> Bool {
        guard let w = pixelWidth, let h = pixelHeight else { return false }
        return max(w, h) < 160
    }

    /// Indeksy elementów w kolumnach (kolejność z góry na dół).
    public static func distribute(heights: [Double], columns: Int) -> [[Int]] {
        let cols = max(1, columns)
        var hs = [Double](repeating: 0, count: cols)
        var out = Array(repeating: [Int](), count: cols)
        for (i, h) in heights.enumerated() {
            var shortest = 0
            for c in 1..<cols where hs[c] < hs[shortest] { shortest = c }
            out[shortest].append(i)
            hs[shortest] += h + spacing
        }
        return out
    }

    /// Strzałki w układzie kolumnowym: góra/dół w obrębie kolumny, lewo/prawo do sąsiedniej kolumny (element na podobnej wysokości).
    public static func move(from index: Int?, heights: [Double], columns: Int, _ dir: GridNavigation.Direction) -> Int? {
        guard !heights.isEmpty else { return nil }
        guard let i = index, heights.indices.contains(i) else { return 0 }
        let layout = distribute(heights: heights, columns: columns)
        guard let c = layout.firstIndex(where: { $0.contains(i) }), let pos = layout[c].firstIndex(of: i) else { return i }
        switch dir {
        case .up: return pos > 0 ? layout[c][pos - 1] : i
        case .down: return pos + 1 < layout[c].count ? layout[c][pos + 1] : i
        case .left, .right:
            let nc = dir == .left ? c - 1 : c + 1
            guard layout.indices.contains(nc), !layout[nc].isEmpty else { return i }
            func center(_ col: [Int], _ p: Int) -> Double { col[..<p].reduce(0) { $0 + heights[$1] + spacing } + heights[col[p]] / 2 }
            let y = center(layout[c], pos)
            return layout[nc].indices.min { abs(center(layout[nc], $0) - y) < abs(center(layout[nc], $1) - y) }.map { layout[nc][$0] } ?? i
        }
    }
}
