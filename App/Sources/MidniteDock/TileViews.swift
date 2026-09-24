import SwiftUI
import AppKit
import DockCore

struct WaveformLane: View {
    let item: MediaItem
    let peaks: [Float]?
    let scale: Double
    let shade: Double
    let accentPlayed: Double?     // 0...1 postęp odtwarzania (waveform w podglądzie), nil = brak
    let accent: Color
    var height: CGFloat = 64
    var ticks = false             // podziałka czasu pod waveformem (kafle)

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.width
            // Skala czasu wspólna dla widoku: krótszy dźwięk = krótszy waveform.
            let w = max(8, min(full, full * CGFloat(item.duration / max(0.5, scale))))
            Canvas { ctx, size in
                let area = ticks ? size.height - 14 : size.height - 6          // pasek na podziałkę u dołu
                let midY = area / 2 + 2
                var base = Path(); base.move(to: CGPoint(x: 0, y: midY)); base.addLine(to: CGPoint(x: size.width, y: midY))
                ctx.stroke(base, with: .color(.primary.opacity(0.10)), lineWidth: 0.5)
                if let peaks, !peaks.isEmpty {
                    let step: CGFloat = 3
                    let n = max(1, Int(w / step))
                    let alpha = 0.25 + 0.65 * shade
                    for i in 0..<n {
                        let src = min(peaks.count - 1, i * peaks.count / n)
                        let h = max(0.05, CGFloat(peaks[src])) * area
                        let played = accentPlayed.map { CGFloat(i) / CGFloat(n) <= CGFloat($0) } ?? false
                        ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * step, y: midY - h / 2, width: 2, height: h), cornerRadius: 1),
                                 with: .color(played ? accent : Color.primary.opacity(alpha)))
                    }
                } else {
                    var p = Path(); p.move(to: CGPoint(x: 0, y: midY)); p.addLine(to: CGPoint(x: w, y: midY))
                    ctx.stroke(p, with: .color(.primary.opacity(0.25)), lineWidth: 1.5)
                }
                if ticks {
                    let step = ScaleTicks.step(forScale: scale)
                    var t = step
                    while t < scale - 0.001 {
                        let x = size.width * CGFloat(t / scale)
                        ctx.fill(Path(CGRect(x: x - 0.25, y: size.height - 11, width: 0.5, height: 4)), with: .color(.primary.opacity(0.28)))
                        t += step
                    }
                    ctx.draw(ctx.resolve(Text(Fmt.duration(scale)).font(.system(size: 8.5)).foregroundStyle(.tertiary)),
                             at: CGPoint(x: size.width - 1, y: size.height - 4), anchor: .trailing)
                    ctx.draw(ctx.resolve(Text("0").font(.system(size: 8.5)).foregroundStyle(.tertiary)), at: CGPoint(x: 1, y: size.height - 4), anchor: .leading)
                }
            }
        }
        .frame(height: height)
    }
}

enum MetaText {
    static func icon(_ i: MediaItem) -> String { switch i.kind { case .audio: "waveform"; case .video: "film"; case .image: "photo" } }
    static func line(_ i: MediaItem) -> String {
        i.kind == .image ? "\(i.pixelWidth ?? 0)×\(i.pixelHeight ?? 0) · \(i.ext.uppercased())" : "\(Fmt.duration(i.duration)) · \(i.ext.uppercased())"
    }
}

