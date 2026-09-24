import Foundation

/// Odczyt ścieżek do plików z eksportu Final Cut Pro (.fcpxml albo pakiet .fcpxmld).
/// FCP zapisuje je w atrybutach `src` elementów `media-rep` (nowsze wersje) i `asset` (starsze) jako `file:///…`.
public enum FCPXMLImport {
    public struct Result: Equatable, Sendable {
        public var name: String            // nazwa projektu (albo eventu, albo pliku) — nazwa nowej kolekcji
        public var existing: [String]      // pliki, które są na dysku
        public var missing: Int            // ścieżki, których na dysku nie ma
        public var tags: [String: [String]] = [:]     // słowa kluczowe z FCP (Keyword Collections) → tagi Handy Hand
        public var favorites: [String] = []           // klipy oznaczone w FCP jako Favorite (rating)
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
        let keep = Set(existing)
        var tags: [String: [String]] = [:]
        for (id, kws) in d.keywordsByAsset {
            guard let src = d.assetSrc[id], let u = URL(string: src), u.isFileURL else { continue }
            let path = PathUtil.canonical(u.path)
            if keep.contains(path) { for k in kws where !(tags[path]?.contains(k) ?? false) { tags[path, default: []].append(k) } }
        }
        let favs = d.favoriteAssets.compactMap { id -> String? in
            guard let src = d.assetSrc[id], let u = URL(string: src), u.isFileURL else { return nil }
            let path = PathUtil.canonical(u.path); return keep.contains(path) ? path : nil
        }
        return Result(name: d.projectName ?? d.eventName ?? fallbackName, existing: existing, missing: missing, tags: tags, favorites: Array(Set(favs)).sorted())
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var sources: [String] = []
        var projectName: String?, eventName: String?
        var assetSrc: [String: String] = [:]           // id zasobu → src
        var keywordsByAsset: [String: [String]] = [:]
        var favoriteAssets: [String] = []
        private var currentAsset: String?
        private struct Clip { var refs: [String] = []; var keywords: [String] = []; var favorite = false }
        private var clips: [Clip] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            switch name {
            case "asset":
                currentAsset = a["id"]
                if let s = a["src"], !s.isEmpty { sources.append(s); if let id = a["id"] { assetSrc[id] = s } }
            case "media-rep":
                if let s = a["src"], !s.isEmpty { sources.append(s); if let id = currentAsset, assetSrc[id] == nil { assetSrc[id] = s } }
            case "project": if projectName == nil { projectName = a["name"] }
            case "event": if eventName == nil { eventName = a["name"] }
            case "asset-clip", "clip", "sync-clip", "mc-clip", "ref-clip":
                var c = Clip(); if let r = a["ref"] { c.refs.append(r) }; clips.append(c)
            case "video", "audio":
                if let r = a["ref"], !clips.isEmpty { clips[clips.count - 1].refs.append(r) }
            case "keyword":
                if let v = a["value"], !clips.isEmpty {
                    clips[clips.count - 1].keywords += v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
            case "rating":
                if a["value"] == "favorite", !clips.isEmpty { clips[clips.count - 1].favorite = true }
            default: break
            }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "asset" { currentAsset = nil }
            if ["asset-clip", "clip", "sync-clip", "mc-clip", "ref-clip"].contains(name), let c = clips.popLast() {
                for r in c.refs {
                    keywordsByAsset[r, default: []] += c.keywords
                    if c.favorite { favoriteAssets.append(r) }
                }
            }
        }
    }
}

/// Ikona aplikacji w pasku menu macOS (wybór w Ustawieniach). `.haha` to napis HA/HA jedno pod drugim (HAndy HAnd).
public enum MenuBarIcon: String, Codable, CaseIterable, Sendable {
    case hand, raised, haha, waveform, film
    /// Nazwa symbolu SF; nil = ikona rysowana własnym kodem (napis).
    public var symbol: String? {
        switch self { case .hand: "hand.point.up.left.fill"; case .raised: "hand.raised.fill"; case .haha: nil; case .waveform: "waveform"; case .film: "film.stack" }
    }
    public var label: String {
        switch self {
        case .hand: LL("Palec", "Pointing hand"); case .raised: LL("Dłoń", "Open hand"); case .haha: "HA HA"
        case .waveform: LL("Fala dźwięku", "Waveform"); case .film: LL("Klatki filmu", "Film frames")
        }
    }
    /// Stare zapisy (np. „paw”, „grid”) wracają do ikony domyślnej.
    public init(from d: Decoder) throws {
        self = MenuBarIcon(rawValue: (try? d.singleValueContainer().decode(String.self)) ?? "") ?? .hand
    }
}
