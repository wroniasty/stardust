# ASSETLIST.md

Spis tego, co trzeba narysować. **Co** ma powstać i **dlaczego akurat jako
sprite** — bo „jak ma wyglądać" jest w UI_STYLE.md, a „kiedy to wchodzi" w
VISUALS.md.

Stan na dziś: **jest komplet placeholderów, nie ma ani jednego docelowego
zasobu.** 41 plików w `assets/art/`, wygenerowanych przez
`tools/make_placeholders.gd`, plus zasoby `resources/fx/looks/*.tres` i
`resources/hulls/*.tres`, które je wiążą z przedmiotami. Wszystko, co widać
**w grze**, jest nadal rysowane w locie — `Polygon2D`, `_draw()`, shadery i
cząstki bez tekstury — bo podmiana rysowania na sprite'y to osobna robota,
rozpisana w VISUALS.md („VS: Przejście na sprite'y").

Placeholdery są generowane, nie rysowane, i to jest celowe: chodzi o właściwą
**liczbę** plików, we właściwych **rozmiarach**, z właściwymi **punktami
zaczepienia**, żeby migrację dało się napisać i przetestować, zanim powstanie
pierwszy prawdziwy piksel. Kadłub-placeholder to dosłownie jego własny obrys
kolizyjny wypełniony kolorem, więc nie może mieć złego kształtu. Prawdziwa
grafika podmienia pliki jeden do jednego; zasoby, pivoty i kod zostają.

## Ramy techniczne

| rzecz | wartość | skutek |
|---|---|---|
| jednostka układu | 640 x 360 | wymiary w tym spisie są **w tej jednostce**, nie w texelach |
| tryb skalowania | `canvas_items`, `expand` | silnik renderuje w rozdzielczości okna, nie w 640x360 |
| **świat: skala rysowania** | **3x** (`Art.FACTOR`) | statek 18x24 jedn. rysujemy jako **54x72 px**, wyświetlamy w skali 1/3 |
| **świat: filtr** | `LINEAR_WITH_MIPMAPS` | kadłub obraca się swobodnie i kamera zjeżdża — patrz niżej |
| **interfejs: skala** | **1:1** | ikona 11x11 jedn. to plik 11x11 px |
| **interfejs: filtr** | `Nearest` | HUD się nie obraca i stoi w skali 1.0; prawo siatki działa tu dosłownie |
| mipmapy przy imporcie | `true` globalnie | `[importer_defaults]` w `project.godot`; bez nich filtr świata cicho degraduje |
| rozmiar fontu w HUD | 8 jedn. | ikona obok tekstu ma 7–9 jedn., nie więcej |
| animacja | dozwolona wszędzie | **każdy sprite może być paskiem klatek**; format poniżej |

### Dlaczego świat i interfejs mają osobne reguły

Wyglądało to na sprzeczność w UI_STYLE.md §2 i nią nie jest — to świat
pożyczał regułę napisaną dla panelu.

**640x360 zostaje jednostką układu i przestaje być budżetem texeli.** Powód
jest w trybie skalowania, który projekt już ma: `canvas_items` renderuje w
rozdzielczości okna, a dokumentacja Godota mówi o nim wprost, że *„nie ma już
odpowiedniości 1:1 między pikselem sprite'a a pikselem ekranu"*. Statek
dostaje przy 1080p **72x96 prawdziwych pikseli** i miał dotąd 24x32 na ich
wypełnienie.

**Trójka, bo 1080p to dokładnie trzykrotność 640x360.** Na najczęstszym
ekranie jeden texel to jeden piksel i nic nie jest przepróbkowywane.

**I dlatego świat nie może być filtrowany przez `Nearest`.** To jest zmierzone,
nie przyjęte: `ShipCamera.ZOOM_LEVELS` daje 1.7 do 0.55, człon prędkości mnoży
to jeszcze przez 0.7, więc sama kamera chodzi w zakresie **1.7 .. 0.385**. Okno
mnoży to przez 2 przy 720p i przez 6 przy 4K. Jeden texel trafia więc na
**ćwierć piksela ekranu albo na trzy i pół** — trzynastokrotny zakres, w jednej
sesji, na jednym sprite. `Nearest` nie ma odpowiedzi na żadnym końcu: gubi
texele w dół i robi nierówne klocki w górę, a na obracającym się kadłubie robi
jedno i drugie naraz, w dodatku pełzająco. Mipmapy są odpowiedzią na dół,
a na górze nie ma już żadnej siatki pikseli do obrony.

**Przesądził obrót.** Statek obraca się swobodnie przez pełne 360 stopni i
**nie robimy pre-renderowanych klatek obrotu** (decyzja pilota). Nie ma więc
kąta, przy którym niskorozdzielczy sprite siada na siatce pikseli — i tak jest
przepróbkowywany co klatkę. Jedyne pytanie brzmi, czy jest przepróbkowywany z
dość materiału.

**HUD zostaje prawdziwym pixel artem.** Nie obraca się, nie zmienia skali i
stoi w skali 1.0 z mocy prawa siatki. Tam design pixel naprawdę jest pikselem,
więc rysujemy 1:1, filtrujemy `Nearest`, i UI_STYLE.md §2 znaczy dokładnie to,
co mówi.

Jedna rzecz zostaje w mocy mimo potrojenia: **te obiekty są malutkie.** Statek
to 18x24 jednostki, skrzynka 12x12, znacznik na mapie 4–10, ikona gniazda ~7.
Trzykrotna skala daje miejsce na detal, nie na ilustrację — a w interfejsie, w
skali 1:1, ręcznie postawiony piksel dalej wygrywa z każdą procedurą.

### Animacja

Każdy sprite wolno animować i część z nich powinna być animowana. Format
jednolity, żeby import był jedną regułą, a nie decyzją per plik:

- **Poziomy pasek klatek** w jednym pliku (`nazwa_strip6.png`), kwadratowe
  klatki, liczba klatek w nazwie. Godot czyta to jako `hframes` na
  `Sprite2D` albo `SpriteFrames` na `AnimatedSprite2D`; w obu wypadkach
  jeden plik na animację, nie katalog po klatce.
- **Klatki na sekundę są daną, nie cechą pliku.** Pióropusz przy pełnej
  przepustnicy biegnie szybciej niż na jednej czwartej — więc tempo jest
  wyliczane z tego samego ułamka, którym skaluje się jasność i światło,
  a nie zapisane w zasobie.
- **Animacja ma coś znaczyć.** Dyszę, wiązkę i lampę stacji animujemy, bo
  w ruchu niosą stan. Ikony w HUD i w edytorze **zostają statyczne**:
  migające ikony na przyrządach to rozpraszanie, a ekran pomocy z
  animowanymi symbolami to jarmark.

## Wygląd wynika z cech, nie z osobnego rzutu

Sprite'y i efekty nie są losowane obok statystyk — **wybiera je to, czym
przedmiot jest**. Ta sama zasada, co z gwiazdą, której kolor wynika z masy:
niebieska naprawdę jest ciężka, więc kolor na skanerze jest odczytem, a nie
ozdobą. Dwa identyczne statystycznie silniki, które wyglądają inaczej bez
powodu, to szum — i gracz przestaje patrzeć po godzinie.

Wiązania są dwa i warto je rozróżniać:

**Po wielkości.** Zasób podaje kilka wariantów, a wybiera się je progiem na
nazwanej statystyce. Przykład podany przez pilota: trzy pióropusze na silnik,
dobierane **mocą**. Słaby ciąg to wąska iskra, średni to stożek, mocny to
rozwidlony płomień z dyszą świecącą do czerwoności.

**Po afiksie.** Afiks może przynieść własny wygląd, bo tłumaczy, co widać.
„steerable" dostaje dyszę na przegubie, „overbored" większy dzwon i brudniejszy
płomień, „frugal" węższy i czystszy, „breaching" grubszą smugę pocisku. Jeśli
dwa afiksy chcą tego samego miejsca, wygrywa ten rzadszy — i tylko on jest
widoczny, bo sylwet nie skaluje się na cztery jednoczesne modyfikacje.

Wynik jest taki sam, jak przy niezależnym losowaniu — dużo wariantów z
niewielu plików — tylko każdy z nich coś mówi.

## Reguła decyzyjna

Trzy pytania, w tej kolejności:

1. **Czy kształt jest daną?** Generowany z seeda — teren, chmury, gwiazda? →
   **zostaje proceduralny**, zawsze. Sprite nie potrafi być parametrem.
   Kadłub statku *wygląda* na taki przypadek i nie jest: obrys nie jest
   dowolny, tylko wybierany z nazwanego katalogu, więc sprite wybiera się tą
   samą nazwą. Patrz sekcja 1a.
2. **Czy rzecz jest mniejsza niż jakieś 16 px na ekranie?** → **sprite**, bo w
   tej skali proceduralne prymitywy nie czytają.
3. **Czy ma stały sylwet, ale zmienną informację** (rzadkość, stan, kolor
   ciała)? → **hybryda**: sprite w bieli plus `modulate` albo narysowana
   obwódka. Nie dwadzieścia wariantów pliku.

---

## 1a. Statek

**Jeden sprite na kadłub, plus osobne sprite'y na to, co do niego
przykręcone.** Nie składanka z kafelków i nie tekstura na wielokącie.

Kolizja zostaje przy `hull_outline` — z niego liczą się kształt zderzeniowy,
punkty styku, masa i moment bezwładności. **Sprite może się od tego obrysu
trochę różnić i to jest w porządku**: dopasowanie jednego do drugiego to
odpowiedzialność autora grafiki, nie kodu. Rozdzielenie „czym się zderza" od
„jak wygląda" jest tu świadome — próba trzymania ich w jednym kształcie
kosztowałaby albo brzydki sprite, albo dziwną fizykę.

Obrysów jest skończenie wiele i **mają nazwy**: katalog `CreativeTool.SHAPES`
plus kadłuby z presetów `ShipFitout`. Edytor statku (`I`) obrysu **nie
zmienia** — tylko go czyta, żeby narysować schemat. Sprite wybiera się więc tą
samą nazwą, którą wybiera się obrys.

Jest ich dziesięć, nie siedem: sześć z `CreativeTool.SHAPES` i cztery kadłuby,
które mają tylko presety w `ShipFitout`. Każdy ma teraz zasób
`resources/hulls/<id>.tres` i wpis w `resources/fx/looks/hull.tres` pod tym
samym `id`. Rozmiar pliku to obrys plus 1 jednostka marginesu, razy `Art.FACTOR`.

| id | kadłub | obrys (jedn.) | plik (px) |
|---|---|---|---|
| `dart` | dart (stock) | 16 x 22 | 54 x 72 |
| `wide_delta` | wide delta | 36 x 19 | 114 x 63 |
| `long_lance` | long lance | 12 x 48 | 42 x 150 |
| `hexagon` | hexagon | 24 x 28 | 78 x 90 |
| `brick` | brick | 28 x 36 | 90 x 114 |
| `sliver` | sliver (bad) | 6 x 38 | 24 x 120 |
| `rhombus` | gimbal podwójny (para sił) | 18 x 30 | 60 x 96 |
| `broad_dart` | gimbal pojedynczy (dryfuje) | 18 x 26 | 60 x 84 |
| `interceptor` | przechwytujący | 14 x 24 | 48 x 78 |
| `freighter` | frachtowiec | 32 x 22 | 102 x 72 |

Margines nie jest ozdobą: sprite z sylwetą wciśniętą w krawędź ramki nie ma
dokąd wygasić filtru liniowego i wychodzi z jasnym rąbkiem z dwóch stron.

Doczepiane osobno, każde w punkcie, który kod już zna:

| element | gdzie | rozmiar | uwagi |
|---|---|---|---|
| dysza silnika | `mount.position`, obrócona o `mount.rotation` | ~7 x 7 | trzy warianty wg `EngineData.Type`, plus wariant na przegubie dla afiksu „steerable", obracany o `gimbal` |
| pióropusz | ta sama dysza | ~10 x 16, pasek 4–6 klatek | **trzy warianty dobierane mocą silnika**; tempo klatek z przepustnicy, nie z pliku |
| działo | pozycja hardpointu, obrócone o `facing` | ~7 x 9 | wg `WeaponData.Type` |
| podwozie | `leg_root()` z obrysu | goleń 3 x 9, stopka 6 x 3 | rozstaw nóg zostaje liczony, grafiką jest noga |
| moduł zewnętrzny | pozycja gniazda | ~6 x 6 | tylko to, co widać z zewnątrz; zatoki wewnętrzne nie |

`Hull` jako `Polygon2D` przestaje być tym, co widać — zostaje źródłem obrysu
dla kolizji i dla schematu w edytorze. Schemat **ma** dalej rysować wielokąt,
bo jego zadaniem jest pokazać prawdę o kształcie zderzeniowym, a nie ładny
obrazek.

## 1b. Rysowane dziś, powinny być spritem

To, co nie jest częścią statku — części statku są wyżej.

| rzecz | dziś | docelowo | rozmiar | uwagi |
|---|---|---|---|---|
| **skrzynka lootu** | dwa `Polygon2D` (`Body` + `Glow`) | **hybryda**: sprite skrzyni + proceduralna obwódka rzadkości | 12 x 12 | przykład podany przez pilota i wzorcowy: sylwet jest stały, rzadkość jest daną z `ModuleData.rarity_color()`. Sprite biały, `modulate` od zawartości, obwódka rysowana |
| **pocisk** | `Polygon2D` „Body" | sprite smugi | 3 x 7 | cztery warianty wg broni (działko, impuls, slug, odłamek) albo jeden biały + `modulate` kolorem broni |
| **rakieta** | `Polygon2D` „Body" + „Fin" | sprite z płetwami | 5 x 11 | ma dziób i stery — to jest sylwet, nie kształt z danych |
| **stacja** | `_draw()`: pierścień, szprychy, piasta | **hybryda**: kafle modułów (segment pierścienia, szprycha, piasta, dok) składane wg seeda | segment ~24 x 24 | wariantowość ma zostać (liczba szprych, kolor), ale z klocków, nie z `draw_arc` |
| **beam** | dwie `draw_line` | sprite rozciągany wzdłuż strzału | 8 x 3, kafelkowany | dziś to dwie kreski jedna na drugiej; wiązka chce rdzenia i poświaty |
| **smuga kondensacyjna** | `Line2D` + `Gradient` | ta sama `Line2D`, ale z teksturą | 8 x 8 kafel | `Line2D` przyjmuje `texture` z `texture_mode`; nie trzeba zmieniać węzła |

## 2. Rysowane dziś, zostają proceduralne

Nie dlatego, że tak wyszło — dlatego, że **kształt jest daną**.

| rzecz | czym jest | dlaczego zostaje |
|---|---|---|
| teren planety | shader z mapy polarnej | kształt jest bitmapą, którą gracz rozwala strzałami |
| atmosfera, chmury | shadery z seeda | pogoda jest losowana i ma być rozpoznawalna per świat |
| gwiazda i korona | shadery | granulacja i pociemnienie brzegowe to ciągłe pole, nie obrazek |
| starfield | shader paralaksy | trzy warstwy generowane z pozycji |
| **obrys kadłuba jako dana** | `hull_outline` | zostaje źródłem kolizji, punktów styku, masy i momentu — ale przestaje być tym, co widać. Patrz 1a |
| orbity, stożki, przerywana trajektoria | `_draw` z całkowania | krzywa jest wynikiem symulacji każdej klatki |
| pierścienie zasięgu na mapie | `_draw` | promienie są liczbami z modelu |
| nakładki debugowe | `_draw` | narzędzia deweloperskie, celowo inne (UI_STYLE.md §8) |
| schemat statku w edytorze | `_draw` z obrysu | ma pokazywać prawdę o kształcie zderzeniowym, a nie sprite'a |

## 3. Nie rysowane wcale — brakujące zasoby

To są dziury, nie upiększenia.

| rzecz | stan | co trzeba |
|---|---|---|
| **dysze silników** | **niewidoczne** — `EngineMount` ma tylko `GPUParticles2D`, zero grafiki | sprite dyszy, 3 warianty wg `EngineData.Type` (MAIN duża z dzwonem, TORQUE mała, THRUSTER płaska), ~7 x 7; dodatkowo wariant wychylany dla gimbala, obracany o `gimbal` |
| **tekstura cząstek pióropusza** | brak — domyślne kwadraty | miękka kropka 8 x 8 z gradientem; bez niej płomień to siatka kwadratów |
| **tekstura cząstek debris** | brak | odłamek 3 x 3, 2–3 warianty |
| **czcionka bitmapowa** | `SystemFont` (Consolas / DejaVu) | font pikselowy o wysokości 8 px. Największa pojedyncza wygrana wizualna w całym spisie: **każdy ekran** jest z niego zbudowany, a systemowy font przy `Nearest` i skalowaniu niecałkowitym rozjeżdża się na kratę |

## 4. Ikony i symbole do narysowania

Wszystkie w **bieli na przezroczystym**, kolor przez `modulate`. Powód jest
mechaniczny: kolory niosą informację (rzadkość, stan, osiągalność, barwa
ciała) i są liczone w kodzie — wypalony kolor w pliku to drugie miejsce,
które musi się z tym zgadzać.

### 4a. Edytor statku — gniazda i wyposażenie

Dziś `_draw_slot_glyph()` rysuje sylwetki liniami, w polu 11 px z glifem ~7 px.

| ikona | dla czego |
|---|---|
| gniazdo silnika: MAIN, TORQUE, THRUSTER | trzy typy z `EngineData.Type` |
| gniazdo broni: działko, impuls, slug, wyrzutnia, wiązka | `WeaponData.Type` |
| gniazdo generatora, komputera, podwozia, ładowni | po jednej |
| gniazdo puste | obrys bez wypełnienia |
| łuk obrotu działka | zostaje proceduralny — kąt jest daną z `traverse()` |

### 4b. HUD

| ikona | dziś | rozmiar |
|---|---|---|
| ostrzeżenie (wykrzyknik) | dwie `draw_line` | 5 x 7 |
| podwozie: schowane / w ruchu / wypuszczone | tekst `GEAR UP` | 7 x 5 |
| apsydy: perycentrum, apocentrum | kropki `draw_circle` | 3 x 3 |
| stan orbity: ORBIT / DECAY / ESCAPE / SUBORBITAL | tekst | 7 x 7 |
| dopalanie, przegrzanie, dok | tekst `BOOST` / `HEAT` / `DOK` | 7 x 7 |
| kursor celowania: wolny / na celu / zablokowany | `draw_arc` | 9 x 9 |

### 4c. Mapa układu

Dziś okręgi i kwadraty o promieniu 2–5 px, czyli **4–10 px średnicy** — poniżej
progu, w którym `draw_arc` cokolwiek znaczy.

| ikona | rozmiar | uwagi |
|---|---|---|
| gwiazda | 11 x 11 | `modulate` barwą z `Star.colour_for()` |
| planeta | 7 x 7 | `modulate` kolorem powierzchni |
| księżyc | 5 x 5 | |
| stacja | 5 x 5 | kształt wyraźnie inny: to nie jest ciało niebieskie |
| statek gracza | 7 x 7 | strzałka, obracana kursem |
| znacznik wyboru | 13 x 13 | nawias dookoła wybranego |

### 4d. Skaner

| ikona | rozmiar | uwagi |
|---|---|---|
| kierunek ciała | 5 x 7 | dziś trójkąt; `modulate` kolorem ciała, jasność = czy jest w świecie |
| loot | 5 x 5 | dziś romb |

### 4e. Moduły w ładowni i na kartach

| ikona | uwagi |
|---|---|
| rodzaj modułu: silnik, broń, generator, komputer, podwozie, mod | 11 x 11, ta sama rodzina co gniazda w edytorze, ale większa |
| ramka rzadkości | 5 poziomów; **jedna ramka** `modulate` kolorem z `rarity_color()`, nie pięć plików |

---

## Placeholdery, które już są

41 plików, generowanych przez `tools/make_placeholders.gd` (uruchamiane dwa
razy, z `--import` pomiędzy: zasób nie może wskazywać na teksturę, której
jeszcze nie zaimportowano). Wymiary w pikselach pliku, czyli już po `Art.FACTOR`.

| rodzina | plików | rozmiar pliku | wiąże je | wybierane po |
|---|---|---|---|---|
| kadłuby | 10 | 24x120 .. 114x63 | `looks/hull.tres` | `HullData.id` |
| dysze | 4 | 18x18 .. 30x27 | `looks/engine_nozzle.tres` | `EngineData.type`, plus afiks „steerable" |
| pióropusze | 3 | paski 6 klatek, 126x30 .. 198x63 | `looks/engine_plume.tres` | `EngineData.max_thrust`, progi 250 i 600 |
| działa | 6 | 24x30 | `looks/weapon_muzzle.tres` | `WeaponData.type` |
| moduły zewnętrzne | 3 | 27x27 | `looks/module_box.tres` | klucz: generator / computer / cargo |
| podwozie | 2 | 11x29, 20x11 | `looks/gear_leg.tres` | klucz: strut / pad |
| pociski i skrzynka | 3 | 11x23 .. 38x38 | `looks/round.tres` | klucz |
| cząstki | 2 | 24x24, pasek 27x9 | `looks/particle.tres` | klucz: dot / debris |
| ikony interfejsu | 8 | 11x11, ramka 13x13 | `looks/module_icon.tres` | klucz, **skala 1:1** |

Czego w placeholderach celowo nie ma: stacji, wiązki, smugi kondensacyjnej,
fontu bitmapowego oraz ikon HUD, mapy i skanera (sekcje 4b–4d). Pierwsze trzy
to hybrydy albo rzeczy proceduralne, których placeholder niczego nie
przyspiesza; font to osobna robota narzędziowa; ikony HUD czekają, aż będzie
wiadomo, które przyrządy zostają po V6.

Co pilnuje, że to się nie rozjedzie: `_check_art()` w smoke teście. Sprawdza,
że każdy kadłub z obu starych katalogów ma zasób o tym samym obrysie, że każdy
pasek ma teksturę dzielącą się przez liczbę klatek i pivot wewnątrz ramki, że
flaga skali zgadza się z katalogiem, w którym plik leży, i — to jest ta
ciekawa część — że tablice wyglądu **cokolwiek rozróżniają**: tablica
sprowadzająca wszystkie siedem silników do jednego obrazka nie jest wiązaniem,
tylko domyślną wartością w przebraniu, i przeszłaby każdy inny test.

---

## Czego świadomie nie ma na liście

- **Statek składany z wielu kafelków.** Jeden sprite na kadłub, i tyle; patrz
  1a. Pierwsza wersja tego spisu odrzucała sprite kadłuba w ogóle, bo
  rozjechałby się z kształtem kolizyjnym — co było przeszacowaniem problemu z
  dwóch powodów. Obrysy nie są dowolne, tylko nazwane, więc sprite wybiera się
  tą samą nazwą; a drobna różnica między sylwetą a kształtem zderzeniowym jest
  normalną ceną w grach 2D i należy do autora grafiki, nie do kodu.
- **Planety jako sprite'y.** Cały sens generatora jest taki, że świat jest
  bitmapą, w której można wykopać dziurę.
- **Warianty kolorystyczne plików.** Wszędzie biały sprite plus `modulate`.

## Kolejność, gdyby robić po jednym

1. **Font bitmapowy** — dotyka każdego ekranu.
2. **Dysze silników** — jedyna rzecz w grze, której po prostu nie widać.
3. **Tekstury cząstek** — płomień i odłamki są dziś kwadratami.
4. **Ikony mapy i skanera** — tam, gdzie proceduralne prymitywy są najmniejsze.
5. **Ikony gniazd w edytorze** — ekran jest gotowy, czeka na symbole.
6. **Skrzynka, pocisk, rakieta** — małe obiekty świata.
7. **Kadłuby** — siedem sprite'ów, ale dopiero gdy dysze i podwozie już są,
   bo dopiero wtedy widać, ile kadłub ma pokazywać, a ile dokładają doczepki.
8. **Stacja** — hybryda, najwięcej roboty na jednostkę efektu.
