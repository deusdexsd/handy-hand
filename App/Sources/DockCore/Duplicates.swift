import Foundation

/// Wykrywanie duplikatów: ta sama nazwa (bez rozszerzenia, bez wielkości liter), ten sam typ
/// i ta sama długość (z dokładnością do 10 ms). Tryb ścisły dokłada jeszcze rozmiar pliku.
public struct DuplicateIndex: Sendable {
    public let keyOf: [String: String]        // ścieżka -> klucz duplikatu
    public let members: [String: [String]]    // klucz -> wszystkie ścieżki

    public static let empty = DuplicateIndex(keyOf: [:], members: [:])

    public static func key(_ i: MediaItem, strict: Bool) -> String {
        let name = i.name.lowercased().trimmingCharacters(in: .whitespaces)
        if i.kind == .image {   // obrazy nie mają długości: nazwa + wymiary + rozmiar (IMG_001.jpg z dwóch aparatów to nie duplikat)
            return "image|\(name)|\(i.pixelWidth ?? 0)x\(i.pixelHeight ?? 0)|\(i.size)"
        }
        let base = "\(i.kind.rawValue)|\(name)|\(Int((i.duration * 100).rounded()))"
        return strict ? base + "|\(i.size)" : base
    }

    public static func build(_ items: [MediaItem], strict: Bool) -> DuplicateIndex {
        var keyOf: [String: String] = [:], members: [String: [String]] = [:]
        for i in items {
            let k = key(i, strict: strict)
            keyOf[i.path] = k
            members[k, default: []].append(i.path)
        }
        return DuplicateIndex(keyOf: keyOf, members: members)
    }

    /// Wszystkie ścieżki, które są "tym samym" plikiem (zawsze zawiera `path`).
    public func equivalents(of path: String) -> [String] {
        guard let k = keyOf[path], let m = members[k] else { return [path] }
        return m
    }

    public func copies(of path: String) -> Int { equivalents(of: path).count }
}

public enum Deduper {
    /// Zwija duplikaty w podanej liście: zostaje kopia z wyższym priorytetem źródła (kolejność źródeł
    /// użytkownika), przy remisie większy plik, przy remisie ścieżka alfabetycznie (stabilnie).
    public static func collapse(_ items: [MediaItem], index: DuplicateIndex, sourceOrder: [UUID]) -> [MediaItem] {
        let rank = Dictionary(uniqueKeysWithValues: sourceOrder.enumerated().map { ($1, $0) })
        var best: [String: MediaItem] = [:]
        var order: [String] = []
        for i in items {
            let k = index.keyOf[i.path] ?? i.path
            if let cur = best[k] {
                let (a, b) = (rank[i.sourceID] ?? Int.max, rank[cur.sourceID] ?? Int.max)
                let better = a != b ? a < b : (i.size != cur.size ? i.size > cur.size : i.path < cur.path)
                if better { best[k] = i }
            } else { best[k] = i; order.append(k) }
        }
        return order.compactMap { best[$0] }
    }
}
