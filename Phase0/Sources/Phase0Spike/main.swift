import AppKit
import DockCore

// Tryby bez UI (do skryptów i dowodów):
//   --make-media     generuje pliki testowe
//   --write-fcpxml   zapisuje FCPXML do Output/
//   --windows        raport z-order okien
let args = CommandLine.arguments
if args.contains("--make-media") {
    do { try TestMedia.ensure(); print("media OK: \(TestMedia.dir.path)") } catch { print("BŁĄD: \(error)"); exit(1) }
    exit(0)
}
if args.contains("--write-fcpxml") {
    try? TestMedia.ensure()
    MainActor.assumeIsolated { _ = Actions.writeFCPXMLFiles() }
    exit(0)
}
if args.contains("--windows") { print(WindowProbe.report()); exit(0) }

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
