# Handy

Natywny panel dla macOS przy notchu: biblioteka Twoich dźwięków (SFX, muzyka), wideo i obrazów, z której przeciągasz pliki prosto na oś czasu Final Cut Pro. Tylko dysk → FCP; aplikacja niczego nie czyta z Final Cut Pro.

- Instrukcja dla użytkownika: [`docs/Instrukcja.html`](docs/Instrukcja.html)
- Stan prac i lista sprawdzonych / niesprawdzonych rzeczy: [`App/STATUS.md`](App/STATUS.md)
- Raport z fazy 0 (weryfikacja wykonalności, drag do FCP): [`archiwum/Phase0-spike/RAPORT-FAZA-0.md`](archiwum/Phase0-spike/RAPORT-FAZA-0.md)

## Układ repozytorium

```
App/                  aplikacja (SwiftPM: DockCore = logika, MidniteDock = interfejs AppKit/SwiftUI, DockCoreTests)
  Resources/          ikona i grafiki
  build-app.sh        buduje .app poza iCloudem (~/Library/Caches), podpis ad-hoc
  package.sh          wersja release -> App/dist/Handy.app
  make-dmg.sh         uniwersalny (Apple Silicon + Intel) build -> Handy.dmg (domyślnie ~/Downloads)
  dev-run.sh          uruchomienie na danych testowych (osobny katalog danych)
docs/                 instrukcja użytkownika, pierwotny prompt
archiwum/Phase0-spike prototyp z fazy 0 (zostawiony do wglądu)
```

## Budowanie

Wymagania: macOS 14+, Xcode / Swift 5.9+.

```bash
cd App
swift test --scratch-path ~/Library/Caches/MidniteDockBuild-App   # testy jednostkowe
./package.sh                                                       # App/dist/Handy.app
./make-dmg.sh                                                      # ~/Downloads/Handy.dmg
```

Repozytorium leży w iCloudzie, dlatego katalog `.git` jest wskaźnikiem na `~/.lapka-repo.git` (iCloud potrafi uszkodzić repozytorium). Artefakty budowania trafiają do `~/Library/Caches/MidniteDockBuild-App`.

## Uwagi

- Aplikacja ma podpis ad-hoc (bez konta deweloperskiego Apple), więc na innych Macach trzeba ją raz zatwierdzić w Ustawieniach systemowych (opisane w instrukcji).
- Dane użytkownika: `~/Library/Application Support/MidniteDock` (nazwa katalogu zostaje po zmianie nazwy z MidniteDock na Handy).
