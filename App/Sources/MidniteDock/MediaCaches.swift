import Foundation
import AVFoundation
import AppKit
import ImageIO
import DockCore

/// Peaki waveformów liczone w tle; widoki obserwują `version`.
@MainActor
final class WaveformStore: ObservableObject {
    @Published private(set) var version = 0
    private var cache: [String: [Float]] = [:]
    private var pending: Set<String> = []

    func peaks(for item: MediaItem) -> [Float]? {
        if let p = cache[item.path] { return p }
        guard item.kind == .audio, !pending.contains(item.path) else { return nil }
        pending.insert(item.path)
        let (url, mod, size, path) = (item.url, item.modified, item.size, item.path)
        Task.detached(priority: .utility) {
            let p = WaveformPeaks.cached(url: url, modified: mod, size: size)
            await MainActor.run { [weak self] in
                self?.cache[path] = p; self?.pending.remove(path); self?.version += 1
            }
        }
        return nil
    }
}

/// Ogranicza liczbę równoległych dekodowań (duże zdjęcia zamulały, gdy wszystkie kafle startowały naraz).
actor ThumbGate {
    private var free: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { free = limit }
    func acquire() async { if free > 0 { free -= 1 } else { await withCheckedContinuation { waiters.append($0) } } }
    func release() { if waiters.isEmpty { free += 1 } else { waiters.removeFirst().resume() } }
}

@MainActor
final class ThumbnailStore: ObservableObject {
    @Published private(set) var version = 0
    /// Miniatury w NSCache z limitem: przy tysiącach plików pamięć nie rośnie bez końca (wyrzucone wczytają się ponownie przy przewinięciu).
    private let cache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 500; return c }()
    private var pending: Set<String> = []
    /// Nieudane miniatury zapamiętujemy: inaczej każda porażka podbijała `version`, widok się odświeżał i ładowanie startowało od nowa w kółko.
    private var failed: Set<String> = []
    private var largeCache: [String: NSImage] = [:]
    private var largeOrder: [String] = []
    private var largePending: Set<String> = []
    private let gate = ThumbGate(limit: 3)
    private(set) var attempts: [String: Int] = [:]      // do autotestu

    func hasFailed(_ item: MediaItem) -> Bool { failed.contains(item.path) }

    func image(for item: MediaItem) -> NSImage? {
        if let i = cache.object(forKey: item.path as NSString) { return i }
        guard item.kind != .audio, !failed.contains(item.path), !pending.contains(item.path) else { return nil }
        pending.insert(item.path); attempts[item.path, default: 0] += 1
        let (url, dur, path, isImage) = (item.url, item.duration, item.path, item.kind == .image)
        let g = gate
        Task.detached(priority: .utility) {
            await g.acquire()
            let img = isImage ? Self.renderImage(url, maxPixel: 320) : await Self.renderVideoFrame(url, dur)
            await g.release()
            await MainActor.run { [weak self] in
                if let img { self?.cache.setObject(img, forKey: path as NSString) } else { self?.failed.insert(path) }
                self?.pending.remove(path); self?.version += 1
            }
        }
        return nil
    }

    /// Duży obraz do okna podglądu (max ~1600 px), trzymamy kilka ostatnich.
    func large(for item: MediaItem) -> NSImage? {
        if let i = largeCache[item.path] { return i }
        guard item.kind == .image, !failed.contains("L" + item.path), !largePending.contains(item.path) else { return nil }
        largePending.insert(item.path)
        let (url, path) = (item.url, item.path)
        let g = gate
        Task.detached(priority: .userInitiated) {
            await g.acquire()
            let img = Self.renderImage(url, maxPixel: 1600)
            await g.release()
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let img {
                    self.largeCache[path] = img; self.largeOrder.append(path)
                    if self.largeOrder.count > 6 { self.largeCache.removeValue(forKey: self.largeOrder.removeFirst()) }
                } else { self.failed.insert("L" + path) }
                self.largePending.remove(path); self.version += 1
            }
        }
        return nil
    }

    nonisolated static func renderImage(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Małe obrazy (ikony, małe PNG) zostają w oryginalnym rozmiarze — ImageIO nie ma ich rozciągać ani zmniejszać poniżej oryginału.
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let original = max(props?[kCGImagePropertyPixelWidth] as? Int ?? maxPixel, props?[kCGImagePropertyPixelHeight] as? Int ?? maxPixel)
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: min(maxPixel, original),
                                     kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        return Optional(src)
            .flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, opts as CFDictionary) }
            .map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    nonisolated static func renderVideoFrame(_ url: URL, _ dur: Double) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        // Plik .mp4/.mov bez ścieżki wideo (sam dźwięk) nie ma klatki: bez tego sprawdzenia generator próbował w kółko.
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { return nil }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 320, height: 180)
        let t = CMTime(seconds: min(1, dur / 2), preferredTimescale: 600)
        guard let cg = try? await gen.image(at: t).image else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// Odsłuch / podgląd: AVPlayer dla audio i wideo.
@MainActor
final class Previewer: ObservableObject {
    @Published private(set) var item: MediaItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var time: Double = 0
    private(set) var player: AVPlayer?
    private var observer: Any?
    private var endObs: NSObjectProtocol?

    var fraction: Double { guard let d = item?.duration, d > 0 else { return 0 }; return min(1, time / d) }

    func load(_ it: MediaItem?) {
        if it?.path == item?.path { return }
        teardown()
        item = it; time = 0; isPlaying = false
        guard let it, it.kind != .image else { return }
        let p = AVPlayer(url: it.url)
        if ProcessInfo.processInfo.environment["MIDNITEDOCK_MUTE"] != nil { p.volume = 0 }
        player = p
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.time = t.seconds.isFinite ? t.seconds : 0 }
        }
        endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = false; self?.player?.seek(to: .zero); self?.time = 0 }
        }
    }

    func play() { guard player != nil else { return }; if fraction >= 0.999 { seek(to: 0) }; player?.play(); isPlaying = true }
    func pause() { player?.pause(); isPlaying = false }
    func toggle() { isPlaying ? pause() : play() }

    func seek(to fraction: Double) {
        guard let d = item?.duration else { return }
        let t = max(0, min(1, fraction)) * d
        time = t
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() { teardown(); item = nil; time = 0; isPlaying = false }

    private func teardown() {
        player?.pause()
        if let o = observer { player?.removeTimeObserver(o) }
        if let e = endObs { NotificationCenter.default.removeObserver(e) }
        observer = nil; endObs = nil; player = nil
    }
}
