import ServiceManagement
import AppKit

/// „Otwieraj przy logowaniu”: stan trzyma system (Ustawienia systemowe → Ogólne → Elementy logowania), nie plik ustawień.
@MainActor
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    /// Aplikacja uruchomiona z katalogu budowania (wersja deweloperska) nie powinna się rejestrować.
    static var isDevBuild: Bool { Bundle.main.bundlePath.contains("/Library/Caches/") }

    /// Zwraca komunikat błędu albo nil, gdy się udało.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch { return error.localizedDescription }
    }
}
