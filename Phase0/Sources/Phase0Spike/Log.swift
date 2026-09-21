import Foundation

/// Log dowodowy: stdout + plik w Phase0/logs + okno kontrolne.
enum Log {
    /// Phase0/ wyliczone z lokalizacji źródła (spike działa z repo, nie z .app).
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    static let logFile = root.appendingPathComponent("logs/phase0.log")
    nonisolated(unsafe) static var sink: (@Sendable (String) -> Void)?

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "[\(fmt.string(from: Date()))] \(message)"
        print(line)
        if let data = (line + "\n").data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: logFile) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: logFile)
            }
        }
        sink?(line)
    }
}
