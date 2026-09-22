import SwiftUI
import AppKit
import AVFoundation
import DockCore

@MainActor
final class PanelState: ObservableObject {
    @Published var glow: Double = 0
    @Published var glowTint: Color?          // własny kolor podświetlenia (z Ustawień); zmiana nie przebudowuje uchwytu
    @Published var glowIntensity: Double = 1
    @Published var tipX: Double = 0        // łapka: cel dłoni względem barku (pt)
    @Published var tipY: Double = -60      // domyślnie schowana nad dolną krawędzią notcha
    @Published var shoulderX: Double = 0   // bark przesuwa się lekko w stronę kursora
    @Published var armActive = false       // symulacja liny chodzi tylko, gdy ramię jest widoczne
    let sim = ArmSim()
    @Published var expanded = false
    @Published var atBottom = false
}

struct DockRootView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var panel: PanelState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let accent = store.settings.accent.color
        VStack(spacing: 0) {
            ToolbarView(store: store)
            if store.settings.categoryLayout == .chips { ChipsBar(store: store) }
            FilterBar(store: store)
            HStack(spacing: 0) {
                if store.settings.categoryLayout == .sidebar {
                    SidebarView(store: store).frame(width: 178)
                }
                VStack(spacing: 0) {
                    ContentArea(store: store)
                    PreviewBar(store: store, previewer: store.previewer, thumbs: store.thumbnails)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)     // rozmiar dyktuje okno (rozciągane myszką)
        .background(VisualEffect(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        .overlay(alignment: .top) {
            // Ciągła, spokojna poświata przy górnej krawędzi panelu, gdy efekt notcha to Podświetlenie — żeby przejście
            // z narastającej poświaty uchwytu do rozwiniętego panelu nie urywało się nagle, tylko płynnie „się ustatkowało”.
            if store.settings.notchEffect == .glow {
                LinearGradient(colors: [PanelController.glowTint(store.settings).opacity(min(1, 0.18 * store.settings.glowIntensity)), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 64)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 16, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .overlay(ResizeGrips(store: store, atBottom: panel.atBottom))
        .environment(\.dockAccent, accent)
        .environment(\.sourceTints, store.settings.sourceTints)
        .tint(accent)
        .scaleEffect(panel.expanded ? 1 : 0.94, anchor: panel.atBottom ? .bottom : .top)
        .opacity(panel.expanded ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 1), value: panel.expanded)
        .focusable(false)
        .overlay { PromptOverlay(store: store) }
    }
}

struct ToolbarView: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dockAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            iconButton(store.settings.categoryLayout == .sidebar ? "sidebar.left" : "rectangle.split.3x1", L("Układ kategorii", "Category layout")) {
                store.settings.categoryLayout = store.settings.categoryLayout == .sidebar ? .chips : .sidebar
            }
            Text(store.categoryTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1).frame(minWidth: 70, alignment: .leading)
            SearchField(text: $store.search, placeholder: L("Szukaj w: \(store.categoryTitle)", "Search in: \(store.categoryTitle)"))
            iconButton(store.settings.searchMetadata ? "tag.fill" : "tag",
                       L("Szukaj też w tagach, rozszerzeniu i wydarzeniu FCP (nie tylko w nazwie)", "Also search tags, extension and FCP event (not just the name)"),
                       active: store.settings.searchMetadata) { store.settings.searchMetadata.toggle() }
            FilterMenu(store: store)
            SortMenu(store: store)
            iconButton(store.settings.favoritesFirst ? "star.fill" : "star",
                       L("Ulubione zawsze na górze listy", "Favorites always on top"),
                       active: store.settings.favoritesFirst) { store.settings.favoritesFirst.toggle() }
            PresetMenu(store: store)
            iconButton(store.config.viewMode == .grid ? "square.grid.2x2" : "list.bullet", L("Przełącz siatkę i listę", "Toggle grid and list")) {
                store.config.viewMode = store.config.viewMode == .grid ? .list : .grid
            }
            iconButton(store.settings.mode == .pinned ? "pin.fill" : "pin", L("Przypnij panel", "Pin panel"), active: store.settings.mode == .pinned) {
                store.settings.mode = store.settings.mode == .pinned ? .hover : .pinned
            }
            iconButton("gearshape", L("Ustawienia", "Settings")) { store.openSettings?() }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    func iconButton(_ symbol: String, _ label: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 26, height: 26)
                .foregroundStyle(active ? accent : Color.secondary).contentShape(Rectangle())
        }
        .buttonStyle(PressableIconStyle())
        .accessibilityLabel(label).help(label)
    }
}

struct PressableIconStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 1), value: configuration.isPressed)
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).accessibilityLabel(L("Wyczyść wyszukiwanie", "Clear search"))
            }
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
    }
}

