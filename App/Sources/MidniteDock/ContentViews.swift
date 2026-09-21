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
        contentBody(vis)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { store.gridColumns = GridNavigation.columns(width: g.size.width) }
                    .onChange(of: g.size.width) { _, w in store.gridColumns = GridNavigation.columns(width: w) }
            })
            .dropDestination(for: URL.self) { urls, _ in store.addDropped(urls) }   // foldery i pliki z Findera
    }

    @ViewBuilder private func contentBody(_ vis: [MediaItem]) -> some View {
        Group {
            if store.sources.isEmpty {
                EmptyState(icon: "folder.badge.plus", title: "Dodaj pierwsze źródło",
                           text: "Wskaż folder, pojedyncze pliki albo bibliotekę FCP. Możesz też przeciągnąć je tutaj z Findera. Appka zaindeksuje pliki i będzie na bieżąco obserwować zmiany.",
                           extra: AnyView(Menu("Dodaj…") { AddMenuItems(store: store) }.menuStyle(.borderedButton).fixedSize()))
            } else if store.isIndexing && store.items.isEmpty {
                VStack(spacing: 10) { ProgressView().controlSize(.small); Text("Indeksuję pliki…").font(.system(size: 12)).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vis.isEmpty {
                if !store.search.isEmpty {
                    EmptyState(icon: "magnifyingglass", title: "Brak wyników", text: "Nic w „\(store.categoryTitle)” nie pasuje do „\(store.search)”.",
                               button: "Szukaj we wszystkich") { store.select(category: .all) }
                } else if store.config.filters.isActive {
                    EmptyState(icon: "line.3.horizontal.decrease.circle", title: "Filtry wykluczają wszystko", text: "Żaden element w tej kategorii nie spełnia aktywnych filtrów.",
                               button: "Wyczyść filtry") { store.config.filters = .none }
                } else {
                    EmptyState(icon: "tray", title: "Ta kategoria jest pusta", text: "Przeciągnij tu pliki z panelu albo wybierz inną kategorię.")
                }
            } else if store.config.viewMode == .grid {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 200), spacing: 10)], spacing: 10) {
                            ForEach(vis) { TileView(store: store, waveforms: store.waveforms, thumbs: store.thumbnails, item: $0).id($0.path) }
                        }.padding(.horizontal, 10).padding(.bottom, 10)
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
            .buttonStyle(PressableIconStyle()).foregroundStyle(.secondary).help("Większy podgląd").accessibilityLabel("Większy podgląd")
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
                            Label("Mniejszy podgląd", systemImage: "chevron.down").font(.system(size: 11))
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12).background(Color.primary.opacity(0.045))
            } else if let it = previewer.item, it.kind == .image {
                HStack(spacing: 10) {
                    Group {
                        if let img = thumbs.image(for: it) { Image(nsImage: img).resizable().scaledToFill() } else { ZStack { Color.primary.opacity(0.08); if thumbs.hasFailed(it) { Image(systemName: "photo").foregroundStyle(.tertiary) } else { ProgressView().controlSize(.mini) } } }
                    }
                    .frame(width: 96, height: 54).clipShape(RoundedRectangle(cornerRadius: 6))
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
                    .buttonStyle(PressableIconStyle()).accessibilityLabel(previewer.isPlaying ? "Wstrzymaj" : "Odtwórz")
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
                    Text(store.isIndexing ? "Indeksuję…" : "\(store.visible.count) elementów").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Spacer()
                    Text("Spacja: odsłuch  ·  przeciągnij kafel na timeline w FCP").font(.system(size: 11)).foregroundStyle(.tertiary)
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
        .accessibilityLabel("Pozycja odtwarzania").accessibilityValue("\(Int(previewer.fraction * 100)) procent")
    }
}
