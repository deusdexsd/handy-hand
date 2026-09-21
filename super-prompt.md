# Super Prompt — Notch Dock dla montażu (FCP companion)

**Założyłem:** appka natywna na macOS, budowana przez agenta kodującego (Claude Code / Cursor) w Swift; „elementy z FCP" traktuję jako najbardziej ryzykowną część i to od niej ma zależeć zakres MVP. Jak nie tak — powiedz.

---

## 1. Doprecyzowany cel

Chcesz mały, zawsze-na-wierzchu panel przy notchu, który jest Twoją **półką z często używanymi elementami** podczas montażu — SFX, b-rolle, sekwencje, może napisy/efekty — poukładanymi w kategorie, z podglądem (waveformy, miniatury), które **przeciągasz stamtąd prosto na timeline FCP**, i którym możesz przypisać **skróty klawiszowe**. Panel ma trzy tryby zachowania: rozwijanie po najechaniu, trzymanie gdy aktywny jest wybrany program, albo trzymanie na stałe.

Kluczowe: **nie wiadomo z góry, ile z tego FCP w ogóle przepuści.** Dlatego prompt zmusza agenta, żeby **najpierw zrobił twardą weryfikację techniczną (spike)** i dopiero na zielonych funkcjach budował MVP. Zero budowania „w ciemno".

---

## 2. Moja szybka ocena wykonalności (żebyś wiedział na wejściu)

Nie jestem od tego, żeby Ci przytakiwać — więc konkret, zanim wydasz na to czas albo kasę:

**Prawie na pewno działa (zielone):**
- Panel przy notchu, zawsze na wierzchu, trzy tryby (hover-expand / follow-active-app / pin na stałe).
- Biblioteka assetów z folderów, kategorie, waveformy dla audio, miniatury dla wideo, podgląd/odsłuch.
- Przeciąganie **plików** (SFX, b-roll) z panelu **do FCP** — na przeglądarkę zdarzeń i na timeline. To zwykły file-drag, FCP to łyka.
- Globalne skróty klawiszowe wyzwalające akcje panelu.

**Da się, ale z gwiazdką (żółte):**
- Upuszczenie klipu **dokładnie w miejscu playheada** — FCP kładzie tam, gdzie puścisz kursor, nie zawsze idealnie „na playhead".
- Wstawianie sekwencji / compound clipów — realne przez **FCPXML** (import albo wklejenie z pasteboardu), ale to nie to samo co żywy drag na otwarty timeline.
- Skrót klawiszowy, który sam „wrzuca" element — najpewniej przez schowek: skrót → kładzie klip jako FCPXML na pasteboard → Ty robisz Cmd+V w FCP.

**Wątpliwe / prawdopodobnie NIE (czerwone):**
- Przeciąganie **wbudowanych efektów, napisów i generatorów z FCP** z zewnętrznej appki. FCP nie udostępnia ich jako plików ani przez publiczne API — nie da się ich wyliczyć ani „chwycić" spoza programu. Obejście: **własne szablony napisów jako Motion (.moTN)**, które instalują się do FCP i pojawiają się w nim natywnie, albo generowanie snippetów **FCPXML** z gotowymi tytułami. To działa, ale to inna mechanika niż drag.

To jest dokładnie powód, dla którego robimy weryfikację najpierw. Poniższy prompt każe agentowi to udowodnić kodem, a nie obiecać.

---

## 3. SUPER PROMPT (do wklejenia agentowi kodującemu)

> Skopiuj wszystko poniżej linii i wklej do Claude Code / Cursor w pustym repo.

---

**ROLA:** Jesteś senior macOS developerem (Swift, AppKit + SwiftUI). Budujemy natywną appkę na macOS: mały panel dokowany przy notchu, zawsze na wierzchu, jako „półka" z często używanymi elementami montażowymi (SFX, b-roll, sekwencje, potencjalnie napisy/efekty), które użytkownik przeciąga stąd na timeline Final Cut Pro, z kategoriami, podglądem (waveformy/miniatury) i skrótami klawiszowymi.

**ZASADA NADRZĘDNA — FAZA 0 ZANIM COKOLWIEK ZBUDUJESZ.**
Nie buduj pełnej aplikacji. Najpierw zrób **feasibility spike**: dla każdej ryzykownej funkcji napisz minimalny kod dowodowy (proof), uruchom go na realnym macOS z zainstalowanym Final Cut Pro i **zaraportuj wynik w tabeli** z werdyktem: `DZIAŁA` / `DZIAŁA CZĘŚCIOWO` / `NIE DZIAŁA` / `OBEJŚCIE (opisz jakie)`. Dopiero po dostarczeniu raportu i mojej akceptacji przejdź do MVP — i buduj **wyłącznie na funkcjach oznaczonych DZIAŁA lub z zaakceptowanym obejściem.**

**MACIERZ DO ZWERYFIKOWANIA W FAZIE 0** (dla każdej pozycji: jak sprawdziłeś + werdykt + ograniczenia):

