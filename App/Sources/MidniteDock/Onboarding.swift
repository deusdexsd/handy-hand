import SwiftUI
import AppKit
import DockCore

// MARK: - Przewodnik pierwszego uruchomienia (okno) + samouczek „co jest co” (przyciemnienie w panelu)
// Wzorzec z „Poradnik – przewodnik pierwszego uruchomienia”. Wszystko zapisuje się od razu; nic nie jest wymagane.

struct OnboardingView: View {
    @ObservedObject var store: LibraryStore
    let onFinish: () -> Void
    let onSkip: () -> Void
    @State var step: Int
    @State private var forward = true
    @State private var loginOn = LoginItem.isOn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let count = 6

    init(store: LibraryStore, step: Int = 0, onFinish: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.store = store; self._step = State(initialValue: step); self.onFinish = onFinish; self.onSkip = onSkip
    }

    private var accent: Color { store.settings.accent.color }

    var body: some View {
        ZStack {
            RadialGradient(colors: [accent.opacity(0.20), accent.opacity(0.06), .clear], center: .top, startRadius: 10, endRadius: 520).allowsHitTesting(false)
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    ForEach(0..<Self.count, id: \.self) { i in
                        Capsule().fill(i == step ? AnyShapeStyle(accent) : AnyShapeStyle(Color.primary.opacity(i < step ? 0.35 : 0.12))).frame(width: i == step ? 22 : 7, height: 7)
                    }
                }.padding(.top, 22).animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: step)
                ZStack {
                    page.id(step)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                                                         removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                footer
            }
        }
        .frame(width: 680, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .focusEffectDisabled()
    }

    private var footer: some View {
        HStack {
            if step > 0 { Button(L("Wstecz", "Back")) { go(-1) } }
            else { Button(L("Pomiń — ustawię później", "Skip — I'll set up later"), action: onSkip).buttonStyle(.borderless).foregroundStyle(.secondary) }
            Spacer()
            Button { step == Self.count - 1 ? onFinish() : go(1) } label: {
                Text(step == Self.count - 1 ? L("Zaczynamy", "Let's go") : L("Dalej", "Next")).frame(minWidth: 90)
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .controlSize(.large).padding(.horizontal, 28).padding(.bottom, 22).padding(.top, 10)
    }

    private func go(_ d: Int) {
        forward = d > 0
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.92)) { step = max(0, min(Self.count - 1, step + d)) }
    }

    @ViewBuilder private var page: some View {
        switch step {
        case 0: welcome
        case 1: panelPage
        case 2: sourcesPage
        case 3: viewsPage
        case 4: lookPage
        default: donePage
        }
    }

    // MARK: kroki
    private func header(_ symbol: String, _ color: Color, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            OnbIcon(symbol: symbol, color: color, size: 56).shadow(color: color.opacity(0.35), radius: 14, y: 6)
            Text(title).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
        }.padding(.top, 18)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            header("hand.point.up.left.fill", accent, L("Witaj w \(AppInfo.name)", "Welcome to \(AppInfo.name)"),
                   L("Panel przy notchu z Twoimi dźwiękami, wideo i obrazami. Znajdujesz plik i przeciągasz go prosto do swojego programu do montażu.",
                     "A notch-docked panel with your sounds, video and images. Find a file and drag it straight into your editor."))
            VStack(spacing: 10) {
                promise("lock.shield.fill", .green, L("Niczego nie zmieniam w Twoich plikach", "I never change your files"), L("Pliki zostają tam, gdzie leżą. Zmieniam nazwę tylko na Twoje wyraźne polecenie.", "Files stay where they are. I rename only when you tell me to."))
                promise("wifi.slash", .blue, L("Wszystko lokalnie", "Everything is local"), L("Bez konta, bez internetu, bez wysyłania czegokolwiek.", "No account, no internet, nothing is sent anywhere."))
                promise("slider.horizontal.3", .orange, L("Wszystko opcjonalne", "Everything is optional"), L("Ten przewodnik można pominąć; ustawienia i samouczek wrócą z menu, kiedy zechcesz.", "You can skip this guide; settings and the tour are always available later."))
            }.padding(.horizontal, 60)
            Spacer(minLength: 0)
        }
    }

    private func promise(_ sym: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            OnbIcon(symbol: sym, color: color)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 13, weight: .semibold)); Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Spacer()
        }.padding(12).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private var panelPage: some View {
        VStack(spacing: 16) {
            header("rectangle.topthird.inset.filled", .purple, L("Gdzie mieszka panel", "Where the panel lives"),
                   L("Najedź kursorem na notch (albo wybraną krawędź ekranu), a panel się rozwinie. Zjedź kursorem — zwinie się sam.", "Move the cursor to the notch (or your chosen screen edge) and the panel opens. Move away and it collapses."))
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Miejsce", "Placement")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(NotchPlacement.allCases, id: \.self) { p in
                        OnbTile(symbol: p == .topCenter ? "rectangle.topthird.inset.filled" : (p == .leftMiddle ? "rectangle.leftthird.inset.filled" : "rectangle.rightthird.inset.filled"),
                                title: p.label, selected: store.settings.placement == p, accent: accent) { store.settings.placement = p }
                    }
                }
                Text(L("Zachowanie", "Behavior")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6)
                HStack(spacing: 10) {
                    ForEach([PanelMode.hover, .pinned], id: \.self) { m in
                        OnbTile(symbol: m == .hover ? "cursorarrow.motionlines" : "pin.fill", title: m.label,
                                subtitle: m == .hover ? L("rozwija się po najechaniu", "opens on hover") : L("zostaje otwarty", "stays open"),
                                selected: store.settings.mode == m, accent: accent) { store.settings.mode = m }
                    }
                }
                Text(L("W pasku menu jest ikona aplikacji: lewy klik otwiera Ustawienia, prawy pokazuje menu.", "The menu bar icon: left click opens Settings, right click shows the menu."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.top, 4)
            }.padding(.horizontal, 60)
            Spacer(minLength: 0)
        }
    }

    private var sourcesPage: some View {
        VStack(spacing: 16) {
            header("folder.badge.plus", .blue, L("Skąd brać pliki", "Where files come from"),
                   L("Wskaż folder albo pojedyncze pliki. Możesz też w każdej chwili przeciągnąć je z Findera na panel.", "Pick a folder or individual files. You can also drag them from Finder onto the panel at any time."))
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button { Pickers.pickFolder(title: L("Wybierz folder z dźwiękami, materiałem lub obrazami", "Choose a folder with sounds, footage or images")) { store.addSource(url: $0, kind: .folder) } } label: {
                        Label(L("Dodaj folder…", "Add folder…"), systemImage: "folder").frame(maxWidth: .infinity)
                    }
                    Button { Pickers.pickFiles { store.addFiles($0) } } label: { Label(L("Dodaj pliki…", "Add files…"), systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                }.controlSize(.large)
                HStack(spacing: 8) {
                    Image(systemName: store.sources.isEmpty ? "circle" : "checkmark.circle.fill").foregroundStyle(store.sources.isEmpty ? Color.secondary : Color.green)
                    Text(store.sources.isEmpty ? L("Nic jeszcze nie dodano — możesz to zrobić później.", "Nothing added yet — you can do it later.")
                                               : L("Dodane źródła: \(store.sources.count), plików: \(store.items.count)", "Sources added: \(store.sources.count), files: \(store.items.count)"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                }
                Text(L("Indeksowanie działa w tle i śledzi zmiany w folderach na bieżąco.", "Indexing runs in the background and follows changes in your folders.")).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }.padding(.horizontal, 60)
            Spacer(minLength: 0)
        }
    }

    private var viewsPage: some View {
        VStack(spacing: 16) {
            header("square.grid.2x2", .pink, L("Jak wyświetlać pliki", "How to show files"),
                   L("Jedna ikona w toolbarze przełącza widoki. Wybierz ten, od którego chcesz zacząć.", "One toolbar icon switches views. Pick the one you want to start with."))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    OnbTile(symbol: "list.bullet", title: L("Lista", "List"), subtitle: L("gęsta, z waveformem", "dense, with waveform"), selected: store.config.viewMode == .list, accent: accent) { store.config.viewMode = .list }
                    OnbTile(symbol: "square.grid.2x2", title: L("Siatka", "Grid"), subtitle: L("kwadratowe kafle", "square tiles"), selected: store.config.viewMode == .grid, accent: accent) { store.config.viewMode = .grid }
                    OnbTile(symbol: "rectangle.3.group", title: L("Minimalistyczny", "Minimalist"), subtitle: L("sam obraz, bez nazw", "just the image, no names"), selected: store.config.viewMode == .minimal, accent: accent) { store.config.viewMode = .minimal }
                }
                Text(L("Dobrze wiedzieć", "Good to know")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 8)
                tip("star.fill", L("Ulubione, tagi i kolekcje (np. po jednej na projekt) porządkują pliki; ten sam plik może być w wielu kolekcjach.", "Favorites, tags and collections (e.g. one per project) organize files; one file can live in many collections."))
                tip("checklist", L("Panel notatek po prawej: globalne albo przypięte do kolekcji, folderu lub typu — przeciągnij notatkę na lewy panel.", "The notes panel on the right: global or pinned to a collection, folder or type — drag a note onto the left sidebar."))
                tip("command", L("Przytrzymaj ⌘ i przeciągaj ikony toolbaru, żeby zmienić ich kolejność.", "Hold ⌘ and drag toolbar icons to reorder them."))
            }.padding(.horizontal, 60)
            Spacer(minLength: 0)
        }
    }

    private func tip(_ sym: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: sym).font(.system(size: 12)).foregroundStyle(accent).frame(width: 18)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lookPage: some View {
        VStack(spacing: 16) {
            header("paintpalette.fill", .orange, L("Wygląd", "Look"), L("Kolor akcentu i ikona w pasku menu. Resztę (przezroczystość, rozmiar, proporcje) znajdziesz w Ustawieniach → Wygląd.", "Accent color and the menu bar icon. The rest (transparency, size, ratios) is in Settings → Appearance."))
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Akcent", "Accent")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(AccentChoice.allCases, id: \.self) { a in
                        Button { store.data.settings.accent = a } label: {
                            Circle().fill(a.color).frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(store.settings.accent == a ? 0.9 : 0), lineWidth: 2).padding(-3))
                        }.buttonStyle(.plain).help(a.label)
                    }
                }
                Text(L("Ikona w pasku menu", "Menu bar icon")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 8)
                HStack(spacing: 8) {
                    ForEach(MenuBarIcon.allCases, id: \.self) { ic in
                        let on = store.settings.menuBarIcon == ic
                        Button { store.data.settings.menuBarIcon = ic } label: {
                            VStack(spacing: 4) {
                                Group {
                                    if let sym = ic.symbol { Image(systemName: sym).font(.system(size: 18)) }
                                    else { VStack(spacing: -3) { Text("HA"); Text("HA") }.font(.system(size: 11, weight: .heavy)) }
                                }.frame(height: 26)
                                Text(ic.label).font(.system(size: 10)).lineLimit(1)
                            }.frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(on ? accent.opacity(0.22) : Color.primary.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? accent : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 60)
            Spacer(minLength: 0)
        }
    }

    private var donePage: some View {
        VStack(spacing: 14) {
            header("checkmark.seal.fill", .green, L("Gotowe", "All set"), L("Oto Twoje ustawienia. Wszystko zmienisz później w Ustawieniach. Zaraz pokażę, co jest gdzie.", "Here are your settings. You can change everything later in Settings. Next I'll show you what is where."))
            VStack(spacing: 8) {
                summary(L("Miejsce panelu", "Panel placement"), store.settings.placement.label, true)
                summary(L("Zachowanie", "Behavior"), store.settings.mode.label, true)
                summary(L("Źródła", "Sources"), store.sources.isEmpty ? L("jeszcze brak — dodasz w panelu", "none yet — add them in the panel") : L("\(store.sources.count), plików: \(store.items.count)", "\(store.sources.count), files: \(store.items.count)"), !store.sources.isEmpty)
                summary(L("Widok", "View"), store.config.viewMode == .list ? L("Lista", "List") : (store.config.viewMode == .grid ? L("Siatka", "Grid") : L("Minimalistyczny", "Minimalist")), true)
                HStack {
                    Image(systemName: loginOn ? "checkmark.circle.fill" : "circle").foregroundStyle(loginOn ? Color.green : Color.secondary)
                    Text(L("Uruchamiaj przy logowaniu", "Open at login")).font(.system(size: 12.5))
                    Spacer()
                    Toggle("", isOn: Binding(get: { loginOn }, set: { on in _ = LoginItem.set(on); loginOn = LoginItem.isOn })).toggleStyle(.switch).labelsHidden()
                }.padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            }.padding(.horizontal, 60)
            Spacer(minLength: 0)
        }
    }

    private func summary(_ title: String, _ value: String, _ ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Color.green : Color.secondary)
            Text(title).font(.system(size: 12.5))
            Spacer()
            Text(value).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

struct OnbIcon: View {
    let symbol: String; let color: Color; var size: CGFloat = 38
    var body: some View {
        ZStack {
            Circle().fill(color.gradient)
            Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct OnbTile: View {
    let symbol: String; let title: String; var subtitle: String?; let selected: Bool; let accent: Color; let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                Text(title).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.center)
                if let subtitle { Text(subtitle).font(.system(size: 10.5)).opacity(0.8).multilineTextAlignment(.center) }
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 84).padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.primary.opacity(hover ? 0.09 : 0.06))))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }.accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Samouczek „co jest co”

