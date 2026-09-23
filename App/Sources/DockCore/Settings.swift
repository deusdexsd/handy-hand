import Foundation

/// Język etykiet w DockCore (Ustawienia → Ogólne → Język ustawia to z poziomu aplikacji).
public enum UILanguage { public static var current: AppLanguage = .pl }
func LL(_ pl: String, _ en: String) -> String { UILanguage.current == .en ? en : pl }

public enum PanelMode: String, Codable, CaseIterable, Sendable {
    case hover, followApp, pinned
    public var label: String {
        switch self { case .hover: LL("Po najechaniu", "On hover"); case .followApp: LL("Podążaj za aplikacją", "Follow app"); case .pinned: LL("Przypięty", "Pinned") }
    }
}

public enum NotchPlacement: String, Codable, CaseIterable, Sendable {
    case topCenter, rightMiddle, leftMiddle
    public var label: String {
        switch self { case .topCenter: LL("Notch (góra, środek)", "Notch (top center)"); case .rightMiddle: LL("Prawa krawędź", "Right edge"); case .leftMiddle: LL("Lewa krawędź", "Left edge") }
    }
    public var isSide: Bool { self != .topCenter }
    /// Stare zapisy (rogi, dół) nie mogą wywalić ustawień: rogi -> najbliższa krawędź, dół -> notch.
    public init(from d: Decoder) throws {
        switch try d.singleValueContainer().decode(String.self) {
        case "rightMiddle", "topRight": self = .rightMiddle
        case "leftMiddle", "topLeft": self = .leftMiddle
        default: self = .topCenter
        }
    }
}

/// Kiedy rysować własną czarną "wysepkę" udającą notch.
public enum VirtualNotchMode: String, Codable, CaseIterable, Sendable {
    case auto, always, never
    public var label: String {
        switch self { case .auto: LL("Tylko bez prawdziwego notcha", "Only without a real notch"); case .always: LL("Zawsze", "Always"); case .never: LL("Nigdy", "Never") }
    }
}

public enum AppLanguage: String, Codable, CaseIterable, Sendable { case pl, en }

/// Co dzieje się przy notchu, gdy kursor się zbliża. Podświetlenie było i zostało zdjęte na życzenie Davida
/// ("działało niebo lepiej wcześniej" — jego słowa); zostaje tylko łapka albo nic.
public enum NotchEffect: String, Codable, CaseIterable, Sendable {
    case none, paw
    public var label: String { switch self { case .none: LL("Brak", "None"); case .paw: LL("Łapka", "Paw") } }
    /// Nieznana wartość (usunięte „glow”/„cat” ze starych zapisów) nie może wywalić całych ustawień — ląduje na łapce.
    public init(from d: Decoder) throws { self = NotchEffect(rawValue: try d.singleValueContainer().decode(String.self)) ?? .paw }
}

public enum CategoryLayout: String, Codable, CaseIterable, Sendable {
    case sidebar, chips
    public var label: String { self == .sidebar ? LL("Pionowy (sidebar)", "Vertical (sidebar)") : LL("Poziomy (pigułki)", "Horizontal (pills)") }
}

