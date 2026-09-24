import SwiftUI
import AppKit
import AVFoundation
import DockCore

struct EmptyState: View {
    let icon: String, title: String, text: String
    var button: String?
    var action: (() -> Void)?
    var extra: AnyView?
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 260)
            if let extra { extra.padding(.top, 4) }
            else if let button, let action { Button(button, action: action).controlSize(.regular).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
    }
}

private struct SoftTopEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.scrollEdgeEffectStyle(.soft, for: .top) } else { content }
    }
}

struct ContentArea: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        let vis = store.visible
        VStack(spacing: 0) {
            contentBody(vis)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { store.contentWidth = g.size.width; store.gridColumns = GridNavigation.columns(width: g.size.width, minItem: 148 * store.settings.tileScale) }
                    .onChange(of: g.size.width) { _, w in
                        // Szerokość służy tylko do policzenia wysokości kafli i liczby kolumn; sam układ nie zależy od niej (bez pętli sprzężenia).
                        let changed = abs(store.contentWidth - w) > 0.5
                        store.contentWidth = w; store.gridColumns = GridNavigation.columns(width: w, minItem: 148 * store.settings.tileScale)
                        if changed, store.config.viewMode == .minimal { store.objectWillChange.send() }     // kafle przeliczają wysokości do nowej szerokości kolumny
                    }
                    .onChange(of: store.settings.tileScale) { _, sc in store.gridColumns = GridNavigation.columns(width: g.size.width, minItem: 148 * sc); store.objectWillChange.send() }
            })
            .dropDestination(for: URL.self) { urls, _ in store.addDropped(urls) }   // foldery i pliki z Findera
            if !store.items.isEmpty { SizeSlider(store: store).coachAnchor("sizeslider") }     // osobny pasek pod listą: nie zasłania elementów
        }
    }

    @ViewBuilder private func contentBody(_ vis: [MediaItem]) -> some View {
        Group {
            if store.sources.isEmpty {
                EmptyState(icon: "folder.badge.plus", title: L("Dodaj pierwsze źródło", "Add your first source"),
                           text: L("Wskaż folder, pojedyncze pliki albo bibliotekę FCP. Możesz też przeciągnąć je tutaj z Findera. Appka zaindeksuje pliki i będzie na bieżąco obserwować zmiany.",
                                   "Point to a folder, individual files, or an FCP library. You can also drag them here from Finder. The app will index the files and keep watching for changes."),
                           extra: AnyView(Menu(L("Dodaj…", "Add…")) { AddMenuItems(store: store) }.menuStyle(.borderedButton).fixedSize()))
            } else if store.isIndexing && store.items.isEmpty {
                VStack(spacing: 10) { ProgressView().controlSize(.small); Text(L("Indeksuję pliki…", "Indexing files…")).font(.system(size: 12)).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vis.isEmpty {
                if !store.search.isEmpty {
                    EmptyState(icon: "magnifyingglass", title: L("Brak wyników", "No results"), text: L("Nic w „\(store.categoryTitle)” nie pasuje do „\(store.search)”.", "Nothing in “\(store.categoryTitle)” matches “\(store.search)”."),
                               button: L("Szukaj we wszystkich", "Search everywhere")) { store.select(category: .all) }
                } else if store.config.filters.isActive {
                    EmptyState(icon: "line.3.horizontal.decrease.circle", title: L("Filtry wykluczają wszystko", "Filters exclude everything"), text: L("Żaden element w tej kategorii nie spełnia aktywnych filtrów.", "Nothing in this category matches the active filters."),
                               button: L("Wyczyść filtry", "Clear filters")) { store.config.filters = .none }
                } else {
                    EmptyState(icon: "tray", title: L("Ta kategoria jest pusta", "This category is empty"), text: L("Przeciągnij tu pliki z panelu albo wybierz inną kategorię.", "Drop files here from the panel, or choose another category."))
                }
            } else if store.config.viewMode != .list {
                ScrollViewReader { proxy in
                    ScrollView {
                        if store.config.viewMode == .minimal {
                            MasonryGrid(store: store, waveforms: store.waveforms, thumbs: store.thumbnails, items: vis)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148 * store.settings.tileScale, maximum: 200 * store.settings.tileScale), spacing: 10)], spacing: 10) {
                                ForEach(vis) { TileView(store: store, waveforms: store.waveforms, thumbs: store.thumbnails, item: $0).id($0.path) }
                            }.padding(.horizontal, 10).padding(.bottom, 10)
                        }
                    }
                    .modifier(SoftTopEdge())
                    .onChange(of: store.scrollTarget) { _, t in if let t { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(t, anchor: nil) } } }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) { ForEach(vis) { RowView(store: store, waveforms: store.waveforms, item: $0).id($0.path) } }
                            .padding(.horizontal, 8).padding(.bottom, 8)
                    }
                    .modifier(SoftTopEdge())
                    .onChange(of: store.scrollTarget) { _, t in if let t { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(t, anchor: nil) } } }
                }
            }
        }
    }
}

/// Suwak wielkości elementów (działa w liście, siatce i widoku minimalistycznym) — mała kapsuła w rogu, jak w Finderze.
struct SizeSlider: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3").font(.system(size: 8)).foregroundStyle(.secondary)
            Slider(value: $store.data.settings.tileScale, in: 0.35...1.8).controlSize(.mini).frame(width: 84)
            Image(systemName: "square.grid.2x2").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .help(L("Rozmiar elementów", "Item size"))
        .accessibilityLabel(L("Rozmiar elementów", "Item size"))
    }
}

struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer?
    final class V: NSView {
        let layerP = AVPlayerLayer()
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.addSublayer(layerP); layerP.videoGravity = .resizeAspect }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() { super.layout(); layerP.frame = bounds }
    }
    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) { v.layerP.player = player }
}

struct PreviewBar: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var previewer: Previewer
    @ObservedObject var thumbs: ThumbnailStore      // bez tego pasek nie wiedział, że miniatura już się wczytała
    @Environment(\.dockAccent) private var accent

    private var expandButton: some View {
        Button { store.data.settings.bigMediaPreview = true } label: { Image(systemName: "chevron.up").font(.system(size: 11)).frame(width: 24, height: 24) }
            .buttonStyle(PressableIconStyle()).foregroundStyle(.secondary).help(L("Większy podgląd", "Bigger preview")).accessibilityLabel(L("Większy podgląd", "Bigger preview"))
    }

    var body: some View {
        Group {
            if let it = previewer.item, it.kind != .audio, store.settings.bigMediaPreview {
                // Większy podgląd obrazu / wideo w pasku na dole (opcja).
                HStack(alignment: .top, spacing: 12) {
                    LargePreviewView(store: store, previewer: previewer, thumbs: thumbs, showsInfoBar: false)
                        .frame(width: 340, height: 190)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(it.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        Text(it.kind == .image ? "\(it.pixelWidth ?? 0)×\(it.pixelHeight ?? 0) · \(ByteCountFormatter.string(fromByteCount: it.size, countStyle: .file)) · \(it.ext.uppercased())"
                                               : "\(Fmt.duration(it.duration)) · \(it.ext.uppercased())")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button { store.data.settings.bigMediaPreview = false } label: {
                            Label(L("Mniejszy podgląd", "Smaller preview"), systemImage: "chevron.down").font(.system(size: 11))
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12).background(Color.primary.opacity(0.045))
            } else if let it = previewer.item, it.kind == .image {
                HStack(spacing: 10) {
                    Group {
                        if let img = thumbs.image(for: it) { Image(nsImage: img).resizable().scaledToFit() } else { ZStack { Color.primary.opacity(0.08); if thumbs.hasFailed(it) { Image(systemName: "photo").foregroundStyle(.tertiary) } else { ProgressView().controlSize(.mini) } } }
                    }
                    .frame(width: 96, height: 54).background(Color.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text("\(it.pixelWidth ?? 0)×\(it.pixelHeight ?? 0) · \(ByteCountFormatter.string(fromByteCount: it.size, countStyle: .file)) · \(it.ext.uppercased())")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    expandButton
                }
                .padding(.horizontal, 12).padding(.vertical, 8).background(Color.primary.opacity(0.045))
            } else if let it = previewer.item {
                HStack(spacing: 10) {
                    if it.kind == .video {
                        PlayerLayerView(player: previewer.player).frame(width: 96, height: 54)
                            .background(Color.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Button { previewer.toggle() } label: {
                        Image(systemName: previewer.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 12))
                            .frame(width: 30, height: 30).background(Circle().fill(accent)).foregroundStyle(.white)
                    }
                    .buttonStyle(PressableIconStyle()).accessibilityLabel(previewer.isPlaying ? L("Wstrzymaj", "Pause") : L("Odtwórz", "Play"))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(it.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text("\(Fmt.clock(previewer.time)) / \(Fmt.clock(it.duration))").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Scrubber(item: it, store: store, waveforms: store.waveforms, previewer: previewer)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.primary.opacity(0.045))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 6) {
                    if store.isIndexing { ProgressView().controlSize(.mini) }
                    Text(store.isIndexing ? L("Indeksuję…", "Indexing…") : L("\(store.visible.count) elementów", "\(store.visible.count) items")).font(.system(size: 11)).foregroundStyle(.tertiary)
                    Spacer()
                }.padding(.horizontal, 12).frame(height: 28)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 1), value: previewer.item?.path)
    }
}

struct Scrubber: View {
    let item: MediaItem
    @ObservedObject var store: LibraryStore
    @ObservedObject var waveforms: WaveformStore
    @ObservedObject var previewer: Previewer
    @Environment(\.dockAccent) private var accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if item.kind == .audio {
                    // Pełna szerokość = cała długość klipu (skala jak w kaflu, tu 1:1).
                    WaveformLane(item: item, peaks: waveforms.peaks(for: item), scale: item.duration, shade: 1,
                                 accentPlayed: previewer.fraction, accent: accent, height: 34)
                } else {
                    Capsule().fill(Color.primary.opacity(0.15)).frame(height: 4)
                    Capsule().fill(accent).frame(width: geo.size.width * previewer.fraction, height: 4)
                }
                Rectangle().fill(accent).frame(width: 1.5, height: item.kind == .audio ? 34 : 14)
                    .offset(x: max(0, geo.size.width * previewer.fraction - 0.75))
            }
            .frame(height: item.kind == .audio ? 34 : 14).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { previewer.seek(to: $0.location.x / max(1, geo.size.width)) })
        }
        .frame(height: item.kind == .audio ? 34 : 14)
        .accessibilityLabel(L("Pozycja odtwarzania", "Playback position")).accessibilityValue(L("\(Int(previewer.fraction * 100)) procent", "\(Int(previewer.fraction * 100)) percent"))
    }
}