struct CoachStep: Identifiable {
    let id = UUID()
    var anchor: String?      // nil = dymek na środku
    var symbol: String
    var title: String
    var text: String
}

struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) { value.merge(nextValue()) { $1 } }
}

extension View {
    func coachAnchor(_ id: String) -> some View { anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [id: $0] } }
}

enum Tour {
    /// Kroki samouczka; te, których elementu nie ma na ekranie (np. suwak przy pustej bibliotece), są pomijane.
    static var steps: [CoachStep] { [
        CoachStep(anchor: "sidebar", symbol: "sidebar.left", title: L("Kategorie", "Categories"),
                  text: L("Ulubione, typy (SFX, muzyka, wideo, obrazy), foldery i kolekcje. Przeciągnij plik na kolekcję, żeby go do niej dodać. Ikona po lewej w toolbarze chowa ten panel.", "Favorites, types (SFX, music, video, images), folders and collections. Drag a file onto a collection to add it. The icon on the left of the toolbar hides this panel.")),
        CoachStep(anchor: "search", symbol: "magnifyingglass", title: L("Szukanie", "Search"),
                  text: L("Wpisz nazwę pliku. Ikona tagu obok włącza szukanie też w tagach i rozszerzeniach.", "Type a file name. The tag icon next to it also searches tags and extensions.")),
        CoachStep(anchor: "tb-filter", symbol: "line.3.horizontal.decrease.circle", title: L("Filtry", "Filters"),
                  text: L("Zawęź listę po typie, długości i dacie. Aktywny filtr podświetla się akcentem.", "Narrow the list by type, length and date. An active filter is highlighted.")),
        CoachStep(anchor: "tb-sort", symbol: "arrow.up.arrow.down", title: L("Sortowanie", "Sorting"), text: L("Nazwa, długość, data, rozmiar — rosnąco lub malejąco.", "Name, length, date, size — ascending or descending.")),
        CoachStep(anchor: "tb-view", symbol: "square.grid.2x2", title: L("Widok", "View"),
                  text: L("Jedna ikona przełącza: lista → siatka → minimalistyczny. Przytrzymaj ⌘ i przeciągaj ikony toolbaru, żeby zmienić ich kolejność.", "One icon cycles list → grid → minimalist. Hold ⌘ and drag toolbar icons to reorder them.")),
        CoachStep(anchor: "tb-notes", symbol: "checklist", title: L("Notatki", "Notes"),
                  text: L("Panel notatek i zadań po prawej: globalnych albo przypiętych do kolekcji, folderu lub typu. Przeciągnij notatkę na pozycję w lewym panelu.", "A notes and tasks panel on the right: global or pinned to a collection, folder or type. Drag a note onto an item in the left sidebar.")),
        CoachStep(anchor: "tb-pin", symbol: "pin", title: L("Przypięcie", "Pin"), text: L("Przypięty panel zostaje otwarty, nawet gdy zjedziesz kursorem.", "A pinned panel stays open even when the cursor leaves.")),
        CoachStep(anchor: "tb-settings", symbol: "gearshape", title: L("Ustawienia", "Settings"),
                  text: L("Tu jest wszystko: wygląd, skróty, jakość miniatur. Otworzysz je też lewym klikiem w ikonę w pasku menu, a Esc je zamknie.", "Everything lives here: look, shortcuts, thumbnail quality. Also opens with a left click on the menu bar icon; Esc closes it.")),
        CoachStep(anchor: "content", symbol: "square.grid.3x3", title: L("Twoje pliki", "Your files"),
                  text: L("Kliknij, żeby odsłuchać; przeciągnij do edytora. Prawy przycisk to menu (ulubione, kolekcja, tag, nazwa). ⌘A/⌘C/⌘V/⌘Z działają jak w Finderze, spacja to podgląd.", "Click to listen; drag into your editor. Right click for the menu (favorite, collection, tag, rename). ⌘A/⌘C/⌘V/⌘Z work like in Finder; Space previews.")),
        CoachStep(anchor: "sizeslider", symbol: "slider.horizontal.3", title: L("Rozmiar", "Size"), text: L("Suwak zmienia wielkość elementów w każdym widoku.", "The slider changes the item size in every view.")),
        CoachStep(anchor: "previewbar", symbol: "play.circle.fill", title: L("Odtwarzacz", "Player"), text: L("Tu słychać i widać zaznaczony plik: odtwarzanie, przewijanie, czas.", "Here you hear and see the selected file: playback, scrubbing, time.")),
        CoachStep(anchor: nil, symbol: "menubar.rectangle", title: L("Ikona w pasku menu", "Menu bar icon"),
                  text: L("Lewy klik otwiera Ustawienia, prawy pokazuje menu z trybem panelu i przewodnikiem. Przewodnik i ten samouczek wrócą tam w każdej chwili.", "Left click opens Settings, right click shows the menu with panel mode and the guide. The guide and this tour are always available there.")),
    ] }
}

