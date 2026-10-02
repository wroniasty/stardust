# VISUALS.md

Tor prezentacji: obraz i dźwięk. Rozwijany **równolegle** do PLAN.md, nie po nim.

Powód jest konkretny. Kryterium zamknięcia M1 brzmi „ocena subiektywna: czy
sterowanie daje radość", a tej oceny nie da się wydać na trójkącie z
`Polygon2D` w ciszy — bo odczucie z gry jest w dużej części prezentacją, a nie
fizyką. Dopóki oba siedzą w jednym planie, linia rozgrywki nie może domknąć
milestone'u, którego brakującą częścią nie jest rozgrywka. Ten plik przejmuje
pytanie „czy to jest przyjemne", a PLAN.md zostaje z pytaniami, na które umie
odpowiedzieć pomiarem.

Kontekst i decyzje projektowe rozgrywki: IDEAS.md. Decyzje prezentacji trzymamy
tutaj, żeby oba tory jak najrzadziej dotykały tych samych plików.

---

Spis tego, **co** trzeba narysować i co ma być spritem, a co zostaje
proceduralne, jest w **ASSETLIST.md**. Ten plik mówi kiedy; UI_STYLE.md mówi
jak to ma wyglądać.

## 1. Kontrakt z linią główną

To jest cała treść tego pomysłu. Reszta dokumentu to zawartość.

**1. Symulacja emituje, prezentacja słucha. Nigdy odwrotnie.** Dodanie dźwięku
przyziemienia ma być nowym plikiem plus jedną linią podłączenia sygnału, a nie
zmianą w `ship.gd`. Jeśli efekt wymaga dopisania czegoś do kodu rozgrywki, to
jest **zadanie szwu** — małe, robione na linii głównej, wypisane w obu planach
(sekcja 6).

**2. Wielkości ciągłe się odpytuje, zdarzenia się subskrybuje.** `air_density`,
`hull_heat`, `hull_integrity`, `effective_output()`, `orbit_state()` to liczby,
które symulacja i tak liczy co tick — prezentacja czyta je w swoim własnym
`_process` i nikomu nie przeszkadza. Sygnały są od rzeczy, które zdarzają się
raz: przyziemienie, trafienie, śmierć, wystrzał.

**3. Prezentacja nie wpływa na fizykę.** Żadna decyzja rozgrywkowa nie czyta
węzła prezentacji. Strażnik jest gotowy: smoke test ma przechodzić z całą
warstwą wyłączoną, a `--headless` już jej nie uruchamia.

**4. Jeden wyłącznik na całą warstwę.** Zepsuty efekt nie może blokować linii
głównej ani testów.

**5. Osobne pliki i osobne poddrzewo.** Kod: `scripts/fx/`. Zasoby: `resources/fx/`,
`assets/audio/`. Węzły prezentacji wiszą pod jednym dzieckiem `Presentation`
w scenach, więc nawet w `ship.tscn` czy `world.tscn` diffy obu torów nie
nachodzą na siebie.

Pliki dzielone (wymienione świadomie, bo to jedyne miejsca styku):
`scenes/ship.tscn`, `scenes/planet.tscn`, `scenes/world.tscn`, `project.godot`
(magistrale audio, warstwy). Wszystko inne należy do jednego toru.

---

## 2. Czym to napędzać: liczbami, które już są

Symulacja liczy komplet wielkości, których nikt jeszcze nie ogląda ani nie
słyszy. Napędzanie prezentacji tymi liczbami jest jednocześnie najtańsze i
najuczciwsze — gra zaczyna tłumaczyć własny model, zamiast go ilustrować.

| liczba | jest w | czym mogłaby być |
|---|---|---|
| `air_density` 0..1 | `Ship`, z `Planet.air_density_at()` | **główny suwak miksu dźwięku**, gęstość smug, rozmycie |
| `hull_heat` 0..1 | `Ship`, rośnie od dragu × v² | poświata kadłuba, narastający ryk wejścia w atmosferę |
| `effective_output()` | każdy `EngineInstance` | głośność i wysokość dźwięku silnika, jasność wydechu |
| `orbit_state()` | `Planet` | kolor HUD (jest) plus sygnał dźwiękowy przy wejściu w DECAYING |
| `hull_integrity` | `Ship` | ślady uszkodzeń na kadłubie, alarm |
| `slope_at()` | `Planet` | podpowiedź na gruncie przy podejściu |
| gęstość powietrza + prędkość | obie | wiatr, drżenie obrazu |

