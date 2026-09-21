# Łapka (dawniej MidniteDock): status (21.09.2026)

Aplikacja: `App/dist/Łapka.app` (release, ad-hoc podpis, aplikacja z paska menu, bez ikony w Docku).
Dane użytkownika: `~/Library/Application Support/MidniteDock/` (`userdata.json`, `index.json`).
Nazwa produktu jest w jednym miejscu (`Sources/MidniteDock/AppInfo.swift`), bo się zmieni.

## Jest (sprawdzone)

| Obszar | Co | Jak sprawdzone |
|---|---|---|
| Panel | NSPanel nad oknami, tryby: po najechaniu / podążaj za aplikacją / przypięty; pozycje: notch (góra-środek), prawa krawędź na środku, lewa krawędź na środku, z suwakiem położenia na bokach (Ustawienia); wirtualny notch (czarna wysepka) auto / zawsze / nigdy | autotest na prawdziwej geometrii ekranu, lista okien systemu |
| Źródła | foldery i biblioteki FCP (czytane jak folder, tylko „Original Media”), symlinki rozwiązywane, obserwowanie zmian na żywo | 58 testów + autotest (plik dodany i usunięty widać w indeksie) |
| Wizualizacje | waveform z prawdziwego pliku (Accelerate, cache na dysku), wspólna skala czasu, miniatura wideo, czas trwania na kaflu, odsłuch/podgląd (AVPlayer) | render widoków + autotest odtwarzania |
| Organizacja | kolekcje własne, smart: przedziały długości (osobno audio i wideo, dowolnie dodawane, z odcieniem szarości), reguły po słowach, typ; ulubione, tagi | testy zapytań |
| Wyszukiwanie i filtry | szukanie w bieżącej kategorii, filtry (typ, długość, data, tag) z widocznymi chipami i „Wyczyść”, sortowanie | testy + render |
| Duplikaty | zwijanie: ten sam typ + nazwa + długość (±10 ms), tryb ścisły dokłada rozmiar; zostaje kopia ze źródła wyżej na liście; znaczek ×N, lista kopii w menu kontekstowym; ulubione/tagi/kolekcje dotyczą wszystkich kopii; w folderze źródła widać jego własną kopię | 4 testy + autotest na danych z kopiami |
| Słowa kluczowe | edycja nazw i słów, dodawanie, usuwanie, kolejność (strzałki), przywracanie domyślnych | render |
| Typy | audio dzieli się na SFX i muzykę wg granicy długości (domyślnie 20 s, edytowalna) z ręczną poprawką prawym przyciskiem (Typ dźwięku); wideo; obrazy (JPG, PNG, WebP, HEIC, TIFF, GIF, BMP, PSD, TGA) z miniaturą i wymiarami; przedziały długości osobno dla SFX, muzyki i wideo | 7 testów + autotest |
| Dodawanie | folder, pojedyncze pliki, biblioteka FCP (menu „+” i Ustawienia), upuszczenie z Findera na panel, „Usuń z biblioteki” dla pojedynczych plików | testy + autotest |
| Zmiana nazwy | prawy przycisk → Zmień nazwę: zmienia plik NA DYSKU i przenosi ulubione/tagi/kolekcje/typ; odmawia przy kolizji nazwy, złych znakach i plikach z bibliotek FCP | autotest |
| Rozmiar panelu | rozciąganie myszką za krawędzie i rogi (wyśrodkowany panel rośnie symetrycznie), zapis w ustawieniach, limity min/max i ekranu | 5 testów + autotest; **działanie myszy nie sprawdzone na żywo** |
| Klawiatura | strzałki (po siatce, bez zawijania, przewija do zaznaczenia), Enter = zmiana nazwy (jak w Finderze), spacja = odtwarzanie; przy otwartym pytaniu klawisze idą do pola; **1–4 zarezerwowane, do zdefiniowania** | autotest + 4 testy nawigacji; **klawisze prawdziwej klawiatury nie sprawdzone na żywo** |
| Skala waveformu | automatyczna: najdłuższy dźwięk w widoku (osobno SFX i muzyka) = pełna szerokość, podziałka czasu pod waveformem; opcja stałej skali | render + autotest |
| Podgląd obrazów i wideo | mały pasek na dole (jak wcześniej); opcja „Większy podgląd” (strzałka w pasku albo Ustawienia → Ogólne): obraz/odtwarzacz 340×190 na dole panelu | render + autotest |
| Miniatury | limit równoległych dekodowań, cache błędów (koniec pętli ponawiania), pasek podglądu odświeża się po wczytaniu | autotest |
| Skróty w panelu | 1–4 filtr typu w bieżącej kategorii (mapowanie w Ustawieniach → Skróty; ponowne = zdejmuje), Shift+1–4 zmienia typ zaznaczonego dźwięku, 5 ulubione, 6 czyści filtry; spacja: dźwięk = odsłuch, obraz/wideo = większy podgląd | autotest |
| Skróty globalne i Finder | globalny skrót pokaż/ukryj panel (domyślnie ⌃⌥⌘L, nagrywany w Ustawieniach → Skróty, można wyłączyć; Carbon, działa z FCP na wierzchu, bez uprawnień); klawisz 9 (do wyboru 7/8/9/0/wyłączony) = pokaż zaznaczone w Finderze | test ustawień, rejestracja skrótu w autotest; **naciśnięcie prawdziwego skrótu nie sprawdzone** |
| Uruchamianie | „Otwieraj przy logowaniu”: przełącznik w menu łapki na pasku menu i w Ustawieniach → Ogólne (SMAppService, stan trzyma system) | kompiluje się; **rejestracja nie była uruchamiana** (nie zmieniam Twoich elementów logowania) |
| Eksport | do folderu „Łapka – eksport”: układ Typ i długość albo Kolekcje; kopiuj albo dowiązania; nie nadpisuje | 2 testy |
| Efekt przy notchu | Ustawienia → Wygląd: Brak / Podświetlenie (kolor z kółka kolorów albo 3 gotowe, suwak siły 0,3–2) / Łapka (domyślnie). Łapka: SZTYWNE ramię (ok. 15% giętkości = lekkie sprężyste dobieganie), łokieć tuż przy notchu, przedramię i pęk pięciu palców skierowane w stronę kursora, grubość 31→25 pt przy notchu 220 pt; reaguje TYLKO na kursor w promieniu ok. 105 pt (wysuwanie/chowanie wolne, chowanie z opóźnieniem 0,45 s; bark przeskakuje krokami po notchu, dłoń „pacuje” w cyklu ok. 1,15 s); na bocznych krawędziach działa tylko podświetlenie | testy (IK, sprężyna), renderowanie póz, test w prawdziwym oknie z symulowanym kursorem; **ruch na żywo niesprawdzony** |
| Układy | zapisane układy (kategoria + filtry + sortowanie + widok) jednym kliknięciem | testy |
| Trwałość | zapis JSON tolerancyjny na brakujące klucze (aktualizacje nie kasują danych) | testy + autotest |
| Wygląd | neutralny, jeden akcent (do wyboru), opcjonalne subtelne kolory źródeł, jasny/ciemny, natywny materiał (NSVisualEffectView), SF Symbols, sprężyny, reduce motion / reduce transparency | render |
| Drag | natywny drag file URL (jak w Finderze), wiele plików, obraz trzyma się kursora, feedback na wciśnięcie | mechanika taka jak w Fazie 0 (FCP przyjmował); **nowy kod nie sprawdzony na żywo** |

