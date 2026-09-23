import Foundation
import AppKit
import SwiftUI
import DockCore

enum SourceTint { case none, folder, fcp, collection, smart, favorite }

struct SidebarEntry: Identifiable {
    var id: String
    var category: CategoryID
    var title: String
    var icon: String
    var tint: SourceTint
    var count: Int
    var chipTitle: String?
    var children: [SidebarEntry] = []
    var collectionID: UUID?
}

struct SidebarSection: Identifiable {
    var id: String
    var title: String?
    var entries: [SidebarEntry]
    var canAdd = false
}

struct PromptRequest: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var placeholder: String
    var initial = ""
    var action: String
    var onConfirm: (String) -> Void
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var data: UserData { didSet { dataVersion += 1; scheduleSave(); Lang.current = data.settings.language } }
    @Published private(set) var items: [MediaItem] = [] { didSet { itemsVersion += 1 } }
    @Published var search = ""
    @Published var selection: Set<String> = []
    @Published var primary: MediaItem?
    @Published var isIndexing = false
    @Published var dragging = false
    @Published var prompt: PromptRequest?
    @Published var lastError: String?
    @Published var notice: String?
    @Published var scrollTarget: String?
    var gridColumns = 3

    let waveforms = WaveformStore()
    let thumbnails = ThumbnailStore()
    let previewer = Previewer()
    var openSettings: (() -> Void)?

    private let userStore: UserDataStore
    private let indexURL: URL
    private let indexer = Indexer()
    private var watcher: FolderWatcher?
    private var saveTask: Task<Void, Never>?
    private var rescanTask: Task<Void, Never>?
    private var dataVersion = 0
    private var itemsVersion = 0
    private var dupMemo: (key: [Int], value: DuplicateIndex)?
    private var visibleMemo: (key: [Int], value: [MediaItem])?
    private var sidebarMemo: (key: [Int], value: [SidebarSection])?
    private var anchorPath: String?
    private var scaleMemo: (key: [Int], value: [MediaClass: Double])?

    init(dir: URL = AppInfo.dataDir) {
        userStore = UserDataStore(url: dir.appendingPathComponent("userdata.json"))
        indexURL = dir.appendingPathComponent("index.json")
        data = userStore.load()
        Lang.current = data.settings.language
        if let d = try? Data(contentsOf: indexURL), let cached = try? JSONDecoder().decode([MediaItem].self, from: d) { items = cached }
        restartWatcher()
        reindexAll()
    }

    // MARK: skróty do danych
    var settings: AppSettings { get { data.settings } set { data.settings = newValue } }
    var org: Organization { get { data.org } set { data.org = newValue } }
    var config: ViewConfig { get { data.lastConfig } set { data.lastConfig = newValue } }
    var sources: [Source] { data.sources }

    /// Indeks duplikatów; pusty, gdy ukrywanie duplikatów jest wyłączone (wtedy każda kopia żyje osobno).
    var dups: DuplicateIndex {
        guard settings.hideDuplicates else { return .empty }
        let key = [itemsVersion, settings.strictDuplicates ? 1 : 0]
        if let m = dupMemo, m.key == key { return m.value }
        let v = DuplicateIndex.build(items, strict: settings.strictDuplicates)
        dupMemo = (key, v)
        return v
    }

    private var sourceOrder: [UUID] { sources.map(\.id) }
    func copies(_ i: MediaItem) -> Int { dups.copies(of: i.path) }
    /// Wszystkie ścieżki tego samego pliku (gdy duplikaty są zwijane), inaczej tylko on sam.
    func equivalents(_ paths: [String]) -> [String] {
        guard settings.hideDuplicates else { return paths }
        let d = dups
        return Array(Set(paths.flatMap { d.equivalents(of: $0) }))
    }
    func duplicateItems(of i: MediaItem) -> [MediaItem] { dups.equivalents(of: i.path).compactMap { item($0) } }
    var hiddenDuplicateCount: Int {
        guard settings.hideDuplicates else { return 0 }
        return items.count - LibraryQuery.count(items, category: .all, org: org, dups: dups, hideDuplicates: true, sourceOrder: sourceOrder)
    }

    var visible: [MediaItem] {
        let key = [dataVersion, itemsVersion, search.hashValue]
        if let m = visibleMemo, m.key == key { return m.value }
        let v = LibraryQuery.apply(items, config: config, search: search, org: org, dups: dups,
                                   hideDuplicates: settings.hideDuplicates, sourceOrder: sourceOrder, favoritesFirst: settings.favoritesFirst,
                                   searchMetadata: settings.searchMetadata)
        visibleMemo = (key, v)
        return v
    }

    /// Skala czasu waveformu: pełna szerokość kafla = najdłuższy dźwięk tej klasy (SFX lub muzyka) w bieżącym widoku.
    func waveformScale(for i: MediaItem) -> Double {
        if !settings.waveformAutoScale { return settings.waveformScaleSeconds }
        let key = [dataVersion, itemsVersion, search.hashValue]
        if scaleMemo?.key != key {
            var d: [MediaClass: Double] = [:]
            for it in visible where it.kind == .audio { let c = mediaClass(it); d[c] = max(d[c] ?? 0, it.duration) }
            scaleMemo = (key, d)
        }
        return max(2, scaleMemo?.value[mediaClass(i)] ?? i.duration)
    }

    /// Prompt lub komunikat otwarty albo przeciąganie w toku: panel nie może się zwinąć.
    var holdsPanelOpen: Bool { dragging || prompt != nil || notice != nil }

    func item(_ path: String) -> MediaItem? { items.first { $0.path == path } }
    func isFavorite(_ i: MediaItem) -> Bool { equivalents([i.path]).contains { org.favorites.contains($0) } }
    func shade(_ i: MediaItem) -> Double { LibraryQuery.shade(for: i, org: org) }
    func mediaClass(_ i: MediaItem) -> MediaClass { org.mediaClass(of: i) }

    var categoryTitle: String {
        func find(_ es: [SidebarEntry]) -> String? {
            for e in es { if e.category == config.category { return e.title }; if let c = find(e.children) { return c } }
            return nil
        }
        return find(sidebar.flatMap(\.entries)) ?? L("Wszystko", "All")
    }

    // MARK: sidebar
    var sidebar: [SidebarSection] {
        let key = [dataVersion, itemsVersion]
        if let m = sidebarMemo, m.key == key { return m.value }
        let v = buildSidebar()
        sidebarMemo = (key, v)
        return v
    }

    private func count(_ c: CategoryID) -> Int {
        LibraryQuery.count(items, category: c, org: org, dups: dups, hideDuplicates: settings.hideDuplicates, sourceOrder: sourceOrder)
    }

    private func buildSidebar() -> [SidebarSection] {
        func e(_ c: CategoryID, _ id: String, _ t: String, _ icon: String, _ tint: SourceTint, children: [SidebarEntry] = [], coll: UUID? = nil) -> SidebarEntry {
            SidebarEntry(id: id, category: c, title: t, icon: icon, tint: tint, count: count(c), children: children, collectionID: coll)
        }
        var out: [SidebarSection] = [SidebarSection(id: "top", title: nil, entries: [
            e(.favorites, "fav", L("Ulubione", "Favorites"), "star", .favorite), e(.all, "all", L("Wszystko", "All"), "square.stack", .none)])]
        let classIcons: [MediaClass: String] = [.sfx: "waveform", .music: "music.note", .video: "film", .image: "photo"]
        out.append(SidebarSection(id: "kind", title: L("Typ", "Type"), entries: MediaClass.allCases.map { e(.klass($0), "t\($0.rawValue)", $0.label, classIcons[$0]!, .smart) }))
        func sourceEntry(_ s: Source) -> SidebarEntry {
            let groups = Set(items.filter { $0.sourceID == s.id }.compactMap(\.group)).sorted()
            let icon = s.kind == .fcpLibrary ? "film.stack" : (s.kind == .files ? "doc.on.doc" : "folder")
            return e(.source(s.id), "s\(s.id)", s.name, icon, s.kind == .fcpLibrary ? .fcp : .folder,
                     children: groups.map { e(.group(s.id, $0), "g\(s.id)\($0)", $0, "folder", s.kind == .fcpLibrary ? .fcp : .folder) })
        }
        out.append(SidebarSection(id: "folders", title: L("Foldery i pliki", "Folders and files"), entries: sources.filter { $0.kind != .fcpLibrary }.map(sourceEntry), canAdd: true))
        let libs = sources.filter { $0.kind == .fcpLibrary }.map(sourceEntry)
        if !libs.isEmpty { out.append(SidebarSection(id: "fcp", title: L("Biblioteki FCP", "FCP libraries"), entries: libs)) }
        out.append(SidebarSection(id: "coll", title: L("Kolekcje", "Collections"), entries: org.collections.map {
            e(.collection($0.id), "c\($0.id)", $0.name, "rectangle.stack", .collection, coll: $0.id) }, canAdd: true))
        for cls in MediaClass.allCases where cls.hasDuration {
            let rs = org.durationRanges.filter { $0.mediaClass == cls }.sorted { $0.minSeconds < $1.minSeconds }
            if rs.isEmpty { continue }
            out.append(SidebarSection(id: "dur-\(cls.rawValue)", title: L("Długość · \(cls.label)", "Length · \(cls.label)"), entries: rs.map {
                var x = e(.duration($0.id), "d\($0.id)", $0.name, classIcons[cls]!, .smart)
                x.chipTitle = "\(cls.label) · \($0.name)"; return x }))
        }
        if !org.keywordRules.isEmpty {
            out.append(SidebarSection(id: "kw", title: L("Słowa kluczowe", "Keywords"), entries: org.keywordRules.map { e(.keyword($0.id), "k\($0.id)", $0.name, "tag", .smart) }))
        }
        return out
    }

    func select(category: CategoryID) {
        guard config.category != category else { return }
        config.category = category
        search = ""; selection = []; primary = nil
    }

    // MARK: źródła i indeks
    func addSource(url: URL, kind: SourceKind) {
        let path = PathUtil.canonical(url.path)
        guard !sources.contains(where: { $0.path == path }) else { return }
        var name = url.deletingPathExtension().lastPathComponent
        if name.isEmpty { name = url.lastPathComponent }
        data.sources.append(Source(name: name, path: path, kind: kind))
        restartWatcher(); reindexAll()
    }

    /// Pojedyncze pliki trafiają do jednego źródła "Pojedyncze pliki".
    func addFiles(_ urls: [URL]) {
        let paths = urls.map { PathUtil.canonical($0.path) }.filter { p in
            MediaFiles.kind(forExtension: (p as NSString).pathExtension) != nil && !items.contains { $0.path == p }
        }
        guard !paths.isEmpty else { return }
        if let i = data.sources.firstIndex(where: { $0.kind == .files }) {
            data.sources[i].filePaths = Array(Set((data.sources[i].filePaths ?? []) + paths)).sorted()
        } else {
            data.sources.append(Source(name: L("Pojedyncze pliki", "Individual files"), path: "", kind: .files, filePaths: paths.sorted()))
        }
        restartWatcher(); reindexAll()
    }

    /// Wrzucone z Findera: foldery jako źródła, .fcpbundle jako biblioteki, reszta jako pojedyncze pliki.
    func addDropped(_ urls: [URL]) -> Bool {
        var files: [URL] = []
        var added = false
        for u in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if u.pathExtension.lowercased() == "fcpbundle" { addSource(url: u, kind: .fcpLibrary); added = true }
            else if isDir.boolValue { addSource(url: u, kind: .folder); added = true }
            else { files.append(u) }
        }
        if !files.isEmpty { addFiles(files); added = true }
        return added
    }

    func removeFromLibrary(_ item: MediaItem) {
        guard let i = data.sources.firstIndex(where: { $0.id == item.sourceID && $0.kind == .files }) else { return }
        data.sources[i].filePaths?.removeAll { $0 == item.path }
        if data.sources[i].filePaths?.isEmpty ?? true { data.sources.remove(at: i) }
        items.removeAll { $0.path == item.path }
        selection.remove(item.path); if primary?.path == item.path { primary = nil; previewer.stop() }
        restartWatcher(); persistIndex()
    }

    func removeSource(_ id: UUID) {
        data.sources.removeAll { $0.id == id }
        items.removeAll { $0.sourceID == id }
        if case .source(id) = config.category { config.category = .all }
        restartWatcher(); persistIndex()
    }

    func reindexAll() {
        rescanTask?.cancel()
        let srcs = sources
        isIndexing = true
        rescanTask = Task { [weak self] in
            guard let self else { return }
            var all: [MediaItem] = []
            let existing = Dictionary(self.items.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            for s in srcs {
                if Task.isCancelled { return }
                all += await self.indexer.scan(s, existing: existing)
            }
            if Task.isCancelled { return }
            let unique = Dictionary(all.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a }).values
            self.items = Array(unique)
            self.isIndexing = false
            self.persistIndex()
        }
    }

    private func restartWatcher() {
        watcher?.stop()
        watcher = FolderWatcher(paths: Array(Set(sources.flatMap(\.watchPaths)))) { [weak self] _ in
            Task { @MainActor in self?.debouncedRescan() }
        }
    }

    private var debounce: Task<Void, Never>?
    private func debouncedRescan() {
        debounce?.cancel()
        debounce = Task { try? await Task.sleep(nanoseconds: 800_000_000); if !Task.isCancelled { reindexAll() } }
    }

    private func persistIndex() {
        let snapshot = items, url = indexURL
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: url, options: .atomic) }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.userStore.save(self.data)
        }
    }

    func flush() { saveTask?.cancel(); userStore.save(data) }

    // MARK: zaznaczenie i podgląd
    func click(_ item: MediaItem, command: Bool, shift: Bool) {
        let vis = visible
        if shift, let a = anchorPath, let i0 = vis.firstIndex(where: { $0.path == a }), let i1 = vis.firstIndex(where: { $0.path == item.path }) {
            selection = Set(vis[min(i0, i1)...max(i0, i1)].map(\.path))
        } else if command {
            if selection.contains(item.path) { selection.remove(item.path) } else { selection.insert(item.path) }
            anchorPath = item.path
        } else {
            selection = [item.path]; anchorPath = item.path
        }
        primary = item
        previewer.load(item)
        if settings.autoplayOnSelect && !command && !shift && item.kind != .image { previewer.play() }
    }

    /// Strzałki: przechodzi po widocznych elementach i (zgodnie z ustawieniem) odtwarza.
    func moveSelection(_ d: GridNavigation.Direction) {
        let vis = visible
        let cols = config.viewMode == .list ? 1 : gridColumns
        let cur = primary.flatMap { p in vis.firstIndex { $0.path == p.path } }
        guard let n = GridNavigation.move(from: cur, count: vis.count, columns: cols, d) else { return }
        click(vis[n], command: false, shift: false)
        scrollTarget = vis[n].path
    }

    /// Wspólne wejście dla menu kontekstowego i klawisza Enter.
    func beginRename(_ item: MediaItem) {
        if sources.first(where: { $0.id == item.sourceID })?.kind == .fcpLibrary {
            notice = L("Plików z biblioteki FCP nie przemianowuję: Final Cut Pro zgubiłby do nich linki.", "I don't rename files from an FCP library: Final Cut Pro would lose its links to them."); return
        }
        let copies = duplicateItems(of: item).count
        var msg = L("Zmienia nazwę pliku na dysku. Jeśli ten plik jest użyty w projekcie Final Cut Pro bez kopiowania do biblioteki, FCP zgubi do niego link.",
                     "Renames the file on disk. If it's used in a Final Cut Pro project without being copied into the library, FCP will lose its link to it.")
        if copies > 1 { msg += L(" Pozostałe kopie (\(copies - 1)) zostają bez zmian.", " The other copies (\(copies - 1)) stay unchanged.") }
        ask(L("Zmień nazwę", "Rename"), message: msg, placeholder: L("Nowa nazwa", "New name"), initial: item.name, action: L("Zmień", "Rename")) { [weak self] new in
            if let err = self?.rename(item, to: new) { self?.notice = err }
        }
    }

    func renameSelected() {
        guard selection.count == 1, let p = selection.first, let it = item(p) else { return }
        beginRename(it)
    }

    /// Klawisze 1-4: filtr typu w bieżącej kategorii (ponowne naciśnięcie zdejmuje); Shift+1-4: zmiana typu zaznaczonego dźwięku;
    /// 5: ulubione; 6: wyczyść filtr i wyszukiwanie.
    func quickKey(_ n: Int, shift: Bool) -> Bool {
        if n == settings.finderKey, !shift { revealSelectionInFinder(); return true }
        switch n {
        case 1...4:
            guard settings.quickKeys.indices.contains(n - 1) else { return false }
            let cls = settings.quickKeys[n - 1]
            if shift {
                guard cls == .sfx || cls == .music else { return true }
                setClass(cls, for: selection.compactMap { item($0) }.filter { $0.kind == .audio }.map(\.path))
            } else { config.filters.klass = config.filters.klass == cls ? nil : cls }
            return true
        case 5:
            if !selection.isEmpty { toggleFavorite(Array(selection)) }
            return true
        case 6: config.filters = .none; search = ""; return true
        default: return false
        }
    }

    /// Pokazuje zaznaczone pliki w Finderze (jak „Pokaż w Finderze” z menu kontekstowego).
    func revealSelectionInFinder() {
        let urls = selection.compactMap { item($0) }.map { URL(fileURLWithPath: $0.path) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    /// Elementy do eksportu: bez duplikatów, jeśli zwijanie jest włączone.
    func exportItems() -> [MediaItem] {
        settings.hideDuplicates ? Deduper.collapse(items, index: dups, sourceOrder: sourceOrder) : items
    }

    func sortByNameForTest() { config.sort = .name; config.ascending = true }

    /// Wciśnięcie (przed puszczeniem): daje od razu podgląd zaznaczenia dla przeciągnięcia. Przy Shift/⌘ NIE dotykamy
    /// zaznaczenia — o wyniku decyduje `click(...)` na puszczeniu, które umie zaznaczyć zakres (Shift) albo dołożyć (⌘).
    func pressDown(_ item: MediaItem, shift: Bool = false, command: Bool = false) {
        guard !shift, !command else { return }
        if !selection.contains(item.path) { selection = [item.path]; anchorPath = item.path; primary = item }
    }

    func dragPaths(for item: MediaItem) -> [String] {
        selection.contains(item.path) ? visible.filter { selection.contains($0.path) }.map(\.path) : [item.path]
    }

    /// Ścieżki bieżącego zaznaczenia, w kolejności widoku (do ⌘C).
    var selectedPaths: [String] { visible.filter { selection.contains($0.path) }.map(\.path) }

    /// Kopiuje pliki do schowka jako PLIKI (nie tekst) — wklejenie w Finderze albo innej aplikacji wkleja same pliki,
    /// tak jak po ⌘C na plikach w Finderze. Osobno od „Skopiuj ścieżkę” (kopiuje tekst do wklejenia np. w terminalu).
    func copyFilesToPasteboard(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(paths.map { NSURL(fileURLWithPath: $0) })
    }

    /// ⌘C w panelu: kopiuje bieżące zaznaczenie jako pliki.
    func copySelectionToPasteboard() { copyFilesToPasteboard(selectedPaths) }

    /// ⌘V poza polem tekstowym: pliki skopiowane skądinąd (np. ⌘C w Finderze) trafiają do biblioteki, tak jak przeciągnięcie.
    @discardableResult
    func pasteFilesFromClipboard() -> Bool {
        guard let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else { return false }
        return addDropped(urls)
    }

    // MARK: ulubione, tagi, kolekcje
    func toggleFavorite(_ paths: [String]) {
        let all = equivalents(paths)
        let allFav = paths.allSatisfy { p in equivalents([p]).contains { org.favorites.contains($0) } }
        for p in all { if allFav { data.org.favorites.remove(p) } else { data.org.favorites.insert(p) } }
    }

    func addTag(_ tag: String, to paths: [String]) {
        let t = tag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        for p in equivalents(paths) where !(data.org.tags[p]?.contains(t) ?? false) { data.org.tags[p, default: []].append(t) }
    }

    func newCollection(name: String, paths: [String] = []) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        data.org.collections.append(MediaCollection(name: n, paths: equivalents(paths)))
    }

    func add(_ paths: [String], toCollection id: UUID) {
        guard let i = data.org.collections.firstIndex(where: { $0.id == id }) else { return }
        for p in equivalents(paths) where !data.org.collections[i].paths.contains(p) { data.org.collections[i].paths.append(p) }
    }

    func remove(_ paths: [String], fromCollection id: UUID) {
        guard let i = data.org.collections.firstIndex(where: { $0.id == id }) else { return }
        let gone = Set(equivalents(paths))
        data.org.collections[i].paths.removeAll { gone.contains($0) }
    }

    func renameCollection(_ id: UUID, to name: String) {
        if let i = data.org.collections.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespaces).isEmpty { data.org.collections[i].name = name }
    }

    func deleteCollection(_ id: UUID) {
        data.org.collections.removeAll { $0.id == id }
        if case .collection(id) = config.category { config.category = .all }
    }

    // MARK: typ dźwięku i zmiana nazwy
    /// `nil` = wróć do automatycznego podziału wg długości.
    func setClass(_ cls: MediaClass?, for paths: [String]) {
        for p in equivalents(paths) { if let cls { data.org.classOverrides[p] = cls } else { data.org.classOverrides.removeValue(forKey: p) } }
    }

    /// Zmienia nazwę pliku NA DYSKU i przenosi na nową ścieżkę ulubione, tagi, kolekcje i ręczne typy.
    /// Zwraca komunikat błędu albo nil.
    func rename(_ item: MediaItem, to input: String) -> String? {
        guard let src = sources.first(where: { $0.id == item.sourceID }) else { return L("Nie znaleziono źródła tego pliku.", "Couldn't find this file's source.") }
        if src.kind == .fcpLibrary { return L("Plików z biblioteki FCP nie przemianowuję: Final Cut Pro zgubiłby do nich linki.", "I don't rename files from an FCP library: Final Cut Pro would lose its links to them.") }
        let old = URL(fileURLWithPath: item.path)
        let ext = old.pathExtension
        var base = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ext.isEmpty, base.lowercased().hasSuffix("." + ext.lowercased()) { base = String(base.dropLast(ext.count + 1)) }
        guard !base.isEmpty, !base.contains("/"), !base.contains(":"), !base.hasPrefix(".") else { return L("Nazwa jest pusta albo zawiera niedozwolone znaki (/ i :).", "The name is empty or contains characters that aren\u{27}t allowed (/ and :).") }
        if base == item.name { return nil }
        var new = old.deletingLastPathComponent().appendingPathComponent(base)
        if !ext.isEmpty { new = new.appendingPathExtension(ext) }
        let fm = FileManager.default
        let caseOnly = new.path.lowercased() == old.path.lowercased()
        if fm.fileExists(atPath: new.path), !caseOnly { return L("W tym folderze jest już plik o nazwie „\(new.lastPathComponent)”.", "A file named “\(new.lastPathComponent)” already exists in this folder.") }
        do {
            if caseOnly {   // system plików nie rozróżnia wielkości liter: przez nazwę tymczasową
                let tmp = old.deletingLastPathComponent().appendingPathComponent(".rename-\(UUID().uuidString)")
                try fm.moveItem(at: old, to: tmp); try fm.moveItem(at: tmp, to: new)
            } else { try fm.moveItem(at: old, to: new) }
        } catch { return L("Nie udało się zmienić nazwy: \(error.localizedDescription)", "Couldn\u{27}t rename: \(error.localizedDescription)") }
        migratePath(old.path, new.path, newName: base)
        return nil
    }

    private func migratePath(_ old: String, _ new: String, newName: String) {
        if primary?.path == old { previewer.stop(); primary = nil }
        if data.org.favorites.remove(old) != nil { data.org.favorites.insert(new) }
        if let t = data.org.tags.removeValue(forKey: old) { data.org.tags[new] = t }
        if let c = data.org.classOverrides.removeValue(forKey: old) { data.org.classOverrides[new] = c }
        for i in data.org.collections.indices { data.org.collections[i].paths = data.org.collections[i].paths.map { $0 == old ? new : $0 } }
        for i in data.sources.indices where data.sources[i].kind == .files { data.sources[i].filePaths = data.sources[i].filePaths?.map { $0 == old ? new : $0 } }
        if selection.remove(old) != nil { selection.insert(new) }
        items = items.map { var x = $0; if x.path == old { x.path = new; x.name = newName }; return x }
        persistIndex()
    }

    // MARK: presety (zapisane układy)
    func savePreset(name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        data.org.presets.append(Preset(name: n, config: config))
    }
    func apply(_ p: Preset) { config = p.config; search = ""; selection = [] }
    func deletePreset(_ id: UUID) { data.org.presets.removeAll { $0.id == id } }

    func ask(_ title: String, message: String = "", placeholder: String, initial: String = "", action: String, _ onConfirm: @escaping (String) -> Void) {
        prompt = PromptRequest(title: title, message: message, placeholder: placeholder, initial: initial, action: action, onConfirm: onConfirm)
    }
}
