import CoreGraphics
import Foundation

/// Minimalny parser ścieżek SVG (M m L l H h V v C c S s Z z) - wystarcza na pliki z potrace.
/// Zwraca osobne podścieżki (obrys + otwory) już w układzie 512×512 z osią Y w dół.
enum SVGPath {
    static func subpaths(_ d: String, transform t: CGAffineTransform) -> [CGPath] {
        var out: [CGMutablePath] = []
        var cur = CGMutablePath(), pos = CGPoint.zero, start = CGPoint.zero, lastC2: CGPoint?
        var cmd: Character = " "
        var nums: [CGFloat] = []
        func flush() {
            guard cmd != " " else { return }
            let rel = cmd.isLowercase
            let c = Character(cmd.uppercased())
            let need: Int = ["M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Z": 0][c] ?? 0
            var i = 0
            if c == "Z" { cur.closeSubpath(); pos = start; return }
            while need > 0, i + need <= nums.count {
                let a = Array(nums[i..<(i + need)]); i += need
                switch c {
                case "M":
                    let p = CGPoint(x: a[0] + (rel ? pos.x : 0), y: a[1] + (rel ? pos.y : 0))
                    if !cur.isEmpty { out.append(cur); cur = CGMutablePath() }
                    cur.move(to: p, transform: t); pos = p; start = p; lastC2 = nil
                    cmd = rel ? "l" : "L"                       // kolejne pary po M to już L
                case "L":
                    pos = CGPoint(x: a[0] + (rel ? pos.x : 0), y: a[1] + (rel ? pos.y : 0)); cur.addLine(to: pos, transform: t); lastC2 = nil
                case "H": pos.x = a[0] + (rel ? pos.x : 0); cur.addLine(to: pos, transform: t); lastC2 = nil
                case "V": pos.y = a[0] + (rel ? pos.y : 0); cur.addLine(to: pos, transform: t); lastC2 = nil
                case "C":
                    let o = rel ? pos : .zero
                    let c1 = CGPoint(x: a[0] + o.x, y: a[1] + o.y), c2 = CGPoint(x: a[2] + o.x, y: a[3] + o.y), e = CGPoint(x: a[4] + o.x, y: a[5] + o.y)
                    cur.addCurve(to: e, control1: c1, control2: c2, transform: t); pos = e; lastC2 = c2
                case "S":
                    let o = rel ? pos : .zero
                    let c1 = lastC2.map { CGPoint(x: 2 * pos.x - $0.x, y: 2 * pos.y - $0.y) } ?? pos
                    let c2 = CGPoint(x: a[0] + o.x, y: a[1] + o.y), e = CGPoint(x: a[2] + o.x, y: a[3] + o.y)
                    cur.addCurve(to: e, control1: c1, control2: c2, transform: t); pos = e; lastC2 = c2
                default: break
                }
            }
        }
        var i = d.startIndex
        var token = ""
        func pushNumber() { if !token.isEmpty, let v = Double(token) { nums.append(CGFloat(v)) }; token = "" }
        while i < d.endIndex {
            let ch = d[i]
            if ch.isLetter {
                pushNumber(); flush(); nums = []; cmd = ch
                if ch == "z" || ch == "Z" { flush(); cmd = " " }
            } else if ch == "-" { pushNumber(); token = "-" }
            else if ch == "." { if token.contains(".") { pushNumber() }; token += "." }
            else if ch.isNumber || ch == "e" || ch == "E" { token.append(ch) }
            else { pushNumber() }
            i = d.index(after: i)
        }
        pushNumber(); flush()
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Wczytuje plik SVG z potrace (transform translate(0,512) scale(0.1,-0.1)): lista <path> i ich podścieżek.
    static func load(_ name: String) -> [[CGPath]] {
        var text: String?
        if let u = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "creatures") ?? Bundle.main.url(forResource: name, withExtension: "svg") {
            text = try? String(contentsOf: u, encoding: .utf8)
        }
        if text == nil {   // uruchomienie deweloperskie spoza paczki
            let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/creatures/\(name).svg")
            text = try? String(contentsOf: dev, encoding: .utf8)
        }
        guard let svg = text else { return [] }
        let t = CGAffineTransform(a: 0.1, b: 0, c: 0, d: -0.1, tx: 0, ty: 512)
        var result: [[CGPath]] = []
        var rest = svg[...]
        while let r = rest.range(of: " d=\"") ?? rest.range(of: "d=\"") {
            let after = rest[r.upperBound...]
            guard let end = after.firstIndex(of: "\"") else { break }
            result.append(subpaths(String(after[..<end]), transform: t))
            rest = after[after.index(after: end)...]
        }
        return result
    }
}
