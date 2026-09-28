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
- [ ] Podwozie jako rysowana geometria, nie tylko punkty kontaktu.

### V3: Zderzenia, kopanie, kurz

- [ ] Iskry i odłamki przy trafieniu, skalowane prędkością z `hull_impact`.
- [ ] Krater ma obrzeże: jaśniejszy pierścień świeżo odsłoniętej skały, ciemniejszy w środku.
- [ ] Pył wyrzucany przy kopaniu, opadający zgodnie z lokalnym „w dół".
- [ ] Kurz spod dysz przy podejściu, gęstość od gęstości powietrza i wysokości.
- [ ] Wstrząs kamery: jedno wspólne źródło, skalowane energią, nie sztywną liczbą na zdarzenie.

### V4: Prędkość, atmosfera, kamera

- [x] Ręczne obracanie kamery strzałkami i `H` — „planeta na dole" na jedno naciśnięcie. Ta sama odpowiedź co niżej, tylko pytana jednorazowo zamiast liczona co klatkę.
- [x] Starfield obraca się z widokiem (`view_rotation` w shaderze). Obrót liczony wokół środka wyznaczonego z `SCREEN_PIXEL_SIZE`, nie podanego ze skryptu — `FRAGCOORD` jest w pikselach bufora, a `get_visible_rect()` przy rozciąganiu `canvas_items` zwraca bazowe 640x360, więc podany środek był o połowę za mały.
- [ ] Obracająca się kamera przy podejściu, automatycznie: promień w górę ekranu, ciągła waga z wysokości, wygładzanie wbudowane w `Camera2D`. Ręczna wersja i naprawa starfieldu są już zrobione, zostaje sama waga z wysokości.
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
- [ ] Układ w czterech narożnikach, środek 400x220 pusty (UI_STYLE.md sekcja 5). Przeniesienie tego, co już jest, na ramę.
- [ ] `scripts/ui/ui_value.gd`: wygładzanie geometrii (~120 ms) osobno od kwantowania cyfr (10 Hz). Bez tego HUD dalej wygląda na debugowy, choćby miał dobry font.
- [ ] Stany ostrzegawcze czytelne bez czytania: kolor, puls prostokątny 2 Hz na tle a nie na tekście, stała pozycja.
- [ ] Pasek energii: komórki z podziałką co koszt strzału, cisza timeoutu odróżnialna od doładowywania bez patrzenia na liczby (mechanika w IDEAS.md sekcja 14). Łuk segmentowy na ciepło kadłuba.
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
