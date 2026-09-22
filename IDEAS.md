# IDEAS.md

Kosmiczny sandbox 2D. Zręcznościowa gra o eksploracji wszechświata: statek sterowany fizyką silników, proceduralny loot, pikselowe planety, ciągłe doświadczenie bez ekranów ładowania. Motto: explore fast, die often.

Ten dokument zbiera wizję i decyzje architektoniczne. Plan realizacji jest w PLAN.md.

---

## 1. Wizja i założenia

- Gra zręcznościowa, nie symulator. Fizyka ma dawać feeling, nie realizm.
- Szybkie tempo: krótkie loty, częsta śmierć, natychmiastowy powrót do gry.
- Eksploracja jako główna nagroda: nowe systemy, planety, stacje, loot.
- Grafika 2D, przyjemna dla oka, stylizowana, nie realistyczna.
- Wszystko, co się da, generowane proceduralnie z seedu.

## 2. Stack technologiczny

**Godot 4.x**, 2D. GDScript do logiki gry, C# lub GDExtension (C++/Rust) do gorących pętli, jeśli profilowanie pokaże potrzebę (kandydaci: marching squares terenu, samplowanie bitmapy).

Dlaczego Godot:
- szybka iteracja (edytor, hot reload, scenki),
- wbudowana fizyka 2D, Area2D z nadpisywaniem grawitacji i tłumienia,
- CanvasItem shaders, oświetlenie 2D, GPUParticles2D,
- Resource jako nośnik danych dla proceduralnych przedmiotów,
- open source, bez licencyjnych niespodzianek.

