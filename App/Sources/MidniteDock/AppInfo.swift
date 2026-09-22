import Foundation

enum AppInfo {
    /// Nazwa produktu w jednym miejscu.
    static let name = "Handy"
    /// Folder danych zostaje pod starą nazwą, żeby zmiana nazwy produktu nie odcięła Cię od zapisanych źródeł, ulubionych i kolekcji.
    static let dataFolder = "MidniteDock"
    /// Znacznik budowy (data.godzina), żeby dało się odróżnić starą wersję od nowej.
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev" }
    static let bundleID = "com.midnitemedia.midnitedock"

    /// Katalog danych; nadpisywalny (testy i dev nie mogą nadpisywać prawdziwych danych Davida).
    static var dataDir: URL {
        if let p = ProcessInfo.processInfo.environment["MIDNITEDOCK_DATA_DIR"] { return URL(fileURLWithPath: p, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(dataFolder, isDirectory: true)
    }
}