struct FilterMenu: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        let f = store.config.filters
        Menu {
            Picker(L("Typ", "Type"), selection: Binding(get: { f.klass }, set: { store.config.filters.klass = $0 })) {
                Text(L("Wszystkie typy", "All types")).tag(MediaClass?.none)
                ForEach(MediaClass.allCases, id: \.self) { Text($0.label).tag(MediaClass?.some($0)) }
            }
            Picker(L("Długość", "Length"), selection: Binding(get: { f.durationRangeID }, set: { store.config.filters.durationRangeID = $0 })) {
                Text(L("Dowolna długość", "Any length")).tag(UUID?.none)
                ForEach(store.org.durationRanges) { Text("\($0.mediaClass.label) · \($0.name)").tag(UUID?.some($0.id)) }
            }
            Picker(L("Data", "Date"), selection: Binding(get: { f.withinDays }, set: { store.config.filters.withinDays = $0 })) {
                Text(L("Dowolna data", "Any date")).tag(Int?.none)
                Text(L("Ostatnie 7 dni", "Last 7 days")).tag(Int?.some(7)); Text(L("Ostatnie 30 dni", "Last 30 days")).tag(Int?.some(30))
            }
            if !store.org.allTags.isEmpty {
                Picker(L("Tag", "Tag"), selection: Binding(get: { f.tag }, set: { store.config.filters.tag = $0 })) {
                    Text(L("Dowolny tag", "Any tag")).tag(String?.none)
                    ForEach(store.org.allTags, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            if f.isActive { Divider(); Button(L("Wyczyść filtry", "Clear filters")) { store.config.filters = .none } }
        } label: {
            Image(systemName: f.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 13)).foregroundStyle(f.isActive ? store.settings.accent.color : Color.secondary).frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(L("Filtry", "Filters"))
    }
}

struct SortMenu: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        Menu {
            Picker(L("Sortuj", "Sort"), selection: Binding(get: { store.config.sort }, set: { store.config.sort = $0 })) {
                ForEach(SortKey.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Divider()
            Toggle(L("Rosnąco", "Ascending"), isOn: Binding(get: { store.config.ascending }, set: { store.config.ascending = $0 }))
        } label: {
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(L("Sortowanie", "Sorting"))
    }
}

struct PresetMenu: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        Menu {
            if store.org.presets.isEmpty {
                Text(L("Zakładka to nazwany widok — kategoria, filtry, sortowanie i siatka/lista — do którego wracasz jednym kliknięciem.",
                       "A bookmark is a named view — category, filters, sorting and grid/list — you can jump back to in one click."))
            } else {
                ForEach(store.org.presets) { p in Button(p.name) { store.apply(p) } }
                Divider()
            }
            Button(L("Zapisz jako zakładkę…", "Save as bookmark…")) {
                store.ask(L("Nowa zakładka", "New bookmark"),
                          message: L("Zapamiętuje kategorię, filtry, sortowanie i widok pod tą nazwą, żebyś mógł tu wrócić jednym kliknięciem.",
                                     "Remembers the category, filters, sorting and view under this name, so you can jump back with one click."),
                          placeholder: L("Nazwa zakładki", "Bookmark name"), action: L("Zapisz", "Save")) { store.savePreset(name: $0) }
            }
            if !store.org.presets.isEmpty {
                Menu(L("Usuń zakładkę", "Delete bookmark")) { ForEach(store.org.presets) { p in Button(p.name, role: .destructive) { store.deletePreset(p.id) } } }
            }
        } label: {
            Image(systemName: "bookmark").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(L("Zakładki", "Bookmarks"))
        .help(L("Zakładki: nazwane widoki do jednego kliknięcia.", "Bookmarks: named views, one click away."))
    }
}

struct FilterBar: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        let f = store.config.filters
        if f.isActive {
            HStack(spacing: 6) {
                if let k = f.kind { chip(k.label) { store.config.filters.kind = nil } }
                if let c = f.klass { chip(c.label) { store.config.filters.klass = nil } }
                if let r = f.durationRangeID.flatMap({ id in store.org.durationRanges.first { $0.id == id } }) { chip(r.name) { store.config.filters.durationRangeID = nil } }
                if let d = f.withinDays { chip(L("Ostatnie \(d) dni", "Last \(d) days")) { store.config.filters.withinDays = nil } }
                if let t = f.tag { chip("#\(t)") { store.config.filters.tag = nil } }
                Button(L("Wyczyść", "Clear")) { store.config.filters = .none }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
    }
    func chip(_ t: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 3) { Text(t); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                .font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(store.settings.accent.color.opacity(0.18)))
        }.buttonStyle(.plain).accessibilityLabel(L("Usuń filtr \(t)", "Remove filter \(t)"))
    }
}