public enum AccentChoice: String, Codable, CaseIterable, Sendable {
    case system, graphite, blue, violet, green, orange
    public var label: String {
        switch self { case .system: LL("Systemowy", "System"); case .graphite: LL("Grafit", "Graphite"); case .blue: LL("Niebieski", "Blue")
        case .violet: LL("Fioletowy", "Violet"); case .green: LL("Zielony", "Green"); case .orange: LL("Pomarańczowy", "Orange") }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var mode: PanelMode = .hover
    public var watchedBundleIDs: [String] = ["com.apple.FinalCut"]
    public var placement: NotchPlacement = .topCenter
    /// Położenie uchwytu na bocznej krawędzi: 0 = góra ekranu, 1 = dół.
    public var sidePosition: Double = 0.5
    public var virtualNotch: VirtualNotchMode = .auto
    public var categoryLayout: CategoryLayout = .sidebar
    /// Pasek kategorii (Ulubione/Typ/Foldery/Kolekcje) całkiem schowany — ikonka w toolbarze, reszta panelu zostaje.
    public var sidebarHidden: Bool = false
    /// Widok minimalistyczny bez nazw przy dźwiękach (obrazy i wideo i tak nie mają podpisów).
    public var minimalistHideAudioNames: Bool = true
    /// Rozmiar elementów we wszystkich widokach (suwak): 0.6…1.8, 1 = domyślny.
    public var tileScale: Double = 1
    /// Kolejność ikon w toolbarze (przeciąganie z ⌘). Puste/nieznane wpisy uzupełnia widok.
    public var toolbarOrder: [String] = ToolbarItemID.defaultOrder
    public var accent: AccentChoice = .system
    public var sourceTints: Bool = false
    public var waveformScaleSeconds: Double = 5
    public var expandedWidth: Double = 720
    public var expandedHeight: Double = 460
    public var autoplayOnSelect: Bool = true
    /// Zwinięcie panelu (kursor całkiem odjeżdża) zatrzymuje odtwarzanie. Wyłącz, żeby grało dalej w tle.
    public var stopPlaybackOnCollapse: Bool = true
    public var hideDuplicates: Bool = true
    public var waveformAutoScale: Bool = true
    /// Większy podgląd obrazów i wideo w pasku na dole panelu (domyślnie wyłączony: jak wcześniej).
    public var bigMediaPreview: Bool = false
    /// Klawisze 1-4: jaki typ pokazują (filtr w bieżącej kategorii).
    public var quickKeys: [MediaClass] = [.sfx, .music, .video, .image]
    public var notchEffect: NotchEffect = .none     // bazowo bez żadnego efektu (David: łapka ma nie rzucać się w oczy domyślnie)
    public var strictDuplicates: Bool = false
    /// Globalny skrót pokazujący/chowający panel bez najeżdżania kursorem (nil = wyłączony).
    public var toggleHotkey: HotKeySpec? {
        get { hotkeyOff ? nil : hotkeySpec }
        set { if let v = newValue { hotkeySpec = v; hotkeyOff = false } else { hotkeyOff = true } }
    }
    var hotkeySpec: HotKeySpec = .defaultToggle      // zapisane osobno, żeby „wyłączony” przetrwał zapis (nil w JSON znika)
    var hotkeyOff = false
    /// Klawisz cyfrowy w panelu: „Pokaż w Finderze” dla zaznaczonych (7, 8, 9 albo 0; -1 = wyłączony).
    public var finderKey: Int = 9
    /// Język interfejsu.
    public var language: AppLanguage = .pl
    /// Ulubione zawsze na górze listy, niezależnie od sortowania i kategorii (gwiazdka w toolbarze).
    public var favoritesFirst: Bool = false
    /// Szukanie sprawdza też tagi, rozszerzenie pliku i wydarzenie FCP (nie tylko nazwę).
    public var searchMetadata: Bool = false
    public init() {}

    enum CodingKeys: String, CodingKey { case hotkeySpec, hotkeyOff, finderKey, language, favoritesFirst, searchMetadata, sidePosition, autoplayOnSelect, stopPlaybackOnCollapse, waveformAutoScale, bigMediaPreview, quickKeys, notchEffect, hideDuplicates, strictDuplicates, mode, watchedBundleIDs, placement, virtualNotch, categoryLayout, sidebarHidden, minimalistHideAudioNames, tileScale, toolbarOrder, accent, sourceTints, waveformScaleSeconds, expandedWidth, expandedHeight }
    /// Tolerancyjne dekodowanie: brakujący klucz (np. po aktualizacji) = wartość domyślna, a nie utrata ustawień.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = AppSettings()
        mode = try c.decodeIfPresent(PanelMode.self, forKey: .mode) ?? def.mode
        watchedBundleIDs = try c.decodeIfPresent([String].self, forKey: .watchedBundleIDs) ?? def.watchedBundleIDs
        placement = try c.decodeIfPresent(NotchPlacement.self, forKey: .placement) ?? def.placement
        sidePosition = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .sidePosition) ?? def.sidePosition))
        virtualNotch = try c.decodeIfPresent(VirtualNotchMode.self, forKey: .virtualNotch) ?? def.virtualNotch
        categoryLayout = try c.decodeIfPresent(CategoryLayout.self, forKey: .categoryLayout) ?? def.categoryLayout
        sidebarHidden = try c.decodeIfPresent(Bool.self, forKey: .sidebarHidden) ?? def.sidebarHidden
        minimalistHideAudioNames = try c.decodeIfPresent(Bool.self, forKey: .minimalistHideAudioNames) ?? def.minimalistHideAudioNames
        tileScale = min(1.8, max(0.6, try c.decodeIfPresent(Double.self, forKey: .tileScale) ?? def.tileScale))
        toolbarOrder = ToolbarItemID.sanitized(try c.decodeIfPresent([String].self, forKey: .toolbarOrder) ?? def.toolbarOrder)
        accent = try c.decodeIfPresent(AccentChoice.self, forKey: .accent) ?? def.accent
        sourceTints = try c.decodeIfPresent(Bool.self, forKey: .sourceTints) ?? def.sourceTints
        waveformScaleSeconds = try c.decodeIfPresent(Double.self, forKey: .waveformScaleSeconds) ?? def.waveformScaleSeconds
        expandedWidth = try c.decodeIfPresent(Double.self, forKey: .expandedWidth) ?? def.expandedWidth
        expandedHeight = try c.decodeIfPresent(Double.self, forKey: .expandedHeight) ?? def.expandedHeight
        autoplayOnSelect = try c.decodeIfPresent(Bool.self, forKey: .autoplayOnSelect) ?? def.autoplayOnSelect
        stopPlaybackOnCollapse = try c.decodeIfPresent(Bool.self, forKey: .stopPlaybackOnCollapse) ?? def.stopPlaybackOnCollapse
        hideDuplicates = try c.decodeIfPresent(Bool.self, forKey: .hideDuplicates) ?? def.hideDuplicates
        waveformAutoScale = try c.decodeIfPresent(Bool.self, forKey: .waveformAutoScale) ?? def.waveformAutoScale
        bigMediaPreview = try c.decodeIfPresent(Bool.self, forKey: .bigMediaPreview) ?? def.bigMediaPreview
        let qk = try c.decodeIfPresent([MediaClass].self, forKey: .quickKeys) ?? def.quickKeys
        quickKeys = qk.count == 4 ? qk : def.quickKeys
        notchEffect = try c.decodeIfPresent(NotchEffect.self, forKey: .notchEffect) ?? def.notchEffect
        strictDuplicates = try c.decodeIfPresent(Bool.self, forKey: .strictDuplicates) ?? def.strictDuplicates
        hotkeySpec = try c.decodeIfPresent(HotKeySpec.self, forKey: .hotkeySpec) ?? def.hotkeySpec
        hotkeyOff = try c.decodeIfPresent(Bool.self, forKey: .hotkeyOff) ?? def.hotkeyOff
        let fk = try c.decodeIfPresent(Int.self, forKey: .finderKey) ?? def.finderKey
        finderKey = [7, 8, 9, 0, -1].contains(fk) ? fk : def.finderKey
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? def.language
        favoritesFirst = try c.decodeIfPresent(Bool.self, forKey: .favoritesFirst) ?? def.favoritesFirst
        searchMetadata = try c.decodeIfPresent(Bool.self, forKey: .searchMetadata) ?? def.searchMetadata
    }
}

