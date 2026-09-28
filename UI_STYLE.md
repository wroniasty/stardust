# UI_STYLE.md

Styl interfejsu. Rozwinięcie punktu **V6** z VISUALS.md — ten plik odpowiada na
pytanie „jak to ma wyglądać", VISUALS.md zostaje z kolejnością prac.

Kontekst rozgrywki: IDEAS.md. Kontrakt z linią główną (symulacja emituje,
prezentacja słucha) obowiązuje tu bez zmian.

---

## 1. Teza

**Retro jest w kształcie i typografii. Nowoczesność jest w ruchu i świetle.**

To cała decyzja. Wszystko poniżej z niej wynika, a każdy pomysł, który jej
przeczy, odpada bez dyskusji.

Retro bierzemy z **wektorowych przyrządów**: Elite (1984), Asteroids, terminale
z „Obcego", paski taśmowe z prawdziwych kokpitów. Znaczy to: kreska 1 px, brak
zaokrągleń, brak gradientów jako dekoracji, drabinki podziałek, narożne nawiasy
zamiast ramek, monospace, wersaliki w etykietach.

Nowoczesność bierzemy z rzeczy, których maszyna z 1984 nie umiała: **60 fps
wygładzania**, addytywna poświata tylko na akcencie, przezroczyste warstwy jako
głębia, reakcja na zmianę stanu w 80 ms, prawdziwa hierarchia typograficzna.

