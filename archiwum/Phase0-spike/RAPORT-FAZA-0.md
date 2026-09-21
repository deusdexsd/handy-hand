# MidniteDock: raport Fazy 0

Data testu: 21.09.2026 · macOS 26.7, Final Cut Pro 12.3, Mac z zewnętrznym Dellem (bez notcha w tej sesji).
Testowane na bibliotece **NotchTest**, projekt **Test**. Każdy testowy drop na timeline cofnięty.

## Werdykty

| # | Funkcja | Werdykt | Dowód / ograniczenia |
|---|---|---|---|
| 1a | Panel nad oknami (NSPanel, poziom 25) | **DZIAŁA** | CGWindowList: panel z-order #0-3, FCP #4-39. Widoczny nad FCP w oknie i w pełnym ekranie (`fullScreenAuxiliary`). |
| 1b | Pozycja pod notchem | **CZĘŚCIOWO** | Geometria (`safeAreaInsets` + `auxiliaryTopLeft/RightArea`) sprawdzona 6 testami na danych MBP 16". Na sprzęcie z notchem **niesprawdzone**, bo w tej sesji jest tylko Dell. |
| 1c | Mac bez notcha / wiele monitorów | **DZIAŁA / CZĘŚCIOWO** | Bez notcha: środek ekranu pod paskiem menu, działa na Dellu. Wybór ekranu (notch > kursor > główny) tylko w testach, nie na realnych dwóch monitorach. |
| 1d | Pełny ekran FCP | **CZĘŚCIOWO** | Panel jest nad FCP, ale wisi ~30 pt pod górną krawędzią (pasek menu schowany). Do poprawki w MVP. |
| 2 | Trzy tryby (najechanie / podążaj za apką / przypięty) | **DZIAŁA** | Najechanie i przypięty sprawdzone przeze mnie. „Podążaj za apką" widać w logu z Twojego uruchomienia (rozwija się przy FCP, zwija przy innych apkach), ja go osobno nie powtarzałem. |
| 3a | Drag pliku (file URL) → Event Browser | **DZIAŁA** | Audio i wideo, bez dialogu, operacja `link`. |
| 3b | Drag pliku (file URL) → timeline | **DZIAŁA** | Audio i wideo. **Ląduje pod kursorem, nie przy playheadzie** (test: kursor x=250, playhead x=500). Wideo jako connected clip nad storyline, audio w paśmie pod. Drop za końcem treści = dokleja na końcu storyline. Drop na istniejący klip lub gap = menu FCP „Replace / Replace from Start / Replace from End / Retime to Fit / Cancel". |
| 3c | File promise (`NSFilePromiseProvider`) | **NIE** | Sam promise: FCP odrzuca (operacja `NONE`) w Event Browser i na timeline. Promise + URL: przyjęty, ale FCP bierze URL i nigdy nie woła zapisu promise. **Używamy zwykłego file URL.** |
| 4a | Import FCPXML (compound: wideo + SFX) | **DZIAŁA (obejście)** | DTD 1.13 z FCP przechodzi. FCP pyta o bibliotekę, tworzy **nowe zdarzenie + projekt** z compound clipem (wideo + przypięty SFX). Nie wstawia do otwartego projektu. |
| 4b | FCPXML na pasteboardzie → ⌘V na timeline | **NIE** | Testowane typy: `com.apple.finalcutpro.xml`, `com.apple.FinalCutPro.xml` + file URL. ⌘V dociera do FCP (kontrola: klip skopiowany w FCP wkleił się przy playheadzie), ale nasze dane ignoruje. FCP używa własnego binarnego typu `com.apple.flexo.proFFPasteboardUTI`. |
| 5a | Globalne skróty klawiszowe | **DZIAŁA** | Carbon `RegisterEventHotKey`, odpalają z FCP na wierzchu, **bez żadnych uprawnień** (ani Accessibility, ani Input Monitoring). |
| 5b | Skrót → wstaw wybrany plik do FCP | **NIE** | Przez schowek: file URL i FCPXML ignorowane (jak 4b). Przez drag: drag wymaga fizycznie wciśniętego przycisku myszy (niesprawdzone, z natury odpada). Jedyna droga to symulacja myszy (Accessibility + współrzędne timeline) i to kruche, więc odradzam. |

## Uprawnienia

- Panel, drag, hotkeye: **żadnych uprawnień**, sandbox nie jest przeszkodą, ale rekomenduję dystrybucję poza App Store (jak Papla).
- Foldery źródłowe (Pulpit, Filmy, Dokumenty): macOS poprosi raz o dostęp do folderów przy pierwszym odczycie. Aplikacja odpalona przez `open` nie zapisała logu do Pulpitu, odpalona z terminala tak. Najpewniej to zgoda na folder, ale tego nie potwierdziłem.

## Rekomendacja zakresu MVP

**Wchodzi (zielone):** panel przy notchu z trzema trybami, indeks folderów, wizualizacje, kategorie (własne i smart), wyszukiwarka, filtry, ulubione (pliki i konfiguracje), **drag zwykłego file URL** do FCP (Event Browser i timeline).

**Odpada:** file promise (nic nie daje), wklejanie z pasteboardu (FCP nie przyjmuje), skrót wstawiający klip na timeline.

**Zmiana znaczenia skrótów (etap 2):** skrót otwiera panel, przełącza kategorię, wywołuje preset, odsłuchuje, oznacza ulubione. Wstawiania klipu skrótem nie da się zrobić bez Accessibility.

**Sekwencje przez FCPXML (etap 3, opcjonalne):** działa jako „importuj jako nowy projekt / compound", z dialogiem wyboru biblioteki. To nie jest wstawianie do otwartego timeline'u, więc wartość jest mniejsza niż drag.

## Znane rzeczy do dopracowania w MVP

- Zwinięty pasek ma 8 pt, więc strefa trafienia jest powiększona i sięga do górnej krawędzi ekranu (bez tego panel migotał).
- Pełny ekran FCP: szczelina ~30 pt pod górną krawędzią.
- Notch: pozycję trzeba potwierdzić na MacBooku z otwartą klapą (jedno uruchomienie).
- Nie sprawdzałem, czy FCP przy dropie kopiuje plik do biblioteki, czy linkuje. Zależy od ustawień importu użytkownika.

## Jak uruchomić kod dowodowy

```
cd Projects/MidniteDock/Phase0
./run.sh          # buduje i odpala aplikację testową
swift test --scratch-path ~/Library/Caches/MidniteDockBuild   # 9 testów (geometria + walidacja FCPXML vs DTD z FCP)
```

Skróty w aplikacji testowej (⌃⌥⌘): 1 = wybrany plik na schowek · 2 = import FCPXML · 3 = następny element · 4 = przypnij/odepnij · 5/6/7 = wariant dragu (URL / promise / oba) · 8/9/0 = rodzaj schowka.
Log z testów: `Phase0/logs/phase0.log`.