struct ChipsBar: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.sidebar.flatMap(\.entries)) { e in
                    let sel = store.config.category == e.category
                    Button { store.select(category: e.category) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: e.icon).font(.system(size: 10))
                            Text(e.chipTitle ?? e.title).font(.system(size: 11.5))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(sel ? store.settings.accent.color : Color.primary.opacity(0.08)))
                        .foregroundStyle(sel ? Color.white : Color.primary)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}

struct SidebarView: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.sourceTints) private var tints
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.sidebar) { sec in
                    if let t = sec.title {
                        HStack {
                            Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                            Spacer()
                            if sec.canAdd {
                                if sec.id == "folders" {
                                    Menu { AddMenuItems(store: store) } label: { Image(systemName: "plus").font(.system(size: 10, weight: .semibold)) }
                                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary).accessibilityLabel(L("Dodaj folder, pliki lub bibliotekę", "Add a folder, files, or a library"))
                                } else {
                                    Button { add(sec.id) } label: { Image(systemName: "plus").font(.system(size: 10, weight: .semibold)) }
                                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(L("Dodaj: \(t)", "Add: \(t)"))
                                }
                            }
                        }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 3)
                    }
                    ForEach(sec.entries) { e in
                        row(e, indent: 0)
                        if !e.children.isEmpty && expanded.contains(e.id) { ForEach(e.children) { row($0, indent: 14) } }
                    }
                }
            }.padding(.horizontal, 6).padding(.vertical, 8)
        }
        .background(Color.primary.opacity(0.045))
    }

    func tint(_ t: SourceTint) -> Color {
        guard tints else { return t == .favorite ? .yellow.opacity(0.9) : .secondary }
        switch t { case .folder: return Color(nsColor: .systemBlue).opacity(0.7); case .fcp: return Color(nsColor: .systemPurple).opacity(0.7); case .collection: return Color(nsColor: .systemTeal).opacity(0.7); case .smart: return Color(nsColor: .systemOrange).opacity(0.65); case .favorite: return .yellow.opacity(0.9); case .none: return .secondary }
    }

    func row(_ e: SidebarEntry, indent: CGFloat) -> some View {
        let sel = store.config.category == e.category
        return HStack(spacing: 7) {
            if !e.children.isEmpty {
                Image(systemName: expanded.contains(e.id) ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary).frame(width: 8)
                    .onTapGesture { if expanded.contains(e.id) { expanded.remove(e.id) } else { expanded.insert(e.id) } }
            } else if indent == 0 { Color.clear.frame(width: 8) }
            Image(systemName: e.icon).font(.system(size: 12)).foregroundStyle(tint(e.tint)).frame(width: 16)
            Text(e.title).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 2)
            Text("\(e.count)").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.tertiary)
        }
        .padding(.leading, 6 + indent).padding(.trailing, 6).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(sel ? 0.13 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { store.select(category: e.category) }
        .dropDestination(for: URL.self) { urls, _ in
            guard let cid = e.collectionID else { return false }
            store.add(urls.map { PathUtil.canonical($0.path) }.filter { store.item($0) != nil }, toCollection: cid); return true
        }
        .contextMenu {
            if let cid = e.collectionID {
                Button(L("Zmień nazwę…", "Rename…")) { store.ask(L("Zmień nazwę", "Rename"), placeholder: L("Nazwa", "Name"), initial: e.title, action: L("Zapisz", "Save")) { store.renameCollection(cid, to: $0) } }
                Button(L("Usuń kolekcję", "Delete collection"), role: .destructive) { store.deleteCollection(cid) }
            }
            if case .source(let sid) = e.category {
                Button(L("Odśwież", "Refresh")) { store.reindexAll() }
                Button(L("Usuń źródło", "Remove source"), role: .destructive) { store.removeSource(sid) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.title), \(e.count)")
        .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
    }

    func add(_ section: String) {
        switch section {
        case "coll": store.ask(L("Nowa kolekcja", "New collection"), placeholder: L("Nazwa kolekcji", "Collection name"), action: L("Utwórz", "Create")) { store.newCollection(name: $0) }
        default: break
        }
    }
}

enum Pickers {
    @MainActor static func pickFolder(title: String, _ done: @escaping (URL) -> Void) {
        let p = NSOpenPanel()
        p.title = title; p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false; p.prompt = L("Wybierz", "Choose")
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK, let u = p.url { done(u) }
    }

    @MainActor static func pickFiles(_ done: @escaping ([URL]) -> Void) {
        let p = NSOpenPanel()
        p.title = L("Wybierz pliki (dźwięk, wideo, obrazy)", "Choose files (audio, video, images)"); p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = true
        p.allowedContentTypes = [.audio, .movie, .image]; p.prompt = L("Dodaj", "Add")
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK { done(p.urls) }
    }

    @MainActor static func pickLibrary(_ done: @escaping (URL) -> Void) {
        let p = NSOpenPanel()
        p.title = L("Wybierz bibliotekę Final Cut Pro (.fcpbundle)", "Choose a Final Cut Pro library (.fcpbundle)")
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = false; p.treatsFilePackagesAsDirectories = false
        p.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK, let u = p.url { done(u) }
    }
}

/// Jedno menu "Dodaj" używane w sidebarze, pustym stanie i ustawieniach.
struct AddMenuItems: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        Button(L("Dodaj folder…", "Add folder…")) { Pickers.pickFolder(title: L("Wybierz folder z dźwiękami, materiałem lub obrazami", "Choose a folder with sounds, footage or images")) { store.addSource(url: $0, kind: .folder) } }
        Button(L("Dodaj pliki…", "Add files…")) { Pickers.pickFiles { store.addFiles($0) } }
        Button(L("Dodaj bibliotekę FCP…", "Add FCP library…")) { Pickers.pickLibrary { store.addSource(url: $0, kind: $0.pathExtension.lowercased() == "fcpbundle" ? .fcpLibrary : .folder) } }
    }
}


