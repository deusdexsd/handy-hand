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
                        .help("Ten plik występuje w \(store.copies(item)) miejscach (duplikaty są zwinięte)")
                        .accessibilityLabel("\(store.copies(item)) kopie")
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
            .frame(height: 64)
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
            Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 64).background(Color.black.opacity(0.22))
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
                    onDown: { store.pressDown(item) }, onPress: { pressed = $0 },
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

    var body: some View {
        let selected = store.selection.contains(item.path)
        HStack(spacing: Self.spacing) {
            Image(systemName: store.isFavorite(item) ? "star.fill" : MetaText.icon(item))
                .font(.system(size: 12)).foregroundStyle(store.isFavorite(item) ? Color.yellow : Color.secondary).frame(width: 16)
            Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if item.kind == .audio {
                WaveformLane(item: item, peaks: waveforms.peaks(for: item), scale: store.waveformScale(for: item),
                             shade: store.shade(item), accentPlayed: nil, accent: accent, height: 22).frame(width: 130)
            } else { Spacer().frame(width: 130) }
            Text(item.kind == .image ? "\(item.pixelWidth ?? 0)×\(item.pixelHeight ?? 0)" : Fmt.duration(item.duration)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 44, alignment: .trailing)
            Text(store.copies(item) > 1 ? "×\(store.copies(item))" : (item.group ?? "")).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).frame(width: Self.groupWidth, alignment: .leading)
        }
        .padding(.horizontal, Self.rowPadding).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(selected ? 0.13 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? accent : .clear, lineWidth: 1.2))
        .scaleEffect(pressed ? 0.985 : 1)
        .overlay(DragOverlay(paths: { store.dragPaths(for: item) }, previewName: { item.name }, isVideo: item.kind == .video,
                             onDown: { store.pressDown(item) }, onPress: { pressed = $0 },
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
        m.addItem(ClosureMenuItem(allFav ? "Usuń z ulubionych" : "Dodaj do ulubionych") { store.toggleFavorite(paths) })
        let coll = NSMenuItem(title: "Dodaj do kolekcji", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for c in store.org.collections { sub.addItem(ClosureMenuItem(c.name) { store.add(paths, toCollection: c.id) }) }
        if !store.org.collections.isEmpty { sub.addItem(.separator()) }
        sub.addItem(ClosureMenuItem("Nowa kolekcja…") {
            store.ask("Nowa kolekcja", placeholder: "Nazwa kolekcji", action: "Utwórz") { store.newCollection(name: $0, paths: paths) }
        })
        coll.submenu = sub; m.addItem(coll)
        if case .collection(let id) = store.config.category {
            m.addItem(ClosureMenuItem("Usuń z tej kolekcji") { store.remove(paths, fromCollection: id) })
        }
        if item.kind == .audio {
            let cur = store.mediaClass(item)
            let overridden = store.org.classOverrides[item.path] != nil
            let tm = NSMenuItem(title: "Typ dźwięku", action: nil, keyEquivalent: "")
            let ts = NSMenu()
            ts.addItem(ClosureMenuItem("SFX", checked: overridden && cur == .sfx) { store.setClass(.sfx, for: paths) })
            ts.addItem(ClosureMenuItem("Muzyka", checked: overridden && cur == .music) { store.setClass(.music, for: paths) })
            ts.addItem(.separator())
            ts.addItem(ClosureMenuItem("Automatycznie (wg długości)", checked: !overridden) { store.setClass(nil, for: paths) })
            tm.submenu = ts; m.addItem(tm)
        }
        m.addItem(ClosureMenuItem("Dodaj tag…") {
            store.ask("Dodaj tag", placeholder: "np. dramat", action: "Dodaj") { store.addTag($0, to: paths) }
        })
        m.addItem(.separator())
        let copies = store.duplicateItems(of: item)
        if copies.count > 1 {
            let dm = NSMenuItem(title: "Kopie (\(copies.count))", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for c in copies {
                let srcName = store.sources.first { $0.id == c.sourceID }?.name ?? "?"
                let parent = URL(fileURLWithPath: c.path).deletingLastPathComponent().lastPathComponent
                sub.addItem(ClosureMenuItem("\(srcName) › \(parent)\(c.path == item.path ? "  (pokazana)" : "")") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: c.path)])
                })
            }
            dm.submenu = sub; m.addItem(dm)
        }
        let srcKind = store.sources.first { $0.id == item.sourceID }?.kind
        if srcKind != .fcpLibrary {
            m.addItem(ClosureMenuItem("Zmień nazwę…") { store.beginRename(item) })
        }
        if srcKind == .files { m.addItem(ClosureMenuItem("Usuń z biblioteki") { store.removeFromLibrary(item) }) }
        m.addItem(ClosureMenuItem("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) }) })
        m.addItem(ClosureMenuItem("Skopiuj ścieżkę") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        })
        return m
    }
}
