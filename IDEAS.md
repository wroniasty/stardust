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

### Realizacja (M1.4)

`Hardpoint` działa tak samo jak `ShipEngine`: transformacja node'a jest
montażem. Obrót node'a w edytorze obraca lufę, bez zmiany kodu. Hardpoint
posiada kadencję, ale nie spust — decyzję o strzale podejmuje statek, więc AI
i autopilot (M5) pójdą dokładnie tą samą ścieżką co gracz.

Pocisk to `Area2D`, nie `Node2D`: statki i stacje *są* ciałami fizycznymi, więc
trafianie w kadłub (M1.7) dostaniemy za darmo. Monitorowanie jest wyłączone do
tego czasu.

Kolizja pocisku z terenem jest samplowana wzdłuż odcinka przelotu, a nie w
punkcie końcowym klatki. Przy 600 px/s tick to 10 px, a teksel terenu ma 1.5 px
— pojedynczy test na końcu klatki przestrzeliwałby cienkie ściany na wylot.
Krok próbkowania 1 px musi zostać poniżej rozmiaru teksela.

Pociski są rodzicowane do węzła z grupy `projectile_container`, nigdy do
statku: pocisk po opuszczeniu lufy nie może dziedziczyć ruchu wystrzeliwującego.
Prędkość statku jest natomiast doliczana raz, przy wystrzale.

Strzelanie jest w `_physics_process`, nie w `_integrate_forces`: ten drugi
callback działa w trakcie flushowania zapytań serwera fizyki i dodawanie tam
węzłów do drzewa jest niedozwolone.

Pociski na razie lecą prosto. Grawitacja na pociskach jest zaplanowana na M3
(razem z procą grawitacyjną) i sprowadza się do jednej linijki, bo
`Ship.gravity_acceleration_at()` już istnieje.

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

### Realizacja (M1.2)

`Planet` to Node2D, nie Area2D z `gravity_point`: wbudowany falloff jest sztywny
i nie da się go wygasić na skraju studni. Planety rejestrują się w grupie
`gravity_sources`, a statek sam sumuje `gravity_at()` każdego ciała w zasięgu.

Wygaszenie na granicy: pełna odwrotność kwadratu do 0.9 promienia wpływu, potem
`smoothstep` do zera. Bez tego statek dostawałby kopniaka przy przekraczaniu
granicy. Pod powierzchnią g jest przytrzymane na wartości powierzchniowej,
inaczej odwrotność kwadratu eksploduje w stronę środka.

Atmosfera to trzy koncentryczne Area2D z `linear_damp_space_override =
COMBINE_REPLACE` i rosnącym `priority` do środka. Wyższy priorytet jest
liczony pierwszy, a COMBINE_REPLACE każe zignorować wszystkie rzadsze powłoki
wokół, więc w danej wysokości obowiązuje dokładnie jedna gęstość. Profil to
3% / 25% / 100% pełnego dragu, czyli górna warstwa ledwo muska (pod aerobraking
z M1.5).

Wartości robocze (do potwierdzenia na koniec M1, patrz "Otwarte pytania"):
promień planety 900..1800 px, g przy powierzchni 25..60 px/s^2, promień wpływu
3.5..6 R, atmosfera 25..45% R, 20% planet bez atmosfery. G jest trzymane
wyraźnie poniżej 80 px/s^2 ciągu silnika głównego, żeby stockowy statek zawsze
mógł wystartować. Prędkość orbitalna przy powierzchni to sqrt(g*R), czyli około
150..330 px/s.

Skala została podniesiona po pierwszej ocenie wzrokowej: przy promieniu rzędu
500 px horyzont był zbyt zakrzywiony, a atmosfera zbyt cienka, żeby cokolwiek
z niej zobaczyć. Większy promień spłaszcza lokalny horyzont, co jest potrzebne
przy lądowaniu, a gruba atmosfera daje widoczne wejście w powietrze.

Konsekwencja, o której łatwo zapomnieć: przy atmosferze sięgającej 1.45 R
orbita na 1.5 R już w niej siedzi. Testy orbitalne przeniesione na 2.0 R.
Progi rim lightu w shaderze atmosfery są ułamkami wysokości atmosfery, więc
też musiały się zacieśnić (0.08/0.7 -> 0.03/0.30): przy 400 px powietrza stara
wartość dawała 270 px poświaty na ekranie wysokim na 360 px.

