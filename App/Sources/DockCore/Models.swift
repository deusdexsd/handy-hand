import Foundation

public enum MediaKind: String, Codable, Sendable, CaseIterable, Hashable {
    case audio, video, image
    public var label: String { switch self { case .audio: "Audio"; case .video: LL("Wideo", "Video"); case .image: LL("Obraz", "Image") } }
}

/// Klasa elementu: audio dzieli się na SFX i muzykę (wg długości albo ręcznie), do tego wideo i obrazy.
public enum MediaClass: String, Codable, Sendable, CaseIterable, Hashable {
    case sfx, music, video, image
    public var label: String { switch self { case .sfx: "SFX"; case .music: LL("Muzyka", "Music"); case .video: LL("Wideo", "Video"); case .image: LL("Obrazy", "Images") } }
    public var kind: MediaKind { switch self { case .sfx, .music: .audio; case .video: .video; case .image: .image } }
    public var hasDuration: Bool { self != .image }
}

public struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var ext: String
    public var kind: MediaKind
    public var duration: Double
    public var size: Int64
    public var created: Date
    public var modified: Date
    public var sourceID: UUID
    /// Pierwszy podfolder względem źródła (dla bibliotek FCP: nazwa zdarzenia).
    public var group: String?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var url: URL { URL(fileURLWithPath: path) }

    public init(path: String, name: String, ext: String, kind: MediaKind, duration: Double, size: Int64,
                created: Date, modified: Date, sourceID: UUID, group: String?, pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
        self.path = path; self.name = name; self.ext = ext; self.kind = kind; self.duration = duration
        self.size = size; self.created = created; self.modified = modified; self.sourceID = sourceID; self.group = group
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
    }
}

/// `files` = źródło z pojedynczymi plikami wskazanymi jeden po drugim (bez folderu nadrzędnego).
public enum SourceKind: String, Codable, Sendable { case folder, fcpLibrary, files }

public struct Source: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var kind: SourceKind
    public var filePaths: [String]?
    public init(id: UUID = UUID(), name: String, path: String, kind: SourceKind, filePaths: [String]? = nil) {
        self.id = id; self.name = name; self.path = path; self.kind = kind; self.filePaths = filePaths
    }

    /// Co obserwować w systemie plików: folder źródła albo foldery nadrzędne pojedynczych plików.
    public var watchPaths: [String] {
        kind == .files ? Array(Set((filePaths ?? []).map { ($0 as NSString).deletingLastPathComponent })).sorted() : [path]
    }
}

