// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MidniteDock",
    platforms: [.macOS(.v14)],
    targets: [
        // Logika bez UI: modele, zapytania, indeks, watcher, waveform, geometria notcha.
        .target(name: "DockCore"),
        .executableTarget(name: "MidniteDock", dependencies: ["DockCore"]),
        .testTarget(name: "DockCoreTests", dependencies: ["DockCore"]),
    ]
)
