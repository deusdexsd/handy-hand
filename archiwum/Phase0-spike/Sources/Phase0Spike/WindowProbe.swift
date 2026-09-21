import AppKit

/// Dowód "ponad normalnymi oknami": kolejność okien front->back z CGWindowList (nie wymaga uprawnień).
enum WindowProbe {
    static func report(focusOwner: String = "Final Cut Pro") -> String {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return "CGWindowList niedostępna"
        }
        let me = ProcessInfo.processInfo.processIdentifier
        var out: [String] = []
        var myIndex: Int?
        var otherIndex: Int?
        for (i, w) in list.enumerated() {
            let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            let pid = w[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let isPanel = (pid == me || owner == "Phase0Spike" || owner == "MidniteDock Phase0") && layer > 0
            if isPanel && myIndex == nil { myIndex = i }
            if owner == focusOwner && layer == 0 && otherIndex == nil { otherIndex = i }
            if isPanel || owner == focusOwner {
                out.append(String(format: "  z-order #%d  %@  layer=%d  bounds=(%.0f,%.0f %.0fx%.0f)",
                                  i, owner, layer, b["X"] ?? 0, b["Y"] ?? 0, b["Width"] ?? 0, b["Height"] ?? 0))
            }
        }
        var verdict = "panel nie jest na ekranie"
        if let m = myIndex {
            if let o = otherIndex { verdict = m < o ? "PANEL NAD \(focusOwner) (z-order \(m) < \(o))" : "PANEL POD \(focusOwner)!" }
            else { verdict = "panel na ekranie (z-order \(m)), okno \(focusOwner) niewidoczne" }
        }
        return (out + [verdict]).joined(separator: "\n")
    }
}