struct TileView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var waveforms: WaveformStore
    @ObservedObject var thumbs: ThumbnailStore
    let item: MediaItem
    @Environment(\.dockAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var hover = false

    var body: some View {
        let selected = store.selection.contains(item.path)
        let fav = store.isFavorite(item)
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                lane
                if store.copies(item) > 1 {
                    Text("×\(store.copies(item))").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 1.5).background(.ultraThinMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(5)
                        .help(L("Ten plik występuje w \(store.copies(item)) miejscach (duplikaty są zwinięte)", "This file appears in \(store.copies(item)) places (duplicates are collapsed)"))
                        .accessibilityLabel(L("\(store.copies(item)) kopie", "\(store.copies(item)) copies"))
                }
                if fav || hover {
                    Image(systemName: fav ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(fav ? Color.yellow : Color.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                        .onTapGesture { store.toggleFavorite([item.path]) }
                        .accessibilityLabel(fav ? "Usuń z ulubionych" : "Dodaj do ulubionych")
                }
            }
            .frame(height: 64 * store.settings.tileScale)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: MetaText.icon(item)).font(.system(size: 9))
                    Text(MetaText.line(item))
                }
                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(selected ? 0.13 : (hover ? 0.09 : 0.06))))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? accent : .clear, lineWidth: 1.5))
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.25, dampingFraction: 1), value: pressed)
        .overlay(dragOverlay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.kind.label), \(Fmt.duration(item.duration))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.click(item, command: false, shift: false) }
    }

    @ViewBuilder private var lane: some View {
        if item.kind == .audio {
            WaveformLane(item: item, peaks: waveforms.peaks(for: item), scale: store.waveformScale(for: item),
                         shade: store.shade(item), accentPlayed: nil, accent: accent, ticks: true)
        } else if let img = thumbs.image(for: item) {
            Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 64 * store.settings.tileScale).background(Color.black.opacity(0.22))
                .overlay(alignment: .bottomTrailing) {
                    if item.kind == .video { Text(Fmt.duration(item.duration)).font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 1.5).background(.ultraThinMaterial, in: Capsule()).padding(4) }
                }
        } else {
            ZStack { Color.primary.opacity(0.08); Image(systemName: MetaText.icon(item)).foregroundStyle(.secondary) }
        }
    }

    private var dragOverlay: some View {
        DragOverlay(paths: { store.dragPaths(for: item) }, previewName: { item.name }, isVideo: item.kind == .video,
                    passThrough: CGRect(x: 4, y: 4, width: 30, height: 30),
                    onDown: { shift, command in store.pressDown(item, shift: shift, command: command) }, onPress: { pressed = $0 },
                    onClick: { c, s in store.click(item, command: c, shift: s) },
                    onDrag: { store.dragging = $0 }, onHover: { hover = $0 },
                    menu: { ItemMenu.build(store: store, item: item) })
    }
}

