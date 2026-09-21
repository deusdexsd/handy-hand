// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MidniteDockPhase0",
    platforms: [.macOS(.v14)],
    targets: [
        // Czysta logika (geometria notcha, generator FCPXML) - testowalna bez UI.
        .target(name: "DockCore"),
        // Uruchamialny kod dowodowy: panel, tryby, drag, hotkeye, schowek.
        .executableTarget(name: "Phase0Spike", dependencies: ["DockCore"]),
        .testTarget(name: "DockCoreTests", dependencies: ["DockCore"]),
    ]
)
