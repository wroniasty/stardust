# ASSETLIST.md

Spis tego, co trzeba narysować. **Co** ma powstać i **dlaczego akurat jako
sprite** — bo „jak ma wyglądać" jest w UI_STYLE.md, a „kiedy to wchodzi" w
VISUALS.md.

Stan na dziś: **gra nie ma ani jednego zasobu graficznego.** `icon.svg` to
domyślna ikona Godota, a `mockups/` ma `.gdignore` i nie jest importowane.
Wszystko, co widać, jest rysowane w locie — `Polygon2D`, `_draw()`, shadery i
cząstki bez tekstury.

## Ramy techniczne

| rzecz | wartość | skutek |
|---|---|---|
| rozdzielczość bazowa | 640 x 360 | sprite 16 px to 1/40 szerokości ekranu |
| tryb skalowania | `canvas_items`, `expand` | zasoby robimy w skali 1:1, silnik skaluje |
| filtr tekstur | `Nearest` (0) | pixel art, bez rozmycia; krawędź musi być zamierzona |
| rozmiar fontu w HUD | 8 px | ikona obok tekstu ma 7–9 px, nie więcej |

Z tego wynika jedna rzecz, którą trzeba mieć z tyłu głowy przy każdej pozycji:
**te obiekty są malutkie.** Statek to 16x22 px, skrzynka 12x12, znacznik na
mapie 4–10 px średnicy, ikona gniazda w edytorze ~7 px. W tej skali ręcznie
postawiony piksel wygrywa z każdą procedurą, bo łuk o promieniu 2 px narysowany
`draw_arc` to kasza, a narysowany ręcznie to czytelny symbol.

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

| kadłub | obrys | sprite |
|---|---|---|
| dart (stock) | 16 x 22 | 16 x 24 |
| wide delta | 36 x 19 | 36 x 20 |
| long lance | 12 x 48 | 12 x 48 |
| hexagon | ~20 x 20 | 20 x 20 |
| brick | ~22 x 18 | 24 x 20 |
| sliver (bad) | 6 x 38 | 8 x 38 |
| romb (para sił) | 18 x 30 | 20 x 32 |

Doczepiane osobno, każde w punkcie, który kod już zna:

| element | gdzie | rozmiar | uwagi |
|---|---|---|---|
| dysza silnika | `mount.position`, obrócona o `mount.rotation` | ~7 x 7 | trzy warianty wg `EngineData.Type`; wariant gimbala obracany dodatkowo o `gimbal` |
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
