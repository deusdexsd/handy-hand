import XCTest
@testable import DockCore

/// Dane syntetyczne = prawdziwe wartości z MacBooków Pro (14": 1512×982, 16": 1728×1117; pasek menu/notch 32-38 pt).
final class NotchGeometryTests: XCTestCase {
    static let mbp16 = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1079),
        safeAreaTop: 38,
        auxiliaryTopLeft: CGRect(x: 0, y: 1079, width: 764, height: 38),
        auxiliaryTopRight: CGRect(x: 964, y: 1079, width: 764, height: 38))

    static let external = ScreenMetrics(
        frame: CGRect(x: 1728, y: 0, width: 3008, height: 1692),
        visibleFrame: CGRect(x: 1728, y: 0, width: 3008, height: 1662))

    func testNotchRectIsBetweenAuxiliaryAreas() {
        let n = NotchGeometry.notchRect(Self.mbp16)!
        XCTAssertEqual(n, CGRect(x: 764, y: 1079, width: 200, height: 38))
        XCTAssertEqual(NotchGeometry.anchorX(Self.mbp16), 864)
    }

    func testPanelHangsDirectlyBelowNotch() {
        let f = NotchGeometry.panelFrame(size: CGSize(width: 440, height: 168), on: Self.mbp16)
        XCTAssertEqual(f.midX, 864)
        XCTAssertEqual(f.maxY, 1079) // dolna krawędź notcha
    }

    func testNoNotchFallsBackToScreenCenterUnderMenuBar() {
        XCTAssertNil(NotchGeometry.notchRect(Self.external))
        let f = NotchGeometry.panelFrame(size: CGSize(width: 440, height: 168), on: Self.external)
        XCTAssertEqual(f.midX, Self.external.frame.midX)
        XCTAssertEqual(f.maxY, Self.external.visibleFrame.maxY)
    }

    func testPanelClampedToScreenEdges() {
        let f = NotchGeometry.panelFrame(size: CGSize(width: 4000, height: 100), on: Self.mbp16)
        XCTAssertEqual(f.minX, 0)
    }

    func testNotchedScreenWinsOverMouseAndOrder() {
        let all = [Self.external, Self.mbp16]
        XCTAssertEqual(NotchGeometry.preferredScreen(all, mouse: CGPoint(x: 2000, y: 500)), Self.mbp16)
    }

    func testWithoutNotchUsesScreenUnderMouseThenMain() {
        let second = ScreenMetrics(frame: CGRect(x: 4736, y: 0, width: 1920, height: 1080),
                                   visibleFrame: CGRect(x: 4736, y: 0, width: 1920, height: 1050))
        let all = [Self.external, second]
        XCTAssertEqual(NotchGeometry.preferredScreen(all, mouse: CGPoint(x: 5000, y: 300)), second)
        XCTAssertEqual(NotchGeometry.preferredScreen(all, mouse: nil), Self.external)
    }
}
