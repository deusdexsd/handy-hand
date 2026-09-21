import AppKit
import DockCore

enum PasteKind: String, CaseIterable, Identifiable {
    case xmlLower = "FCPXML · com.apple.finalcutpro.xml"
    case xmlUTI = "FCPXML · com.apple.FinalCutPro.xml"
    case fileURL = "Tylko file URL"
    case all = "Wszystko naraz"
    var id: String { rawValue }
}

@MainActor
enum Actions {
    static let outDir = Log.root.appendingPathComponent("Output")
    static let fcpURL = URL(fileURLWithPath: "/Applications/Final Cut Pro.app")
    static let typeLower = NSPasteboard.PasteboardType("com.apple.finalcutpro.xml")
    static let typeUTI = NSPasteboard.PasteboardType("com.apple.FinalCutPro.xml")

    @discardableResult
    static func writeFCPXMLFiles() -> (event: URL, compound: URL) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let a = TestMedia.assets
        let event = outDir.appendingPathComponent("probe-event-import.fcpxml")
        let compound = outDir.appendingPathComponent("probe-compound-project.fcpxml")
        try? FCPXMLBuilder.eventImport(eventName: "MidniteDock Probe", assets: a)
            .write(to: event, atomically: true, encoding: .utf8)
        try? FCPXMLBuilder.compoundProject(eventName: "MidniteDock Probe", projectName: "Probe compound",
                                           video: a[1], sfx: a[0])
            .write(to: compound, atomically: true, encoding: .utf8)
        Log.write("zapisano FCPXML: \(event.lastPathComponent), \(compound.lastPathComponent)")
        return (event, compound)
    }

    static func importIntoFCP(_ file: URL) {
        Log.write("IMPORT do FCP: \(file.lastPathComponent)")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([file], withApplicationAt: fcpURL, configuration: cfg) { _, err in
            Log.write(err == nil ? "  FCP przyjął plik do otwarcia (dalszy efekt: patrz okno FCP)" : "  BŁĄD open: \(err!)")
        }
    }

    static func putOnPasteboard(_ asset: ProbeAsset, kind: PasteKind) {
        let xml = FCPXMLBuilder.eventImport(eventName: "MidniteDock Probe", assets: [asset]).data(using: .utf8)!
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        switch kind {
        case .xmlLower: item.setData(xml, forType: typeLower)
        case .xmlUTI: item.setData(xml, forType: typeUTI)
        case .fileURL: break
        case .all: item.setData(xml, forType: typeLower); item.setData(xml, forType: typeUTI)
        }
        if kind == .fileURL || kind == .all {
            item.setString(asset.url.absoluteString, forType: .fileURL)
        }
        pb.writeObjects([item])
        Log.write("SCHOWEK: wpisano \(asset.name) jako [\(kind.rawValue)] -> teraz ⌘V w FCP")
    }

    static func dumpPasteboard() {
        let pb = NSPasteboard.general
        Log.write("SCHOWEK zrzut: changeCount=\(pb.changeCount), elementów=\(pb.pasteboardItems?.count ?? 0)")
        for (i, item) in (pb.pasteboardItems ?? []).enumerated() {
            for t in item.types {
                let data = item.data(forType: t)
                var preview = ""
                if let d = data, d.count < 2_000_000, let s = String(data: d.prefix(160), encoding: .utf8),
                   s.unicodeScalars.allSatisfy({ $0.value >= 9 }) {
                    preview = "  «\(s.replacingOccurrences(of: "\n", with: " "))»"
                }
                Log.write("  item \(i)  \(t.rawValue)  \(data?.count ?? 0) B\(preview)")
            }
        }
    }
}