Jedna decyzja projektowa wynika z tego wprost i warto ją postawić na początku:
**próżnia jest cicha.** W kosmosie słychać tylko to, co przechodzi przez
konstrukcję — silniki i uderzenia — a reszta miksu jest wyciszona przez
`air_density`. Wejście w atmosferę to moment, w którym świat zaczyna brzmieć.
Gracz uczy się modelu atmosfery uchem, zanim przeczyta go z HUD.

### Stan szwów dzisiaj

Jest: `landed`, `landing_rejected`, `destroyed`, `hull_impact(speed, damage)`,
`hull_changed`, `flight_mode_changed`, `deployment_changed`, `impacted` na
pocisku. To dobra podstawa — `hull_impact` niesie już prędkość uderzenia, czyli
dokładnie to, czym skaluje się głośność i siła wstrząsu.

Brakuje (to są zadania szwu z sekcji 6): zapłon i zgaszenie silnika, wystrzał z
hardpointu, wyrwanie dziury w terenie, przekroczenie granicy atmosfery.

---

## 3. Tor wizualny

### V0: Fundament

Cel: nic nie wygląda inaczej, ale wszystko dalej da się robić bez dotykania
linii głównej.

- [ ] Poddrzewo `Presentation` w `ship.tscn` i `world.tscn`, globalny wyłącznik.
- [ ] `scripts/fx/` i pierwszy odbiornik zdarzeń podpięty do istniejących sygnałów (wstrząs kamery od `hull_impact`) — jako dowód, że szew działa.
- [ ] `tools/gallery.tscn`: renderuje każdy podsystem wizualny do PNG, rozszerzenie `cloud_preview.tscn` (sekcja 5).
- [ ] Paleta jako zasób, nie jako stałe rozsiane po shaderach.

Gotowe, gdy: smoke test przechodzi z warstwą włączoną i wyłączoną, a `gallery`
wypluwa komplet zrzutów jednym poleceniem.

### VS: Przejście na sprite'y

Cel: to, co dziś jest `Polygon2D` i `_draw()`, staje się animowanym spritem —
bez zmiany jednej liczby w symulacji.

Idzie **równolegle do V1**, nie przed nim ani po nim: światło dotyka shaderów
terenu i atmosfery, sprite'y dotykają statku i drobnych obiektów, i te zbiory
się nie przecinają.

#### Co już stoi

- [x] **Decyzja o rozdzielczości i filtrze** (`scripts/fx/art.gd`). Świat
  rysowany w skali 3x i wyświetlany w 1/3, filtrowany
  `LINEAR_WITH_MIPMAPS`; interfejs 1:1 i `Nearest`. Uzasadnienie i pomiar w
  ASSETLIST.md, „Dlaczego świat i interfejs mają osobne reguły". Mipmapy
  włączone globalnie przez `[importer_defaults]`, bo filtr świata ich
  wymaga, a bez nich degraduje po cichu.
- [x] **Format zasobu**: `SpriteStrip` (pasek klatek, pivot, tempo przy
  pełnej mocy, flaga świat/interfejs) i `LookTable` (który obrazek dostaje
  rzecz — po kluczu, po afiksie, po progu na statystyce).
- [x] **Węzeł**: `StripSprite extends Sprite2D`. Nie `AnimatedSprite2D` — bo
  `SpriteFrames` trzyma fps w zasobie, a ASSETLIST mówi, że tempo jest
  odczytem ze statku; i bo każdy `AnimatedSprite2D` chodzi na własnym
  zegarze, a tu zegar jest jeden, w skórce.
- [x] **`HullData`** i dziesięć kadłubów jako zasoby, na razie jako trzecia
  kopia katalogu — z testem, który pilnuje, żeby trzy kopie się zgadzały.
- [x] **41 placeholderów** i dziewięć tablic wyglądu, generowanych przez
  `tools/make_placeholders.gd`.

#### Krok 1: poddrzewo i wyłącznik

- [ ] Węzeł `Presentation` w `ship.tscn` (sekcja 1, punkt 5) i jeden
  wyłącznik na całą warstwę. `--headless` jej nie uruchamia, smoke test
  przechodzi z wyłączoną.
