import SwiftUI
import CoreGraphics
import DockCore

struct SVGShape: Shape {
    let cg: CGPath
    func path(in rect: CGRect) -> Path {
        Path(cg).applying(CGAffineTransform(scaleX: rect.width / 512, y: rect.height / 512)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Wczytane sylwetki (SVG z Downloads -> Resources/creatures).
enum CreatureArt {
    static let cat: [[CGPath]] = SVGPath.load("cat")
}

/// Ramię dwuczłonowe z łapką na końcu (jak w filmie referencyjnym): dłoń jedzie za celem, łokieć wynika z IK.
/// Kształt jest animowalny, więc sprężyna SwiftUI interpoluje pozycję dłoni klatka po klatce (przeciąganie, „bicz”).
struct ArmShape: Shape {
    enum Part { case limb, paw }
    var part: Part
    var notchH: CGFloat
    var shoulderX: CGFloat
    var tip: CGPoint
    static let l1: CGFloat = 68, l2: CGFloat = 68

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(shoulderX, .init(tip.x, tip.y)) }
        set { shoulderX = newValue.first; tip = CGPoint(x: newValue.second.first, y: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        let s = CGPoint(x: rect.midX + shoulderX, y: notchH - 6)
        let r = ArmIK.solve(shoulder: s, target: CGPoint(x: s.x + tip.x, y: s.y + tip.y), l1: Self.l1, l2: Self.l2, elbowFloor: notchH + 4)
        if part == .limb {
            var line = Path(); line.move(to: s); line.addLine(to: r.elbow); line.addLine(to: r.tip)
            return line                                              // rysowane grubą kreską z okrągłymi końcami
        }
        // łapka: poduszka i cztery palce od strony kierunku przedramienia
        var p = Path()
        let dx = r.tip.x - r.elbow.x, dy = r.tip.y - r.elbow.y
        let len = max(0.001, hypot(dx, dy)), ux = dx / len, uy = dy / len
        p.addEllipse(in: CGRect(x: r.tip.x - 9, y: r.tip.y - 9, width: 18, height: 18))
        for a in [-46.0, -16.0, 16.0, 46.0] {
            let rad = a * .pi / 180
            let tx = ux * cos(rad) - uy * sin(rad), ty = ux * sin(rad) + uy * cos(rad)
            p.addEllipse(in: CGRect(x: r.tip.x + tx * 11 - 4.6, y: r.tip.y + ty * 11 - 4.6, width: 9.2, height: 9.2))
        }
        return p
    }
}

/// Głowa kota: czarny obrys, białe oczy z pionową źrenicą (przerwa między połówkami), powieki do mrugania.
struct CatArt: View {
    let blink: Double
    private var subs: [CGPath] { CreatureArt.cat.first ?? [] }
    private var eyes: [CGPath] { Array(subs.dropFirst()) }
    private var eyeBoxes: [CGRect] {
        let left = eyes.filter { $0.boundingBox.midX < 256 }.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
        let right = eyes.filter { $0.boundingBox.midX >= 256 }.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
        return [left, right].filter { !$0.isNull }
    }
    var body: some View {
        GeometryReader { g in
            let k = g.size.width / 512
            ZStack(alignment: .topLeading) {
                if let head = subs.first { SVGShape(cg: head).fill(Color.black) }
                ForEach(Array(eyes.enumerated()), id: \.offset) { _, e in SVGShape(cg: e).fill(Color(white: 0.96)) }
                ForEach(Array(eyeBoxes.enumerated()), id: \.offset) { _, b in
                    Rectangle().fill(Color.black)
                        .frame(width: (b.width + 6) * k, height: (b.height + 4) * k * blink)
                        .offset(x: (b.minX - 3) * k, y: (b.minY - 2) * k)
                }
            }
        }
    }
}

/// Stworek wychylający się spod notcha: rysowany tylko poniżej dolnej krawędzi notcha (jakby wysuwał się ze szczeliny).
struct CreatureLayer: View {
    let effect: NotchEffect
    let notch: CGSize
    @ObservedObject var state: PanelState
    private let size: CGFloat = 104

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            if effect == .paw {
                EmptyView()
            } else {
                ZStack(alignment: .top) {
                    CatArt(blink: state.blink)
                        .frame(width: size, height: size)
                        .rotationEffect(.degrees(180))                                 // zwisa w dół
                        .offset(y: (state.amount - 1) * size)                          // 0 = całe schowane nad krawędzią, 1 = całe wysunięte
                }
                .frame(width: size, height: size, alignment: .top)
                .rotationEffect(.degrees(state.angle), anchor: .top)               // obrót wokół „barku” na dolnej krawędzi notcha
                .animation(.spring(response: 0.5, dampingFraction: 0.55), value: state.amount)      // sprężysto, z rozmachem
                .animation(.spring(response: 0.38, dampingFraction: 0.68), value: state.angle)
                .animation(.easeInOut(duration: 0.09), value: state.blink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if effect == .paw {
                ZStack {
                    ArmShape(part: .limb, notchH: notch.height, shoulderX: state.shoulderX, tip: CGPoint(x: state.tipX, y: state.tipY))
                        .stroke(Color.black, style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
                    ArmShape(part: .paw, notchH: notch.height, shoulderX: state.shoulderX, tip: CGPoint(x: state.tipX, y: state.tipY)).fill(Color.black)
                }
                // sprężyna z niskim tłumieniem: dłoń dobiega z rozmachem i lekko „przestrzeliwuje”
                .animation(.spring(response: 0.42, dampingFraction: 0.5), value: ArmKey(x: state.tipX, y: state.tipY, s: state.shoulderX))
            }
        }
        .mask(alignment: .top) {
            VStack(spacing: 0) { Color.clear.frame(height: notch.height); Color.black }     // nic nad dolną krawędzią notcha
        }
        .allowsHitTesting(false)
    }
}

private struct ArmKey: Equatable { var x: Double, y: Double, s: Double }