/// Widok minimalistyczny: prawdziwa siatka „Pinterest” — kolumny o równej szerokości, każdy kafel w naturalnej
/// proporcji materiału, bez dziur (nowy element trafia do aktualnie najkrótszej kolumny), bez karty/obwódki dookoła.
struct MasonryGrid: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var waveforms: WaveformStore
    @ObservedObject var thumbs: ThumbnailStore
    let items: [MediaItem]

    var body: some View {
        let cols = max(1, store.gridColumns)
        let cw = MasonryLayout.columnWidth(contentWidth: store.contentWidth, columns: cols)
        let heights = items.map { MasonryLayout.tileHeight(isAudio: $0.kind == .audio, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight, columnWidth: cw, scale: store.settings.tileScale) }
        let distributed = MasonryLayout.distribute(heights: heights, columns: cols)
        HStack(alignment: .top, spacing: MasonryLayout.spacing) {
            ForEach(0..<cols, id: \.self) { c in
                LazyVStack(spacing: MasonryLayout.spacing) {
                    ForEach(distributed[c], id: \.self) { i in
                        MinimalistTile(store: store, waveforms: waveforms, thumbs: thumbs, item: items[i], height: heights[i]).id(items[i].path)
                    }
                }.frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
    }

}

/// Kafel w widoku minimalistycznym: sam obraz/waveform w naturalnej proporcji, zaokrąglone rogi, bez tła karty
/// i bez paddingu dookoła — jak na Pintereście. Gwiazdka, znaczek kopii, zaznaczenie i przeciąganie zostają.
struct MinimalistTile: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var waveforms: WaveformStore
    @ObservedObject var thumbs: ThumbnailStore
    let item: MediaItem
    let height: Double
    @Environment(\.dockAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var hover = false

    var body: some View {
        let selected = store.selection.contains(item.path)
        let fav = store.isFavorite(item)
        ZStack(alignment: .topLeading) {
            content
            if store.copies(item) > 1 {
                Text("×\(store.copies(item))").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 1.5).background(.ultraThinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(6)
                    .help(L("Ten plik występuje w \(store.copies(item)) miejscach (duplikaty są zwinięte)", "This file appears in \(store.copies(item)) places (duplicates are collapsed)"))
                    .accessibilityLabel(L("\(store.copies(item)) kopie", "\(store.copies(item)) copies"))
            }
            if fav || hover {
                Image(systemName: fav ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(fav ? Color.yellow : Color.white)
                    .padding(6)
                    .contentShape(Rectangle())
                    .onTapGesture { store.toggleFavorite([item.path]) }
                    .accessibilityLabel(fav ? L("Usuń z ulubionych", "Remove from favorites") : L("Dodaj do ulubionych", "Add to favorites"))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? accent : .clear, lineWidth: 2))
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.25, dampingFraction: 1), value: pressed)
        .overlay(dragOverlay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.kind.label), \(Fmt.duration(item.duration))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.click(item, command: false, shift: false) }
    }

    @ViewBuilder private var content: some View {
        Group {
            if item.kind == .audio {
                WaveformLane(item: item, peaks: waveforms.peaks(for: item), scale: store.waveformScale(for: item),
                             shade: store.shade(item), accentPlayed: nil, accent: accent, ticks: true)
                    .background(Color.primary.opacity(0.08))
                    .overlay(alignment: .bottomLeading) {
                        if !store.settings.minimalistHideAudioNames {
                            Text(item.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).padding(.horizontal, 7).padding(.bottom, 4)
                        }
                    }
            } else if let img = thumbs.image(for: item) {
                if MasonryLayout.isSmallImage(pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight) {
                    // Mała ikona / PNG: w oryginalnym rozmiarze (nie rozciągamy do szerokości kolumny), wyśrodkowana na neutralnym tle.
                    ZStack { Color.primary.opacity(0.08); Image(nsImage: img).interpolation(.high).frame(width: img.size.width, height: img.size.height) }
                } else {
                    Color.black.opacity(0.22).overlay { Image(nsImage: img).resizable().scaledToFill() }.clipped()
                        .overlay(alignment: .bottomTrailing) {
                            if item.kind == .video { Text(Fmt.duration(item.duration)).font(.system(size: 10, weight: .medium)).monospacedDigit()
                                .padding(.horizontal, 5).padding(.vertical, 1.5).background(.ultraThinMaterial, in: Capsule()).padding(4) }
                        }
                }
            } else {
                ZStack { Color.primary.opacity(0.08); Image(systemName: MetaText.icon(item)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)      // stała wysokość: wczytanie miniatury niczego nie przesuwa
    }

    private var dragOverlay: some View {
        DragOverlay(paths: { store.dragPaths(for: item) }, previewName: { item.name }, isVideo: item.kind == .video,
                    passThrough: CGRect(x: 4, y: 4, width: 30, height: 30),
                    onDown: { shift, command in store.pressDown(item, shift: shift, command: command) }, onPress: { pressed = $0 },
                    onClick: { c, s in store.click(item, command: c, shift: s) },
                    onDrag: { store.dragging = $0 }, onHover: { hover = $0 },
                    menu: { ItemMenu.build(store: store, item: item) })
    }
}

struct RowView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var waveforms: WaveformStore
    let item: MediaItem
    static let rowPadding: CGFloat = 8, groupWidth: CGFloat = 80, spacing: CGFloat = 10
    @Environment(\.dockAccent) private var accent
    @State private var pressed = false
    @State private var hover = false

    var body: some View {
        let selected = store.selection.contains(item.path)
        let fav = store.isFavorite(item)
        HStack(spacing: Self.spacing) {
            // Ikona typu; przy ulubionym albo najechaniu zamienia się w klikalną gwiazdkę (dodaje/usuwa z ulubionych).
            Image(systemName: fav ? "star.fill" : (hover ? "star" : MetaText.icon(item)))
                .font(.system(size: 12)).foregroundStyle(fav ? Color.yellow : Color.secondary).frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onTapGesture { store.toggleFavorite([item.path]) }
                .help(fav ? L("Usuń z ulubionych", "Remove from favorites") : L("Dodaj do ulubionych", "Add to favorites"))
                .onHover { hover = $0 }
            Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if item.kind == .audio {
                WaveformLane(item: item, peaks: waveforms.peaks(for: item), scale: store.waveformScale(for: item),
                             shade: store.shade(item), accentPlayed: nil, accent: accent, height: 22).frame(width: 130)
            } else { Spacer().frame(width: 130) }
            Text(item.kind == .image ? "\(item.pixelWidth ?? 0)×\(item.pixelHeight ?? 0)" : Fmt.duration(item.duration)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 44, alignment: .trailing)
            Text(store.copies(item) > 1 ? "×\(store.copies(item))" : (item.group ?? "")).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).frame(width: Self.groupWidth, alignment: .leading)
        }
        .padding(.horizontal, Self.rowPadding).frame(height: 22 + 8 * store.settings.tileScale)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(selected ? 0.13 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? accent : .clear, lineWidth: 1.2))
        .scaleEffect(pressed ? 0.985 : 1)
        .overlay(DragOverlay(paths: { store.dragPaths(for: item) }, previewName: { item.name }, isVideo: item.kind == .video,
                             passThrough: CGRect(x: 0, y: 0, width: Self.rowPadding + 16 + Self.spacing, height: 30),   // gwiazdka: klik ma trafić do SwiftUI, nie do warstwy przeciągania
                             onDown: { shift, command in store.pressDown(item, shift: shift, command: command) }, onPress: { pressed = $0 },
                             onClick: { c, s in store.click(item, command: c, shift: s) },
                             onDrag: { store.dragging = $0 }, onHover: { _ in },
                             menu: { ItemMenu.build(store: store, item: item) }))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.kind.label), \(Fmt.duration(item.duration))")
        .accessibilityAddTraits(.isButton)
    }
}

