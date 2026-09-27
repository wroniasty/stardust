# PLAN.md

Plan realizacji w milestone'ach. Każdy milestone kończy się czymś, w co da się grać albo co da się zobaczyć. Kolejność wynika z ryzyka: najpierw to, co może wywrócić architekturę, potem zawartość.

Kontekst i decyzje projektowe: IDEAS.md.

Obraz i dźwięk mają własny, równoległy plan: VISUALS.md. Ten plik nie odpowiada
za to, jak gra wygląda i brzmi — i dlatego jego kryteria zamknięcia nie mogą od
tego zależeć.

---

## M0: Szkielet projektu

Cel: pusty, ale poprawnie ustawiony projekt Godot 4.x z repo.

- [x] Projekt Godot 4.x (2D, standardowy build, GDScript), repo git, `.gitignore` dla Godota (`.godot/`, `*.import` opcjonalnie).
- [x] Struktura katalogów: `scenes/`, `scripts/`, `resources/`, `shaders/`, `addons/`.
- [x] Autoloady jako puste szkielety: `Galaxy`, `StreamingManager`, `LootGenerator`.
- [x] Scena `World` z pustym `Player` i miejscem na `System`.
- [x] Ustawienia renderowania: SubViewport w niskiej rozdzielczości i upscale (decyzja o docelowej rozdzielczości pikselowej, np. 640x360).
- [x] Skrypt uruchamiający projekt headless do sprawdzania błędów (`godot --headless --path . --quit`).

Gotowe, gdy: projekt się uruchamia, pusty ekran, brak błędów w konsoli.

---

## M1: Jedna planeta do zabawy i testów

Cel: piaskownica. Jeden statek, jedna planeta, można latać, spadać, rozbijać się i rozwalać teren. To milestone testowy dla feelingu fizyki i dla wydajności pikselowego terenu. Jeśli tu nie będzie fajnie, reszta nie ma sensu.

### 1.1 Statek

- [x] `Ship` jako RigidBody2D z `_integrate_forces`.
- [x] Komponent `Engine`: pozycja, wektor ciągu, typ, sprawność, niezawodność.
- [x] Grupy sterowania z geometrii: `EngineMount` plus `EngineData`, sześć komend liczonych z wkładu c_i, wagi z kary bocznej, autorytet na grupę, ostrzeżenia o pustych grupach.
- [x] Statek testowy: silnik główny, dwie pary obrotowe, dwa silniki strafe, silnik hamujący. Sterowanie: WSAD + QE.
- [x] Kill rotation (X) z progiem wygaszenia liczonym z autorytetu statku.
- [x] Brake (Z): rozkład prędkości na komendy, bez ruszania obrotu.
- [x] Debug draw silników: trójkąt z przepustnicą i typem, krzyżyk w środku masy, wspólny przełącznik F7.
- [x] Kamera podążająca za statkiem, lekki zoom zależny od prędkości.
- [x] GPUParticles2D na silnikach, intensywność od ciągu.
- [x] Debug overlay: prędkość, siły, stan silników.

### 1.2 Planeta

- [x] `Planet` jako koło z parametrami: promień, G, promień wpływu, promień atmosfery.
- [x] Grawitacja własną funkcją w statku: odwrotność kwadratu nad powierzchnią, płynne wygaszenie na granicy wpływu.
- [x] `linear_damp` i `angular_damp` projektu na 0.
- [x] Atmosfera jako Area2D z `linear_damp`, kilka koncentrycznych obszarów z gradientem, górna warstwa z minimalnym dragiem.
- [x] Prosty shader atmosfery: kolor, rim light, przewijany szum na chmury.

### 1.3 Teren z pikseli

- [x] Generacja bitmapy terenu z seedu (szum na powierzchni koła, góry i równiny).
- [x] Render terenu jako tekstura z paletą.
- [x] Kolizja statku z terenem przez samplowanie bitmapy w punktach kadłuba. Normalna z gradientu pikseli, odbicie, obrażenia zależne od prędkości uderzenia.
- [x] Modyfikacja terenu: usuwanie pikseli w promieniu (eksplozja) z aktualizacją tekstury.
- [x] Pomiar: czas aktualizacji tekstury przy modyfikacji, czas samplowania na klatkę.

### 1.4 Jedna broń