- [ ] `scripts/fx/ship_skin.gd`: jeden `_process`, który obchodzi statek i
  tyka wszystkie `StripSprite`. Czyta wielkości ciągłe, nie dostaje ich
  podanych — `Ship` nie dowiaduje się, że skórka istnieje.
- [ ] Porządek rysowania jako jawne `z_index` na rodzinę: dysze pod
  kadłubem, pióropusze pod dyszami, działa i podwozie nad. Domyślny
  porządek drzewa to porządek dodawania węzłów, czyli przypadek.

#### Krok 2: dysze i pióropusze

Najtańsza prawdziwa wygrana i zerowe ryzyko regresji: **dysz dziś po prostu
nie widać** (`EngineMount` ma sam `GPUParticles2D`), więc ten krok nic nie
zastępuje, tylko dodaje.

- [ ] Dysza na każdym `EngineMount`, wybierana z `engine_nozzle.tres` po
  `EngineData.type`, obracana dodatkowo o `gimbal`.
- [ ] Pióropusz wybierany z `engine_plume.tres` po `max_thrust`, napędzany
  `EngineInstance.effective_output()` przez `StripSprite.drive()`.
  To jest cała implementacja reguły „tempo klatek jest daną".
- [ ] Tekstura cząstek (`particles/dot.png`) do wydechu. Bez niej płomień
  jest siatką kwadratów, bo `GPUParticles2D` bez tekstury rysuje quady.
- [ ] Zmierzyć koszt `tools/frame_bench.gd`. Osiem mocowań razy dwa sprite'y
  to ~16 węzłów na statek; jeśli to widać w klatce, trzeba wiedzieć **teraz**,
  a nie po kadłubach.

#### Krok 3: kadłub

Ten krok ma zależność i warto ją nazwać: **statek nie wie, jakim jest
kadłubem.** `Ship.hull_outline` to goła tablica punktów, a sprite wybiera
się nazwą.

- [ ] `Ship.hull: HullData` obok `hull_outline`, ustawiane przez
  `ShipFitout` i `CreativeTool`. To jest jednocześnie checkbox „Kadłuby jako
  zasoby" z M3.5 — trzy katalogi schodzą do jednego i test, który dziś
  pilnuje zgodności, zmienia się w test, że pozostałe dwa już nie istnieją.
- [ ] `StripSprite` z `hull.tres` zamiast `Hull` jako `Polygon2D`.
- [ ] **Kadłub przebudowany w narzędziu kreatywnym nie ma `id`, więc nie ma
  sprite'a** — i wtedy `Polygon2D` zostaje widoczny. To nie jest awaria,
  to jest poprawna odpowiedź: piaskownica ma pokazywać kształt, który
  naprawdę dostała.
- [ ] Schemat w edytorze dalej rysuje wielokąt (ASSETLIST, sekcja 2): jego
  zadaniem jest pokazać prawdę o kształcie zderzeniowym.

#### Krok 4: cieniowanie przenosi się do skórki

- [ ] `Ship._catch_the_light()` wychodzi z `ship.gd`. Dziś symulacja sięga
  po `get_node("Hull")` i ustawia `self_modulate` — czyli rysuje. Po
  przeniesieniu skórka czyta `GravityWell.daylight_at()` sama.
- [ ] Pióropusze i błyski **nie** są przygaszane: są addytywne i robią
  własne światło. `SpriteStrip.additive` jest tym znacznikiem, więc skórka
  nie potrzebuje listy wyjątków.

#### Krok 5: działa i podwozie

- [ ] Działo na każdym `Hardpoint`, z `weapon_muzzle.tres` po
  `WeaponData.type`, obracane o `facing`.
- [ ] Noga: `gear/strut` rozciągany wzdłuż Y przez `LandingGear.extension`,
  `gear/pad` na stopie. `_draw()` zostaje jako zapas, dopóki sprite nie
  wygląda lepiej od kreski.

#### Krok 6: drobne obiekty świata

- [ ] Skrzynka: sprite plus **proceduralna** obwódka rzadkości. Wzorcowa
  hybryda — sylwet jest stały, kolor jest daną z `rarity_color()`.
- [ ] Pocisk i rakieta z `round.tres`.
- [ ] Odłamki (`particles/debris_strip3.png`) przy trafieniu, razem z V3.

#### Krok 7: interfejs