@MainActor
enum ItemMenu {
    static func build(store: LibraryStore, item: MediaItem) -> NSMenu {
        let paths = store.dragPaths(for: item)
        let m = NSMenu()
        let allFav = paths.allSatisfy { store.org.favorites.contains($0) }
        m.addItem(ClosureMenuItem(allFav ? L("Usuń z ulubionych", "Remove from favorites") : L("Dodaj do ulubionych", "Add to favorites")) { store.toggleFavorite(paths) })
        let coll = NSMenuItem(title: L("Dodaj do kolekcji", "Add to collection"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for c in store.org.collections { sub.addItem(ClosureMenuItem(c.name) { store.add(paths, toCollection: c.id) }) }
        if !store.org.collections.isEmpty { sub.addItem(.separator()) }
        sub.addItem(ClosureMenuItem(L("Nowa kolekcja…", "New collection…")) {
            store.ask(L("Nowa kolekcja", "New collection"), placeholder: L("Nazwa kolekcji", "Collection name"), action: L("Utwórz", "Create")) { store.newCollection(name: $0, paths: paths) }
        })
        coll.submenu = sub; m.addItem(coll)
        if case .collection(let id) = store.config.category {
            m.addItem(ClosureMenuItem(L("Usuń z tej kolekcji", "Remove from this collection")) { store.remove(paths, fromCollection: id) })
        }
        if item.kind == .audio {
            let cur = store.mediaClass(item)
            let overridden = store.org.classOverrides[item.path] != nil
            let tm = NSMenuItem(title: L("Typ dźwięku", "Sound type"), action: nil, keyEquivalent: "")
            let ts = NSMenu()
            ts.addItem(ClosureMenuItem("SFX", checked: overridden && cur == .sfx) { store.setClass(.sfx, for: paths) })
            ts.addItem(ClosureMenuItem(L("Muzyka", "Music"), checked: overridden && cur == .music) { store.setClass(.music, for: paths) })
            ts.addItem(.separator())
            ts.addItem(ClosureMenuItem(L("Automatycznie (wg długości)", "Automatic (by length)"), checked: !overridden) { store.setClass(nil, for: paths) })
            tm.submenu = ts; m.addItem(tm)
        }
        m.addItem(ClosureMenuItem(L("Dodaj tag…", "Add tag…")) {
            store.ask(L("Dodaj tag", "Add tag"), placeholder: L("np. dramat", "e.g. drama"), action: L("Dodaj", "Add")) { store.addTag($0, to: paths) }
        })
        m.addItem(.separator())
        let copies = store.duplicateItems(of: item)
        if copies.count > 1 {
            let dm = NSMenuItem(title: L("Kopie (\(copies.count))", "Copies (\(copies.count))"), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for c in copies {
                let srcName = store.sources.first { $0.id == c.sourceID }?.name ?? "?"
                let parent = URL(fileURLWithPath: c.path).deletingLastPathComponent().lastPathComponent
                sub.addItem(ClosureMenuItem("\(srcName) › \(parent)" + (c.path == item.path ? L("  (pokazana)", "  (shown)") : "")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: c.path)])
                })
            }
            dm.submenu = sub; m.addItem(dm)
        }
        let srcKind = store.sources.first { $0.id == item.sourceID }?.kind
        if srcKind != .fcpLibrary {
            m.addItem(ClosureMenuItem(L("Zmień nazwę…", "Rename…")) { store.beginRename(item) })
        }
        if srcKind == .files { m.addItem(ClosureMenuItem(L("Usuń z biblioteki", "Remove from library")) { store.removeFromLibrary(item) }) }
        m.addItem(ClosureMenuItem(L("Pokaż w Finderze", "Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) }) })
        m.addItem(ClosureMenuItem(L("Kopiuj pliki", "Copy files") + "  ⌘C") { store.copyFilesToPasteboard(paths) })
        m.addItem(ClosureMenuItem(L("Skopiuj ścieżkę", "Copy path")) {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        })
        return m
    }
}