- [x] Klasa bazowa pocisku, jeden typ: projectile.
- [x] Hardpoint na statku, strzelanie, pocisk niszczy teren przy trafieniu.
- [x] Pocisk koliduje z terenem przez samplowanie.

### 1.5 Orbitowanie

- [x] Sprawdzenie, że orbita kołowa i eliptyczna utrzymują się przez kilka minut bez znaczącego dryfu.
- [x] Przewidywana trajektoria na HUD: symulacja naprzód 200 do 400 kroków, Line2D, znaczniki apoapsy i periapsy, marker punktu uderzenia w powierzchnię.
- [x] Stan orbity czytany z trajektorii (ORBIT / DECAYING / SUBORBITAL / ESCAPE), wskaźnik na HUD. Pierwotny orbit lock — przejście w analityczną orbitę kołową — usunięty, bo pomiar dryfu go nie uzasadniał (IDEAS.md sekcja 8).
- [x] Aerobraking: drag górnych warstw atmosfery hamuje statek na orbicie, prosty licznik ciepła kadłuba.

### 1.6 Lądowanie

- [x] Podwozie: 2 do 3 punktów kontaktu, wysuwanie klawiszem, drag przy wysuniętym.
- [x] Sprawdzenie warunków przy dotknięciu: prędkość pionowa, boczna, kąt, nachylenie terenu pod nogami (próbkowanie w układzie biegunowym).
- [x] Udane lądowanie: zamrożenie statku i przypięcie do planety, start z prędkością styczną.
- [x] Nieudane: obrażenia od nadwyżki prędkości, przewrócenie przez fizykę punktów kontaktu przy złym nachyleniu.
- [x] Generator terenu gwarantuje plateau do lądowania (parametr częstości).
- [x] HUD: wysokościomierz, prędkość pionowa, wskaźnik nachylenia pod statkiem, stan podwozia.
- [x] Opcjonalna rotacja planety (dzień i noc) i sprawdzenie, że wylądowany statek jedzie razem z nią.

### 1.7 Śmierć i restart

- [x] Kadłub ma HP, zderzenia i własne pociski zadają obrażenia.
- [x] Śmierć: efekt, natychmiastowy respawn na orbicie. Bez menu.


### 1.8 Narzędzia deweloperskie

- [x] Konfigurator planety (F6): parametry generatora w panelu, przebudowa planety i teleport na jej lądowisko. Wymusił rozdzielenie `roll_parameters()` od `rebuild()` w `Planet` (IDEAS.md sekcja 5).
- [x] `tools/cloud_preview.tscn`: zrzuty archetypów chmur do PNG.
- [x] `tools/check.ps1`: przebieg gry plus smoke test, wspólne wyłapywanie błędów silnika i shaderów.

Gotowe, gdy: da się wystartować z powierzchni, wejść na orbitę i na niej zaparkować, zejść deorbitem na wybrane miejsce, wylądować na zboczu i zobaczyć, że to zależy od nachylenia i prędkości, rozwalić kawałek góry, rozbić się i od razu lecieć dalej.

Ocena subiektywna ograniczona do **sterowania**: czy statek robi to, co każe
pilot, i czy da się wylądować świadomie, a nie przypadkiem. Jeśli nie, tu się
kręci fizyką, nie idzie dalej.

Czego to kryterium celowo **nie** obejmuje: czy gra wygląda i brzmi dobrze. To
jest pytanie dla VISUALS.md i nie może blokować M1. Pierwotne sformułowanie
mieszało jedno z drugim, przez co zamknięcie M1 zależało od warstwy, której w
M1 nigdy nie było.

Pytania do rozstrzygnięcia na koniec M1 (zapisać odpowiedzi w IDEAS.md):
- jednostki: promień planety, promień wpływu, prędkości (wartości robocze w IDEAS po M1.2, potwierdzić),
- ~~czy samplowanie bitmapy wystarcza, czy potrzebne są chunki z marching squares~~ — wystarcza, zmierzone w M1.3,
- ~~rozdzielczość bitmapy terenu na planetę~~ — 1.5 px na teksel, siatka biegunowa, zmierzone w M1.3,
- progi lądowania (prędkości, kąt, nachylenie) dla statku bazowego,
- czy planety się obracają,
- ~~tolerancje orbit lock i długość przewidywanej trajektorii~~ — lock usunięty (stan orbity jest wyliczany), długość trajektorii ustalona w M1.5, wartości w IDEAS.

