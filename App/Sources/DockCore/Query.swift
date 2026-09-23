import Foundation

public enum ViewMode: String, Codable, Sendable, CaseIterable { case list, grid, minimal }
public enum SortKey: String, Codable, Sendable, CaseIterable {
    case name, duration, dateAdded, dateModified
    public var label: String {
        switch self { case .name: LL("Nazwa", "Name"); case .duration: LL("Długość", "Length"); case .dateAdded: LL("Data dodania", "Date added"); case .dateModified: LL("Data zmiany", "Date modified") }
    }
}

public enum CategoryID: Hashable, Codable, Sendable {
    case favorites, all
    case source(UUID)
    case group(UUID, String)
    case collection(UUID)
    case duration(UUID)
    case keyword(UUID)
    case kind(MediaKind)
    case klass(MediaClass)
}

public struct Filters: Codable, Equatable, Sendable {
    public var kind: MediaKind?
    public var klass: MediaClass?
    public var durationRangeID: UUID?
    public var withinDays: Int?
    public var tag: String?
    public init(kind: MediaKind? = nil, klass: MediaClass? = nil, durationRangeID: UUID? = nil, withinDays: Int? = nil, tag: String? = nil) {
        self.kind = kind; self.klass = klass; self.durationRangeID = durationRangeID; self.withinDays = withinDays; self.tag = tag
    }
    public var isActive: Bool { kind != nil || klass != nil || durationRangeID != nil || withinDays != nil || tag != nil }
    public static let none = Filters()
}

/// Wszystko, co składa się na "układ" widoku (używane też jako preset).
public struct ViewConfig: Codable, Equatable, Sendable {
    public var category: CategoryID = .all
    public var filters: Filters = .none
    public var sort: SortKey = .name
    public var ascending: Bool = true
    public var viewMode: ViewMode = .grid
    public init() {}

    enum CodingKeys: String, CodingKey { case category, filters, sort, ascending, viewMode }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        category = try c.decodeIfPresent(CategoryID.self, forKey: .category) ?? .all
        filters = try c.decodeIfPresent(Filters.self, forKey: .filters) ?? .none
        sort = try c.decodeIfPresent(SortKey.self, forKey: .sort) ?? .name
        ascending = try c.decodeIfPresent(Bool.self, forKey: .ascending) ?? true
        viewMode = try c.decodeIfPresent(ViewMode.self, forKey: .viewMode) ?? .grid
    }
}

public struct Preset: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var config: ViewConfig
    public init(id: UUID = UUID(), name: String, config: ViewConfig) { self.id = id; self.name = name; self.config = config }
}

/// Dane użytkownika potrzebne do filtrowania (bez UI).
/// Notatka / zadanie w panelu po prawej. `collectionID == nil` = globalna (widoczna wszędzie).
public struct NoteItem: Identifiable, Hashable, Codable, Sendable {
    public var id = UUID()
    public var text: String
    public var done = false
    public var collectionID: UUID?
    public var created = Date()
    public init(text: String, collectionID: UUID? = nil) { self.text = text; self.collectionID = collectionID }
    enum CodingKeys: String, CodingKey { case id, text, done, collectionID, created }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        collectionID = try c.decodeIfPresent(UUID.self, forKey: .collectionID)
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }

    /// Notatki widoczne w danym miejscu: globalne + przypisane do zaznaczonej kolekcji.
    public static func visible(_ notes: [NoteItem], collection: UUID?) -> [NoteItem] {
        notes.filter { $0.collectionID == nil || $0.collectionID == collection }
    }
}

public struct Organization: Codable, Equatable, Sendable {
    public var favorites: Set<String> = []
    public var tags: [String: [String]] = [:]
    public var collections: [MediaCollection] = []
    public var durationRanges: [DurationRange] = DurationRange.defaults()
    public var keywordRules: [KeywordRule] = KeywordRule.defaults()
    public var presets: [Preset] = []
    /// Audio krótsze lub równe tej wartości to SFX, dłuższe to muzyka (chyba że plik ma ręczne przypisanie).
    public var sfxMaxSeconds: Double = 20
    public var classOverrides: [String: MediaClass] = [:]
    public var notes: [NoteItem] = []
    public init() {}

    public func mediaClass(of i: MediaItem) -> MediaClass {
        switch i.kind {
        case .video: return .video
        case .image: return .image
        case .audio:
            if let o = classOverrides[i.path], o == .sfx || o == .music { return o }
            return i.duration <= sfxMaxSeconds ? .sfx : .music
        }
    }

    enum CodingKeys: String, CodingKey { case favorites, tags, collections, durationRanges, keywordRules, presets, sfxMaxSeconds, classOverrides, notes }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        favorites = try c.decodeIfPresent(Set<String>.self, forKey: .favorites) ?? []
        tags = try c.decodeIfPresent([String: [String]].self, forKey: .tags) ?? [:]
        collections = try c.decodeIfPresent([MediaCollection].self, forKey: .collections) ?? []
        durationRanges = try c.decodeIfPresent([DurationRange].self, forKey: .durationRanges) ?? DurationRange.defaults()
        keywordRules = try c.decodeIfPresent([KeywordRule].self, forKey: .keywordRules) ?? KeywordRule.defaults()
        presets = try c.decodeIfPresent([Preset].self, forKey: .presets) ?? []
        sfxMaxSeconds = try c.decodeIfPresent(Double.self, forKey: .sfxMaxSeconds) ?? 20
        classOverrides = try c.decodeIfPresent([String: MediaClass].self, forKey: .classOverrides) ?? [:]
        notes = try c.decodeIfPresent([NoteItem].self, forKey: .notes) ?? []
    }

    public var allTags: [String] { Set(tags.values.flatMap { $0 }).sorted() }
}

