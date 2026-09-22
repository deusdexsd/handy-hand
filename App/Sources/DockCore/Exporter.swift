import Foundation

public enum ExportLayout: String, Codable, CaseIterable, Sendable {
    case byTypeAndLength, byCollection
    public var label: String { self == .byTypeAndLength ? LL("Typ i długość (SFX, Muzyka, Wideo, Obrazy → przedział)", "Type and length (SFX, Music, Video, Images → range)") : LL("Kolekcje", "Collections") }
}
public enum ExportMode: String, Codable, CaseIterable, Sendable {
    case copy, link
    public var label: String { self == .copy ? LL("Kopiuj pliki", "Copy files") : LL("Dowiązania (bez kopiowania)", "Links (no copying)") }
}
public struct ExportEntry: Equatable, Sendable { public var source: String; public var relative: String }

/// Eksport skategoryzowanej biblioteki do struktury folderów. Nigdy nie nadpisuje istniejących plików.
public enum LibraryExporter {
    static func clean(_ s: String) -> String { s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }

    public static func plan(items: [MediaItem], org: Organization, layout: ExportLayout) -> [ExportEntry] {
        var used: Set<String> = []
        func add(_ folder: String, _ i: MediaItem, into out: inout [ExportEntry]) {
            let file = URL(fileURLWithPath: i.path).lastPathComponent
            var rel = "\(folder)/\(clean(file))", n = 2
            while used.contains(rel.lowercased()) {   // ta sama nazwa w tym samym folderze: numerujemy
                let base = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
                rel = "\(folder)/\(clean(base)) \(n)" + (ext.isEmpty ? "" : ".\(ext)"); n += 1
            }
            used.insert(rel.lowercased()); out.append(ExportEntry(source: i.path, relative: rel))
        }
        var out: [ExportEntry] = []
        switch layout {
        case .byTypeAndLength:
            for i in items {
                let c = org.mediaClass(of: i)
                var folder = clean(c.label)
                if c.hasDuration { folder += "/" + clean(org.durationRanges.first { $0.mediaClass == c && $0.contains(i.duration) }?.name ?? "Inne") }
                add(folder, i, into: &out)
            }
        case .byCollection:
            let byPath = Dictionary(items.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            for c in org.collections { for p in c.paths { if let i = byPath[p] { add("Kolekcje/" + clean(c.name), i, into: &out) } } }
        }
        return out
    }

    public static func run(_ plan: [ExportEntry], to dest: URL, mode: ExportMode) -> (done: Int, skipped: Int, failed: [String]) {
        let fm = FileManager.default
        var done = 0, skipped = 0, failed: [String] = []
        for e in plan {
            let target = dest.appendingPathComponent(e.relative)
            if fm.fileExists(atPath: target.path) { skipped += 1; continue }
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if mode == .copy { try fm.copyItem(atPath: e.source, toPath: target.path) }
                else { try fm.createSymbolicLink(atPath: target.path, withDestinationPath: e.source) }
                done += 1
            } catch { failed.append("\((e.source as NSString).lastPathComponent): \(error.localizedDescription)") }
        }
        return (done, skipped, failed)
    }
}