---

## M2: Silniki, awarie, loot

Cel: statek jako zestaw modułów, które są lootem.

- [ ] Komputer lotu: alokacja NNLS z rzeczywistymi ciągami i stanem silników, czysty obrót i czysty strafe mimo asymetrii i uszkodzeń. Zastępuje heurystykę wag z M1.1 tam, gdzie gracz znajdzie moduł.
- [ ] Gimbal na silniku MAIN: sterowany wektor ciągu zamiast stałego kierunku montażu.
- [ ] Punkty kontaktu wyprowadzane z obrysu kadłuba zamiast stałej `HULL_POINTS`: wierzchołki plus podział krawędzi krokiem ~6 px (cztery teksele terenu), liczone raz przy `configure()`.
- [ ] `CollisionShape2D` dla pocisków liczony z tego samego obrysu jako otoczka wypukła, zamiast rysowany drugi raz.
- [ ] `MAX_PENETRATION` i `CONTACT_ITERATIONS` skalowane rozmiarem kadłuba i liczbą punktów, zamiast stałych dobranych pod trójkąt.
- [ ] Wytyczne obrysu kadłuba (obwód, wierzchołki, wypukłość, najcieńszy detal, rozstaw nóg) sprawdzane w raporcie konfiguracji — wartości i uzasadnienie w IDEAS.md sekcja 6.
- [ ] Test: iglica terenu węższa niż odstęp punktów kontaktu nie przechodzi przez kadłub.
- [x] Raport konfiguracji przy montażu: autorytet w każdą stronę, asymetria par lustrzanych, puste grupy, boczny dryf pary obrotowej jako przyspieszenie. `compare()` pokazuje w ekranie wymiany, co zrobił moduł — różnice, nie stan. Wytyczne obrysu kadłuba dojdą osobno.
- [ ] Awarie silników: spadek sprawności od zderzeń, niezawodność jako dropout i oscylacja ciągu.
- [ ] Lądowanie z uszkodzonymi silnikami: asymetria, oscylacje, sprawdzenie, że jest trudno, ale możliwe.
- [ ] Podwozie jako moduł (tolerancja nachylenia, próg prędkości) i moduły asystujące (auto-poziomowanie, hold wysokości, cyrkularyzacja, komputer deorbitu).
- [ ] Auto-orbit jako opcjonalna funkcja komputera lotu: część komputerów ją ma, część nie. Załącza się w polu grawitacyjnym i poza atmosferą, sam wchodzi na orbitę (IDEAS.md sekcja 8).
- [ ] Zużycie w czasie, naprawa (na razie klawisz debug).
- [ ] Silniki manewrowe i hamujące, statek z pełnym zestawem vs statek minimalny.
- [x] Broń jako Resource: typ, obrażenia, kadencja, rozrzut, zasięg, afiksy. Hardpoint to montaż z listą dopuszczalnych typów, `fit()` oddaje poprzednią broń.
- [x] `LootGenerator`: tabele rzadkości, afiksy, generacja broni i silników. Pięć poziomów rzadkości, 0..4 afiksy, siła jako wykładnik; każdy przedmiot z jawnego seeda.
- [x] `EngineData.bulk`: gabaryt silnika jako jego masa i zarazem warunek zmieszczenia się w slocie (`bulk <= size`). Typy zostają otwarte; ceną za dziwne dopasowanie jest fizyka, nie tabelka.
- [x] Skaner jako element HUD: trójkąty dla ciał niebieskich (kierunek, odległość do powierzchni, rozmiar ciała, wygaszenie poza polem grawitacyjnym) i romby dla lootu (kolor z rzadkości, osobny krótszy zasięg, znacznik także na ekranie). Zalążek — zasięgi stałe, w M5 własność modułu skanera.
- [ ] Pozostałe typy broni: laser, dumb missile, homing missile, AoE, pulse.
- [x] Skrzynki z lootem na powierzchni planety, podnoszenie, wymiana modułu w locie (Tab, bez pauzy). Skrzynki stoją na półkach do lądowania, kolor z rzadkości.
- [ ] Energia: `GeneratorData` (pojemność, recharge, timeout, bulk) jako moduł, pula na statku liczona w `_physics_process`, minimalna szyna wbudowana w kadłub, gdy generatora nie ma (IDEAS.md sekcja 14).
- [ ] `energy_cost` broni faktycznie wydawany: strzał bez pełnego kosztu nie wychodzi, każdy wydatek resetuje timeout. `energy_cost` wchodzi do tabel lootu (afiksy `efficient`, `capacitor-fed`), do `HIGHER_IS_BETTER` i do `LIMITS`.
- [ ] HUD energii: pasek z podziałką co koszt zamontowanej broni (pilot liczy strzały, nie procenty), widoczna różnica między „czeka na timeout" i „ładuje się", wyraźna odmowa strzału.
- [ ] Statystyki statku liczone przy montażu: `stat_add` i `stat_mul` na modułach, agregat w raporcie konfiguracji z rozbiciem na moduły, nieznany klucz to `push_error`. Afiksy międzystatowe na silnikach (`dynamo`, `buffered`) — silnik, który podnosi recharge.
- [ ] Moduły broni: `mod_slots` na broni, `ShotModData` z `energy_multiplier > 1`, efekty pocisku jako dane (eksplozja przy kontakcie, podpalenie, przebicie), kolejność bez znaczenia. Test: każdy moduł w tabeli podnosi koszt energii.
- [ ] Pomiar energii: sustained dps bazowych broni w granicach ±10%, burst różny co najmniej 1.5× — generator nie może spłaszczyć różnic między broniami do jednej liczby.

