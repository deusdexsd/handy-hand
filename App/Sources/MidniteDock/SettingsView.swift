import SwiftUI
import AppKit
import DockCore

struct SettingsView: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        TabView {
            GeneralTab(store: store).tabItem { Label("Ogólne", systemImage: "gearshape") }
            SourcesTab(store: store).tabItem { Label("Źródła", systemImage: "folder") }
            AppearanceTab(store: store).tabItem { Label("Wygląd", systemImage: "paintpalette") }
            DurationsTab(store: store).tabItem { Label("Długości", systemImage: "timer") }
            KeywordsTab(store: store).tabItem { Label("Słowa kluczowe", systemImage: "tag") }
            ShortcutsTab(store: store).tabItem { Label("Skróty", systemImage: "keyboard") }
            ExportTab(store: store).tabItem { Label("Eksport", systemImage: "square.and.arrow.up") }
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
            Section("Uruchamianie") {
                Toggle("Otwieraj Łapkę przy logowaniu do komputera", isOn: Binding(get: { loginOn }, set: { on in
                    loginError = LoginItem.set(on); loginOn = LoginItem.isOn
                }))
                if let e = loginError { Text(e).font(.caption).foregroundStyle(.red) }
                else if LoginItem.needsApproval { Text("Zatwierdź Łapkę w Ustawieniach systemowych → Ogólne → Elementy logowania.").font(.caption).foregroundStyle(.secondary) }
                else if LoginItem.isDevBuild { Text("Wersja deweloperska: włącz w zainstalowanej aplikacji z Programów.").font(.caption).foregroundStyle(.secondary) }
                else { Text("Najlepiej działa, gdy Łapka leży w folderze Programy. Wyłączysz to tu albo w menu łapki na pasku menu.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Zachowanie panelu") {
                Picker("Tryb", selection: $store.data.settings.mode) { ForEach(PanelMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                if store.settings.mode == .followApp {
                    LabeledContent("Aplikacje") { Text(store.settings.watchedBundleIDs.joined(separator: ", ")).foregroundStyle(.secondary).font(.caption) }
                    Menu("Dodaj uruchomioną aplikację") {
                        ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier!) {
                                if let b = app.bundleIdentifier, !store.settings.watchedBundleIDs.contains(b) { store.data.settings.watchedBundleIDs.append(b) }
                            }
                        }
                    }
                    Button("Przywróć tylko Final Cut Pro") { store.data.settings.watchedBundleIDs = ["com.apple.FinalCut"] }
                }
                Toggle("Odtwarzaj po kliknięciu kafla", isOn: $store.data.settings.autoplayOnSelect)
                Toggle("Większy podgląd obrazów i wideo na dole panelu", isOn: $store.data.settings.bigMediaPreview)
            }
            Section("Notch") {
                Picker("Położenie", selection: $store.data.settings.placement) { ForEach(NotchPlacement.allCases, id: \.self) { Text($0.label).tag($0) } }
                if store.settings.placement.isSide {
                    LabeledContent("Położenie na krawędzi") { HStack { Text("góra").font(.caption).foregroundStyle(.secondary); Slider(value: $store.data.settings.sidePosition, in: 0...1); Text("dół").font(.caption).foregroundStyle(.secondary) }.frame(width: 240) }
                }
                Picker("Wirtualny notch", selection: $store.data.settings.virtualNotch) { ForEach(VirtualNotchMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                Text("Wirtualny notch to czarna wysepka na górze ekranu. Przydaje się na monitorze zewnętrznym; poza górnym środkiem jest używany zawsze.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Układ") {
                Picker("Kategorie", selection: $store.data.settings.categoryLayout) { ForEach(CategoryLayout.allCases, id: \.self) { Text($0.label).tag($0) } }
                LabeledContent("Szerokość panelu") { Stepper(value: $store.data.settings.expandedWidth, in: 560...1000, step: 20) { Text("\(Int(store.settings.expandedWidth)) pt") } }
                LabeledContent("Wysokość panelu") { Stepper(value: $store.data.settings.expandedHeight, in: 340...700, step: 20) { Text("\(Int(store.settings.expandedHeight)) pt") } }
            }
        }.formStyle(.grouped)
    }
}

struct SourcesTab: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        Form {
            Section("Źródła (obserwowane na żywo; wyżej = ważniejsze przy duplikatach)") {
                if store.sources.isEmpty { Text("Brak źródeł. Dodaj folder z SFX lub b-rollem.").foregroundStyle(.secondary) }
                ForEach(store.sources) { s in
                    HStack {
                        Image(systemName: s.kind == .fcpLibrary ? "film.stack" : (s.kind == .files ? "doc.on.doc" : "folder")).foregroundStyle(.secondary)
                        VStack(alignment: .leading) { Text(s.name); Text(s.kind == .files ? "Pliki dodane pojedynczo" : s.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                        Spacer()
                        Text("\(store.items.filter { $0.sourceID == s.id }.count)").foregroundStyle(.secondary).monospacedDigit()
                        Button { moveSource(s.id, -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).accessibilityLabel("Wyżej")
                        Button { moveSource(s.id, 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).accessibilityLabel("Niżej")
                        Button(role: .destructive) { store.removeSource(s.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                            .accessibilityLabel("Usuń źródło \(s.name)")
                    }
                }
            }
            Section("Duplikaty") {
                Toggle("Zwijaj duplikaty (jedna pozycja zamiast kilku)", isOn: $store.data.settings.hideDuplicates)
                if store.settings.hideDuplicates {
                    Toggle("Tryb ścisły: doliczaj rozmiar pliku", isOn: $store.data.settings.strictDuplicates)
                    Text("Duplikat to ten sam typ, ta sama nazwa (bez rozszerzenia) i ta sama długość. Zostaje kopia ze źródła wyżej na liście. Ulubione, tagi i kolekcje dotyczą wszystkich kopii, a w folderze źródła dalej widać jego własną kopię. Aktualnie zwiniętych: \(store.hiddenDuplicateCount).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Menu("Dodaj…") { AddMenuItems(store: store) }.fixedSize()
                    Spacer()
                    if store.isIndexing { ProgressView().controlSize(.small) }
                    Button("Odśwież teraz") { store.reindexAll() }
                }
                Text("Biblioteka FCP jest czytana jak zwykły folder: tylko pliki z „Original Media”. Aplikacja nie pyta Final Cut Pro o nic.")
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
            Section("Kolor akcentu") {
                HStack(spacing: 12) {
                    ForEach(AccentChoice.allCases, id: \.self) { a in
                        Button { store.data.settings.accent = a } label: {
                            Circle().fill(a.color).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: store.settings.accent == a ? 2 : 0).padding(-3))
                        }.buttonStyle(.plain).help(a.label).accessibilityLabel(a.label)
                    }
                }
                Text("Akcent oznacza tylko zaznaczenie, odtwarzanie i aktywne filtry. Reszta interfejsu zostaje neutralna.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Źródła") {
                Toggle("Subtelne kolory ikon źródeł w sidebarze", isOn: $store.data.settings.sourceTints)
            }
            Section("Notch: reakcja na kursor") {
                Picker("Efekt", selection: $store.data.settings.notchEffect) { ForEach(NotchEffect.allCases, id: \.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                if store.settings.notchEffect == .glow {
                    GlowColorRow(hex: $store.data.settings.glowHex)
                    LabeledContent("Siła") {
                        HStack { Text("słabo").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $store.data.settings.glowIntensity, in: 0.3...2)
                            Text("mocno").font(.caption).foregroundStyle(.secondary) }.frame(width: 240)
                    }
                }
                Text("Łapka wychyla się spod notcha i „pacuje” w stronę kursora tylko wtedy, gdy jest blisko (ok. 105 pt), a poza tym całkiem się chowa. Podświetlenie rozjaśnia się przy kursorze w promieniu ok. 140 pt. Łapka działa tylko przy notchu (górny środek); na bocznych krawędziach jest podświetlenie. Symulacja chodzi tylko, gdy łapka jest widoczna; „Brak” nie zużywa nic.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Waveform") {
                Toggle("Skala automatyczna (najdłuższy dźwięk w widoku = pełna szerokość)", isOn: $store.data.settings.waveformAutoScale)
                if !store.settings.waveformAutoScale {
                    LabeledContent("Stała skala kafla") {
                        Stepper(value: $store.data.settings.waveformScaleSeconds, in: 2...120, step: 1) { Text("\(Int(store.settings.waveformScaleSeconds)) s = pełna szerokość") }
                    }
                }
                Text("SFX i muzyka mają osobne skale, więc 6 s wygląda krócej niż 20 s. Pod waveformem jest podziałka czasu. Odcień waveformu zależy od przedziału długości (zakładka Długości).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

struct DurationsTab: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        Form {
            Section("Podział audio: SFX i muzyka") {
                LabeledContent("Granica SFX / muzyka") {
                    Stepper(value: $store.data.org.sfxMaxSeconds, in: 5...300, step: 5) { Text("\(Int(store.org.sfxMaxSeconds)) s") }
                }
                Text("Dźwięki krótsze lub równe tej wartości to SFX, dłuższe to muzyka. Pojedynczy plik przestawisz prawym przyciskiem: Typ dźwięku.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(MediaClass.allCases.filter(\.hasDuration), id: \.self) { cls in
                Section("\(cls.label): przedziały długości") {
                    ForEach($store.data.org.durationRanges.filter { $0.wrappedValue.mediaClass == cls }) { $r in row($r) }
                    Button("Dodaj przedział") {
                        let step: Double = cls == .music ? 60 : 5
                        let last = store.org.durationRanges.filter { $0.mediaClass == cls }.compactMap(\.maxSeconds).max() ?? 0
                        store.data.org.durationRanges.append(DurationRange(name: DurationRange.autoName(min: last, max: last + step), mediaClass: cls, minSeconds: last, maxSeconds: last + step, shade: 0.75))
                    }
                }
            }
            Text("Każdy przedział to osobna kategoria w sidebarze i odcień szarości waveformu. Zostaw „do” puste dla przedziału bez górnego limitu.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }

    func row(_ r: Binding<DurationRange>) -> some View {
        HStack(spacing: 8) {
            TextField("Nazwa", text: r.name).labelsHidden().frame(width: 120)
            Text("od").foregroundStyle(.secondary).font(.caption)
            TextField("od", value: Binding(get: { r.wrappedValue.minSeconds }, set: { v in edit(r) { $0.minSeconds = max(0, v ?? 0) } }), format: .number).labelsHidden().frame(width: 44).multilineTextAlignment(.trailing)
            Text("do").foregroundStyle(.secondary).font(.caption)
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
            Section("Reguły po słowach w nazwie pliku") {
                ForEach($store.data.org.keywordRules) { $rule in
                    HStack {
                        VStack(spacing: 0) {
                            Button { moveRule(rule.id, -1) } label: { Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)) }.buttonStyle(.borderless).accessibilityLabel("Wyżej")
                            Button { moveRule(rule.id, 1) } label: { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }.buttonStyle(.borderless).accessibilityLabel("Niżej")
                        }
                        TextField("Nazwa", text: $rule.name).labelsHidden().frame(width: 120)
                        TextField("słowa, po przecinku", text: Binding(get: { rule.keywords.joined(separator: ", ") },
                                                                         set: { rule.keywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                            .labelsHidden().textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { store.data.org.keywordRules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("Dodaj regułę") { store.data.org.keywordRules.append(KeywordRule(name: "Nowa", keywords: [])) }
                    Spacer()
                    Button("Przywróć domyślne") { store.data.org.keywordRules = KeywordRule.defaults() }
                }
            }
            Text("Każda reguła tworzy kategorię w sekcji Inteligentne i aktualizuje się sama, gdy pojawią się nowe pliki.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}


struct ShortcutsTab: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        Form {
            Section("Klawisze 1–4: szybki filtr typu") {
                ForEach(0..<4, id: \.self) { i in
                    Picker("Klawisz \(i + 1)", selection: Binding(get: { store.settings.quickKeys[i] }, set: { store.data.settings.quickKeys[i] = $0 })) {
                        ForEach(MediaClass.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Text("W bieżącej kategorii (folder, kolekcja…) pokazuje tylko wybrany typ. Ponowne naciśnięcie zdejmuje filtr. Shift + klawisz zmienia typ zaznaczonego dźwięku (SFX albo muzyka).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Skrót globalny: pokaż / ukryj panel") {
                HotkeyRecorder(spec: $store.data.settings.toggleHotkey)
                Text("Działa z każdej aplikacji (także z Final Cut Pro), bez najeżdżania kursorem na notch. Ten sam skrót chowa panel. Wymaga co najmniej jednego modyfikatora (⌘, ⌥, ⌃ lub ⇧).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Pokaż w Finderze") {
                Picker("Klawisz w panelu", selection: $store.data.settings.finderKey) {
                    ForEach([9, 8, 7, 0], id: \.self) { Text("\($0)").tag($0) }
                    Text("wyłączony").tag(-1)
                }
                Text("Po naciśnięciu pokazuje w Finderze zaznaczone pliki (tak samo jak „Pokaż w Finderze” z menu prawego przycisku).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Pozostałe") {
                LabeledContent("5") { Text("dodaj zaznaczone do ulubionych (lub usuń)") }
                LabeledContent("6") { Text("wyczyść filtry i wyszukiwanie") }
                LabeledContent("Strzałki") { Text("przejście po elementach") }
                LabeledContent("Enter") { Text("zmiana nazwy") }
                LabeledContent("Spacja") { Text("odsłuch (dźwięk) lub większy podgląd (obraz, wideo)") }
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
            Section("Eksport do folderów") {
                Picker("Układ folderów", selection: $layout) { ForEach(ExportLayout.allCases, id: \.self) { Text($0.label).tag($0) } }
                Picker("Sposób", selection: $mode) { ForEach(ExportMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                Text("Tworzy folder „Łapka – eksport” w wybranym miejscu. Nic nie nadpisuje. Dowiązania nie zajmują miejsca, ale przestają działać, gdy przeniesiesz oryginały. Duplikaty są pomijane, jeśli zwijanie jest włączone.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Eksportuj…") { run() }
            }
        }.formStyle(.grouped)
    }

    func run() {
        Pickers.pickFolder(title: "Wybierz miejsce na folder eksportu") { base in
            let dest = base.appendingPathComponent("Łapka – eksport", isDirectory: true)
            let plan = LibraryExporter.plan(items: store.exportItems(), org: store.org, layout: layout)
            let r = LibraryExporter.run(plan, to: dest, mode: mode)
            let a = NSAlert()
            a.messageText = "Eksport zakończony"
            a.informativeText = "Zapisano: \(r.done), pominięto istniejące: \(r.skipped)" + (r.failed.isEmpty ? "" : ", błędy: \(r.failed.count)") + "\n\(dest.path)"
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
        LabeledContent("Skrót") {
            HStack(spacing: 8) {
                Text(recording ? "naciśnij kombinację…" : (spec.map(HotKeyText.string) ?? "wyłączony"))
                    .font(.system(.body, design: .rounded)).foregroundStyle(recording ? Color.accentColor : .primary)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
                Button(recording ? "Anuluj" : "Zmień") { recording ? stop() : start() }
                if spec != nil { Button("Wyłącz") { stop(); spec = nil } }
                else { Button("Domyślny") { spec = .defaultToggle } }
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

/// Kolor poświaty: trzy gotowe kolory i kółko kolorów systemu (dowolny kolor).
struct GlowColorRow: View {
    @Binding var hex: String
    private var color: Binding<Color> {
        Binding(get: { PanelController.glowTint(AppSettingsHex(hex: hex)) },
                set: { c in
                    if let n = NSColor(c).usingColorSpace(.sRGB) { hex = HexColor.format(r: n.redComponent, g: n.greenComponent, b: n.blueComponent) }
                })
    }
    var body: some View {
        LabeledContent("Kolor poświaty") {
            HStack(spacing: 10) {
                ForEach(GlowChoice.allCases, id: \.self) { g in
                    Button { hex = g.hex } label: {
                        Circle().fill(PanelController.glowTint(AppSettingsHex(hex: g.hex))).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(hex == g.hex ? 0.9 : 0.15), lineWidth: hex == g.hex ? 2 : 1))
                    }.buttonStyle(.plain).help(g.label)
                }
                ColorPicker("Własny", selection: color, supportsOpacity: false).labelsHidden()
                    .onAppear { NSColorPanel.shared.mode = .wheel }        // od razu kółko kolorów
            }
        }
    }
}

/// Pomocnik: AppSettings z ustawionym kolorem (do jednego wspólnego przeliczania #RRGGBB -> Color).
private func AppSettingsHex(hex: String) -> AppSettings { var s = AppSettings(); s.glowHex = hex; return s }