/// Okno pytania i komunikatu wewnątrz panelu (zamiast systemowego alertu, który w panelu bez aktywacji bywa kapryśny).
struct PromptOverlay: View {
    @ObservedObject var store: LibraryStore
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dockAccent) private var accent

    var body: some View {
        ZStack {
            if let p = store.prompt {
                card {
                    Text(p.title).font(.system(size: 13, weight: .semibold))
                    if !p.message.isEmpty { Text(p.message).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    TextField(p.placeholder, text: $text).textFieldStyle(.roundedBorder).focused($focused).onSubmit { confirm(p) }
                    HStack {
                        Spacer()
                        Button(L("Anuluj", "Cancel")) { store.prompt = nil }.keyboardShortcut(.cancelAction)
                        Button(p.action) { confirm(p) }.keyboardShortcut(.defaultAction)
                    }
                }
                .id(p.id)
                .onAppear { text = p.initial; focused = true; selectAllSoon() }
            } else if let n = store.notice {
                card {
                    Text(L("Uwaga", "Note")).font(.system(size: 13, weight: .semibold))
                    Text(n).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack { Spacer(); Button("OK") { store.notice = nil }.keyboardShortcut(.defaultAction) }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.prompt?.id)
        .animation(.easeOut(duration: 0.15), value: store.notice)
    }

    private func confirm(_ p: PromptRequest) { let t = text; store.prompt = nil; p.onConfirm(t) }

    /// Jak w Finderze przy zmianie nazwy: tekst zaznaczony, gotowy do nadpisania.
    private func selectAllSoon() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil) } }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ZStack {
            Color.black.opacity(0.35).onTapGesture { store.prompt = nil; store.notice = nil }
            VStack(alignment: .leading, spacing: 10, content: content)
                .padding(16).frame(width: 360)
                .background(VisualEffect(material: .popover).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
        .transition(.opacity)
    }
}