Gotowe, gdy: znajduje się losowy silnik lub broń, montuje, czuć różnicę, uszkodzony silnik zmienia sposób latania, a spust ma swój koszt — seria się kończy i trzeba zdecydować, kiedy przestać strzelać.


---

## MAUX1: Edytor statku (prototyp)

Cel: jeden ekran, na którym widać cały statek i wszystko, co się na nim wozi.
Prototyp do testów — otwiera się wszędzie (klawisz `I`), nie tylko po
wylądowaniu, bo teraz chodzi o to, żeby dało się go pomacać.

Szybka wymiana na Tab zostaje tym, czym jest: jedno gniazdo, bez pauzy,
decyzja podjęta w locie. To jest druga połowa.

- [x] `bulk` na `WeaponData`: jedna jednostka dla każdego rodzaju modułu, żeby cargo nie potrzebowało tabeli przeliczeń, a pilot drugiej liczby do nauczenia. Afiks `lightweight` (gabaryt w dół za cenę obrażeń).
- [x] Ładownia cargo jako **pojemność w gabarytach**, nie zestaw slotów. Ładunek jest masą: pełne cargo to wolniejszy statek. Luk cargo siedzi na środku masy pustego statku, więc ładowanie jest odczuwalne jako ociężałość, a nie jako ostrzeżenie w raporcie.
- [x] Wyrzucanie za burtę tworzy **prawdziwą skrzynkę**, do której można wrócić, z chwilą nietykalności, żeby nie podnieść jej z powrotem w tej samej klatce.
- [x] Ekran: cargo + ładownia jako jedna lista, schemat statku, info o module, podświetlenie pasujących gniazd, montaż, chowanie, wyrzucanie.
- [x] Schemat **generowany** z wielokąta kadłuba i pozycji mountów, nigdy rysowany ręcznie — ręczny byłby nieprawdziwy w chwili, gdy mount się przesunie (a przesunęły się dwa razy przy okazji `bulk`).
- [ ] Podgląd skutku przed montażem: najechanie na gniazdo pokazuje, co zrobi `ConfigurationReport.compare()`, zanim cokolwiek zostanie wkręcone. Dziś raport pojawia się dopiero po.
- [ ] Mysz: klikanie po liście i po kropkach schematu. Dziś wszystko na klawiaturze.
- [ ] Reguła docelowa: edytor tylko po wylądowaniu lub zadokowaniu, żeby lądowisko miało powód istnienia inny niż „miejsce, gdzie się nie ginie".
- [ ] Pojemność cargo jako własność kadłuba/modułu, a nie stała.

Gotowe, gdy: da się znaleźć moduł, obejrzeć go obok tego, co już jest zamontowane, wsadzić w konkretne gniazdo i wyrzucić to, czego się nie chce — bez zgadywania, gdzie co pasuje.

---

## M3: System gwiezdny i streaming

Cel: gwiazda, kilka planet, księżyce, stacja. Planety włączają się i wyłączają w zależności od odległości.

