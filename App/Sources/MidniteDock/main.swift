import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--make-devmedia"), i + 1 < args.count {
    do { try DevMedia.generate(into: URL(fileURLWithPath: args[i + 1])); print("dev media OK: \(args[i + 1])") } catch { print("BŁĄD: \(error)"); exit(1) }
    exit(0)
}

// Łagodne zamknięcie na SIGTERM (restart aplikacji, wylogowanie): zapis danych zamiast utraty ostatnich zmian.
signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
termSource.resume()

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(ProcessInfo.processInfo.environment["MIDNITEDOCK_REGULAR"] != nil ? .regular : .accessory)
app.run()
