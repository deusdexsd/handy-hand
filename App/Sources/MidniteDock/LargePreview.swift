import SwiftUI
import AppKit
import DockCore

/// Osobne, większe okno podglądu dla wideo i obrazów (jak Quick Look), pod panelem.
struct LargePreviewView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var previewer: Previewer
    @ObservedObject var thumbs: ThumbnailStore
    /// Pasek z nazwą i wymiarami obrazu; w podglądzie w liście chowamy go, bo to samo jest w pasku na dole panelu.
    var showsInfoBar = true
    @Environment(\.dockAccent) private var accent

    var body: some View {
        let it = store.primary
        VStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.28)
                if let it, it.kind == .image {
                    if let img = thumbs.large(for: it) ?? thumbs.image(for: it) {
                        Image(nsImage: img).resizable().scaledToFit().padding(6)
                    } else if thumbs.hasFailed(it) {
                        Image(systemName: "photo.badge.exclamationmark").font(.system(size: 30)).foregroundStyle(.tertiary)
                    } else { ProgressView().controlSize(.small) }
                } else if let it, it.kind == .video {
                    PlayerLayerView(player: previewer.item?.path == it.path ? previewer.player : nil)
                }
            }
            if let it, it.kind == .video || showsInfoBar {
                HStack(spacing: 10) {
                    if it.kind == .video {
                        Button { previewer.toggle() } label: {
                            Image(systemName: previewer.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 11))
                                .frame(width: 26, height: 26).background(Circle().fill(accent)).foregroundStyle(.white)
                        }.buttonStyle(PressableIconStyle()).accessibilityLabel(previewer.isPlaying ? "Wstrzymaj" : "Odtwórz")
                        Scrubber(item: it, store: store, waveforms: store.waveforms, previewer: previewer)
                        Text("\(Fmt.clock(previewer.time)) / \(Fmt.clock(it.duration))").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    } else {
                        Text(it.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text("\(it.pixelWidth ?? 0)×\(it.pixelHeight ?? 0) · \(ByteCountFormatter.string(fromByteCount: it.size, countStyle: .file)) · \(it.ext.uppercased())")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 12).frame(height: 38)
            }
        }
        .background(VisualEffect(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        .environment(\.dockAccent, store.settings.accent.color)
        .tint(store.settings.accent.color)
    }
}