- [ ] Model danych systemu w `Galaxy`: gwiazda, planety, księżyce, stacje, orbity, seedy.
- [ ] Orbity analityczne od globalnego czasu.
- [ ] `StreamingManager`: poziomy 0..3 z histerezą, kolejka instancjonowania, generacja terenu w WorkerThreadPool.
- [ ] Zapis delty przy wyłączaniu planety (piksele, loot), odtwarzanie przy powrocie.
- [ ] Gwiazda: grawitacja, strefa obrażeń, oświetlenie 2D, cień nocnej strony planet.
- [ ] Orbitowanie księżyca w polu planety, proca grawitacyjna między ciałami, pociski pod wpływem grawitacji.
- [ ] Stacja orbitująca i stacja w deep space: dokowanie, naprawa, tankowanie.
- [ ] Test: przelot przez wszystkie planety systemu bez przycięć, powrót do zmodyfikowanej planety pokazuje zmiany.
- [ ] Decyzja o floating origin na podstawie rozmiaru systemu.

Gotowe, gdy: lot planeta-planeta jest płynny, a wyłączona planeta pamięta stan.

---

## M4: Galaktyka, skaner, skok

Cel: wiele systemów, podróż skokiem bez bramek.

- [ ] Generacja galaktyki: Poisson disk sampling, seedy systemów, sprawdzenie spójności grafu.
- [ ] Mass lock gwiazdy i strefa skoku.
- [ ] Moduły: skaner (zasięg, jakość), napęd skokowy (zasięg), bak (paliwo). Wszystkie jako loot.
- [ ] HUD: wskaźniki systemów na krawędzi ekranu, kolor wg osiągalności, informacje wg jakości skanera.
- [ ] Maszyna stanów skoku: Idle, Charging, Transit, Arrival.
- [ ] Shader tranzytu, wymiana sceny systemu pod graczem w trakcie efektu.
- [ ] Pozycja przylotu na krawędzi celu od strony źródła.
- [ ] Misjump: sektor międzygwiezdny bez gwiazdy, ryzyko od niedoboru paliwa i zasięgu.
- [ ] Zapis gry: seed plus delty, autosave przy skoku.

Gotowe, gdy: wylot z jednego systemu i wlot do drugiego czuje się jak jeden lot.

---

## M5: Wrogowie, zasoby, pętla gry

Cel: powód, żeby latać.

- [ ] AI wrogów: steering behaviours, maszyna stanów, kilka archetypów (patrol, agresor, uciekinier).
- [ ] Wrogowie na planetach i w przestrzeni, spawnery z timerami respawnu.
- [ ] Zasoby na planetach: zbieranie, wartość, sprzedaż na stacjach.
- [ ] Ekonomia paliwa: skąd się bierze, ile kosztuje.
- [ ] Poziom zagrożenia systemu, skalowanie lootu i wrogów z odległością od startu.
- [ ] Zasady śmierci: co gracz traci, co zostaje.
- [ ] Eventy w deep space: wraki, zasadzki, anomalie.

Gotowe, gdy: jest cel krótkoterminowy (loot, paliwo, przeżyć) i długoterminowy (dalej, lepszy statek).

---

## M6: Szlif

- [ ] Pojazd naziemny: wyjazd z wylądowanego statku, koła próbkujące teren, kamera, zbieranie zasobów z pojazdu.
- [ ] Typy atmosfer i planet (kolory, gęstości, wzory chmur, biomy powierzchni).
- [ ] Budynki, lądowiska, ruiny na powierzchni.
- [ ] Dźwięk: silniki, broń, zderzenia, skok.
- [ ] Menu, ustawienia, mapowanie klawiszy, pad.
- [ ] Mapa galaktyki jako dodatek (odkryte systemy).
- [ ] Optymalizacja i profilowanie na słabszym sprzęcie.
- [ ] Ewentualne przeniesienie gorących pętli do GDExtension.

---

## Zasady pracy

- Jeden milestone naraz. Nie zaczynać M2, dopóki M1 nie daje radości z latania.
- Każda decyzja techniczna po pomiarze trafia do IDEAS.md (sekcja otwartych pytań kurczy się, sekcje techniczne rosną).
- Prototypować brzydko, szlifować późno. Placeholdery graficzne do M5 włącznie.
- Wszystko z seedu od pierwszego dnia. Żadnych ręcznie ułożonych planet, nawet w M1.
