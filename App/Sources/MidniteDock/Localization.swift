import DockCore

/// Bieżący język interfejsu (synchronizowany z ustawieniami w `LibraryStore`). Statyczny, żeby `L(...)`
/// dało się wołać wszędzie — w widokach SwiftUI, w budowanych ręcznie NSMenu i w komunikatach store'u —
/// bez przekazywania stanu wszędzie w dół.
enum Lang {
    static var current: AppLanguage {
        get { UILanguage.current }
        set { UILanguage.current = newValue }
    }
}

/// Tekst interfejsu: polski i angielski obok siebie w miejscu użycia (żadnego oddzielnego słownika do
/// rozjeżdżania się z kodem). Przełącza Ustawienia → Ogólne → Język.
func L(_ pl: String, _ en: String) -> String { Lang.current == .en ? en : pl }
