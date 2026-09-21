import Foundation
import AVFoundation
import UniformTypeIdentifiers
import ImageIO

public enum MediaFiles {
    /// Obrazy, które FCP potrafi zaimportować jako klatki nieruchome (bez SVG i ikon).
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "gif", "bmp", "psd", "tga"]

    public static func kind(forExtension ext: String) -> MediaKind? {
        if imageExtensions.contains(ext.lowercased()) { return .image }
        guard let t = UTType(filenameExtension: ext.lowercased()) else { return nil }
        if t.conforms(to: .audio) { return .audio }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
        return nil
    }
}

/// Kanoniczna ścieżka (realpath z libc). `URL.resolvingSymlinksInPath` zamienia /private/var z powrotem na /var,
/// co rozjeżdża się z tym, co zwraca enumerator.
public enum PathUtil {
    public static func canonical(_ path: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        return realpath(path, &buf) != nil ? String(cString: buf) : path
    }
}

struct ScannedFile { var url: URL; var name: String; var ext: String; var kind: MediaKind; var size: Int64; var created: Date; var modified: Date; var group: String? }

/// Indeksuje foldery: pliki audio/wideo z metadanymi (długość). Biblioteki FCP: tylko "Original Media".
public actor Indexer {
    public init() {}

    static func collectFiles(_ source: Source) -> [ScannedFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]
        return (source.filePaths ?? []).compactMap { p in
            let url = URL(fileURLWithPath: PathUtil.canonical(p))
            guard let kind = MediaFiles.kind(forExtension: url.pathExtension),
                  let rv = try? url.resourceValues(forKeys: keys), rv.isRegularFile == true else { return nil }
            return ScannedFile(url: url, name: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension.lowercased(), kind: kind,
                               size: Int64(rv.fileSize ?? 0), created: rv.creationDate ?? .distantPast, modified: rv.contentModificationDate ?? .distantPast, group: nil)
        }
    }

    static func collect(_ source: Source) -> [ScannedFile] {
        if source.kind == .files { return collectFiles(source) }
        let root = URL(fileURLWithPath: PathUtil.canonical(source.path))
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var out: [ScannedFile] = []
        while let obj = en.nextObject() {
            guard let url = obj as? URL else { continue }
            let path = url.path
            if source.kind == .fcpLibrary {
                if path.contains("/Transcoded Media/") || path.contains("/Render Files/") || path.contains("/Analysis Files/") || path.contains("/Proxy Media/") { en.skipDescendants(); continue }
                if !path.contains("/Original Media/") { continue }
            }
            let ext = url.pathExtension
            guard let kind = MediaFiles.kind(forExtension: ext) else { continue }
            let resolved = URL(fileURLWithPath: PathUtil.canonical(url.path))
            guard let rv = try? resolved.resourceValues(forKeys: Set(keys)), rv.isRegularFile == true else { continue }
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let comps = rel.split(separator: "/").map(String.init)
            let group: String? = comps.count > 1 ? comps[0] : nil
            out.append(ScannedFile(url: resolved, name: resolved.deletingPathExtension().lastPathComponent, ext: ext.lowercased(), kind: kind,
                                   size: Int64(rv.fileSize ?? 0), created: rv.creationDate ?? .distantPast,
                                   modified: rv.contentModificationDate ?? .distantPast, group: group))
        }
        return out
    }

    /// Skanuje źródło; pliki bez zmian (ścieżka + data + rozmiar) biorą metadane z `existing`.
    public func scan(_ source: Source, existing: [String: MediaItem]) async -> [MediaItem] {
        let files = Self.collect(source)
        var result: [MediaItem] = []
        var todo: [ScannedFile] = []
        for f in files {
            if let e = existing[f.url.path], e.modified == f.modified, e.size == f.size, e.sourceID == source.id {
                var keep = e; keep.group = f.group; result.append(keep)
            } else { todo.append(f) }
        }
        var i = 0
        while i < todo.count {
            let batch = Array(todo[i..<min(i + 8, todo.count)])
            i += 8
            let loaded: [MediaItem?] = await withTaskGroup(of: MediaItem?.self) { g in
                for f in batch {
                    g.addTask {
                        if f.kind == .image {
                            var w: Int?, h: Int?
                            if let src = CGImageSourceCreateWithURL(f.url as CFURL, nil),
                               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                                w = props[kCGImagePropertyPixelWidth] as? Int; h = props[kCGImagePropertyPixelHeight] as? Int
                            }
                            guard w != nil else { return nil }   // nieczytelny obraz pomijamy
                            return MediaItem(path: f.url.path, name: f.name, ext: f.ext, kind: .image, duration: 0, size: f.size,
                                             created: f.created, modified: f.modified, sourceID: source.id, group: f.group, pixelWidth: w, pixelHeight: h)
                        }
                        let d = (try? await AVURLAsset(url: f.url).load(.duration).seconds) ?? 0
                        guard d.isFinite, d > 0 else { return nil }
                        return MediaItem(path: f.url.path, name: f.name, ext: f.ext, kind: f.kind, duration: d, size: f.size,
                                         created: f.created, modified: f.modified, sourceID: source.id, group: f.group)
                    }
                }
                var r: [MediaItem?] = []
                for await x in g { r.append(x) }
                return r
            }
            result += loaded.compactMap { $0 }
        }
        return result
    }
}

/// Obserwuje zmiany plików na żywo (FSEvents).
public final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable ([String]) -> Void
    private let queue = DispatchQueue(label: "dock.fsevents")

    public init(paths: [String], latency: TimeInterval = 0.7, onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
        guard !paths.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, pathsPtr, _, _ in
            guard let info else { return }
            let me = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let arr = unsafeBitCast(pathsPtr, to: NSArray.self) as? [String] ?? []
            me.onChange(Array(arr.prefix(count)))
        }
        stream = FSEventStreamCreate(nil, cb, &ctx, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        if let s = stream { FSEventStreamSetDispatchQueue(s, queue); FSEventStreamStart(s) }
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s); stream = nil
    }
    deinit { stop() }
}