struct CoachOverlay: View {
    @ObservedObject var store: LibraryStore
    let anchors: [String: Anchor<CGRect>]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let steps = Tour.steps.filter { $0.anchor == nil || anchors[$0.anchor!] != nil }
            let _ = { store.tourAvailable = steps.count }()
            let i = min(max(0, store.tourStep), max(0, steps.count - 1))
            if store.tourActive, steps.indices.contains(i) {
                let s = steps[i]
                let rect = s.anchor.flatMap { anchors[$0] }.map { geo[$0].insetBy(dx: -5, dy: -5) }
                let accent = store.settings.accent.color
                ZStack(alignment: .topLeading) {
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: geo.size))
                        if let rect { p.addRoundedRect(in: rect, cornerSize: CGSize(width: 9, height: 9)) }
                    }
                    .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle()).onTapGesture { store.tourNext(count: steps.count) }
                    if let rect {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(accent, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY).allowsHitTesting(false)
                    }
                    bubble(s, index: i, count: steps.count, accent: accent).frame(width: 300).position(position(rect, in: geo.size))
                }
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9), value: i)
            }
        }
    }

    private func bubble(_ s: CoachStep, index: Int, count: Int, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) { OnbIcon(symbol: s.symbol, color: accent, size: 28); Text(s.title).font(.system(size: 14, weight: .semibold)) }
            Text(s.text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(index + 1) / \(count)").font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                Button(L("Pomiń", "Skip")) { store.tourFinish() }.buttonStyle(.borderless).foregroundStyle(.secondary)
                Button(index == count - 1 ? L("Gotowe", "Done") : L("Dalej", "Next")) { store.tourNext(count: count) }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    /// Dymek pod elementem (albo nad nim, gdy brakuje miejsca); bez elementu — na środku.
    private func position(_ r: CGRect?, in size: CGSize) -> CGPoint {
        guard let r else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let w: CGFloat = 300, h: CGFloat = 165
        let x = min(max(w / 2 + 10, r.midX), size.width - w / 2 - 10)
        if r.width > size.width * 0.5, r.height > size.height * 0.4 { return CGPoint(x: size.width / 2, y: size.height / 2) }        // duży obszar: dymek na nim
        if r.maxX + 14 + w < size.width, r.height > 60 { return CGPoint(x: r.maxX + 14 + w / 2, y: min(max(h / 2 + 10, r.midY), size.height - h / 2 - 10)) }
        let below = r.maxY + 14 + h < size.height
        return CGPoint(x: x, y: below ? r.maxY + 14 + h / 2 : max(h / 2 + 10, r.minY - 14 - h / 2))
    }
}