/// Globalny skrót klawiszowy (kod klawisza + modyfikatory w formacie Carbon: cmd 256, shift 512, option 2048, control 4096).
public struct HotKeySpec: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    public static let cmd: UInt32 = 256, shift: UInt32 = 512, option: UInt32 = 2048, control: UInt32 = 4096
    /// Domyślny: ⌃⌥⌘L (trzy modyfikatory, mało prawdopodobne, że coś koliduje).
    public static let defaultToggle = HotKeySpec(keyCode: 37, modifiers: control | option | cmd)
}

public struct UserData: Codable, Equatable, Sendable {
    public var settings = AppSettings()
    public var sources: [Source] = []
    public var org = Organization()
    public var lastConfig = ViewConfig()
    public var schemaVersion = 3
    public init() {}

    enum CodingKeys: String, CodingKey { case settings, sources, org, lastConfig, schemaVersion }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        sources = try c.decodeIfPresent([Source].self, forKey: .sources) ?? []
        org = try c.decodeIfPresent(Organization.self, forKey: .org) ?? Organization()
        lastConfig = try c.decodeIfPresent(ViewConfig.self, forKey: .lastConfig) ?? ViewConfig()
        let v = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        if v < 2 {   // v2: audio dzieli się na SFX i muzykę; zapisane wcześniej przedziały audio stały się SFX, dokładamy przedziały muzyki
            if !org.durationRanges.contains(where: { $0.mediaClass == .music }) { org.durationRanges += DurationRange.musicDefaults() }
        }
        if v < 3 { settings.notchEffect = .paw }      // v3: łapka jako efekt domyślny (to o nią prosił David)
        schemaVersion = 3
    }
}

/// Zapis JSON w Application Support (trwałość między sesjami).
public final class UserDataStore: @unchecked Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static func defaultURL(appName: String = "MidniteDock") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(appName, isDirectory: true).appendingPathComponent("userdata.json")
    }

    public func load() -> UserData {
        guard let d = try? Data(contentsOf: url), let u = try? JSONDecoder().decode(UserData.self, from: d) else { return UserData() }
        return u
    }

    public func save(_ u: UserData) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(u) { try? d.write(to: url, options: .atomic) }
    }
}

/// Ikony toolbaru, które da się przestawiać (⌘ + przeciągnięcie). Pole wyszukiwania i tytuł kategorii zostają na stałe.
public enum ToolbarItemID {
    public static let defaultOrder = ["metadata", "filter", "sort", "favorites", "presets", "view", "pin", "settings"]
    /// Wyrzuca nieznane i zdublowane wpisy, brakujące dokłada na końcu.
    public static func sanitized(_ order: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for id in order where defaultOrder.contains(id) && seen.insert(id).inserted { out.append(id) }
        for id in defaultOrder where !seen.contains(id) { out.append(id) }
        return out
    }
}