Czego **nie robimy**, świadomie i na piśmie: żadnej nakładki skanlinów, żadnej
dystorsji beczkowej, żadnej aberracji chromatycznej na całym ekranie, żadnej
persystencji fosforu nad światem, żadnego „zepsutego CRT" jako efektu. To jest
kostium, nie styl — czyta się jako cudzysłów („patrzcie, retro!") zamiast jako
sprzęt. Nasz interfejs ma być *sprzętem, który działa*, a nie pamiątką.

Jedno zdanie do zapamiętania: **to nie jest menu, to jest przyrząd.**

---

## 2. Prawo siatki

Ekran ma 640x360 i skaluje się tylko całkowicie. Interfejs to szanuje:

- Wszystkie współrzędne rysowania są całkowite. `snap()` na wejściu każdego
  pomocnika rysującego, nie na wyjściu — pozycja przyrządu nigdy nie jest
  liczona w podpikselach.
- Kreska ma **1 px**, zawsze. Grubsza linia to nie emfaza, to błąd. Emfaza
  idzie kolorem i jasnością.
- `antialiased = false` na całej strukturze. Antyaliasing wolno wyłącznie
  warstwie poświaty (sekcja 7).
- Font bez antyaliasingu, bez pozycjonowania subpikselowego, w rozmiarze
  będącym wielokrotnością rozmiaru projektowego.
- Żaden element interfejsu nie ma skali innej niż 1.0. Nie ma „małego okna"
  zrobionego przez `scale = 0.5`.

Konsekwencja, którą trzeba przyjąć: **mamy mało miejsca**. 640x360 to około 45
znaków szerokości na panel przyrządowy. Każda liczba na ekranie musi zarabiać
na swoje piksele.

---

## 3. Paleta

Jeden zasób, `resources/ui/palette.tres`, zamiast stałych rozsianych po
`landing_hud.gd`, `ship_editor.gd`, `loadout_screen.gd` i `scanner_hud.gd`
(dziś są w czterech miejscach i już się rozjechały). To jednocześnie zamyka
pozycję „Paleta jako zasób" z V0.

| nazwa | hex | rola |
|---|---|---|
| `void` | `#05070B` | przyciemnienie pod panelem, scrim pod ekranem modalnym |
| `panel` | `#0A0E15` | wypełnienie panelu (alfa 0.82 nad światem) |
| `edge` | `#26303D` | krawędź panelu, linie rozdzielające |
| `grid` | `#3A4757` | podziałki, drobna struktura, tło paska |
| `inert` | `#4A5665` | brak danych, pozycja nieaktywna |
| `label` | `#78899C` | etykieta, jednostka, tekst drugorzędny |
| `value` | `#D8E4F0` | liczba, tekst pierwszorzędny |
| `accent` | `#5FE3C0` | **systemy statku**: ciąg, energia, podwozie, kadłub |
| `nav` | `#7BA7FF` | **świat**: planeta, orbita, skaner, horyzont |
| `ok` | `#62E08C` | stan dobry, uzbrojone, zmieszczone |
| `caution` | `#FFC24A` | uwaga, wybór kursora, jesteś blisko granicy |
| `alarm` | `#FF5B4D` | przekroczone, uszkodzone, odmowa |

Dwie reguły trzymające to w kupie:

**1. Dwa kanały akcentu, nie jeden.** `accent` (fosforowy cyjan) to statek,
`nav` (błękit) to świat. Ten podział nie jest wymyślony — debug overlay już go
ma (`Label` zielonkawy, `Planet` błękitny) i okazał się czytelny w praktyce.
Teraz staje się regułą: pilot rozpoznaje, o czym mówi liczba, zanim przeczyta
jej etykietę.

**2. Ostrzeżenia płacą za swoją uwagę nieobecnością.** `caution` i `alarm` nie
występują w stanie normalnym **nigdzie** — żaden element dekoracyjny, żadna
ramka, żaden akcent „bo ładnie" nie jest pomarańczowy ani czerwony. Jedyny
powód, dla którego pomarańcz na ekranie działa, jest ten, że przez większość
lotu go nie ma.

Kolory rzadkości lootu zostają jak są — należą do przedmiotu, nie do
interfejsu, i mają własny słownik.

---

## 4. Typografia

Dzisiaj HUD używa domyślnego fontu Godota w rozmiarze 10. To jest ta jedna
rzecz, która najbardziej psuje wrażenie: font jest proporcjonalny, więc **cyfry
tańczą** — `ALT 11111` i `ALT 88888` mają różną szerokość. Liczba, która drga,
jest nieczytelna bez względu na resztę.

- **Monospace obowiązkowo na wszystkich liczbach.** Cyfry tabelaryczne, stała
  szerokość kolumny, wartość wyrównana do prawej.
- **Font pikselowy, nie zeskalowany zwykły.** Propozycja: *Departure Mono*
  (2024, CC0, pikselowy monospace zaprojektowany dokładnie do tego zastosowania)
  jako główny, *Pixel Operator Mono* (CC0) jako zapas. Oba są bitmapowo czyste
  w swoim rozmiarze bazowym.
- **Trzy rozmiary, ani jednego więcej:**
  - `7 px` — overlay debugowy i tylko on (sekcja 8),
  - `8 px` — etykiety i wartości przyrządów, chleb powszedni,
  - `16 px` — nagłówek ekranu modalnego i jedna duża liczba, gdy naprawdę jest
    tylko jedna ważna (np. wysokość przy końcowym podejściu).
- **Wersaliki w etykietach, mieszane w zdaniach.** `ALT`, `V/S`, `GEAR` to
  etykiety. `Wave off: slope too steep` to zdanie i tak ma zostać — wersaliki w
  całym komunikacie czytają się wolniej, a to jest tekst, który pilot ma
  przeczytać w sekundę.
- **Stała szerokość etykiety w kolumnie.** 5 znaków, dopełnione. Nic się nie
  przelewa, nic nie skacze, gdy `PERI` zmieni się w `SLOPE`.

---

## 5. Układ: rama, nie okno

Środek ekranu należy do pilota. Prostokąt **400x220 px w centrum jest
nietykalny** — nic tam nie wchodzi poza wskaźnikami nałożonymi na świat
(horyzont, wektor prędkości), które są przezroczyste i mają 1 px.

Cztery narożniki mają stałe zadania, żeby oko wiedziało, gdzie patrzeć, bez
czytania:

```
+-- STATEK -----------------+  +------------- ŚWIAT ---------+
|  co mnie zabije:          |  |  gdzie jestem:              |
|  kadłub, ciepło, energia  |  |  planeta, orbita, PERI/APO  |
+---------------------------+  +-----------------------------+
              (pole pilota 400x220, puste)
+-- KONTEKST ---------------+  +---------- PRZYRZĄDY --------+
|  chwilowe: podniesiony    |  |  co robię teraz:            |
|  moduł, tryb, komunikat   |  |  ALT, V/S, SLOPE, GEAR      |
+---------------------------+  +-----------------------------+
```

Pierścień krawędzi ekranu zostaje skanerowi (jest, działa).

Metryka, jedna dla wszystkiego: **4 px od krawędzi ekranu, 3 px wyściółki
wewnątrz panelu, 1 px odstępu między wierszami, panel nie szerszy niż 140 px i
nie wyższy niż 120 px.** Panel nie ma ramki z czterech stron — ma przyciemnione
tło (`panel` z alfą) i **narożne nawiasy** po 4 px w dwóch narożnikach od
strony krawędzi ekranu. Pełna ramka zjada cztery linie budżetu wizualnego, żeby
powiedzieć to, co nawias mówi dwiema.

Prawy dolny panel (przyrządy lotu) dostaje pełną krawędź `edge` jako jedyny, bo
przy lądowaniu leży na najbardziej zaśmieconym tle, jakie gra ma: terenie.

---

## 6. Słownik widgetów

Sześć prymitywów. Wszystko w grze jest zbudowane z nich i tylko z nich — nowy
widget wymaga zmiany w tym pliku, nie w ekranie.

**1. Wiersz odczytu.** `ETYKI` (dim, do lewej, 5 znaków) + wartość (mono, do
prawej) + opcjonalna jednostka (dim). Kolor wartości nosi stan. Kolumny stałe.
To 80% interfejsu i ma być nudne.

**2. Drabinka (taśma).** Pionowa dla wysokości, pozioma dla prędkości. Kreski
1 px, co piąta dłuższa i opisana, wartość pod stałym kursorem w środku. Retro:
paski taśmowe z kokpitu. Nowoczesność: taśma przesuwa się płynnie (przesunięcie
w shaderze, nie przeskok etykiet), a liczba przy kursorze kwantuje się osobno.

**3. Pasek z podziałką znaczącą.** Energia: **komórki, nie gładkie
wypełnienie**, a podziałka jest co koszt jednego strzału. Pilot widzi „mam trzy
strzały", nie „mam 62%". Gdy trwa timeout, komórki są obrysowane w `grid` i
puste; gdy się doładowują, wypełniają się w `accent`. Różnica jest widoczna bez
liczby — to wymaganie z V6 i podziałka jest na nie odpowiedzią.

**4. Łuk segmentowy.** Ciepło kadłuba: 24 segmenty po 1 px na łuku. Dyskretny z
premedytacją — łuk gładki wygląda nowocześniej i mówi mniej.

**5. Nawias.** Cztery narożniki, bez pełnego prostokąta. Cel, wybrany slot,
skrzynia na ekranie. Czyta się natychmiast i kosztuje osiem kresek.

**6. Wskaźnik nałożony na świat.** Linia horyzontu i wektor prędkości przy
lądowaniu: 1 px, `nav`, rysowane w przestrzeni świata, nie w warstwie panelu.
Wskaźnik ma przecinać obraz, bo mówi o obrazie.

---

## 7. Ruch i światło

Tu jest cała nowoczesność i tu najłatwiej przesadzić.

**Wygładzanie osobne dla igły i dla cyfry.** Wielkość ciągła jest wygładzana
wykładniczo (połowa zaniku około 120 ms), żeby pasek i drabinka nie drgały. Ale
**cyfra kwantuje się i odświeża najwyżej 10 razy na sekundę** — wysokość do 1,
V/S do 0.1. Cyfra zmieniająca się 60 razy na sekundę jest nieczytelna nawet gdy
jest prawdziwa. To dwa różne wymagania na tej samej liczbie i implementacja
musi je rozdzielić (`UiValue`: `smooth()` dla geometrii, `stepped()` dla tekstu).

**Zmiana stanu: 80 ms przejścia koloru.** Nie natychmiast (wygląda jak błąd),
nie 300 ms (wygląda jak animacja z telefonu).

**Alarm pulsuje falą prostokątną 2 Hz, wypełnienie 50%** — prostokąt, bo sinus
jest zbyt miękki na ostrzeżenie. I reguła twarda: **pulsuje tło albo nawias,
nigdy tekst.** Mrugająca liczba to liczba, której przez połowę czasu nie ma,
akurat wtedy, gdy jest najpotrzebniejsza.

**Panel wjeżdża wycieraniem od swojej krawędzi**, 4 px na klatkę, około 120 ms
całości. Bez przygaszania całych paneli, bez skalowania.

**Poświata tylko na akcencie, tylko 1 px.** Osobna `CanvasLayer` z glow o progu
ustawionym tak, że bleeduje wyłącznie `accent`, `nav` i kolory ostrzegawcze —
nigdy tekst `value`, nigdy `edge`. Efekt ma być taki, że jasne elementy
wyglądają na *świecące*, a nie że ekran wygląda na rozmyty. Jeśli na zrzucie
widać poświatę na literach, próg jest za nisko.

**Nic nie rusza się, jeśli nie jest danymi.** Zero animacji jałowej, zero
przewijających się ozdób, zero „żyjącego" interfejsu. Ruch na ekranie znaczy
„coś się zmieniło" i ta umowa nie może być nadużywana dla efektu.

---

## 8. Overlay debugowy jest inny celowo

F7 zostaje brzydki i to jest decyzja, nie zaniedbanie. Rozmiar 7, jeden płaski
kolor na kolumnę, bez paneli, bez wygładzania, bez kwantowania, bez poświaty —
surowe liczby z maksymalną częstotliwością i maksymalną gęstością.

Powód: przyrząd i oscyloskop mają sprzeczne wymagania. HUD ma być czytelny w
ćwierć sekundy przy 200 px/s w stronę skały; overlay ma pokazać, że siła
drgnęła w trzeciej cyfrze. Wygładzanie, które ratuje pierwsze, niszczy drugie.

To zamyka pozycję „Rozdzielenie: HUD gry kontra overlay debugowy" z V6:
rozdzielenie jest stylistyczne, nie tylko organizacyjne, i dlatego samo się
pilnuje. Jeśli ktoś doda do overlaya panel i wygładzanie, będzie to widać.

---

## 9. Kształt implementacji

Nic z tego nie wchodzi w pliki linii głównej.

```
resources/ui/palette.tres     UiPalette: nazwane kolory, jedno źródło
resources/ui/ui_theme.tres    Theme: fonty, rozmiary, odstępy
resources/ui/fonts/           Departure Mono + zapas, bez AA, bez subpiksela
scripts/ui/ui_palette.gd      class_name UiPalette extends Resource
scripts/ui/ui_draw.gd         statyczne: row() ladder() cells() arc() bracket() snap()
scripts/ui/ui_value.gd        smooth() dla geometrii, stepped() dla tekstu
scripts/ui/ui_glow.gd         warstwa poświaty, jeden wyłącznik
```

Migracja istniejących ekranów to wymiana lokalnych stałych na paletę i wymiana
ręcznego `draw_*` na pomocniki: `landing_hud.gd`, `scanner_hud.gd`,
`loadout_screen.gd`, `ship_editor.gd`, `configuration_report.gd`. Żaden z nich
nie zmienia tego, co liczy — tylko to, czym rysuje.

Sprawdzanie: każdy widget ląduje w `tools/gallery.tscn` jako dwa PNG (stan
normalny i stan alarmowy). Galeria jest jedynym miejscem, gdzie styl daje się
oglądać bez latania, i dlatego powstaje przed drugim widgetem, nie po ostatnim.

---

## 10. Tryby: jedna rama, cztery rozkłady

Interfejs zmienia się ze stanem lotu. Ale zmienia się w jeden konkretny sposób
i tylko w ten:

**Rama się nie przestawia. Przyrządy awansują i wycofują się.**

Cztery narożniki z sekcji 5 mają swoje zadania na zawsze. Zmienia się to, jakie
przyrządy je zajmują i jak dużo miejsca dostają — nigdy to, gdzie szukać danej
klasy informacji. Powód jest jeden i wystarczający: **pamięć mięśniowa**. Jeśli
`ALT` wędruje między stanami, pilot uczy się ekranu od nowa przy każdej zmianie
stanu — a stan zmienia się dokładnie wtedy, gdy nie ma na to uwagi. Tryb, który
przestawia układ, jest gorszy od braku trybów.

Z tego wynika reszta reguł.

### Cztery stany

| tryb | warunek | co awansuje | co się wycofuje |
|---|---|---|---|
| `DEEP` | brak ciała w zasięgu grawitacji | taśma kursu, prędkość, skaner | **wszystkie przyrządy lotu**, orbita, teren |
| `ORBIT` | w studni, powyżej atmosfery, `orbit_state()` w ORBIT/DECAYING | rysowany diagram orbity, czas do perycentrum | nachylenie, podwozie, taśma wysokości |
| `LANDING` | w atmosferze, albo poniżej progu wysokości, albo podwozie wysunięte | pełne przyrządy, taśma wysokości, wskaźniki po terenie | orbita do jednej przygaszonej linii |
| `COMBAT` | wrogi kontakt w zasięgu albo świeży strzał | sylwetka kadłuba, duża energia, nawias celu | wszystko nieśmiertelne przygasza się |

Najważniejszy jest `DEEP` i to on jest dowodem, że pomysł jest dobry: w próżni
prawy dolny narożnik jest **pusty**, i ta pustka jest treścią. Mówi „nic tutaj
nie może cię teraz zabić". HUD lądowania w przestrzeni międzyplanetarnej to
szum, a szum uczy pilota ignorować panel, na który ma patrzeć przy podejściu.

### Stany nie są rozłączne, są warstwami z priorytetem

Lądowanie pod ostrzałem się zdarzy i nie może wybierać między dwoma HUD-ami.
Rozwiązanie jest w podziale nieruchomości, nie w priorytecie globalnym:

- `LANDING` jest właścicielem **nakładki na świat** i prawego dolnego narożnika.
- `COMBAT` jest właścicielem **lewego górnego** narożnika i nawiasu celu.
- `ORBIT` jest właścicielem **prawego górnego**.
- `DEEP` jest rozłączny ze wszystkim z definicji: bez ciała nie ma ani orbity,
  ani gruntu.

Dwa tryby aktywne naraz nie kolidują, bo z założenia dostały różne narożniki.
To jest cały mechanizm i nie potrzebuje arbitra.

### Przejścia

- **Histereza na każdym progu.** Wejście w `LANDING` na 2000 m, wyjście na
  2600 m. Bez tego lot po granicy stroboskopuje interfejs.
- **Minimalny czas trwania trybu około 1.5 s.** Przelot przez atmosferę nie ma
  prawa przemeblować ekranu dwa razy w sekundę.
- **Awans jest szybszy od wycofania: 120 ms w górę, 400 ms w dół.** Przyrząd,
  który pojawia się za późno, zabija. Przyrząd, który znika za późno, tylko
  irytuje. Asymetria jest celowa.
- **Przygaszaj, nie usuwaj**, gdy wartość jest nadal prawdziwa, tylko przestała
  być najważniejsza. Usunięcie odbiera odczyt, przygaszenie zostawia go do
  doczytania.
- Przejście jest wycieraniem z sekcji 7, nie przenikaniem i nie skalowaniem.

### Skąd się bierze tryb

Prezentacja **wyprowadza** tryb z liczb, które symulacja już liczy —
`nearest_planet()`, `air_density`, `altitude_at()`, `orbit_state()`,
`gear.is_deployed()` — i trzyma go u siebie (`scripts/ui/hud_mode.gd`). `Ship`
nie dostaje pola `hud_mode` i nie wie, że tryby istnieją. Jedyny szew, którego
brakuje, to wrogi kontakt, i ten wpada do listy z VISUALS.md sekcja 6, kiedy M5
dowiezie wrogów; do tego czasu `COMBAT` odpala sam strzał.

---

## 11. Ekrany pełnoekranowe

Trzy ekrany nie są kokpitem: edytor statku, mapa systemu, mapa galaktyki. Mają
tę samą paletę, tę samą kreskę 1 px i tę samą typografię, ale wolno im to,
czego HUD-owi nie wolno: **pełną ramę, tytuł i środek ekranu**.

**Edytor statku.** Warsztat, więc pokazuje narzędzia. Siatka montażowa jako
kropki co 8 px w `grid`, kadłub jako obrys 1 px (ten sam wielokąt, który jest
kształtem kolizji — jeśli się rozjadą, widać to od razu), gniazda jako nawiasy,
podniesiony moduł jako widmo przy kursorze w `caution`. Prawa kolumna to
**raport, nie lista**: masa, przesunięcie środka masy, sześć pasków autorytetu
po jednym na komendę, i blok „gdyby to zamontować" z różnicą w `ok`/`alarm`.
Wszystko, co tam stoi, liczy już `configuration_report.gd` — ekran tego nie
wymyśla. Dwa markery środka masy naraz (obecny w `label`, po montażu w `ok`)
są tańsze niż liczba i mówią więcej.

**Mapa systemu.** Schemat, nie widok — nie renderujemy planet, rysujemy je.
Orbity jako okręgi kreskowane w `nav`, ciała jako dyski o promieniu z
logarytmu prawdziwego promienia, granica wpływu jako okrąg kropkowany,
statek jako nawias z przewidywaną trajektorią i czasem dolotu. Podpis tylko
przy ciele wybranym i przy tym, na którym stoimy — reszta dostaje jedną literę.
Podziałka skali w narożniku, bo bez niej schemat kłamie o odległościach.

**Mapa galaktyki.** Punkt na gwiazdę, kolor z klasy widmowej, `inert` na
nieskanowane. Nawias na systemie bieżącym, kreskowany okrąg zasięgu skoku,
trasa jako linia 1 px z kwadratem na każdym przeskoku. Liczba, która się liczy,
to **liczba przeskoków**, nie odległość — odległość jest drugorzędna, bo paliwo
wydaje się na skok.

Wspólna reguła dla wszystkich trzech: **klawisze wypisane na dole ekranu**,
zawsze, tą samą metryką. Ekran modalny, który nie mówi, jak z niego wyjść, jest
błędem, a nie stylem.

---

## 12. Przyrząd jest widgetem, a widget wymaga modułu

Każdy przyrząd jest osobnym, małym obiektem, a jego obecność na ekranie wynika z
tego, co jest zamontowane na statku. Wysokościomierz pokazuje wysokość, bo na
statku jest radar terenu. Nie ma radaru — nie ma taśmy wysokości.

To jest dobra decyzja i to z tego samego powodu, z którego dobry jest model
silników z IDEAS.md sekcja 3: **zdolność wynika z budowy, a nie z przypisanej
roli**. HUD przestaje być dekoracją nałożoną na grę i staje się konsekwencją
decyzji podjętej w edytorze. Utrata modułu w walce **oślepia** w sposób, który
widać, a nie w sposób, który trzeba wyczytać z liczby. To rozgrywka, nie chrom.

Ale to jest też cztery pułapki, i każda z nich musi być zamknięta w projekcie,
bo inaczej pomysł psuje grę zamiast ją pogłębiać.

### Pułapka 1: nie wolno ukryć tego, co zabija

Kadłub, ciepło i energia są własnościami **kadłuba**, nie modułu. Są zawsze, bez
warunku. Gdyby dały się wyłączyć budową, gracz mógłby zbudować statek, który
usunął własne ostrzeżenie o uszkodzeniu — a wtedy śmierć jest niesprawiedliwa i
gra jest zepsuta.

Linia podziału jest uczciwa i łatwa do zapamiętania: **przyrząd mówiący o świecie
wymaga modułu, przyrząd mówiący o statku — nie.** Wysokościomierz mierzy planetę.
Wskaźnik kadłuba mierzy ciebie, i ty jesteś tu zawsze.

### Pułapka 2: brak przyrządu musi być widoczny

Brakujący przyrząd nie może wyglądać jak działający przyrząd wskazujący zero. Nie
może też wyglądać jak pusty narożnik, bo pusty narożnik w trybie `DEEP` znaczy
„nic tutaj nie może cię zabić" (sekcja 10) — czyli dokładnie coś innego.

Trzy stany, trzy różne obrazy, i gracz musi je rozróżniać, bo naprawia się je
zupełnie inaczej:

| stan | jak wygląda | jak się naprawia |
|---|---|---|
| jest przyrząd, jest odczyt | etykieta `label`, wartość `value` | — |
| jest przyrząd, nie ma danych | etykieta `label`, wartość `--` w `inert` | leć gdzie indziej |
| nie ma przyrządu | etykieta w `inert`, w miejscu wartości `NO MOD` | zamontuj moduł |
| przyrząd uszkodzony | etykieta w `alarm`, ostatni odczyt przygaszony | napraw albo wymień |

Czwarty wiersz jest okazją, nie obowiązkiem: uszkodzony wysokościomierz, który
pokazuje ostatni znany odczyt zamiast żadnego, jest bardziej przerażający niż
pusty panel, i dokładnie w duchu tej gry.

### Pułapka 3: układ nie może się przelewać

Widgety pojawiające się i znikające w `VBoxContainer` przetasują panel przy każdej
zmianie budowy — i tracimy dokładnie tę pamięć mięśniową, którą sekcja 10 chroni.

Dlatego: **gniazda, nie przepływ.** Panel to siatka wierszy o stałej wysokości.
Widget deklaruje, którego gniazda chce i ile wierszy zajmuje; puste gniazdo
zostaje puste. Kolizję rozstrzyga priorytet, deterministycznie. Rozwiązany układ
liczy się **raz, przy montażu i przy zmianie trybu** — nigdy co klatkę. Efekt
uboczny jest pożądany: dwa statki o podobnej budowie mają podobny ekran.

### Pułapka 4: to nie może wyrosnąć we framework

Widget jest mały i ma pozostać mały. Zasób deklaruje:

```
slot: StringName       które gniazdo w którym panelu
rows: int              ile wierszy zajmuje
requires: StringName   wymagana zdolność, puste = zawsze
modes: int             maska trybów, w których się pokazuje
priority: int          rozstrzyganie kolizji w gnieździe
```

plus jedna funkcja rysująca, która dostaje prostokąt i statek, i woła `ui_draw`.
**Bez własnego `_process`, bez własnych sygnałów, bez własnego węzła.** Panel
przechodzi po swoich widgetach w jednym przebiegu, w swoim `_process`. Inaczej
dwanaście przyrządów to dwanaście pętli klatkowych i problem z czasem klatki w
grze 640x360, która nie ma prawa go mieć.

### Zdolność, nie typ modułu

Widget wymaga **zdolności** (`ALTIMETRY`, `ORBIT_SOLUTION`, `SCAN`, `TARGETING`,
`GROUND_SLOPE`), a moduły zdolności dostarczają. Nie wymaga „modułu Mk2 radar",
bo wtedy każdy nowy moduł to edycja listy w każdym widgecie. To ta sama zasada,
co przy silnikach: rola wynika z tego, co rzecz potrafi.

Dwie bramki są ortogonalne i obie muszą przejść: `requires` pyta o budowę,
`modes` o sytuację. Bramka budowy jest pierwsza — jeśli nie masz przyrządu, tryb
jest bez znaczenia. Bramka trybu tylko przygasza i wycofuje.

### Zapłata, którą to otwiera

Lepszy moduł nie tylko włącza widget — **poprawia go**. Tani wysokościomierz:
sama liczba, zaokrąglona do 50, odświeżana 2 razy na sekundę. Dobry: taśma,
metr, 10 Hz. Ten sam widget, ta sama jedna linia kodu rysująca, a różnica jest
odczuwalna przy każdym lądowaniu. To jest dużo rozgrywki za bardzo mało
konstrukcji i dlatego warto zaprojektować widget tak, żeby jakość modułu była
jego parametrem od początku — nawet jeśli pierwsze moduły będą miały jedną klasę.

Ryzyko wypisane wprost: **da się zbudować statek bez przyrządów.** To jest w
porządku, a nawet zabawne, pod warunkiem że pułapki 1 i 2 są zamknięte. Edytor
ma to powiedzieć w raporcie konfiguracji, w tym samym miejscu, gdzie dziś stoi
„pusta grupa komend": `no altimetry`, `no orbit solution`. Informacja tak, zakaz
nie — zbudowanie sobie kłopotu jest legalnym sposobem gry.

---

## 13. Makiety

`mockups/` — rysunki 1:1 w SVG dla HUD-u w czterech trybach, edytora i obu map.
Makieta ustala układ, gęstość i hierarchię przed kodem, bo to najtańsze miejsce
na zmianę zdania. Nie ustala, jak rzecz wygląda w ruchu; na to jest galeria i
odpalenie gry. Jeśli makieta kłóci się z tym plikiem, ten plik ma rację.

---

## 14. Kolejność

Zależność jest jedna: paleta i font przed czymkolwiek, bo inaczej migrujemy dwa
razy.

1. **Paleta i font** — sam zasób, sam theme, HUD zaczyna używać monospace.
   Najmniejsza zmiana z największym skokiem: cyfry przestają tańczyć.
2. **`ui_draw.gd` + galeria** — wiersz odczytu i nawias, dwa prymitywy, i
   miejsce do oglądania ich.
3. **Układ w czterech narożnikach** — przeniesienie tego, co jest, na ramę.
4. **`ui_value.gd`** — wygładzanie i kwantowanie, czyli moment, w którym
   interfejs przestaje wyglądać na debugowy.
5. **Pasek energii z podziałką** i **łuk ciepła** — pierwsze przyrządy, które
   nie są wierszem tekstu.
6. **Wskaźniki nad światem** przy lądowaniu.
7. **Poświata** — na końcu, bo to jedyna rzecz, którą da się ocenić tylko na
   gotowym obrazie, i jedyna, którą wolno wyciąć bez straty.
