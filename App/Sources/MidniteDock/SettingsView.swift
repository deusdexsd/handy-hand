import SwiftUI
import AppKit
import DockCore

struct SettingsView: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        TabView {
            GeneralTab(store: store).tabItem { Label(L("Ogólne", "General"), systemImage: "gearshape") }
            SourcesTab(store: store).tabItem { Label(L("Źródła", "Sources"), systemImage: "folder") }
            AppearanceTab(store: store).tabItem { Label(L("Wygląd", "Appearance"), systemImage: "paintpalette") }
            DurationsTab(store: store).tabItem { Label(L("Długości", "Durations"), systemImage: "timer") }
            KeywordsTab(store: store).tabItem { Label(L("Słowa kluczowe", "Keywords"), systemImage: "tag") }
            ShortcutsTab(store: store).tabItem { Label(L("Skróty", "Shortcuts"), systemImage: "keyboard") }
            ExportTab(store: store).tabItem { Label(L("Eksport", "Export"), systemImage: "square.and.arrow.up") }
        }
        .frame(width: 600, height: 520)
    }
}

struct GeneralTab: View {
    @ObservedObject var store: LibraryStore
    @State private var loginOn = LoginItem.isOn
    @State private var loginError: String?
    var body: some View {
        Form {
            Section(L("Język", "Language")) {
                Picker(L("Język interfejsu", "Interface language"), selection: $store.data.settings.language) {
                    Text("Polski").tag(AppLanguage.pl)
                    Text("English").tag(AppLanguage.en)
                }
            }
            Section(L("Uruchamianie", "Startup")) {
                Toggle(L("Otwieraj \(AppInfo.name) przy logowaniu do komputera", "Open \(AppInfo.name) at login"), isOn: Binding(get: { loginOn }, set: { on in
                    loginError = LoginItem.set(on); loginOn = LoginItem.isOn
                }))
                if let e = loginError { Text(e).font(.caption).foregroundStyle(.red) }
                else if LoginItem.needsApproval { Text(L("Zatwierdź \(AppInfo.name) w Ustawieniach systemowych → Ogólne → Elementy logowania.", "Approve \(AppInfo.name) in System Settings → General → Login Items.")).font(.caption).foregroundStyle(.secondary) }
                else if LoginItem.isDevBuild { Text(L("Wersja deweloperska: włącz w zainstalowanej aplikacji z Programów.", "Development build: enable this in the app installed in Applications.")).font(.caption).foregroundStyle(.secondary) }
                else { Text(L("Najlepiej działa, gdy \(AppInfo.name) leży w folderze Programy. Wyłączysz to tu albo w menu \(AppInfo.name) na pasku menu.", "Works best when \(AppInfo.name) sits in the Applications folder. Turn it off here or from the \(AppInfo.name) menu-bar menu.")).font(.caption).foregroundStyle(.secondary) }
            }
            Section(L("Zachowanie panelu", "Panel behavior")) {
                Picker(L("Tryb", "Mode"), selection: $store.data.settings.mode) { ForEach(PanelMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                if store.settings.mode == .followApp {
                    LabeledContent(L("Aplikacje", "Apps")) { Text(store.settings.watchedBundleIDs.joined(separator: ", ")).foregroundStyle(.secondary).font(.caption) }
                    Menu(L("Dodaj uruchomioną aplikację", "Add a running app")) {
                        ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier!) {
                                if let b = app.bundleIdentifier, !store.settings.watchedBundleIDs.contains(b) { store.data.settings.watchedBundleIDs.append(b) }
                            }
                        }
                    }
                    Button(L("Przywróć tylko Final Cut Pro", "Reset to Final Cut Pro only")) { store.data.settings.watchedBundleIDs = ["com.apple.FinalCut"] }
                }
                Toggle(L("Odtwarzaj po kliknięciu kafla", "Play on tile click"), isOn: $store.data.settings.autoplayOnSelect)
                Toggle(L("Zatrzymaj odtwarzanie po zwinięciu panelu", "Stop playback when the panel collapses"), isOn: $store.data.settings.stopPlaybackOnCollapse)
                Toggle(L("Większy podgląd obrazów i wideo na dole panelu", "Bigger image/video preview at the bottom of the panel"), isOn: $store.data.settings.bigMediaPreview)
            }
            Section("Notch") {
                Picker(L("Położenie", "Position"), selection: $store.data.settings.placement) { ForEach(NotchPlacement.allCases, id: \.self) { Text($0.label).tag($0) } }
                if store.settings.placement.isSide {
                    LabeledContent(L("Położenie na krawędzi", "Position on the edge")) { HStack { Text(L("góra", "top")).font(.caption).foregroundStyle(.secondary); Slider(value: $store.data.settings.sidePosition, in: 0...1); Text(L("dół", "bottom")).font(.caption).foregroundStyle(.secondary) }.frame(width: 240) }
                }
                Picker(L("Wirtualny notch", "Virtual notch"), selection: $store.data.settings.virtualNotch) { ForEach(VirtualNotchMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                Text(L("Wirtualny notch to czarna wysepka na górze ekranu. Przydaje się na monitorze zewnętrznym; poza górnym środkiem jest używany zawsze.",
                       "The virtual notch is a black island at the top of the screen. Useful on an external monitor; away from top-center it's always used."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Układ", "Layout")) {
                Picker(L("Kategorie", "Categories"), selection: $store.data.settings.categoryLayout) { ForEach(CategoryLayout.allCases, id: \.self) { Text($0.label).tag($0) } }
                LabeledContent(L("Szerokość panelu", "Panel width")) { Stepper(value: $store.data.settings.expandedWidth, in: 560...1000, step: 20) { Text("\(Int(store.settings.expandedWidth)) pt") } }
                LabeledContent(L("Wysokość panelu", "Panel height")) { Stepper(value: $store.data.settings.expandedHeight, in: 340...700, step: 20) { Text("\(Int(store.settings.expandedHeight)) pt") } }
            }
        }.formStyle(.grouped)
    }
}

struct SourcesTab: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        Form {
            Section(L("Źródła (obserwowane na żywo; wyżej = ważniejsze przy duplikatach)", "Sources (watched live; higher = wins on duplicates)")) {
                if store.sources.isEmpty { Text(L("Brak źródeł. Dodaj folder z SFX lub b-rollem.", "No sources yet. Add a folder with SFX or b-roll.")).foregroundStyle(.secondary) }
                ForEach(store.sources) { s in
                    HStack {
                        Image(systemName: s.kind == .fcpLibrary ? "film.stack" : (s.kind == .files ? "doc.on.doc" : "folder")).foregroundStyle(.secondary)
                        VStack(alignment: .leading) { Text(s.name); Text(s.kind == .files ? L("Pliki dodane pojedynczo", "Files added individually") : s.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                        Spacer()
                        Text("\(store.items.filter { $0.sourceID == s.id }.count)").foregroundStyle(.secondary).monospacedDigit()
                        Button { moveSource(s.id, -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).accessibilityLabel(L("Wyżej", "Move up"))
                        Button { moveSource(s.id, 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).accessibilityLabel(L("Niżej", "Move down"))
                        Button(role: .destructive) { store.removeSource(s.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                            .accessibilityLabel(L("Usuń źródło \(s.name)", "Remove source \(s.name)"))
                    }
                }
            }
            Section(L("Duplikaty", "Duplicates")) {
                Toggle(L("Pokaż duplikaty osobno", "Show duplicates separately"), isOn: Binding(
                    get: { !store.settings.hideDuplicates }, set: { store.data.settings.hideDuplicates = !$0 }))
                if store.settings.hideDuplicates {
                    Toggle(L("Tryb ścisły: doliczaj rozmiar pliku", "Strict mode: also match file size"), isOn: $store.data.settings.strictDuplicates)
                    Text(L("Duplikat to ten sam typ, ta sama nazwa (bez rozszerzenia) i ta sama długość. Zostaje kopia ze źródła wyżej na liście. Ulubione, tagi i kolekcje dotyczą wszystkich kopii, a w folderze źródła dalej widać jego własną kopię. Aktualnie zwiniętych: \(store.hiddenDuplicateCount).",
                           "A duplicate is the same type, same name (without extension) and same length. The copy from the higher-listed source wins. Favorites, tags and collections apply to all copies, and each source folder still shows its own copy. Currently collapsed: \(store.hiddenDuplicateCount)."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                HStack(spacing: 8) {
                    AddMenuItems(store: store)     // trzy przyciski wprost, bez zagnieżdżonego menu (Menu w Form/Section bywa zawodne)
                    Spacer()
                    if store.isIndexing { ProgressView().controlSize(.small) }
                    Button(L("Odśwież teraz", "Refresh now")) { store.reindexAll() }
                }
                Text(L("Biblioteka FCP jest czytana jak zwykły folder: tylko pliki z „Original Media”. Aplikacja nie pyta Final Cut Pro o nic.",
                       "An FCP library is read like a plain folder: only files under “Original Media”. The app doesn't ask Final Cut Pro for anything."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    func moveSource(_ id: UUID, _ d: Int) {
        guard let i = store.data.sources.firstIndex(where: { $0.id == id }), store.data.sources.indices.contains(i + d) else { return }
        store.data.sources.swapAt(i, i + d)
    }

}

struct AppearanceTab: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        Form {
            Section(L("Kolor akcentu", "Accent color")) {
                HStack(spacing: 12) {
                    ForEach(AccentChoice.allCases, id: \.self) { a in
                        Button { store.data.settings.accent = a } label: {
                            Circle().fill(a.color).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: store.settings.accent == a ? 2 : 0).padding(-3))
                        }.buttonStyle(.plain).help(a.label).accessibilityLabel(a.label)
                    }
                }
                Text(L("Akcent oznacza tylko zaznaczenie, odtwarzanie i aktywne filtry. Reszta interfejsu zostaje neutralna.",
                       "The accent marks only selection, playback and active filters. The rest of the interface stays neutral.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Źródła", "Sources")) {
                Toggle(L("Subtelne kolory ikon źródeł w sidebarze", "Subtle source-icon colors in the sidebar"), isOn: $store.data.settings.sourceTints)
            }
            Section(L("Siatka", "Grid")) {
                Toggle(L("Widok minimalistyczny (bez nazw i wymiarów pod kaflem)", "Minimalist view (no names or dimensions under tiles)"), isOn: $store.data.settings.minimalistGrid)
                Text(L("Zostaje sam obraz albo waveform — czyściej, bliżej siatki w stylu Pinteresta.", "Just the image or waveform stays — cleaner, closer to a Pinterest-style grid."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Notch: reakcja na kursor", "Notch: cursor reaction")) {
                Picker(L("Efekt", "Effect"), selection: $store.data.settings.notchEffect) { ForEach(NotchEffect.allCases, id: \.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                Text(L("Łapka wychyla się spod notcha i „pacuje” w stronę kursora tylko wtedy, gdy jest blisko (ok. 105 pt), a poza tym całkiem się chowa. Działa tylko przy notchu (górny środek); na bocznych krawędziach nic się nie dzieje. Symulacja chodzi tylko, gdy łapka jest widoczna; „Brak” nie zużywa nic.",
                       "The paw pokes out from under the notch and “pats” toward the cursor only when it's close (~105 pt), and stays fully hidden otherwise. Only works at the notch (top-center); the side edges show nothing. The simulation only runs while the paw is visible; “None” uses nothing."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Waveform") {
                Toggle(L("Skala automatyczna (najdłuższy dźwięk w widoku = pełna szerokość)", "Automatic scale (longest sound in view = full width)"), isOn: $store.data.settings.waveformAutoScale)
                if !store.settings.waveformAutoScale {
                    LabeledContent(L("Stała skala kafla", "Fixed tile scale")) {
                        Stepper(value: $store.data.settings.waveformScaleSeconds, in: 2...120, step: 1) { Text(L("\(Int(store.settings.waveformScaleSeconds)) s = pełna szerokość", "\(Int(store.settings.waveformScaleSeconds)) s = full width")) }
                    }
                }
                Text(L("SFX i muzyka mają osobne skale, więc 6 s wygląda krócej niż 20 s. Pod waveformem jest podziałka czasu. Odcień waveformu zależy od przedziału długości (zakładka Długości).",
                       "SFX and music have separate scales, so 6 s looks shorter than 20 s. There's a time scale under the waveform. Its shade depends on the duration range (Durations tab)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

struct DurationsTab: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        Form {
            Section(L("Podział audio: SFX i muzyka", "Audio split: SFX and music")) {
                LabeledContent(L("Granica SFX / muzyka", "SFX / music threshold")) {
                    Stepper(value: $store.data.org.sfxMaxSeconds, in: 5...300, step: 5) { Text("\(Int(store.org.sfxMaxSeconds)) s") }
                }
                Text(L("Dźwięki krótsze lub równe tej wartości to SFX, dłuższe to muzyka. Pojedynczy plik przestawisz prawym przyciskiem: Typ dźwięku.",
                       "Sounds at or below this length are SFX, longer ones are music. Override a single file with right-click: Sound type."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(MediaClass.allCases.filter(\.hasDuration), id: \.self) { cls in
                Section(L("\(cls.label): przedziały długości", "\(cls.label): duration ranges")) {
                    ForEach($store.data.org.durationRanges.filter { $0.wrappedValue.mediaClass == cls }) { $r in row($r) }
                    Button(L("Dodaj przedział", "Add range")) {
                        let step: Double = cls == .music ? 60 : 5
                        let last = store.org.durationRanges.filter { $0.mediaClass == cls }.compactMap(\.maxSeconds).max() ?? 0
                        store.data.org.durationRanges.append(DurationRange(name: DurationRange.autoName(min: last, max: last + step), mediaClass: cls, minSeconds: last, maxSeconds: last + step, shade: 0.75))
                    }
                }
            }
            Text(L("Każdy przedział to osobna kategoria w sidebarze i odcień szarości waveformu. Zostaw „do” puste dla przedziału bez górnego limitu.",
                   "Each range is its own sidebar category and waveform shade. Leave “to” empty for a range with no upper limit."))
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }

    func row(_ r: Binding<DurationRange>) -> some View {
        HStack(spacing: 8) {
            TextField(L("Nazwa", "Name"), text: r.name).labelsHidden().frame(width: 120)
            Text(L("od", "from")).foregroundStyle(.secondary).font(.caption)
            TextField(L("od", "from"), value: Binding(get: { r.wrappedValue.minSeconds }, set: { v in edit(r) { $0.minSeconds = max(0, v ?? 0) } }), format: .number).labelsHidden().frame(width: 44).multilineTextAlignment(.trailing)
            Text(L("do", "to")).foregroundStyle(.secondary).font(.caption)
            TextField("∞", value: Binding(get: { r.wrappedValue.maxSeconds }, set: { v in edit(r) { $0.maxSeconds = v } }), format: .number).labelsHidden().frame(width: 44).multilineTextAlignment(.trailing)
            Text("s").foregroundStyle(.secondary).font(.caption)
            Slider(value: r.shade, in: 0.1...1).frame(minWidth: 70)
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.25 + 0.65 * r.wrappedValue.shade)).frame(width: 26, height: 12)
            Button(role: .destructive) { store.data.org.durationRanges.removeAll { $0.id == r.wrappedValue.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
        }
    }

    /// Zmiana granic przemianowuje przedział tylko wtedy, gdy nazwa była jeszcze automatyczna.
    func edit(_ r: Binding<DurationRange>, _ change: (inout DurationRange) -> Void) {
        var v = r.wrappedValue
        let wasAuto = v.name == DurationRange.autoName(min: v.minSeconds, max: v.maxSeconds)
        change(&v)
        if wasAuto { v.name = DurationRange.autoName(min: v.minSeconds, max: v.maxSeconds) }
        r.wrappedValue = v
    }
}

struct KeywordsTab: View {
    @ObservedObject var store: LibraryStore
    func moveRule(_ id: UUID, _ d: Int) {
        guard let i = store.data.org.keywordRules.firstIndex(where: { $0.id == id }), store.data.org.keywordRules.indices.contains(i + d) else { return }
        store.data.org.keywordRules.swapAt(i, i + d)
    }
    var body: some View {
        Form {
            Section(L("Reguły po słowach w nazwie pliku", "Rules by word in the filename")) {
                ForEach($store.data.org.keywordRules) { $rule in
                    HStack {
                        VStack(spacing: 0) {
                            Button { moveRule(rule.id, -1) } label: { Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)) }.buttonStyle(.borderless).accessibilityLabel(L("Wyżej", "Move up"))
                            Button { moveRule(rule.id, 1) } label: { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }.buttonStyle(.borderless).accessibilityLabel(L("Niżej", "Move down"))
                        }
                        TextField(L("Nazwa", "Name"), text: $rule.name).labelsHidden().frame(width: 120)
                        TextField(L("słowa, po przecinku", "words, comma-separated"), text: Binding(get: { rule.keywords.joined(separator: ", ") },
                                                                         set: { rule.keywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                            .labelsHidden().textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { store.data.org.keywordRules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button(L("Dodaj regułę", "Add rule")) { store.data.org.keywordRules.append(KeywordRule(name: L("Nowa", "New"), keywords: [])) }
                    Spacer()
                    Button(L("Przywróć domyślne", "Restore defaults")) { store.data.org.keywordRules = KeywordRule.defaults() }
                }
            }
            Text(L("Każda reguła tworzy kategorię w sekcji Inteligentne i aktualizuje się sama, gdy pojawią się nowe pliki.",
                   "Each rule creates a category under Smart and updates itself as new files show up.")).font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}


struct ShortcutsTab: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        Form {
            Section(L("⌘1–⌘4: szybki filtr typu", "⌘1–⌘4: quick type filter")) {
                ForEach(0..<4, id: \.self) { i in
                    Picker(L("⌘\(i + 1)", "⌘\(i + 1)"), selection: Binding(get: { store.settings.quickKeys[i] }, set: { store.data.settings.quickKeys[i] = $0 })) {
                        ForEach(MediaClass.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Text(L("W bieżącej kategorii (folder, kolekcja…) pokazuje tylko wybrany typ. Ponowne naciśnięcie zdejmuje filtr. ⌘⇧ + klawisz zmienia typ zaznaczonego dźwięku (SFX albo muzyka). Zawsze z ⌘, żeby nie kolidowało z pisaniem w wyszukiwarce.",
                       "Shows only the chosen type within the current category (folder, collection…). Press again to clear the filter. ⌘⇧ + key changes the selected sound's type (SFX or music). Always with ⌘, so it never collides with typing in search."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Skrót globalny: pokaż / ukryj panel", "Global shortcut: show / hide panel")) {
                HotkeyRecorder(spec: $store.data.settings.toggleHotkey)
                Text(L("Działa z każdej aplikacji (także z Final Cut Pro), bez najeżdżania kursorem na notch. Ten sam skrót chowa panel. Wymaga co najmniej jednego modyfikatora (⌘, ⌥, ⌃ lub ⇧).",
                       "Works from any app (including Final Cut Pro), without hovering the notch. The same shortcut hides the panel. Needs at least one modifier (⌘, ⌥, ⌃ or ⇧)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Pokaż w Finderze", "Reveal in Finder")) {
                Picker(L("Klawisz w panelu", "Key in the panel"), selection: $store.data.settings.finderKey) {
                    ForEach([9, 8, 7, 0], id: \.self) { Text("⌘\($0)").tag($0) }
                    Text(L("wyłączony", "off")).tag(-1)
                }
                Text(L("Po naciśnięciu pokazuje w Finderze zaznaczone pliki (tak samo jak „Pokaż w Finderze” z menu prawego przycisku).",
                       "Shows the selected files in Finder (same as “Reveal in Finder” from the right-click menu)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Pozostałe", "Other")) {
                LabeledContent("⌘5") { Text(L("dodaj zaznaczone do ulubionych (lub usuń)", "add selected to favorites (or remove)")) }
                LabeledContent("⌘6") { Text(L("wyczyść filtry i wyszukiwanie", "clear filters and search")) }
                LabeledContent(L("Strzałki", "Arrows")) { Text(L("przejście po elementach", "move between items")) }
                LabeledContent("Enter") { Text(L("zmiana nazwy", "rename")) }
                LabeledContent(L("Spacja", "Space")) { Text(L("odsłuch (dźwięk) lub większy podgląd (obraz, wideo)", "playback (sound) or bigger preview (image, video)")) }
            }
        }.formStyle(.grouped)
    }
}

struct ExportTab: View {
    @ObservedObject var store: LibraryStore
    @State private var layout: ExportLayout = .byTypeAndLength
    @State private var mode: ExportMode = .copy
    var body: some View {
        Form {
            Section(L("Eksport do folderów", "Export to folders")) {
                Picker(L("Układ folderów", "Folder layout"), selection: $layout) { ForEach(ExportLayout.allCases, id: \.self) { Text($0.label).tag($0) } }
                Picker(L("Sposób", "Method"), selection: $mode) { ForEach(ExportMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                Text(L("Tworzy folder „\(AppInfo.name) – eksport” w wybranym miejscu. Nic nie nadpisuje. Dowiązania nie zajmują miejsca, ale przestają działać, gdy przeniesiesz oryginały. Duplikaty są pomijane, jeśli zwijanie jest włączone.",
                       "Creates a “\(AppInfo.name) – export” folder in the place you pick. Nothing is overwritten. Links take no space but stop working if you move the originals. Duplicates are skipped when collapsing is on."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Eksportuj…", "Export…")) { run() }
            }
        }.formStyle(.grouped)
    }

    func run() {
        Pickers.pickFolder(title: L("Wybierz miejsce na folder eksportu", "Choose where to put the export folder")) { base in
            let dest = base.appendingPathComponent(L("\(AppInfo.name) – eksport", "\(AppInfo.name) – export"), isDirectory: true)
            let plan = LibraryExporter.plan(items: store.exportItems(), org: store.org, layout: layout)
            let r = LibraryExporter.run(plan, to: dest, mode: mode)
            let a = NSAlert()
            a.messageText = L("Eksport zakończony", "Export finished")
            a.informativeText = L("Zapisano: \(r.done), pominięto istniejące: \(r.skipped)", "Saved: \(r.done), skipped existing: \(r.skipped)") + (r.failed.isEmpty ? "" : L(", błędy: \(r.failed.count)", ", errors: \(r.failed.count)")) + "\n\(dest.path)"
            a.runModal()
        }
    }
}

/// Pole do nagrywania skrótu: klik „Zmień”, naciśnij kombinację z modyfikatorem (Esc anuluje).
struct HotkeyRecorder: View {
    @Binding var spec: HotKeySpec?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(L("Skrót", "Shortcut")) {
            HStack(spacing: 8) {
                Text(recording ? L("naciśnij kombinację…", "press a combination…") : (spec.map(HotKeyText.string) ?? L("wyłączony", "off")))
                    .font(.system(.body, design: .rounded)).foregroundStyle(recording ? Color.accentColor : .primary)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
                Button(recording ? L("Anuluj", "Cancel") : L("Zmień", "Change")) { recording ? stop() : start() }
                if spec != nil { Button(L("Wyłącz", "Turn off")) { stop(); spec = nil } }
                else { Button(L("Domyślny", "Default")) { spec = .defaultToggle } }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }                    // Esc: anuluj
            let mods = HotKeyText.carbon(e.modifierFlags)
            guard mods != 0 else { NSSound.beep(); return nil }          // bez modyfikatora skrót przechwyciłby zwykłe pisanie
            spec = HotKeySpec(keyCode: UInt32(e.keyCode), modifiers: mods)
            stop(); return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