Odrzucone alternatywy: Bevy (brak edytora, słabe UI), Ebitengine w Go (wszystko trzeba pisać samemu), Unity (nic lepiej, licencja i C# to dodatkowy ciężar).

Opcjonalne addony: godot-rapier (Rapier 2D) jeśli domyślna fizyka będzie niestabilna przy wielu ciałach, LimboAI jeśli będą potrzebne drzewa zachowań.

## 3. Statek i silniki

Statek to RigidBody2D z własnym `_integrate_forces`.

Silnik jako komponent (node dziecko statku):
- pozycja względem środka masy,
- wektor ciągu (kierunek i maksymalna siła),
- typ: główny, obrotowy, manewrowy, hamujący, inny,
- stan: sprawność 0..1 (mnoży ciąg),
- niezawodność 0..1: szansa na dropout na tick, przerwy, oscylacja siły.

Każdy działający silnik robi `apply_force(thrust, offset)`. Moment obrotowy wychodzi sam z offsetu, więc silniki obrotowe to po prostu silniki z niezerowym offsetem prostopadłym.

Minimum dla grywalnego statku: silnik główny plus silniki obrotowe. Reszta to loot i konfiguracja.

Awarie silników pochodzą ze zderzeń, zużycia i ataków. Awaria to modyfikacja parametrów sprawności i niezawodności, nic specjalnego w silniku fizycznym.

### Realizacja (M1.1)

Klasa nazywa się `ShipEngine`, nie `Engine`, bo `Engine` to singleton Godota.

Montaż silnika bierze się z transformacji node'a: `position` to offset od środka
statku, a kierunek ciągu to `thrust_direction` (domyślnie lokalne "do góry")
przepuszczone przez obrót node'a. Dzięki temu obrócenie silnika w edytorze
obraca jednocześnie siłę i wydech cząsteczkowy.

Wybór silników obrotowych jest liczony, nie okablowany: `torque_sign()` zwraca
znak `position.cross(kierunek_ciągu)`, a statek odpala tylko te silniki, których
znak zgadza się z żądanym kierunkiem skrętu. Przeniesienie silnika w inne
miejsce kadłuba automatycznie zmienia to, w którą stronę kręci, co będzie
potrzebne, gdy silniki staną się lootem (M2).

Statek trzyma komendy sterowania (`thrust_command`, `turn_command`) osobno od
źródła inputu. `use_player_input = false` odcina klawiaturę, dzięki czemu tym
samym `Ship` będą sterować wrogowie w M5 i testy headless.

`can_sleep = false` na statku: uśpione ciało nie dostaje `_integrate_forces`,
więc statek stojący w bezruchu przestałby reagować na ciąg.

Statek bazowy do testów (wartości do przestrojenia, gdy będzie planeta i G):
masa 10, kadłub ~24 px, silnik główny 800 (czyli 80 px/s^2), dwa silniki
obrotowe po 60 zamontowane przy dziobie.

Do rozstrzygnięcia przy strojeniu feelingu: pojedynczy silnik obrotowy daje
oprócz momentu także siłę boczną (znosi statek w bok przy skręcaniu). Fizycznie
poprawne, ale może być nieprzyjemne. Alternatywa to para silników działających
jako czysty moment, kosztem złamania zasady "dwa silniki obrotowe".

## 4. Broń i loot

Broń montowana w hardpointach statku (pozycja, kąt, dopuszczalne typy).

Typy: laser (hitscan), projectile, dumb missile, homing missile, AoE (różne), pulse. Kilka klas bazowych pocisków, reszta to dane.

Definicja broni jako Resource: typ, obrażenia, kadencja, rozrzut, zasięg, prędkość pocisku, koszt energii, lista afiksów. Generator losuje z tabel rzadkości i modyfikatorów w stylu Borderlands: bazowy szablon plus 0..N afiksów, rzadkość podnosi liczbę i siłę afiksów.

To samo podejście dla silników, skanerów, napędów skokowych i baków: każdy moduł statku jest lootem z parametrami.

## 5. Struktura wszechświata

Galaktyka składa się z systemów. System ma gwiazdę, planety, opcjonalnie stacje i pola asteroid. Planety mogą mieć księżyce. Stacje kosmiczne orbitują wokół planet albo stoją w deep space.

### Ciała niebieskie

- Gwiazda: grawitacja, brak atmosfery, opcjonalnie strefa obrażeń od ciepła.
- Planeta: koło z nieregularną powierzchnią (góry, równiny, budynki, lądowiska), własne G, promień wpływu grawitacji, opcjonalna atmosfera.
- Księżyc: mała planeta na wolnej orbicie wokół planety.

### Grawitacja

Liczona własną funkcją, nie wbudowanym gravity_point (falloff jest sztywny). Statek w `_physics_process` sumuje siły od ciał w zasięgu. Funkcja: odwrotność kwadratu nad powierzchnią, g(r) = g_pow * (R/r)^2, z płynnym wygaszeniem do zera na skraju promienia wpływu. Odwrotność kwadratu daje zamknięte orbity i proce grawitacyjne (patrz sekcja 8). Każda planeta ma inne g_pow i promień wpływu.

### Atmosfera

Drag przez Area2D z `linear_damp` (tryb replace lub combine). Kilka koncentrycznych obszarów daje stopniowanie gęstości. Wygląd przez shader (patrz sekcja 11).

### Orbity

Księżyce i orbitujące stacje liczone analitycznie: pozycja = f(globalny czas). Kinematyczne, nie fizyczne. Dzięki temu poruszają się także wtedy, kiedy nie istnieją w scenie.

## 6. Planety z pikseli i kolizje

Teren planety to bitmapa, modyfikowalna (eksplozje, kopanie, zniszczenia). Nie zabija to kolizji, o ile piksele nie są ciałami fizycznymi.

Dwie techniki, docelowo hybryda:

1. **Samplowanie bitmapy** dla statków i pocisków względem terenu. Obiekty są małe, więc kilka punktów kadłuba sprawdzanych w bitmapie wystarcza. Normalna i odbicie z gradientu sąsiednich pikseli. Tanie, deterministyczne, dobre dla zręcznościówki. To główna metoda.
2. **Chunki plus marching squares** do CollisionPolygon2D per chunk (np. 64x64 px), regenerowane tylko dla brudnych chunków. Godot ma `BitMap.opaque_to_polygons()`, dla dużych zmian własna implementacja w GDExtension będzie szybsza. Potrzebne tylko tam, gdzie fizyka silnika musi widzieć teren (np. wraki, odłamki, fizyczne obiekty na powierzchni).

Fizyka silnika Godota zostaje dla interakcji statek-statek, statek-stacja i pocisków.

Kolizję planety tworzysz przy wejściu w promień wpływu, poza nim planeta to sprite i pozycja.

Teren generowany z seedu planety (szum), przechowywana tylko delta zmian.

## 7. Lądowanie

Lądowanie jest mechaniką skillową. Trudność wynika z parametrów (G, stan silników, atmosfera, teren), nie ze skryptów.

### Podwozie i warunki udanego lądowania

Statek ma podwozie jako 2 do 3 punktów kontaktu na kadłubie, wysuwane klawiszem. Wysunięte podwozie zwiększa drag w atmosferze; lądowanie bez podwozia daje obrażenia.

W chwili dotknięcia terenu sprawdzane są:
- prędkość pionowa względem powierzchni poniżej progu (stat podwozia),
- prędkość boczna poniżej progu,
- kąt między "górą" statku a normalną terenu w tolerancji (np. 15°),
- nachylenie terenu pod nogami poniżej tolerancji podwozia.

Nachylenie: wysokość terenu próbkowana pod każdą nogą w układzie biegunowym planety (promień w stronę środka), nachylenie = atan(dh/dx) między nogami. Tolerancja to stat podwozia: szeroki rozstaw nóg i niski środek masy = łatwiej. Podwozie jest modułem, więc jest lootem.

### Porażka

Nie binarnie:
- nadwyżka prędkości = obrażenia proporcjonalne do nadwyżki, głównie podwozie i silniki dolne,
- przekroczenie nachylenia lub kąta = przewrócenie: tryb fizyki punktów kontaktu (każda noga to punkt z siłą podparcia i tarciem, nie wchodzi w teren), statek toczy się w dół zbocza i obija, silniki dostają, gracz może ratować ciągiem.

### Stan "wylądowany"

Po udanym lądowaniu statek zamrożony (`freeze = true`, tryb kinematyczny) i przypięty do node'a planety. Planety mogą się obracać (dzień i noc); wylądowany statek obraca się razem z nią. Start = odmrożenie z prędkością styczną powierzchni.

W stanie wylądowanym: naprawa, tankowanie, zbieranie zasobów, handel na lądowisku, autosave.

### Skąd trudność

- silne G: stosunek ciągu do ciężaru bliski 1, mało zapasu na hamowanie,
- uszkodzony silnik główny oscyluje i przerywa,
- asymetryczna awaria silnika obrotowego ciągnie w bok przy każdym odpaleniu,
- rzadka atmosfera nie hamuje, gęsta hamuje mocno,
- planety górzyste mają mało płaskich miejsc.

### Generacja terenu pod lądowanie

Generator gwarantuje miejsca do lądowania: po szumie przebieg wyrównujący wybrane odcinki (plateau), częstość zależna od typu planety. Lądowiska przy bazach płaskie z definicji. Kratery po eksplozjach tworzą nowe zbocza; lądowanie na skraju krateru jest ryzykowne.

### Czytelność na HUD

- wysokościomierz i prędkość pionowa,
- wskaźnik nachylenia terenu pod statkiem, kolorowany (zielony, żółty, czerwony),
- stan podwozia,
- moduły asystujące jako loot: auto-poziomowanie, hold wysokości, autolądowanie na lądowiskach.

### Pojazd naziemny (później)

Po wylądowaniu można wyjechać pojazdem; statek zostaje jako baza. Koła próbkują teren jak nogi podwozia, "góra" to kierunek od środka planety. Wszystkie obliczenia powierzchniowe od początku w układzie biegunowym planety, żeby pojazd nie wymagał przeróbek.

## 8. Orbitowanie

Strefa między atmosferą a granicą pola grawitacyjnego. Orbity wychodzą z fizyki same, trzeba tylko dobrać funkcję grawitacji, uszczelnić numerykę i dać graczowi czytelny HUD.

### Fizyka

- Grawitacja jako odwrotność kwadratu (sekcja 5), inaczej orbity nie zamykają się i wyglądają jak błąd.
- `linear_damp` i `angular_damp` w ustawieniach projektu na 0 (domyślnie 0.1, co gasi orbity).
- Granica atmosfery jako gradient, nie ostra krawędź: górne warstwy z minimalnym dragiem. Niska orbita powoli opada i wymaga poprawek.
- Semi-implicit Euler w Godocie: orbity lekko precesują i wahają się, ale nie uciekają. Akceptowalne dla zręcznościówki.
- Księżyc wewnątrz pola planety: sumowanie sił, blisko księżyca dominuje księżyc. Orbitowanie księżyca działa bez dodatkowego kodu.

### Orbit lock

Ręczne utrzymanie idealnej orbity kołowej jest nudne. Jeśli przez ~2 s brak ciągu, prędkość radialna bliska zeru, prędkość styczna bliska orbitalnej (tolerancja zależna od modułu), statek przechodzi w kinematyczną orbitę kołową liczoną analitycznie, HUD pokazuje "ORBIT". Ciąg lub trafienie wraca do fizyki. Orbity eliptyczne zostają w pełni fizyczne.

Orbita zamknięta to stan spoczynku jak lądowanie: bezpieczne miejsce (jeśli nikt nie patroluje), skanowanie powierzchni, autosave, planowanie.

### Przewidywana trajektoria na HUD

Co klatkę symulacja naprzód 200 do 400 kroków tej samej funkcji grawitacji (bez dragu i ciągu), rysowana jako Line2D. Gracz widzi od razu: elipsa, ucieczka, uderzenie. Znaczniki apoapsy i periapsy. Jeśli trajektoria przecina powierzchnię: marker punktu uderzenia. Marker spina orbitę z lądowaniem: deorbit burn dobrany tak, żeby punkt uderzenia wypadł na plateau, to czysty skill.

### Zastosowania w rozgrywce

- Aerobraking: zejście na skraj atmosfery na prędkości orbitalnej hamuje bez paliwa, ale grzeje kadłub i szarpie uszkodzonymi silnikami.
- Deorbit na cel: precyzyjne zejście na lądowisko lub plateau.
- Proce grawitacyjne od księżyców i planet zamiast paliwa przy przelotach w systemie.
- Stacje orbitalne: dolatuje się orbitując, nie na wprost.
- Walka orbitalna: przeciwnicy na tej samej orbicie, pociski też podlegają grawitacji.

### Moduły asystujące (loot)

Automatyczna cyrkularyzacja, komputer deorbitu pokazujący moment odpalenia, większa tolerancja orbit lock.

## 9. Seamless: streaming świata

Dwie warstwy:

- **Model świata** (autoload `Universe` / `Galaxy`): czyste dane, bez node'ów. Systemy, gwiazdy, planety, orbity, stacje, seedy, delty stanu.
- **Scena**: tylko to, co blisko gracza. Instancjonowane i zwalniane przez `StreamingManager`.

Gracz i jego statek nigdy nie są dziećmi systemu. Żyją bezpośrednio pod światem, systemy pojawiają się i znikają pod nimi.

### Poziomy aktywności obiektów

Manager co ~0.5 s liczy odległość gracza od obiektów i przełącza poziomy:

| Poziom | Kiedy | Co istnieje |
|---|---|---|
| 0 | daleko | nic, ewentualnie punkt na mapie |
| 1 | w systemie | gwiazda i planety jako sprite'y, orbity analityczne |
| 2 | zbliżanie do planety | shader atmosfery, chunki terenu blisko statku, kolizje tych chunków |
| 3 | powierzchnia | AI, loot, budynki, spawnery |

Progi z histerezą (wejście na 3000, wyjście na 4000), żeby nie migotało na granicy.

### Zapis stanu przy wyłączaniu

Przy schodzeniu w dół poziomu delta stanu trafia do modelu: zmodyfikowane piksele, zabici wrogowie, zebrany loot. Node'y zwalniane. AI zamarza. Przy powrocie stan sprzed wyjścia plus proste timery respawnu. Bez symulacji offline.

### Wydajność

Generacja chunków i marching squares w WorkerThreadPool. Instancjonowanie node'ów na głównym wątku, kilka na klatkę, żeby nie było przycięć przy podchodzeniu do planety.

### Floating origin

Godot liczy pozycje w float32, powyżej ~100k jednostek zaczyna się drżenie. Skoro podróż między systemami jest skokiem, jeden system w scenie naraz, początek układu w gwieździe. Floating origin potrzebny tylko wtedy, gdy systemy przekroczą ~100k jednostek średnicy. Jeśli tak: prawdziwe współrzędne jako double w modelu, scena względem ruchomego początku, przesunięcie wszystkiego o minus offset po przekroczeniu progu, RigidBody2D przez `PhysicsServer2D.body_set_state` z zachowaniem prędkości.

Alternatywa: własny build Godota z `precision=double`, ale wymaga tak samo kompilowanych GDExtension. Floating origin to kilkadziesiąt linii i działa wszędzie.

## 10. Podróż między systemami: skok bez bramek

Skok, ale ciągły w odbiorze: bez portali, bez stargate, bez ekranu mapy jako obowiązkowego kroku.

### Dwie przestrzenie współrzędnych

Galaktyka ma własne współrzędne (system to punkt na płaszczyźnie, umowna jednostka), niezależne od jednostek w systemie. Obie są 2D w tej samej płaszczyźnie, więc kierunek do innego systemu na mapie galaktyki jest tym samym kierunkiem, w którym trzeba lecieć w scenie. Żeby skoczyć na północny wschód, obracasz statek na północny wschód i lecisz. Wylatujesz z celu na jego południowo-zachodniej krawędzi, z gwiazdą przed dziobem.

### Mass lock i strefa skoku

Gwiazda ma promień mass lock (np. 1.5 promienia orbity ostatniej planety). Poza nim skaner zaczyna działać i skok jest możliwy.

### Skaner

`Galaxy.systems_within(current_pos, scanner_range)` zwraca kandydatów. HUD rysuje wskaźniki na krawędzi ekranu w kierunku każdego. Trzy niezależne parametry, każdy z osobnego modułu statku (czyli z lootu):

- zasięg skanera: które systemy w ogóle widzisz,
- zasięg napędu: dokąd fizycznie doskoczysz,
- paliwo: koszt = f(dystans, masa statku), z aktualnego stanu baku.

Systemy widoczne, ale nieosiągalne, pokazywane szaro. Jakość skanera decyduje, ile wiesz przed skokiem: kierunek i dystans, potem typ gwiazdy, liczba planet, poziom zagrożenia, stacje. Opcjonalnie czas skanowania i szum sygnału.

### Sekwencja skoku

Maszyna stanów w kontrolerze statku:

1. **Idle**: poza mass lock, cel wybrany przez wycelowanie dziobem w wskaźnik (stożek ±15°) i przytrzymanie klawisza.
2. **Charging**: 2 do 4 s, przerywane obrażeniami lub puszczeniem klawisza, częściowe spalenie paliwa, awaryjny napęd może przerwać sam.
3. **Transit**: shader pełnoekranowy (smugi, radialne rozmycie, przesunięcie koloru), 1.5 do 2 s. Pod efektem: zapis delty starego systemu, zwolnienie sceny, generacja nowej z seedu w wątku, instancjonowanie.
4. **Arrival**: pozycja = `target.outer_radius * (source_pos - target_pos).normalized()`, kierunek zachowany, prędkość zredukowana. Efekt wygasa, lecisz dalej.

### Paliwo jako ryzyko

Skok z niedoborem paliwa nie jest zablokowany, tylko ryzykowny. Brakujący procent to szansa na misjump: pusty sektor międzygwiezdny (typ "systemu" bez gwiazdy: wraki, piraci, porzucony tanker z paliwem) albo dotarcie z uszkodzonym napędem. Analogicznie skok na styku zasięgu.

### Generacja galaktyki

Jeden seed galaktyki. Systemy rozłożone przez Poisson disk sampling, odległości zbliżone do zasięgów skoku. Seed systemu = hash(galaxy_seed, index), seed planety = hash(seed_systemu, index). Sprawdzenie spójności grafu (BFS) dla bazowego zasięgu napędu, żeby startowy statek nie utknął. Wyspy poza grafem jako late game za lepszym napędem. Dane w autoloadzie `Galaxy` z gridem do zapytań o sąsiedztwo.

Save = seed galaktyki plus słownik delt.

## 11. Grafika

- Atmosfera: shader na kole nieco większym od planety. Szum FBM przewijany w czasie na chmury, rim light na krawędzi, kolor i gęstość z parametrów planety. Różne typy atmosfer (kolor, gęstość, prędkość chmur, wzór).
- Powierzchnia: bitmapa terenu jako tekstura z paletą.
- Pixel-art: bazowa rozdzielczość 640x360, skalowanie przez tryb rozciągania `canvas_items` z aspektem `expand` (ustawienia projektu), filtr tekstur Nearest. SubViewport nie jest potrzebny: `canvas_items` renderuje w niskiej rozdzielczości i skaluje całość, a `expand` pozwala na szersze ekrany bez czarnych pasów. SubViewport dopiero wtedy, gdy HUD będzie musiał być w pełnej rozdzielczości.
- Silniki: GPUParticles2D, intensywność od ciągu, zmiana przy warpie i awariach.
- Tło: paralaksa gwiazd w shaderze, smugi przy skoku.
- Oświetlenie 2D od gwiazdy, cień strony nocnej planety.

## 12. AI i zawartość planet

- Wrogowie sterowani steering behaviours (seek, pursue, orbit, flee) plus maszyna stanów. Drzewa zachowań (LimboAI) jeśli zajdzie potrzeba.
- Na planetach: zasoby do zbierania, loot, budynki, lądowiska, spawnery wrogów.
- Stacje: handel, naprawa, tankowanie, misje.
- Eventy w deep space i przy misjumpach: wraki, zasadzki, anomalie.

## 13. Struktura projektu (Godot)

Autoloady:
- `Galaxy` / `Universe`: dane świata, seedy, delty.
- `StreamingManager`: odległości, poziomy, kolejka instancjonowania.
- `OriginShifter`: tylko jeśli okaże się potrzebny.
- `LootGenerator`: tabele rzadkości, afiksy.

Sceny:
- `World`: korzeń, pod nim `Player` i aktywny `System`.
- `System`: gwiazda, planety, stacje, instancjonowany per aktywny system.
- `Planet`: komponenty ładowane warunkowo (Atmosphere, Terrain, Surface).
- `Ship`: RigidBody2D, komponenty Engine, Hardpoint, Module.
- `HUD`: wskaźniki skoku, stan silników, paliwo.

## 14. Otwarte pytania

- Jednostki: ile jednostek ma promień typowej planety i typowego systemu? Decyduje o potrzebie floating origin.
- Czy teren planety zawija się (powierzchnia koła) czy jest to bitmapa w układzie biegunowym? Wpływa na generację i samplowanie.
- Ile chunków terenu jednocześnie w scenie przy podejściu do planety?
- Ekonomia paliwa: czy paliwo to zasób z planet, ze stacji, czy jedno i drugie?
- Śmierć: co gracz traci, co zostaje (statek, loot, odkryte systemy)?
- Zapis: autosave przy skoku i lądowaniu, czy permadeath z meta-progresją?