1. **Okno przy notchu, zawsze na wierzchu.** NSPanel na poziomie okna ponad normalnymi oknami, pozycjonowanie pod notchem (uwzględnij `safeAreaInsets` / `auxiliaryTopLeftArea`), zachowanie na Macach bez notcha i przy wielu monitorach.
2. **Trzy tryby zachowania panelu:** (a) zwinięty, rozwija się po najechaniu; (b) trzyma się rozwinięty gdy aktywna jest wybrana aplikacja (obserwuj `NSWorkspace.didActivateApplicationNotification`); (c) pinned na stałe. Przełączane checkboxem.
3. **Biblioteka z folderów + kategorie.** Wskazanie folderów źródłowych, podział na kategorie (SFX / B-roll / Sekwencje / Napisy). Odświeżanie przy zmianach plików.
4. **Waveformy dla audio + miniatury/podgląd dla wideo.** Render waveformu (AVFoundation / Accelerate), miniatura pierwszej klatki, odsłuch/podgląd po kliknięciu.
5. **Drag pliku Z panelu DO FCP — audio i wideo.** `NSDraggingSource` z file URL (najlepiej file promise). Sprawdź drop: na przeglądarkę zdarzeń FCP **oraz na sam timeline**. Zaraportuj, czy klip ląduje przy playheadzie, czy tam gdzie kursor.
6. **Wstawianie sekwencji / compound clipu.** Przez FCPXML: (a) import do zdarzenia, (b) wklejenie klipu z pasteboardu (sprawdź typ pasteboardu FCPXML i czy FCP przyjmuje Cmd+V klipu na timeline). Zaraportuj co realnie wchodzi na otwarty projekt.
7. **Napisy/tytuły i efekty.** Zweryfikuj i rozstrzygnij jednoznacznie: czy da się z zewnętrznej appki (a) wyliczyć wbudowane efekty/tytuły FCP, (b) przeciągnąć je na timeline. Jeśli nie — udokumentuj **obejścia**: generowanie FCPXML z gotowym tytułem (z podanym effect UID) oraz instalowanie własnych szablonów Motion (.moTN) tak, by pojawiały się w FCP natywnie. Pokaż działający minimalny przykład przynajmniej jednego obejścia.
8. **Globalne skróty klawiszowe do elementów.** Rejestracja globalnych hotkeyów; po wyzwoleniu wykonaj realną akcję (np. połóż wybrany klip jako FCPXML na pasteboard do wklejenia, albo zainicjuj drag). Zaraportuj, która akcja jest wykonalna bez ingerencji w UI FCP.

**OGRANICZENIA I WSKAZÓWKI TECHNICZNE:**
- FCP nie ma sensownego API do edycji timeline'u ani (praktycznie) skryptowania AppleScript montażu — nie zakładaj, że jest. Wymianą danych jest **FCPXML** i standardowy **drag/drop plików** oraz **pasteboard**.
- Nie symuluj UI FCP przez Accessibility/klikanie na ślepo jako podstawowy mechanizm — to kruche. Jeśli gdzieś to jedyna droga, wyraźnie to oznacz jako ryzyko.
- Stack: Swift, AppKit dla okna/dragów (NSPanel, NSDraggingSource), SwiftUI dla UI wewnątrz. Bez zewnętrznych zależności tam, gdzie natywne API wystarcza.
- Zgłoś od razu, jeśli któraś funkcja wymaga uprawnień (Accessibility, Full Disk Access, dostęp do folderów) albo wyłączenia sandboxu.

**FORMAT DOSTARCZENIA FAZY 0:**
- Tabela macierzy z werdyktami i ograniczeniami.
- Minimalny kod dowodowy dla każdej pozycji (osobne, uruchamialne targety/przykłady).
- Rekomendacja zakresu MVP: co wchodzi (zielone), co odpada lub idzie na obejście, co zostawiamy na później.
- **STOP.** Czekaj na moją akceptację zakresu przed budową MVP.

---

## 4. Struktura appki (docelowo, po weryfikacji)

- **Warstwa okna** — NSPanel przy notchu, poziom always-on-top, logika trzech trybów.
- **Warstwa biblioteki** — foldery źródłowe, indeks, kategorie, cache miniatur/waveformów.
- **Warstwa podglądu** — waveform, miniatura, odsłuch/podgląd.
- **Warstwa eksportu do FCP** — drag plików + generator FCPXML + obsługa pasteboardu.
- **Warstwa skrótów** — globalne hotkeye mapowane na elementy/akcje.
- **Ustawienia** — wybór folderów, tryby panelu, mapowanie skrótów.

---

## 5. Plan działania

1. Wklej super prompt do agenta w pustym repo.
2. Odbierz raport Fazy 0. Patrz twardo na kolumnę werdyktów — zwłaszcza pkt 5, 6, 7.
3. Zatnij zakres MVP do zielonych: realnie to panel + biblioteka SFX/b-roll + drag plików do FCP + skróty.
4. Napisy/efekty i sekwencje potraktuj jako osobny etap na obejściach (FCPXML / Motion), nie jako część MVP.
5. Zbuduj i testuj na swoim realnym flow montażowym, nie na sztucznych plikach.

---

## 6. Opcje podejścia

- **A — Tylko media (SFX/b-roll) + skróty.** Najszybciej działa, najmniej ryzyka. Zacznij tu, jeśli chcesz mieć coś użytecznego w tydzień.
- **B — Media + własne napisy jako Motion/FCPXML.** Wchodzisz w to, jeśli po Fazie 0 obejście na tytuły okaże się wygodne — daje Ci Twoje presety napisów pod ręką.
- **C — Pełna wizja z efektami FCP.** Realizuj tylko jeśli Faza 0 pokaże zieleń tam, gdzie się jej nie spodziewam. Nie zaczynaj od tego.

---

## Wdrożenie — pierwszy ruch

Weź super prompt z sekcji 3, odpal agenta w pustym repo i **nie pozwól mu zacząć budować, dopóki nie odda raportu Fazy 0.** Cała gra toczy się o to, żeby najpierw wiedzieć, co FCP naprawdę przepuści — reszta to już rzemiosło.