- [ ] Ikony gniazd w edytorze z `module_icon.tres` zamiast
  `_draw_slot_glyph()`. Biel plus `modulate`, więc pięć poziomów rzadkości
  to jedna ramka, nie pięć plików.
- [ ] `tools/gallery.tscn` (wspólne z V0): wszystkie paski obok siebie, z
  zaznaczonym pivotem. **Pivot przesunięty o dwa piksele czyta się jak błąd
  fizyki**, a nie jak błąd grafiki, i nie da się go zobaczyć inaczej niż
  patrząc.

#### Czego ten tor nie rusza

Stacja, wiązka, smuga kondensacyjna i wszystko proceduralne z sekcji 2
ASSETLIST. Stacja to hybryda z klocków i najwięcej roboty na jednostkę
efektu; reszta ma kształt, który jest daną.

#### Co na pewno ugryzie

- **Pivoty.** Dysza przesunięta o dwa texele nie wygląda na przesuniętą,
  wygląda na przykręconą krzywo.
- **Kolejność rysowania.** Bez jawnego `z_index` jest to kolejność dodawania
  węzłów, czyli kolejność przypadkowa.
- **Przebudowany kadłub.** Narzędzie kreatywne zmienia obrys w locie —
  skórka musi się przebudować i umieć nie mieć sprite'a.
- **Koszt.** Dwadzieścia węzłów na statek to nie jest zero. Mierzyć, nie
  zgadywać — raz już zgadliśmy, że pocisk kosztuje 0.9 ms, a kosztuje 7 us.

---

### V1: Światło

Największy skok wrażenia na najmniej kodu, i dotyka wyłącznie shaderów.