public enum LibraryQuery {
    private static func any(_ item: MediaItem, _ dups: DuplicateIndex, _ test: (String) -> Bool) -> Bool {
        dups.equivalents(of: item.path).contains(where: test)
    }

    public static func matches(_ item: MediaItem, category: CategoryID, org: Organization, dups: DuplicateIndex = .empty) -> Bool {
        switch category {
        case .all: return true
        case .favorites: return any(item, dups) { org.favorites.contains($0) }
        case .source(let id): return item.sourceID == id
        case .group(let id, let g): return item.sourceID == id && item.group == g
        case .collection(let id):
            guard let c = org.collections.first(where: { $0.id == id }) else { return false }
            return any(item, dups) { c.paths.contains($0) }
        case .duration(let id): return org.durationRanges.first { $0.id == id }.map { $0.mediaClass == org.mediaClass(of: item) && $0.contains(item.duration) } ?? false
        case .keyword(let id): return org.keywordRules.first { $0.id == id }?.matches(item) ?? false
        case .kind(let k): return item.kind == k
        case .klass(let c): return org.mediaClass(of: item) == c
        }
    }

    /// Ile elementów ma kategoria (po zwinięciu duplikatów, jeśli włączone) - bez sortowania.
    public static func count(_ items: [MediaItem], category: CategoryID, org: Organization, dups: DuplicateIndex = .empty,
                             hideDuplicates: Bool = false, sourceOrder: [UUID] = []) -> Int {
        let hit = items.filter { matches($0, category: category, org: org, dups: dups) }
        return hideDuplicates ? Deduper.collapse(hit, index: dups, sourceOrder: sourceOrder).count : hit.count
    }

    public static func apply(_ items: [MediaItem], config: ViewConfig, search: String, org: Organization,
                             now: Date = Date(), dups: DuplicateIndex = .empty, hideDuplicates: Bool = false,
                             sourceOrder: [UUID] = [], favoritesFirst: Bool = false, searchMetadata: Bool = false) -> [MediaItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let f = config.filters
        var out = items.filter { matches($0, category: config.category, org: org, dups: dups) }
        if !q.isEmpty {
            out = out.filter { i in
                if i.name.lowercased().contains(q) { return true }
                guard searchMetadata else { return false }
                if i.ext.lowercased().contains(q) { return true }
                if let g = i.group, g.lowercased().contains(q) { return true }
                return any(i, dups) { org.tags[$0]?.contains { $0.lowercased().contains(q) } ?? false }
            }
        }
        if let k = f.kind { out = out.filter { $0.kind == k } }
        if let c = f.klass { out = out.filter { org.mediaClass(of: $0) == c } }
        if let rid = f.durationRangeID, let r = org.durationRanges.first(where: { $0.id == rid }) {
            out = out.filter { org.mediaClass(of: $0) == r.mediaClass && r.contains($0.duration) }
        }
        if let days = f.withinDays, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) {
            out = out.filter { $0.created >= cutoff || $0.modified >= cutoff }
        }
        if let t = f.tag { out = out.filter { i in any(i, dups) { org.tags[$0]?.contains(t) ?? false } } }
        if hideDuplicates { out = Deduper.collapse(out, index: dups, sourceOrder: sourceOrder) }
        out.sort { a, b in
            let r: Bool
            switch config.sort {
            case .name: r = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .duration: r = a.duration < b.duration
            case .dateAdded: r = a.created < b.created
            case .dateModified: r = a.modified < b.modified
            }
            return config.ascending ? r : !r
        }
        if favoritesFirst, config.category != .favorites {
            let isFav: (MediaItem) -> Bool = { any($0, dups) { org.favorites.contains($0) } }
            out.sort { a, b in let fa = isFav(a), fb = isFav(b); return fa != fb ? fa : false }     // stabilny sort: kolejność w grupie zostaje
        }
        return out
    }

    /// Odcień szarości (0...1) wg przedziałów użytkownika i klasy elementu (SFX/muzyka/wideo).
    public static func shade(for item: MediaItem, org: Organization) -> Double {
        let c = org.mediaClass(of: item)
        return org.durationRanges.first { $0.mediaClass == c && $0.contains(item.duration) }?.shade ?? 0.6
    }

    /// Odcień szarości (0...1) dla elementu wg przedziałów użytkownika; domyślnie środek.
    public static func shade(for item: MediaItem, ranges: [DurationRange]) -> Double {
        ranges.first { $0.kind == item.kind && $0.contains(item.duration) }?.shade ?? 0.6
    }
}