## Nie sprawdzone na żywo (ekran był zajęty przez inną sesję Claude)

- prawdziwa mysz: najechanie, klik, spacja, drag z nowej aplikacji do FCP,
- menu kontekstowe, dialogi (nowa kolekcja, tag, zapis układu),
- wygląd na prawdziwym materiale tła (renderowałem na atrapie tła).

## Odłożone / odrzucone

- kotek (usunięty na prośbę Davida),
- czarna dziura, sekwencje/compound przez FCPXML (odpuszczone), więcej kolorów (niepotrzebne).

## Jeszcze nie ma

- globalne skróty klawiszowe do plików i układów (etap 2),
- sekwencje przez FCPXML (etap 3, opcjonalne),
- czarna dziura i kotek (później), nowa nazwa i wizualia,
- przeciąganie plików z Findera do panelu, zarządzanie tagami poza dodawaniem,
- eksport skategoryzowanej biblioteki do struktury folderów (pomysł Davida, na później).

## Dystrybucja

`App/make-dmg.sh` buduje uniwersalną aplikację (arm64 + x86_64) i pakuje w `~/Downloads/Łapka.dmg` (dysk z Łapką i skrótem do Programów). Podpis ad-hoc, bez notaryzacji: na innym Macu trzeba raz zatwierdzić aplikację (Ustawienia → Prywatność i ochrona → Otwórz mimo to albo `xattr -dr com.apple.quarantine`); opisane w `docs/Instrukcja.html`. Uruchomienie na innym Macu **nie było sprawdzone** (nie miałem drugiego komputera); sprawdzone: DMG się montuje, podpis jest poprawny, w środku oba typy procesorów.

## Uruchamianie i testy

```
cd Projects/MidniteDock/App
./package.sh        # release -> dist/MidniteDock.app
./dev-run.sh        # wersja deweloperska na danych testowych (osobny katalog danych)
swift test --scratch-path ~/Library/Caches/MidniteDockBuild-App   # 58 testów
```
Zmienne środowiskowe dev: `MIDNITEDOCK_DATA_DIR`, `MIDNITEDOCK_DEV_MEDIA`, `MIDNITEDOCK_MUTE`, `MIDNITEDOCK_SHOTS=<katalog>` (renderuje stany do PNG), `MIDNITEDOCK_SELFTEST=1` (autotest logiki panelu).