/// Przedział długości ustawiany przez użytkownika, osobno dla SFX, muzyki i wideo.
/// `shade` (0...1) to odcień szarości waveformu / kafla: im wyższy, tym mocniejszy.
public struct DurationRange: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var mediaClass: MediaClass
    public var minSeconds: Double
    public var maxSeconds: Double?
    public var shade: Double
    public var kind: MediaKind { mediaClass.kind }

    public init(id: UUID = UUID(), name: String, mediaClass: MediaClass, minSeconds: Double, maxSeconds: Double?, shade: Double) {
        self.id = id; self.name = name; self.mediaClass = mediaClass; self.minSeconds = minSeconds
        self.maxSeconds = maxSeconds; self.shade = shade
    }

    /// Zgodność wsteczna: audio = SFX.
    public init(id: UUID = UUID(), name: String, kind: MediaKind, minSeconds: Double, maxSeconds: Double?, shade: Double) {
        self.init(id: id, name: name, mediaClass: kind == .video ? .video : .sfx, minSeconds: minSeconds, maxSeconds: maxSeconds, shade: shade)
    }

    enum CodingKeys: String, CodingKey { case id, name, mediaClass, kind, minSeconds, maxSeconds, shade }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        minSeconds = try c.decode(Double.self, forKey: .minSeconds)
        maxSeconds = try c.decodeIfPresent(Double.self, forKey: .maxSeconds)
        shade = try c.decodeIfPresent(Double.self, forKey: .shade) ?? 0.6
        if let mc = try c.decodeIfPresent(MediaClass.self, forKey: .mediaClass) { mediaClass = mc }
        else { mediaClass = (try c.decodeIfPresent(MediaKind.self, forKey: .kind)) == .video ? .video : .sfx }   // stary zapis: audio -> SFX
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(mediaClass, forKey: .mediaClass)
        try c.encode(minSeconds, forKey: .minSeconds); try c.encodeIfPresent(maxSeconds, forKey: .maxSeconds); try c.encode(shade, forKey: .shade)
    }

    public func contains(_ d: Double) -> Bool { d >= minSeconds && (maxSeconds.map { d < $0 } ?? true) }

    public static func autoName(min: Double, max: Double?, lang: AppLanguage = UILanguage.current) -> String {
        let pl = lang == .pl
        func f(_ x: Double) -> String {
            if x >= 60, x.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(x / 60)) min" }
            let n = x == x.rounded() ? "\(Int(x))" : String(format: "%.1f", x).replacingOccurrences(of: ".", with: pl ? "," : ".")
            return "\(n) s"
        }
        switch (min, max) {
        case (0, let m?): return "\(pl ? "Do" : "Up to") \(f(m))"
        case (let a, let m?):
            let mins = a >= 60 && m >= 60 && a.truncatingRemainder(dividingBy: 60) == 0 && m.truncatingRemainder(dividingBy: 60) == 0
            if mins { return "\(Int(a / 60))–\(Int(m / 60)) min" }
            return "\(f(a).replacingOccurrences(of: " s", with: ""))–\(f(m))"
        case (let a, nil): return "\(pl ? "Powyżej" : "Over") \(f(a))"
        }
    }

    /// Nazwa do wyświetlania: przedział nazwany automatycznie (nie zmieniony ręcznie) tłumaczy się na aktualny język; własne nazwy zostają.
    public var displayName: String {
        name == Self.autoName(min: minSeconds, max: maxSeconds, lang: .pl) || name == Self.autoName(min: minSeconds, max: maxSeconds, lang: .en)
            ? Self.autoName(min: minSeconds, max: maxSeconds) : name
    }

    public static func musicDefaults() -> [DurationRange] {
        [DurationRange(name: "Do 1 min", mediaClass: .music, minSeconds: 0, maxSeconds: 60, shade: 0.35),
         DurationRange(name: "1–3 min", mediaClass: .music, minSeconds: 60, maxSeconds: 180, shade: 0.6),
         DurationRange(name: "Powyżej 3 min", mediaClass: .music, minSeconds: 180, maxSeconds: nil, shade: 0.9)]
    }

    public static func defaults() -> [DurationRange] {
        [DurationRange(name: "Do 1 s", mediaClass: .sfx, minSeconds: 0, maxSeconds: 1, shade: 0.35),
         DurationRange(name: "1–3 s", mediaClass: .sfx, minSeconds: 1, maxSeconds: 3, shade: 0.6),
         DurationRange(name: "Powyżej 3 s", mediaClass: .sfx, minSeconds: 3, maxSeconds: nil, shade: 0.9)]
        + musicDefaults() +
        [DurationRange(name: "Do 5 s", mediaClass: .video, minSeconds: 0, maxSeconds: 5, shade: 0.35),
         DurationRange(name: "5–15 s", mediaClass: .video, minSeconds: 5, maxSeconds: 15, shade: 0.6),
         DurationRange(name: "Powyżej 15 s", mediaClass: .video, minSeconds: 15, maxSeconds: nil, shade: 0.9)]
    }
}

/// Reguła "smart" po słowach w nazwie (edytowalna).
public struct KeywordRule: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var keywords: [String]
    public init(id: UUID = UUID(), name: String, keywords: [String]) { self.id = id; self.name = name; self.keywords = keywords }

    public func matches(_ item: MediaItem) -> Bool {
        let n = item.name.lowercased()
        return keywords.contains { !$0.isEmpty && n.contains($0.lowercased()) }
    }

    public static func defaults() -> [KeywordRule] {
        [KeywordRule(name: "Whoosh", keywords: ["whoosh", "swish", "swoosh"]),
         KeywordRule(name: "Impact", keywords: ["impact", "hit", "slam"]),
         KeywordRule(name: "Riser", keywords: ["riser", "rise", "build"]),
         KeywordRule(name: "Boom", keywords: ["boom", "sub", "low"]),
         KeywordRule(name: "Click", keywords: ["click", "tick", "pop"])]
    }
}

public struct MediaCollection: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var paths: [String]
    public init(id: UUID = UUID(), name: String, paths: [String] = []) { self.id = id; self.name = name; self.paths = paths }
}
