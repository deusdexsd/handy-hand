import Foundation

public enum PanelMode: String, Codable, CaseIterable, Sendable {
    case hover, followApp, pinned
    public var label: String {
        switch self { case .hover: "Po najechaniu"; case .followApp: "Podążaj za aplikacją"; case .pinned: "Przypięty" }
    }
}

public enum NotchPlacement: String, Codable, CaseIterable, Sendable {
    case topCenter, topLeft, topRight, bottomCenter
    public var label: String {
        switch self { case .topCenter: "Góra, środek (przy notchu)"; case .topLeft: "Góra, lewy róg"
        case .topRight: "Góra, prawy róg"; case .bottomCenter: "Dół, środek" }
    }
}

/// Kiedy rysować własną czarną "wysepkę" udającą notch.
public enum VirtualNotchMode: String, Codable, CaseIterable, Sendable {
    case auto, always, never
    public var label: String {
        switch self { case .auto: "Tylko bez prawdziwego notcha"; case .always: "Zawsze"; case .never: "Nigdy" }
    }
}

/// Kolor podświetlenia notcha (z palety ikony łapki).
public enum GlowChoice: String, Codable, CaseIterable, Sendable {
    case violet, teal, blue
    public var label: String { switch self { case .violet: "Fioletowy"; case .teal: "Turkusowy"; case .blue: "Niebieski" } }
}

/// Co dzieje się przy notchu, gdy kursor się zbliża.
public enum NotchEffect: String, Codable, CaseIterable, Sendable {
    case none, glow, paw
    public var label: String { switch self { case .none: "Brak"; case .glow: "Podświetlenie"; case .paw: "Łapka" } }
    /// Nieznana wartość (np. usunięty „cat” ze starego zapisu) nie może wywalić całych ustawień.
    public init(from d: Decoder) throws { self = NotchEffect(rawValue: try d.singleValueContainer().decode(String.self)) ?? .glow }
}

public enum CategoryLayout: String, Codable, CaseIterable, Sendable {
    case sidebar, chips
    public var label: String { self == .sidebar ? "Pionowy (sidebar)" : "Poziomy (pigułki)" }
}

public enum AccentChoice: String, Codable, CaseIterable, Sendable {
    case system, graphite, blue, violet, green, orange
    public var label: String {
        switch self { case .system: "Systemowy"; case .graphite: "Grafit"; case .blue: "Niebieski"
        case .violet: "Fioletowy"; case .green: "Zielony"; case .orange: "Pomarańczowy" }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var mode: PanelMode = .hover
    public var watchedBundleIDs: [String] = ["com.apple.FinalCut"]
    public var placement: NotchPlacement = .topCenter
    public var virtualNotch: VirtualNotchMode = .auto
    public var categoryLayout: CategoryLayout = .sidebar
    public var accent: AccentChoice = .system
    public var sourceTints: Bool = false
    public var waveformScaleSeconds: Double = 5
    public var expandedWidth: Double = 720
    public var expandedHeight: Double = 460
    public var autoplayOnSelect: Bool = true
    public var hideDuplicates: Bool = true
    public var waveformAutoScale: Bool = true
    /// Większy podgląd obrazów i wideo w pasku na dole panelu (domyślnie wyłączony: jak wcześniej).
    public var bigMediaPreview: Bool = false
    /// Klawisze 1-4: jaki typ pokazują (filtr w bieżącej kategorii).
    public var quickKeys: [MediaClass] = [.sfx, .music, .video, .image]
    public var notchGlow: Bool = true      // zastąpione przez notchEffect (zostaje dla wczytania starych zapisów)
    public var notchEffect: NotchEffect = .glow
    public var glowColor: GlowChoice = .violet
    public var strictDuplicates: Bool = false
    public init() {}

    enum CodingKeys: String, CodingKey { case autoplayOnSelect, waveformAutoScale, bigMediaPreview, quickKeys, notchGlow, notchEffect, glowColor, hideDuplicates, strictDuplicates, mode, watchedBundleIDs, placement, virtualNotch, categoryLayout, accent, sourceTints, waveformScaleSeconds, expandedWidth, expandedHeight }
    /// Tolerancyjne dekodowanie: brakujący klucz (np. po aktualizacji) = wartość domyślna, a nie utrata ustawień.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = AppSettings()
        mode = try c.decodeIfPresent(PanelMode.self, forKey: .mode) ?? def.mode
        watchedBundleIDs = try c.decodeIfPresent([String].self, forKey: .watchedBundleIDs) ?? def.watchedBundleIDs
        placement = try c.decodeIfPresent(NotchPlacement.self, forKey: .placement) ?? def.placement
        virtualNotch = try c.decodeIfPresent(VirtualNotchMode.self, forKey: .virtualNotch) ?? def.virtualNotch
        categoryLayout = try c.decodeIfPresent(CategoryLayout.self, forKey: .categoryLayout) ?? def.categoryLayout
        accent = try c.decodeIfPresent(AccentChoice.self, forKey: .accent) ?? def.accent
        sourceTints = try c.decodeIfPresent(Bool.self, forKey: .sourceTints) ?? def.sourceTints
        waveformScaleSeconds = try c.decodeIfPresent(Double.self, forKey: .waveformScaleSeconds) ?? def.waveformScaleSeconds
        expandedWidth = try c.decodeIfPresent(Double.self, forKey: .expandedWidth) ?? def.expandedWidth
        expandedHeight = try c.decodeIfPresent(Double.self, forKey: .expandedHeight) ?? def.expandedHeight
        autoplayOnSelect = try c.decodeIfPresent(Bool.self, forKey: .autoplayOnSelect) ?? def.autoplayOnSelect
        hideDuplicates = try c.decodeIfPresent(Bool.self, forKey: .hideDuplicates) ?? def.hideDuplicates
        waveformAutoScale = try c.decodeIfPresent(Bool.self, forKey: .waveformAutoScale) ?? def.waveformAutoScale
        bigMediaPreview = try c.decodeIfPresent(Bool.self, forKey: .bigMediaPreview) ?? def.bigMediaPreview
        let qk = try c.decodeIfPresent([MediaClass].self, forKey: .quickKeys) ?? def.quickKeys
        quickKeys = qk.count == 4 ? qk : def.quickKeys
        notchGlow = try c.decodeIfPresent(Bool.self, forKey: .notchGlow) ?? def.notchGlow
        notchEffect = try c.decodeIfPresent(NotchEffect.self, forKey: .notchEffect) ?? (notchGlow ? .glow : .none)
        glowColor = try c.decodeIfPresent(GlowChoice.self, forKey: .glowColor) ?? def.glowColor
        strictDuplicates = try c.decodeIfPresent(Bool.self, forKey: .strictDuplicates) ?? def.strictDuplicates
    }
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