- [ ] Kierunek gwiazdy na system, losowany z seeda jak wszystko inne.
- [ ] Cieniowanie terenu: jasna strona, ciemna strona, terminator jako gradient, nie jako krawędź.
- [ ] Chmury oświetlone z tego samego kierunku (dziś mają sztywne „góra jasna, dół ciemny").
- [ ] Atmosfera jaśniejsza od strony gwiazdy, rozświetlony rąbek na terminatorze.
- [ ] Kadłub i teren dostają wspólny kierunek światła, żeby statek nie wyglądał na wycięty z innego obrazka.

Gotowe, gdy: na zrzucie z galerii widać, z której strony świeci gwiazda, bez patrzenia na nią.

### V2: Statek

- [ ] Kadłub przestaje być trójkątem: sylwetka z segmentów, widoczne montaże silników.
- [ ] Wydech zależny od typu silnika (MAIN ciągły, TORQUE impulsowy — modulacja delta-sigma jest już w kodzie i powinna być widoczna).
- [ ] Poświata od `hull_heat`, od ledwie widocznej do białej.
- [ ] Ślady uszkodzeń od `hull_integrity`, uszkodzony silnik widocznie kuleje.
- [x] Podwozie jako rysowana geometria, nie tylko punkty kontaktu. Zastrzał wychodzi z obrysu kadłuba (liczony co rysowanie, więc trzyma się kadłuba przerobionego w narzędziu kreatywnym), stopka leży płasko w miejscu, w którym solver naprawdę dotknie. W trakcie wysuwania przygaszona — podwozie w połowie drogi nie może czytać się jako podwozie, na którym da się wylądować.

### V3: Zderzenia, kopanie, kurz

- [ ] Iskry i odłamki przy trafieniu, skalowane prędkością z `hull_impact`.
- [ ] Krater ma obrzeże: jaśniejszy pierścień świeżo odsłoniętej skały, ciemniejszy w środku.
- [ ] Pył wyrzucany przy kopaniu, opadający zgodnie z lokalnym „w dół".
- [ ] Kurz spod dysz przy podejściu, gęstość od gęstości powietrza i wysokości.
- [ ] Wstrząs kamery: jedno wspólne źródło, skalowane energią, nie sztywną liczbą na zdarzenie.

### V4: Prędkość, atmosfera, kamera

- [x] Ręczne obracanie kamery strzałkami i `H` — „planeta na dole" na jedno naciśnięcie. Ta sama odpowiedź co niżej, tylko pytana jednorazowo zamiast liczona co klatkę.
- [x] Starfield obraca się z widokiem (`view_rotation` w shaderze). Obrót liczony wokół środka wyznaczonego z `SCREEN_PIXEL_SIZE`, nie podanego ze skryptu — `FRAGCOORD` jest w pikselach bufora, a `get_visible_rect()` przy rozciąganiu `canvas_items` zwraca bazowe 640x360, więc podany środek był o połowę za mały.
- [x] Obracająca się kamera przy podejściu, automatycznie: promień w górę ekranu, ciągła waga z wysokości, wygładzanie wbudowane w `Camera2D`. Bramka to **podwozie i wysokość poniżej 300 px nad terenem** — dwa warunki mówiące co innego: podwozie to deklaracja zamiaru lądowania, wysokość to postęp tego zamiaru. Strzałka w ręce pilota wygrywa z blokadą na tę klatkę.
- [ ] Smugi i rozmycie przy dużej prędkości w powietrzu.
- [ ] Widoczne wejście w atmosferę: jonizacja przed dziobem narastająca z `hull_heat`.
- [ ] Smugi kondensacyjne przerobione na zależne od gęstości powietrza, nie od samej prędkości.

### V5: Niebo

- [ ] Gwiazdy w kilku warstwach paralaksy zamiast jednej.
- [ ] Mgławice i pasmo galaktyki jako tło systemu, z seeda.
- [ ] Inne ciała widoczne na niebie: księżyc, druga planeta, pierścienie jako sylwetka.
- [ ] Gwiazdy przygasają w dzień po stronie oświetlonej.

### V6: Interfejs

Styl jest rozpisany osobno: **UI_STYLE.md**. Teza tamtego pliku, w jednym
zdaniu: retro siedzi w kształcie i typografii (kreska 1 px, wektorowe
przyrządy, monospace), nowoczesność w ruchu i świetle (wygładzanie, poświata
tylko na akcencie, reakcja w 80 ms) — i żadnego kostiumu CRT. Tutaj zostaje
tylko kolejność prac.

- [ ] Paleta jako zasób `resources/ui/palette.tres` i pikselowy font monospace w theme. Dziś HUD ma font proporcjonalny, więc cyfry drgają — to jest najtańsza poprawka o największym skutku. Wspólne z V0.
- [ ] `scripts/ui/ui_draw.gd`: wiersz odczytu i narożny nawias, plus `tools/gallery.tscn` do ich oglądania.
- [ ] Oprawa kart modułów: ramki, ikony, **kolor wiersza wg kierunku zmiany** zamiast słów „lepiej / gorzej”. Treść karty jest zrobiona i mieszka na `ModuleData.card_lines()` (M2.3); zostało samo malowanie, więc siedzi tu, a nie w M2 — robione przed paletą i `ui_draw.gd` byłoby robione dwa razy.
- [ ] Układ w czterech narożnikach, środek 400x220 pusty (UI_STYLE.md sekcja 5). Przeniesienie tego, co już jest, na ramę.
- [ ] `scripts/ui/ui_value.gd`: wygładzanie geometrii (~120 ms) osobno od kwantowania cyfr (10 Hz). Bez tego HUD dalej wygląda na debugowy, choćby miał dobry font.
- [ ] Stany ostrzegawcze czytelne bez czytania: kolor, puls prostokątny 2 Hz na tle a nie na tekście, stała pozycja.
- [ ] Pasek energii: komórki z podziałką co koszt strzału, cisza timeoutu odróżnialna od doładowywania bez patrzenia na liczby (mechanika w IDEAS.md sekcja 14). Łuk segmentowy na ciepło kadłuba.
- [x] **Przyrząd orbity zamiast ośmiu wierszy tekstu** (`scripts/flight_hud.gd`). Planeta jako kropka w ognisku, pierścień gruntu w skali, stożek toru z kropkami na perycentrum i apocentrum, kropka statku na krzywej. **W orbicie linia jest grubsza i zielona** — „czy jestem na orbicie” to pytanie tak/nie, a sam kolor to odcień, który trzeba pamiętać. Obok liczby, które naprawdę są liczbami: PERI, APO, ALT, V/S, SLOPE, GEAR. Odmowa lądowania jako **wykrzyknik i powód**, bez słowa „WAVE OFF” — etykieta na newsie, który kolor już niosł.
- [x] Poza studnią grawitacyjną przyrząd zmienia się na **strzałkę kierunku lotu i prędkość**. Wewnątrz pytanie brzmi „co robi ta orbita”, na zewnątrz „gdzie lecę i jak szybko”, a diagram orbity wokół planety, przy której nie jesteś, nie odpowiada na żadne z nich.
- [x] Kadłub jako **pasek na górze ekranu**, nie wiersz tekstu: nikt nie lata na 63 procentach, lata się na „jeszcze większość” albo „prawie nic”, a długość mówi to bez czytania.
- [ ] Wskaźnik horyzontu i wektora prędkości przy lądowaniu, rysowany nad światem a nie w panelu.
- [ ] Rozdzielenie: HUD gry kontra overlay debugowy pod F7. Rozdzielenie jest stylistyczne (UI_STYLE.md sekcja 8), więc samo się pilnuje.
- [ ] `scripts/ui/hud_mode.gd`: tryby DEEP / ORBIT / LANDING / COMBAT wyprowadzone z liczb, które symulacja już liczy, z histerezą i minimalnym czasem trwania (UI_STYLE.md sekcja 10). `Ship` nie dowiaduje się, że tryby istnieją.
- [ ] Awans i wycofanie przyrządów na przejściu trybu: 120 ms w górę, 400 ms w dół, przygaszanie zamiast usuwania.
- [ ] Przyrząd jako widget w gniazdach panelu, z bramką zdolności i bramką trybu (UI_STYLE.md sekcja 12). Układ liczony przy montażu i zmianie trybu, nie co klatkę.
- [ ] Trzy odróżnialne obrazy braku: brak danych, brak modułu, moduł uszkodzony. Bez tego brakujący przyrząd czyta się jako zepsuty odczyt.
- [ ] Zdolności statku (`ALTIMETRY`, `ORBIT_SOLUTION`, `SCAN`, `GROUND_SLOPE`) jako zbiór wyprowadzony z zamontowanych modułów — zadanie szwu, bo mieszka w linii głównej razem z modułami (M5).
- [ ] Raport konfiguracji mówi o brakujących przyrządach (`no altimetry`) tam, gdzie dziś mówi o pustej grupie komend.
- [ ] Poświata jako ostatnia: osobna warstwa, próg tylko na akcentach, jeden wyłącznik.

Ekrany pełnoekranowe (edytor, mapa systemu, mapa galaktyki) mają własne reguły
w UI_STYLE.md sekcja 11. Mapy należą do M3 i M4 i nie zaczynamy ich wcześniej —
tutaj jest tylko zapisany ich styl, żeby powstały od razu w tym języku.

---

## 4. Tor dźwiękowy

Zero dźwięku dzisiaj, więc pierwszy krok jest duży, a każdy następny mały.

### S0: Fundament

- [ ] Magistrale: `Master`, `Sfx`, `Ambient`, `Ui`, z filtrem dolnoprzepustowym na `Sfx` sterowanym gęstością powietrza.
- [ ] Spawner dźwięków jednorazowych: `(strumień, pozycja, głośność, wysokość)`, pula `AudioStreamPlayer2D`.
- [ ] Reguła próżni: w `air_density == 0` słychać wyłącznie dźwięki przewodzone konstrukcją (silniki, uderzenia w kadłub), reszta wyciszona.
- [ ] `tools/soundcheck.tscn`: odpala po kolei każde zdarzenie i wypisuje, co zagrało.

Gotowe, gdy: przelot przez atmosferę słychać jako wejście świata, a nie jako zmianę głośności.

### S1: Silniki

- [ ] Pętla na typ silnika, wysokość i głośność z `effective_output()`.
- [ ] Silniki TORQUE brzmią impulsowo, bo takie są — modulacja jest w kodzie.
- [ ] Zapłon i zgaszenie jako osobne zdarzenia (zadanie szwu).
- [ ] Uszkodzony silnik brzmi gorzej: oscylacja, przerwy.

### S2: Kadłub, lądowanie, śmierć

- [ ] Uderzenie skalowane `impact_speed` — od stuknięcia do zgrzytu.
- [ ] Wysuwanie podwozia, przyziemienie na nogach, skrzypienie przy postoju.
- [ ] Odmowa lądowania (`landing_rejected`) jako krótki sygnał z powodem.
- [ ] Eksplozja i respawn.

### S3: Broń i teren

- [ ] Wystrzał (zadanie szwu), lot pocisku, trafienie w skałę kontra w próżnię.
- [ ] Osypywanie się terenu po wyrwaniu dziury.

### S4: Atmosfera

- [ ] Wiatr proporcjonalny do gęstości × prędkości.
- [ ] Ryk wejścia w atmosferę z `hull_heat`, z osobnym progiem ostrzegawczym.
- [ ] Cisza tuż po wyjściu w próżnię jako świadomy efekt, nie jako brak dźwięku.

### S5: Ambient z seeda

- [ ] Ton tła planety losowany z tego samego seeda co kolor i pogoda — świat brzmi tak, jak wygląda.
- [ ] Osobne tło dla próżni, atmosfery i powierzchni.

### S6: Interfejs i ostrzeżenia

- [ ] Zmiana stanu orbity na DECAYING, niska integralność kadłuba, przegrzanie.
- [ ] Puste magazyny energii: odmowa strzału jako krótki, jednoznaczny klik — bez niego brak energii brzmi jak zacięty klawisz.
- [ ] Zasada: ostrzeżenie dźwiękowe tylko dla rzeczy, na które gracz ma jeszcze czas zareagować.

**Skąd dźwięki.** Proponuję małą bazę próbek plus mocna parametryzacja
(wysokość, filtr, warstwy), a nie generowanie proceduralne — `AudioStreamGenerator`
to osobna królicza nora i nie ma jej za co zapłacić na tym etapie. Jedynym
kandydatem na proceduralność jest ambient z seeda (S5), gdzie chodzi o ton, a
nie o brzmienie konkretnego przedmiotu.

---

## 5. Jak to sprawdzać

Testy tej warstwy mogą pilnować tylko własności, nigdy tego, co się naprawdę
liczy. To już wiemy drogo: cztery rundy poprawek atmosfery minęły, zanim
ktokolwiek zmierzył artefakt, i dopiero `cloud_preview` zrobił z oglądania
rzecz tanią. Ta sama dyscyplina obowiązuje tutaj.

- **`tools/gallery.tscn`** — po dwa PNG na podsystem, jedno polecenie. Każde zadanie z toru V kończy się zrzutem w galerii.
- **`tools/soundcheck.tscn`** — każde zadanie z toru S kończy się linią w soundchecku.
- **`tools/check.ps1`** — już teraz wyłapuje błędy kompilacji shaderów i błędy silnika; warstwa prezentacji nie może go zepsuć.
- **Strażnik niezależności** — smoke test przechodzi przy wyłączonej prezentacji. Jeśli przestanie, złamano regułę 3.

Czego żaden z nich nie powie: czy to jest ładne i czy brzmi dobrze. Na to jest
tylko odpalenie gry, i to jest jedyne kryterium zamknięcia każdego kroku w tym
pliku.

---

## 6. Zadania szwu (robione na linii głównej)

Małe, mechaniczne, każde to jeden sygnał albo jedno pole publiczne. Wypisane
tutaj, żeby tor wizualny nigdy nie musiał sam wchodzić w `ship.gd`.

- [ ] `Ship`: sygnał zapłonu i zgaszenia silnika (`engine_ignited` / `engine_cut` z referencją do silnika).
- [ ] `Hardpoint`: sygnał wystrzału z pozycją i kierunkiem.
- [ ] `Planet`: sygnał wyrwania dziury (`carved(point, radius)`), dziś `carve()` tylko zwraca `bool`.
- [ ] `Ship`: sygnał przekroczenia granicy atmosfery w obie strony.
- [ ] `Ship`: sygnał zmiany stanu orbity (dziś stan jest odpytywany, co wystarcza HUD-owi, ale nie wystarcza do zagrania dźwięku raz).
- [ ] `project.godot`: magistrale audio.

---

## 7. Kolejność

Zależności od linii głównej są prawie żadne — to jest cel. Jedyne twarde:
zadania szwu (sekcja 6) i to, że V2 ładniej wygląda po M2, kiedy statki mają
różne konfiguracje silników.

Proponowany pierwszy kęs, w kolejności zwrotu z zainwestowanego czasu:

1. **V0** — bez tego reszta wsiąknie w pliki rozgrywki.
2. **V1 Światło** — największa zmiana wrażenia na najmniej kodu, same shadery.
3. **S0 + S1** — od ciszy do silników słyszalnych przez kadłub; próżnia zaczyna coś znaczyć.
4. **V3 Zderzenia** — uderzenia są w tej grze wszystkim, a dziś nie mają wagi.

V4 (kamera) nie zależy od niczego i można go wciągnąć wcześniej, jeśli
podejście do lądowania okaże się nieczytelne.