Zmierzone: orbita kołowa na 2.0 R trzyma promień z dryfem 0.05% przez 30 s przy
semi-implicit Euler w 60 Hz. Wystarczy dla zręcznościówki, pełny test na kilka
minut jest w M1.5.

Shader atmosfery dostaje tylko `surface_ratio` (promień powierzchni podzielony
przez promień atmosfery), kolor i gęstość; cała geometria to UV kwadratu.
Chmury są próbkowane na okręgu, a nie na rozwiniętym kącie, więc obracają się
bez szwu.

## 6. Planety z pikseli i kolizje

Teren planety to bitmapa, modyfikowalna (eksplozje, kopanie, zniszczenia). Nie zabija to kolizji, o ile piksele nie są ciałami fizycznymi.

Dwie techniki, docelowo hybryda:

1. **Samplowanie bitmapy** dla statków i pocisków względem terenu. Obiekty są małe, więc kilka punktów kadłuba sprawdzanych w bitmapie wystarcza. Normalna i odbicie z gradientu sąsiednich pikseli. Tanie, deterministyczne, dobre dla zręcznościówki. To główna metoda.
2. **Chunki plus marching squares** do CollisionPolygon2D per chunk (np. 64x64 px), regenerowane tylko dla brudnych chunków. Godot ma `BitMap.opaque_to_polygons()`, dla dużych zmian własna implementacja w GDExtension będzie szybsza. Potrzebne tylko tam, gdzie fizyka silnika musi widzieć teren (np. wraki, odłamki, fizyczne obiekty na powierzchni).

Fizyka silnika Godota zostaje dla interakcji statek-statek, statek-stacja i pocisków.

Kolizję planety tworzysz przy wejściu w promień wpływu, poza nim planeta to sprite i pozycja.

Teren generowany z seedu planety (szum), przechowywana tylko delta zmian.

### Realizacja (M1.3)

Rozstrzygnięcie otwartego pytania: **bitmapa w układzie biegunowym**, nie kwadrat
z wyciętym kołem. Powody: zawija się bez szwu, nie marnuje narożników, a kolumna
tekseli to dosłownie "grunt pod tym kątem", czyli dokładnie to, czego potrzebują
próbkowanie nóg podwozia (M1.6) i pojazd naziemny (M6). Zgadza się też z
konwencją z CLAUDE.md, że cała matematyka powierzchni jest biegunowa.

Przechowywana jest tylko skorupa: pas od 0.90 R do 1.12 R. Niżej jest lity
rdzeń, wyżej niebo, więc żadne z nich nie potrzebuje tekseli.

Rozdzielczość: 1.5 px na teksel przy powierzchni, liczba próbek wyliczana z
promienia, więc gęstość pikseli jest ta sama na małej i dużej planecie.
Zajętość trzymana w `PackedByteArray` (zapytania kolizyjne są zbyt częste na
`Image.get_pixel()`) i lustrzana w `Image` dla GPU.

Normalna nie jest liczona z zapisanej wysokości, tylko odczytywana z bitmapy:
osiem prób na okręgu o promieniu 4 px, normalna to średnia kierunków, w których
jest pusto. Dzięki temu ściana świeżego krateru daje normalną tej samej jakości
co nietknięty grunt, bez żadnego dodatkowego stanu.

Shader terenu czyta tę samą bitmapę tym samym mapowaniem co kolizja, więc to,
co widać, jest dokładnie tym, w co się uderza. Warstwy skalne (skorupa, skała,
rdzeń) są odczytywane z bitmapy przez zapytanie "czy wyżej jest jeszcze skała",
więc nowy krater sam z siebie dostaje obrys skorupy.

**Zmierzone** (AMD RX 7900 XT, GDScript, planety R 1025..1710):

| | R 1025 | R 1710 |
|---|---|---|
| siatka | 4295 x 150 (629 KB) | 7163 x 251 (1756 KB) |
| generacja | 7.8 ms | 14.4 ms |
| krater r=28 + upload tekstury | 0.25 ms | 0.51 ms |
| samplowanie kadłuba (6 punktów, wszystkie w skale) | 0.127 ms/tick | 0.124 ms/tick |

Górny limit próbek kątowych musiał wzrosnąć z 4096 do 8192, inaczej największe
planety schodziły poniżej obiecanych 1.5 px na teksel. Pamięć na planetę
dochodzi do 1.7 MB; przy systemie z ośmioma planetami w M3 to rzędu 14 MB, co
jest do przyjęcia, ale warto pamiętać przy streamingu.

