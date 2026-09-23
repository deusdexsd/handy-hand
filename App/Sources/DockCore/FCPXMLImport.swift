import Foundation

/// Odczyt ścieżek do plików z eksportu Final Cut Pro (.fcpxml albo pakiet .fcpxmld).
/// FCP zapisuje je w atrybutach `src` elementów `media-rep` (nowsze wersje) i `asset` (starsze) jako `file:///…`.
public enum FCPXMLImport {
    public struct Result: Equatable, Sendable {
        public var name: String            // nazwa projektu (albo eventu, albo pliku) — nazwa nowej kolekcji
        public var existing: [String]      // pliki, które są na dysku
        public var missing: Int            // ścieżki, których na dysku nie ma
    }

    public static func isFCPXML(_ url: URL) -> Bool { ["fcpxml", "fcpxmld"].contains(url.pathExtension.lowercased()) }

    public static func read(_ url: URL) -> Result? {
        var file = url
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            file = url.appendingPathComponent("Info.fcpxml")
        }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return parse(data, fallbackName: url.deletingPathExtension().lastPathComponent)
    }

    public static func parse(_ data: Data, fallbackName: String) -> Result? {
        let d = Delegate()
        let p = XMLParser(data: data)
        p.delegate = d
        guard p.parse() || !d.sources.isEmpty else { return nil }
        var seen = Set<String>(); var existing: [String] = []; var missing = 0
        for src in d.sources {
            guard let u = URL(string: src), u.isFileURL else { continue }
            let path = PathUtil.canonical(u.path)
            guard seen.insert(path).inserted else { continue }
            if FileManager.default.fileExists(atPath: path) { existing.append(path) } else { missing += 1 }
        }
        return Result(name: d.projectName ?? d.eventName ?? fallbackName, existing: existing, missing: missing)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var sources: [String] = []
        var projectName: String?, eventName: String?
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            switch name {
            case "media-rep", "asset": if let s = a["src"], !s.isEmpty { sources.append(s) }
            case "project": if projectName == nil { projectName = a["name"] }
            case "event": if eventName == nil { eventName = a["name"] }
            default: break
            }
        }
    }
}

/// Ikona aplikacji w pasku menu macOS (wybór w Ustawieniach).
public enum MenuBarIcon: String, Codable, CaseIterable, Sendable {
    case paw, hand, waveform, film, grid
    public var symbol: String {
        switch self { case .paw: "pawprint.fill"; case .hand: "hand.raised.fill"; case .waveform: "waveform"; case .film: "film.stack"; case .grid: "square.grid.2x2.fill" }
    }
    public var label: String {
        switch self {
        case .paw: LL("Łapka", "Paw"); case .hand: LL("Dłoń", "Hand"); case .waveform: LL("Fala dźwięku", "Waveform")
        case .film: LL("Klatki filmu", "Film frames"); case .grid: LL("Siatka", "Grid")
        }
    }
}
