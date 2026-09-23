# Handy (dawniej MidniteDock/Łapka): status (22.09.2026)

Aplikacja: `App/dist/Handy.app` (release, ad-hoc podpis, aplikacja z paska menu, bez ikony w Docku).
Dane użytkownika: `~/Library/Application Support/MidniteDock/` (`userdata.json`, `index.json`).
Nazwa produktu jest w jednym miejscu (`Sources/MidniteDock/AppInfo.swift`); bundle id i katalog danych zostają `MidniteDock` z historycznych powodów.

## Jest (sprawdzone)

| Obszar | Co | Jak sprawdzone |
|---|---|---|
| Panel | NSPanel nad oknami, tryby: po najechaniu / podążaj za aplikacją / przypięty; pozycje: notch (góra-środek), prawa krawędź na środku, lewa krawędź na środku, z suwakiem położenia na bokach (Ustawienia); wirtualny notch (czarna wysepka) auto / zawsze / nigdy | autotest na prawdziwej geometrii ekranu, lista okien systemu |
| Źródła | foldery i biblioteki FCP (czytane jak folder, tylko „Original Media”), symlinki rozwiązywane, obserwowanie zmian na żywo | 61 testów + autotest (plik dodany i usunięty widać w indeksie) |
| Wizualizacje | waveform z prawdziwego pliku (Accelerate, cache na dysku), wspólna skala czasu, miniatura wideo, czas trwania na kaflu, odsłuch/podgląd (AVPlayer) | render widoków + autotest odtwarzania |
| Organizacja | kolekcje własne, smart: przedziały długości (osobno audio i wideo, dowolnie dodawane, z odcieniem szarości), reguły po słowach, typ; ulubione, tagi | testy zapytań |
| Wyszukiwanie i filtry | szukanie w bieżącej kategorii (domyślnie tylko po nazwie; ikona tagu przy polu wyszukiwania włącza szukanie też po tagach, rozszerzeniu i wydarzeniu FCP, wyłączone domyślnie, żeby nie spowalniać), filtry (typ, długość, data, tag) z widocznymi chipami i „Wyczyść”, sortowanie | testy + render |
| Duplikaty | zwijanie: ten sam typ + nazwa + długość (±10 ms), tryb ścisły dokłada rozmiar; zostaje kopia ze źródła wyżej na liście; znaczek ×N, lista kopii w menu kontekstowym; ulubione/tagi/kolekcje dotyczą wszystkich kopii; w folderze źródła widać jego własną kopię; przełącznik „Pokaż duplikaty osobno” (Ustawienia → Źródła) | 4 testy + autotest na danych z kopiami |
| Słowa kluczowe | edycja nazw i słów, dodawanie, usuwanie, kolejność (strzałki), przywracanie domyślnych | render |
| Typy | audio dzieli się na SFX i muzykę wg granicy długości (domyślnie 20 s, edytowalna) z ręczną poprawką prawym przyciskiem (Typ dźwięku); wideo; obrazy (JPG, PNG, WebP, HEIC, TIFF, GIF, BMP, PSD, TGA) z miniaturą i wymiarami; przedziały długości osobno dla SFX, muzyki i wideo | 7 testów + autotest |
| Dodawanie | folder, pojedyncze pliki, biblioteka FCP: przycisk „+” w sidebarze ORAZ trzy osobne przyciski w Ustawienia → Źródła (bez zagnieżdżonego menu — menu w Form/Section bywało zawodne), upuszczenie z Findera na panel, „Usuń z biblioteki” dla pojedynczych plików | testy + autotest; **klik w Ustawieniach nie sprawdzony na żywo** |
| Zmiana nazwy | prawy przycisk → Zmień nazwę: zmienia plik NA DYSKU i przenosi ulubione/tagi/kolekcje/typ; odmawia przy kolizji nazwy, złych znakach i plikach z bibliotek FCP | autotest |
| Wielozaznaczenie (Shift) | Shift-klik zaznacza zakres; wcześniej `mouseDown` zerował zaznaczenie zanim Shift zdążył zadziałać (nowy plik poza zaznaczeniem = reset do 1 elementu) — naprawione: `pressDown` pomija reset, gdy trzymany jest Shift albo ⌘. Prawy przycisk i ⌘5 (ulubione) na wielozaznaczeniu działają na całej grupie | autotest w prawdziwym oknie (zakres 4 elementów, ⌘5 na wszystkich naraz) |
| Rozmiar panelu | rozciąganie myszką za krawędzie i rogi (wyśrodkowany panel rośnie symetrycznie), zapis w ustawieniach, limity min/max i ekranu | 5 testów + autotest; **działanie myszy nie sprawdzone na żywo** |
| Klawiatura | strzałki (po siatce, bez zawijania, przewija do zaznaczenia), Enter = zmiana nazwy (jak w Finderze), spacja = odtwarzanie; skróty cyfrowe (1–9/0) działają TYLKO z ⌘, żeby nigdy nie kolidowały z pisaniem w wyszukiwarce; panel przy rozwinięciu staje się naprawdę klawiszowy (`makeKeyAndOrderFront`, nie tylko na wierzchu), żeby klik w pole tekstowe zawsze dawał mu fokus | autotest w prawdziwym oknie (cyfra bez ⌘ wpisuje się do pola, ⌘+cyfra działa jako skrót, Esc wychodzi z pola) |
| Skala waveformu | automatyczna: najdłuższy dźwięk w widoku (osobno SFX i muzyka) = pełna szerokość, podziałka czasu pod waveformem; opcja stałej skali | render + autotest |
| Podgląd obrazów i wideo | mały pasek na dole (jak wcześniej); opcja „Większy podgląd” (strzałka w pasku albo Ustawienia → Ogólne): obraz/odtwarzacz 340×190 na dole panelu | render + autotest |
| Miniatury | limit równoległych dekodowań, cache błędów (koniec pętli ponawiania), pasek podglądu odświeża się po wczytaniu | autotest |
| Odtwarzanie: kliknięcie przełącza | ponowne zwykłe kliknięcie już zaznaczonego, grającego elementu pauzuje zamiast zaczynać od nowa; zwinięcie panelu domyślnie zatrzymuje odtwarzanie (Ustawienia → Ogólne: „Zatrzymaj odtwarzanie po zwinięciu panelu”, można wyłączyć) | ręczny przegląd kodu (bez automatycznego testu odtwarzania) |
| Zaznaczanie i wklejanie | ⌘A: w polu tekstowym zaznacza tekst, poza polem zaznacza wszystkie widoczne pliki (jak w Finderze); ⌘V poza polem wkleja pliki skopiowane skądinąd (np. ⌘C w Finderze) — dokłada je do biblioteki jak przeciągnięcie | autotest w prawdziwym oknie, w tym przez `NSApp.sendAction` (prawdziwa ścieżka fizycznej klawiatury, nie tylko wewnętrzne przechwytywanie) |
| Kopiowanie plików | ⌘C (poza polem tekstowym) kopiuje zaznaczone pliki do schowka jako pliki — wklejasz je w Finderze albo innej aplikacji zwykłym ⌘V; menu kontekstowe ma to samo jako „Kopiuj pliki”, osobno od „Skopiuj ścieżkę” (tekst). **Naprawione**: ⌘C/⌘V/⌘A działają teraz też jako właściwe akcje NSResponder (`copy(_:)`/`paste(_:)`/`selectAll(_:)` na oknie), bo macOS kieruje te konkretne skróty przez system komunikatów akcji, nie zawsze przez zwykły keyDown — samo przechwytywanie zdarzenia w `sendEvent` nie wystarczało na żywej klawiaturze, mimo że przechodziło w testach (błąd metodologii testu, nie kodu) | autotest przez `NSApp.sendAction`, symulujący prawdziwą ścieżkę klawiatury |
| Chowanie paska bocznego | ikonka w toolbarze (po lewej, obok tytułu kategorii) — chowa cały pasek Ulubione/Typ/Foldery/Kolekcje, reszta (wyszukiwanie, filtry, siatka, podgląd) zostaje bez zmian | render (widok z paskiem i bez) |
| Widok minimalistyczny | ikonka w toolbarze (duży kwadrat — celowo inna niż ikonka siatka/lista) + Ustawienia → Wygląd. **Prawdziwa siatka masonry** (kolumny równej szerokości, każdy nowy element trafia do aktualnie najkrótszej kolumny — bez dziur, jak na Pintereście), kafle bez tła/obwódki karty, same zaokrąglone rogi; kafle obrazów/wideo w proporcji materiału (70–260 pt). Wideo dostaje wymiary z `AVAssetTrack.naturalSize` + transform; **stare, już zaindeksowane pliki wideo dostają je automatycznie przy najbliższym indeksowaniu** (nie trzeba dotykać plików na dysku — indeksator sam dobiera te bez wymiarów) | render (kolumny różnej wysokości, bez dziur, potwierdzone) |
| Przeciąganie z Findera z otwieraniem panelu | trzymanie pliku nad notchem (bez klikania) rozwija panel tak samo jak zwykłe najechanie — globalny monitor łapie teraz też `.leftMouseDragged`, nie tylko `.mouseMoved` (podczas przeciągania system nie generuje tego drugiego); upuszczenie dalej działa jak wcześniej | **nie sprawdzone na żywo — prawdziwego przeciągania z Findera nie da się zasymulować w autoteście** |
| Skróty w panelu | ⌘1–⌘4 filtr typu w bieżącej kategorii (mapowanie w Ustawieniach → Skróty; ponowne = zdejmuje), ⌘⇧1–⌘⇧4 zmienia typ zaznaczonego dźwięku, ⌘5 ulubione, ⌘6 czyści filtry; spacja: dźwięk = odsłuch, obraz/wideo = większy podgląd (bez ⌘, bo nic nie koliduje z pisaniem) | autotest |
| Skróty globalne i Finder | globalny skrót pokaż/ukryj panel (domyślnie ⌃⌥⌘L, nagrywany w Ustawieniach → Skróty, można wyłączyć; Carbon, działa z FCP na wierzchu, bez uprawnień); ⌘9 (do wyboru ⌘7/⌘8/⌘9/⌘0/wyłączony) = pokaż zaznaczone w Finderze | test ustawień, rejestracja skrótu w autotest; **naciśnięcie prawdziwego skrótu nie sprawdzone** |
| Esc w wyszukiwarce | Esc wychodzi z pola wyszukiwania (tekst zostaje), potem działają klawisze 1–0, strzałki, spacja; przy otwartym pytaniu Esc idzie do pytania | autotest w prawdziwym oknie (pole w edycji → Esc → klawisz 2 filtruje) |
| Język | Polski / English w Ustawieniach → Ogólne, przełącza cały interfejs od razu (etykiety enumów w DockCore, teksty w aplikacji przez `L(pl, en)`) | testy dekodowania; wizualny render obu wersji |
| Ulubione | gwiazdka na kaflu i w liście jest klikalna (dodaje/usuwa bez menu); gwiazdka w toolbarze (obok sortowania) włącza/wyłącza „zawsze na górze” — domyślnie wyłączone, żeby lista nie skakała przy dodawaniu | test sortowania (rdzeń) + autotest |
| Uruchamianie | „Otwieraj przy logowaniu”: przełącznik w menu Handy na pasku menu i w Ustawieniach → Ogólne (SMAppService, stan trzyma system) | kompiluje się; **rejestracja nie była uruchamiana** (nie zmieniam Twoich elementów logowania) |
| Eksport | do folderu „Handy – eksport”: układ Typ i długość albo Kolekcje; kopiuj albo dowiązania; nie nadpisuje | 2 testy |
| Efekt przy notchu | Ustawienia → Wygląd: Brak (domyślnie) / Łapka. **Podświetlenie usunięte całkowicie** (David: „działało niebo lepiej wcześniej"; cały kod koloru/siły/gradientu/ambientnej poświaty panelu wyrzucony, nie tylko schowany). Stare zapisy z "glow" ładują się jako Łapka. Łapka: SZTYWNE ramię (ok. 15% giętkości = lekkie sprężyste dobieganie), łokieć tuż przy notchu, przedramię i pęk pięciu palców skierowane w stronę kursora, grubość 31→25 pt przy notchu 220 pt; reaguje TYLKO na kursor w promieniu ok. 105 pt (wysuwanie/chowanie wolne, chowanie z opóźnieniem 0,45 s; bark przeskakuje krokami po notchu, dłoń „pacuje” w cyklu ok. 1,15 s); na bocznych krawędziach działa tylko podświetlenie | testy (IK, sprężyna), renderowanie póz, test w prawdziwym oknie z symulowanym kursorem; **ruch na żywo niesprawdzony** |
| Zakładki | zapisane, nazwane widoki (kategoria + filtry + sortowanie + widok) do jednego kliknięcia; osobne od bieżącego widoku, który zapamiętuje się sam bez zapisywania | testy |
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

`App/make-dmg.sh` buduje uniwersalną aplikację (arm64 + x86_64) i pakuje w `~/Downloads/Handy.dmg` (dysk z Handy i skrótem do Programów). Podpis ad-hoc, bez notaryzacji: na innym Macu trzeba raz zatwierdzić aplikację (Ustawienia → Prywatność i ochrona → Otwórz mimo to albo `xattr -dr com.apple.quarantine`); opisane w `docs/Instrukcja.html`. Uruchomienie na innym Macu **nie było sprawdzone** (nie miałem drugiego komputera); sprawdzone: DMG się montuje, podpis jest poprawny, w środku oba typy procesorów.

## Uruchamianie i testy

```
cd Projects/MidniteDock/App
./package.sh        # release -> dist/MidniteDock.app
./dev-run.sh        # wersja deweloperska na danych testowych (osobny katalog danych)
swift test --scratch-path ~/Library/Caches/MidniteDockBuild-App   # 65 testów
```
Zmienne środowiskowe dev: `MIDNITEDOCK_DATA_DIR`, `MIDNITEDOCK_DEV_MEDIA`, `MIDNITEDOCK_MUTE`, `MIDNITEDOCK_SHOTS=<katalog>` (renderuje stany do PNG), `MIDNITEDOCK_SELFTEST=1` (autotest logiki panelu).