Wniosek: **samplowanie bitmapy wystarcza, chunki z marching squares nie są
potrzebne**. Budżet klatki przy 60 Hz to 16.6 ms; najgorszy przypadek kolizji
zjada 0.4% z tego, a krater 1.7% jednorazowo. Upload całej tekstury przy każdym
kraterze jest na tyle tani, że częściowa aktualizacja nie ma uzasadnienia.
Marching squares zostaje na wypadek, gdyby fizyka silnika musiała widzieć teren
(wraki, odłamki).

### Odpowiedź kolizji (poprawione po ocenie wzrokowej)

Pierwsza wersja była zagregowana: jedna uśredniona normalna, odbicie prędkości
liniowej i sztuczne tłumienie obrotu. Nie działała i nie mogła: skoro żaden
impuls nie był przyłożony w punkcie kontaktu, moment obrotowy w ogóle nie
powstawał, więc statek dotykający gruntu jednym narożnikiem nie przewracał się,
tylko zsuwał płasko. Do tego podskakiwał.

Obecnie każdy punkt kadłuba w skale dostaje własny impuls przyłożony we własnym
ramieniu względem środka masy:

- normalny impuls `j = -(1+e) * v_n / (1/m + (r x n)^2 / I)`,
- tarcie Coulomba wzdłuż stycznej, ograniczone przez `mu * j`,
- cztery przebiegi solvera, bo kontakty są sprzężone (impuls na dziobie zmienia
  prędkość zbliżania na ogonie).

Ramię liczone jest do środka masy (`transform.origin + state.center_of_mass`),
nie do origin node'a. Na tym kadłubie różnica to ~3 px i wystarcza, żeby
przewracanie wyglądało źle.

Trzy rzeczy okazały się konieczne, żeby statek przestał drgać w spoczynku:

1. **Restytucja tylko powyżej progu** (30 px/s). Sprężystość na kontakcie
   spoczynkowym powoduje, że kadłub bez końca wymienia z gruntem drobne impulsy.
2. **Częściowa korekcja penetracji** (slop 0.5 px, 60% reszty na tick).
   Wypychanie kadłuba całkowicie co tick oddaje wysokość, którą grawitacja
   zaraz zabiera, i statek skacze po gruncie w nieskończoność.
3. **Pomiar penetracji dokładniejszy niż slop.** To była najbardziej podstępna
   z trzech: marsz co 1 px przy slopie 0.5 px nie potrafi odróżnić zanurzenia
   0.4 px od 1.0 px, więc korekcja podnosiła kadłub o ~0.3 px co tick i
   kołysanie nigdy nie gasło. Cztery bisekcje po marszu dają 1/16 px i dopiero
   wtedy prędkość obrotowa schodzi do zera.

Koszt bisekcji: samplowanie kadłuba w najgorszym przypadku wzrosło z 0.08 do
0.13 ms na tick. Nadal 0.8% budżetu klatki.

Przewracanie się na bok jest teraz normalnym wynikiem i tak ma być — to
zaplanowana forma nieudanego lądowania (sekcja 7). Nogi podwozia i progi
lądowania przychodzą w M1.6.

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
- Tło: paralaksa gwiazd w shaderze, smugi przy skoku. Zrealizowane w M1.1:
  jeden pełnoekranowy quad na CanvasLayer -100 z `follow_viewport_enabled =
  false`. Quad nigdy się nie rusza, cały ruch robi uniform `world_offset`
  karmiony pozycją kamery, więc pole gwiazd jest nieskończone i nie ma czego
  streamować. Gwiazdy są hashowane z siatki, czyli odtwarzalne z samej pozycji:
  odlot i powrót pokazuje te same gwiazdy. Trzy warstwy (paralaksa 0.10 / 0.30 /
  0.65) dają czytelne poczucie głębi. Offset mnożony przez zoom kamery, inaczej
  gwiazdy dryfują w złym tempie przy oddaleniu.
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
- ~~Czy teren planety zawija się czy jest to bitmapa w układzie biegunowym?~~ Rozstrzygnięte w M1.3: bitmapa biegunowa, 1.5 px na teksel, tylko pas skorupy. Szczegóły i pomiary w sekcji 6.
- Ile chunków terenu jednocześnie w scenie przy podejściu do planety?
- Ekonomia paliwa: czy paliwo to zasób z planet, ze stacji, czy jedno i drugie?
- Śmierć: co gracz traci, co zostaje (statek, loot, odkryte systemy)?
- Zapis: autosave przy skoku i lądowaniu, czy permadeath z meta-progresją?
