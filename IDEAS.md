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

Statek to RigidBody2D z własnym `_integrate_forces` i `center_of_mass_mode =
CUSTOM`: masa, środek masy i moment bezwładności są liczone z kadłuba i
zamontowanych modułów, a nie brane z kształtu kolizji.

### Silnik nie ma roli, ma geometrię

Wcześniejszy model przypisywał silnikom sztywne role (główny, obrotowy). Został
zastąpiony: silnik ma tylko pozycję i kierunek, a do czego się nadaje **wynika z
obliczeń przy montażu**. Przesunięcie silnika zmienia jego zadanie bez dotykania
jakiegokolwiek kodu.

Trzy elementy:

- `EngineMount` (node dziecko statku): `position`, `thrust_direction`
  (jednostkowy wektor **siły na statek**; wylot spalin jest przeciwny),
  `allowed_types`, `size`. Rozmiar slotu jest zarazem masą, jaką zamontowany
  moduł dokłada do statku, czyli tym, co przesuwa środek masy.
- `EngineData` (Resource w `resources/engines/`): `type`, `max_thrust`,
  `spool_time`, `reliability`, `fuel_cost`. To jest przyszły loot z M2.
- `EngineInstance`: para (dane, mount) plus `health`, `throttle`,
  `target_throttle`.

Typ opisuje charakter przepustnicy, nie przeznaczenie:

- **MAIN** rozpędza się liniowo, 1/`spool_time` na sekundę, w obie strony.
- **TORQUE** jest impulsowy: chwilowa przepustnica to zawsze 0 albo 1.
- **THRUSTER** odpowiada natychmiast i proporcjonalnie.

### Grupy sterowania liczone z geometrii

`Ship.rebuild_control_groups()` po każdej zmianie konfiguracji liczy dla
każdego silnika wkład

    F_i = kierunek_montażu * max_thrust
    r_i = pozycja_montażu - środek_masy
    c_i = (F_i.x / masa, F_i.y / masa, (r_i x F_i) / bezwładność * promień_bezwładności)

Sześć komend (FORWARD, BACK, STRAFE_LEFT, STRAFE_RIGHT, CCW, CW) to kierunki w
tej samej przestrzeni. Waga silnika w komendzie to `wzdłuż - SIDE_PENALTY *
w_bok`, normalizowana tak, żeby najsilniejszy w grupie miał 1.0; poniżej progu
0.05 silnik do grupy nie wchodzi. Jeden silnik może należeć do kilku grup.

**Trzeci składnik musi być przeskalowany promieniem bezwładności
`sqrt(bezwładność/masa)`.** Bez tego wektor miesza px/s^2 z rad/s^2 i te dwie
wielkości nie są porównywalne: własny efekt boczny silnika obrotowego (kilka
px/s^2) przytłacza jego wkład kątowy (ułamek rad/s^2), kara boczna go odrzuca i
**żaden silnik nigdy nie trafia do grupy obrotu**. Pomnożenie przez promień
bezwładności wyraża wszystkie trzy składowe jako przyspieszenie widziane na tym
promieniu, czyli robi porównanie, które heurystyka i tak próbuje zrobić.

Przy przebudowie zapisywany jest też `max_authority` każdej grupy w jednostkach
natywnych (siła dla komend liniowych, moment dla obrotowych), bo hamowanie przez
niego dzieli. Skład grup jest wypisywany do konsoli przy starcie, z ostrzeżeniem
dla każdej pustej — statek, który nie potrafi skręcić w jedną stronę, to błąd
konfiguracji i ma być widoczny od razu.

**Grupy liczone są z ciągu nominalnego, bez `health`.** To celowe: gdyby
uszkodzenie przeliczało wagi, zepsuty silnik byłby po cichu kompensowany, a cały
sens modelu uszkodzeń polega na tym, że pół-martwy silnik sprawia, że statek
leci krzywo. Kompensujący komputer lotu to moduł do znalezienia w M2.

### Para obrotowa musi być symetryczna

Dwa silniki obrotowe po przeciwnych stronach dziobu, skierowane w przeciwne
strony, **nie tworzą pary obrotowej** — ich momenty też się znoszą. Para
wymaga rozsunięcia wzdłuż osi statku: dziób-lewo z ogon-prawo daje siły, które
znoszą się dokładnie, i momenty, które się dodają. Do obrotu w obie strony
potrzebne są więc dwie pary, czyli cztery silniki.

Ramiona obu silników pary muszą być **równe co do długości**, inaczej
normalizacja nada im różne wagi (np. 1.00 i 0.40), siły przestaną się znosić i
obrót będzie dryfował w bok. Na statku testowym wymusza to rozstaw: dysze
dziobowe na y = -10, ogonowe na y = 13.5, przy środku masy na y = 1.75.

### Modulacja impulsowa silników TORQUE

Odczytanie „0 albo 1" jako „odpal, kiedy cokolwiek od ciebie żądane" jest
pułapką: dysza obrotowa należąca do grupy strafe z wagą 0.16 odpalała pełną
mocą, dawała czterokrotnie większą siłę boczną niż zamierzona, a hamulec gonił
dryf, który sam tworzył, i się rozbiegał.

Ułamek jest więc **wypełnieniem, nie amplitudą**: modulator delta-sigma
pierwszego rzędu akumuluje żądanie i odpala silnik na cały tick za każdym razem,
gdy akumulator przekroczy 1. Średni ciąg równa się dokładnie żądaniu, każdy
pojedynczy tick jest nadal twardo włączony albo wyłączony, a mały udział oznacza
sporadyczny puff zamiast pełnego wypału.

### Asysty

- **Kill rotation**: dokłada komendę przeciwną do znaku prędkości kątowej o
  wartości `|omega| / KILL_GAIN`. Próg wygaszenia jest **liczony z autorytetu
  statku**, nie stały: jeden impuls zmienia prędkość kątową o ustaloną wartość,
  więc jeśli epsilon jest mniejszy niż jeden impuls, każda korekta przestrzeliwuje
  i zmienia znak, a asysta klekocze wokół zera zamiast skończyć. `KILL_GAIN` jest
  wyraźnie poniżej 1 rad/s, bo poniżej progu spadek jest wykładniczy i przy 1.0
  ostatni ułamek trwa dłużej niż całe wyhamowanie pierwszego radiana.
- **Brake**: rozkłada `-v` w układzie statku na oś przód/tył i bok, i dla każdej
  składowej dobiera komendę z wartością `|składowa| * masa / autorytet`, czyli
  czasem potrzebnym na wyhamowanie, przyciętym do sekundy. Obrotu nie rusza.
  Kierunek bez silników po prostu nie jest hamowany — statek bez silnika
  wstecznego nie wyhamuje ruchu do przodu. To konsekwencja liczenia grup z
  geometrii, nie luka.

Komendy pilota i zestaw efektywny są **rozdzielone**. Asysty dopisują do kopii
na dany tick, nie do intencji pilota; kiedy pisały wprost do niej, wpisy nigdy
nie były czyszczone dla statku nie sterowanego wejściem i hamulec pchał dalej po
zatrzymaniu, rozpędzając statek do tyłu.

### Sterowanie

    W  ciąg do przodu        S  ciąg wstecz
    A  obrót w lewo (CCW)    D  obrót w prawo (CW)
    Q  strafe w lewo         E  strafe w prawo
    X  kill rotation         Z  hamowanie
    spacja / ctrl  ogień
    F7 warstwa debug   F5 uszkodź dyszę (debug)   C  krater (debug)

Awarie silników pochodzą ze zderzeń, zużycia i ataków. Awaria to zmiana `health`,
nic specjalnego w silniku fizycznym.

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

**Siła dragu to nie pokrętło od feelingu, tylko limit prędkości.** Tłumienie
liniowe daje prędkość graniczną `g / damp`, więc drag przy ziemi decyduje o tym,
czy statek w ogóle może się rozbić. Pierwsze ustawienie (MAX_ATMOSPHERE_DAMP
2.0) dawało przy ziemi 31 px/s przy progu obrażeń 60 px/s — powietrze czyniło
uderzenie z prędkością zdolną cokolwiek uszkodzić fizycznie niemożliwym i
lądowanie przestawało być umiejętnością. Obniżone do 0.4, co na tej samej
planecie daje 154 px/s: hamowanie należy do pilota.

Profil powłok zaostrzony z 3/25/100 na 15/50/100, tak dobrany, żeby górna
powłoka miała **dokładnie ten sam** drag co wcześniej. Aerobraking jest
nietknięty, puściło tylko dolne powietrze.

Rozpiętość po zmianie (prędkość graniczna przy ziemi): od 62 px/s na planecie o
najgęstszej atmosferze i najsłabszej grawitacji, do 375 px/s na rzadkiej
atmosferze przy silnym G. Ten dolny skraj jest nadal wyrozumiały i tak ma być —
sekcja 7 chce, żeby gęsta atmosfera hamowała mocno. Pilnuje tego test:
prędkość graniczna musi przekraczać próg obrażeń z zapasem.

**Smugi kondensacyjne** jako informacja zwrotna o atmosferze. Dwie linie
schodzące z tylnych narożników kadłuba, długość i krycie liczone z
`gęstość * prędkość` — czyli z tej samej wielkości, która daje drag i
nagrzewanie. Dzięki temu to, co widać, jest tym, co hamuje: nic w próżni, cienka
nitka wysoko, gruby warkocz nisko i szybko. Linie mają `top_level`, więc
zostawione punkty zostają tam, gdzie je upuszczono, zamiast być ciągnięte przez
statek.

Powietrze tłumi też obrót, ale słabiej: `angular_damp = linear_damp * 0.5` na
tej samej powłoce. Powód jest rozgrywkowy, nie fizyczny — nisko nad planetą
gracz najbardziej potrzebuje precyzyjnego celowania dziobem, a stockowe silniki
obrotowe mają tylko po 60 jednostek ciągu. Dzięki temu lot w atmosferze różni
się od lotu w próżni nie tylko hamowaniem, a opadanie przez gęste warstwy samo
trochę stabilizuje statek.

`angular_damp_space_override` jest ustawiane jawnie na każdej powłoce, mimo że
to samo, co dałaby wartość domyślna z zamysłu. `Area2D.angular_damp` domyślnie
wynosi 1.0, więc pozostawienie override'a w spokoju parkuje na każdej powłoce
bardzo mocne tłumienie czekające na przypadkowe włączenie.

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
też musiały się zacieśnić (0.08/0.7 -> 0.02/0.18): przy 400 px powietrza stara
wartość dawała 270 px poświaty na ekranie wysokim na 360 px.

Zmierzone: orbita kołowa na 2.0 R trzyma promień z dryfem 0.05% przez 30 s przy
semi-implicit Euler w 60 Hz. Wystarczy dla zręcznościówki, pełny test na kilka
minut jest w M1.5.

**Atmosfera to jedna warstwa rysowana POD terenem.** Kwadrat sięga promienia
atmosfery, shader zna tylko `surface_ratio`, kolor i gęstość — nic o
powierzchni. Powyżej nominalnego promienia krycie opada od `shell_haze` (0.80)
do zera na szczycie z wykładnikiem `shell_falloff` 0.70, czyli po krzywej
**wklęsłej**: wykładnik poniżej 1 utrzymuje realne krycie przez środek
wznoszenia, zamiast upychać całą atmosferę w dolnej jednej trzeciej. Tuż nad
gruntem jest wąski rim light (`rim_strength` 0.25). Poniżej promienia warstwa
tylko gęstnieje — przez `opaque_depth` (6% promienia kwadratu) dochodzi do
pełnego krycia i tak zostaje aż do środka planety.

Gęstość planety skaluje całość przez `mix(0.55, 1.0, gęstość)` — rzadka
atmosfera ma być słabsza, ale nigdy nieobecna, inaczej co piąta planeta
wyglądałaby na bezpowietrzną, choć nie jest.

Zmierzone krycie przy gęstości 0.51: grunt 0.234, szczyty gór 0.475, połowa
atmosfery 0.384, 9/10 wysokości 0.124, szczyt 0. Gwiazdy tła są zasłonięte przez
większość wznoszenia i wychodzą dopiero blisko krańca atmosfery.

**Dlaczego pod terenem, a nie nad nim.** Bo wtedy kopanie nie odsłania niczego
poza tym, co i tak już tam było. Poprzednie podejście — shader z polem wysokości
gruntu (`ground_heights`, teksel na kolumnę kątową) — kosztowało cztery rundy
poprawek i każda odsłaniała nową wadę tego samego błędu: mgiełka wlewała się w
świeżo wystrzelone szyby (sąsiednie kolumny przy r=1050 miały 0.233, 0.594 i
0.777 krycia, czyli jasne pasy stojące między filarami skały), krater wycinał
promienistą szczelinę w chmurach aż po szczyt nieba, a każdy filtr wygładzający
to pole psuł coś innego — średnia była ciągnięta w dół przez tę samą dziurę,
którą miała zignorować, średnia z górnej połowy próbek unosiła się osiem pikseli
nad nietkniętym gruntem na całym horyzoncie, a domknięcie morfologiczne
działało, ale podwoiło czas generacji planety. Reguła na przyszłość: **warstwa
atmosfery nie dostaje danych o powierzchni.** Kolejność rysowania załatwia
wszystko, czego pole wysokości miało dowieść.

**Chmury to osobne obiekty, nie wzór wypełniający pierścień.** Pierwsze dwie
wersje rysowały szum w pierścieniu wokół planety (`ColorRect` na całą tarczę) i
obie wyglądały jak obręcz, którą planeta ma na sobie. To nie był problem
parametrów — kamera lata **w środku** tego pierścienia, więc każda chmura była
wycinkiem jednego ciągłego pola wygiętego po horyzoncie. Nie da się tego
naprawić ani częstotliwością, ani progiem: dopóki niebo jest polem, nie ma
krawędzi, a chmura bez krawędzi to mgła.

Teraz każda chmura to instancja: `CloudField` (MultiMeshInstance2D) trzyma po
kilkadziesiąt quadów, każdy ustawiony w biegunowej ramce planety, a
`shaders/cloud.gdshader` rysuje w tym quadzie **jedną** chmurę. Jeden batch na
warstwę, kilkaset quadów na planetę — dla GPU to nic, a niebo składa się z
obiektów, które można minąć.

Pokrywa ma trzy warstwy (`CLOUD_LAYERS`), każda na innej wysokości i z inną
prędkością obrotu. Jedna warstwa czyta się jak arkusz naklejek niezależnie od
tego, jak dobre są pojedyncze chmury; dopiero rozjazd warstw daje głębię przy
przelocie.

**Sylwetka: łańcuch płatów na wspólnym korpusie, w przestrzeni skorygowanej o
proporcje.** Koła liczone wprost w UV to była pierwsza próba i wychodziły z
niej naleśniki, bo quad chmury jest 2 do 20 razy szerszy niż wyższy — koło w UV
spłaszcza się dokładnie o ten czynnik. Wszystko liczy się więc w jednostkach
**wysokości** chmury (`point = vec2(UV.x * aspect, UV.y)`, gdzie `aspect`
przychodzi w `INSTANCE_CUSTOM.w`). Dzięki temu jeden shader rysuje przysadzisty
cumulus i smugę cirrusa dwadzieścia razy dłuższą od własnej wysokości.

Kolejność jest istotna: najpierw ciągły korpus (kapsuła wzdłuż długości), potem
płaty na nim. Bez korpusu długa chmura jest rzędem osobnych kółek — gąsienicą, a
nie chmurą — bo każdy płat musi sam sięgnąć podstawy. Płaty trzymane są w
granicach korpusu (0.12..0.88 długości), inaczej skrajne odrywają się jako
bąbelki.

Pozostałe parametry shadera: `softness` (ostry cumulus vs woalka bez sylwetki),
`detail` (ile szum nadgryza kontur), `pile` (jak wysoko piętrzą się płaty),
`flat_base` (płaskie spody cumulusów biorą się z tego, że cała pokrywa skrapla
się na tej samej wysokości; wisior cirrusa nie ma podstawy w ogóle),
`shading` + `shade_color` (jaśniejsze szczyty, ciemniejsze spody — stąd bierze
się objętość). Per instancja: seed, krycie, własny udział w `pile`, aspect.

Zmierzona pułapka: `QuadMesh` kładzie UV v = 0 wzdłuż swojego lokalnego +y, a w
kanwie +y jest w dół, więc quad trzeba obrócić o `angle - PI/2`, nie `+ PI/2`.
Pierwsza wersja rysowała wszystkie chmury do góry nogami — płaskie podstawy
patrzyły w kosmos, płaty zwisały ku planecie.

**Archetypy zamiast niezależnych losowań.** Niezależne rolle na ośmiu
parametrach uśredniłyby każdą planetę do tej samej mgiełki, więc najpierw
losowany jest typ nieba, a potem jitter w jego granicach. Rozmiary są podawane
w grubościach pokrywy, więc znaczą to samo na księżycu i na gazowym olbrzymie;
`coverage` to ułamek obwodu stojący pod chmurą (1.0 = chmury ułożone jedna za
drugą obeszłyby planetę, powyżej — zachodzą na siebie w ciągłą pokrywę).

| typ | udział | szer. x wys. | pokrycie | charakterystyczne |
|---|---|---|---|---|
| CUMULUS | 40% | 1.4..2.6 x 0.7..1.0 | 0.5..0.8 | ostre krawędzie, płaskie spody 0.7..0.9 |
| STRATUS | 30% | 3..6 x 0.35..0.55 | 1.2..1.8 | zachodzą na siebie w pokrywę |
| CIRRUS | 20% | 5..9 x 0.25..0.45 | 0.4..0.7 | wysoko (0.55..0.80 atmosfery), bez podstawy, duży shear |
| BANDED | 10% | 5..10 x 0.5..0.8 | 1.0..1.5 | shear ±1.0..1.8, pasma gazowego olbrzyma |

Pozostałe wspólne: 75% planet z atmosferą ma chmury, obrót ±0.008..0.05 rad/s
(znak losowy), kolor to biel zmieszana z kolorem atmosfery w 5..45%, spód to ten
kolor przyciemniony i pociągnięty w stronę atmosfery. Bezpowietrzne skały nie
mają pogody.

Wylosowana wysokość to tylko życzenie: relief sięga ~12% R ponad nominalny
promień, a najniższa baza wypada na 6% R, więc pokrywa potrafiłaby wisieć w
zboczu góry. `cloud_base_radius()` podnosi ją ponad `terrain.outer_radius` (z
20 px zapasu) i trzyma pod stropem powietrza. Pilnuje tego przemiatanie 40
seedów w smoke teście: chmury zawsze nad skałą, zawsze w powietrzu, zawsze
niezerowej grubości, zawsze w niezerowej liczbie; osobne przemiatanie 120
seedów pilnuje, że każdy archetyp faktycznie wypada (BANDED 4 na 120).

**Oglądanie jest tańsze niż mierzenie.** `tools/cloud_preview.tscn` renderuje po
dwa PNG-i na archetyp — cała tarcza i przelot pod pokrywą:

    godot --path . tools/cloud_preview.tscn -- <katalog wyjściowy>

Testy tej warstwy mogą pilnować tylko własności (nad skałą, w powietrzu,
niezerowa grubość), nigdy tego, co naprawdę się liczy. Cztery rundy uwag do
atmosfery minęły, zanim ktokolwiek zmierzył artefakt; to narzędzie jest po to,
żeby następnym razem popatrzeć od razu.
żyje wysoko.

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
| generacja | 27.7 ms | 56.6 ms |
| krater r=28 + upload tekstury | 0.69 ms | 1.00 ms |
| samplowanie kadłuba (6 punktów, wszystkie w skale) | 0.127 ms/tick | 0.124 ms/tick |

Generacja urosła czterokrotnie (z 7.8/14.4 ms) po dołożeniu domknięcia
morfologicznego podłogi mgły w M1.6+, które przy tworzeniu planety przebiega
cały pierścień. Jednorazowo na planetę i tak trafia w M3 na wątek roboczy.

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

### Realizacja (M1.6)

`LandingGear` trzyma nogi i wszystkie progi, `Ship` je sprawdza, nic innego nie
decyduje. Wysuwanie klawiszem G zajmuje `deploy_time`; do pełnego wysunięcia
nogi nie liczą się ani jako punkty kontaktu, ani jako podwozie — inaczej timer
byłby dekoracją. Drag wysuniętego podwozia jest mnożony przez gęstość powietrza,
więc w próżni nie kosztuje nic.

**Kiedy oceniać lądowanie.** Pierwsza wersja czekała, aż obie nogi będą w skale.
To było za późno: solver kontaktów zdążył przechylić statek na nodze, która
dotknęła pierwsza, i lądowanie było oceniane po kącie, który samo wywołało —
poziome przyziemienie na płaskim gruncie wychodziło 32 stopnie od pionu. Teraz
próba lądowania idzie **przed** impulsami, a noga liczy się jako stojąca, jeśli
grunt jest w zasięgu `LEG_CONTACT_REACH` (5 px, czyli skok zawieszenia), nie gdy
jest już zagrzebana.

**Kąt jest sprawdzany na pierwszej nodze, nie na wszystkich.** Przy rozstawie
18 px i 5 px skoku dwie nogi mogą być jednocześnie na gruncie tylko przy
przechyle poniżej ~16 stopni, więc czekanie na obie czyniło tolerancję 15 stopni
nieosiągalną i kontrolę kąta martwym kodem. Wczesna odmowa daje też pilotowi
powód zamiast niewyjaśnionego przewrotu.

**Nachylenie liczone pod nogami, nie przez środek statku.** Dwupunktowy pomiar
przez kadłub potrafi pokazać idealnie równy teren, gdy statek stoi okrakiem na
grzbiecie: obie próbki lądują na zboczach i żadna nie widzi wierzchołka między
nimi. Szukanie „najpłaszczejszego" miejsca miarą, którą da się oszukać, znajduje
dokładnie te miejsca, które ją oszukują — grunt pod nogami różnił się wtedy o
10 px przy raportowanym nachyleniu 0 stopni. Pytanie każdej nogi o jej własny
kawałek gruntu jest odporne i jest tym, co sekcja 7 i tak nakazuje.

**Normalna terenu do kontroli kąta jest liczona z pola wysokości**
(`up.rotated(-nachylenie)`), a nie próbkowana z bitmapy. Pierścień prób
potrzebuje powierzchni do objęcia; noga oparta kilka pikseli w skale ma
większość pierścienia w środku i zwraca śmieć — równa półka wychodziła ścianą
55 stopni. Przy okazji normalna i nachylenie nie mogą się teraz nie zgadzać.

**Stan wylądowany.** Statek jest zamrażany (`freeze`, tryb kinematyczny) i
zapamiętywany jako (kąt, promień, kurs) w układzie biegunowym planety, a nie
jako transformacja świata — dzięki temu obracająca się planeta go wiezie.
Statek **nie** jest przepinany pod planetę: sekcja 9 wymaga, żeby gracz pozostał
bezpośrednim dzieckiem świata, bo systemy są strumieniowane pod nim.

Pułapka warta zapamiętania: `polar_to_world` przepuszcza kąt przez `to_global`,
które już stosuje obrót planety. Dodanie obrotu po raz drugi zamieniło
zaparkowany statek w taki, który sunie po gruncie z podwójną prędkością
powierzchni.

Zamrożenie idzie przez `set_deferred("freeze", true)`. `freeze` to zmiana stanu
ciała w serwerze fizyki, a `_integrate_forces` działa w trakcie flushowania
zapytań i serwer takiej zmiany odmawia. To dokładnie ta sama pułapka co ze
spawnowaniem pocisków (sekcja 4) — warto ją traktować jako regułę: **z
`_integrate_forces` wolno zmieniać tylko to, co wystawia obiekt stanu**.
`freeze_mode` jest ustawiany raz w `_ready`, bo i tak się nie zmienia.

Odczyt wejścia i decyzja o starcie są w `_physics_process`, nie w
`_integrate_forces`: zamrożone ciało nie dostaje tego drugiego w ogóle, więc
wylądowany statek nasłuchujący tylko tam nigdy nie mógłby wystartować. Lądowanie
jest też blokowane w trakcie komendy ruchu — bez tego statek zaraz po starcie
nadal stoi na nogach przy zerowym opadaniu, spełnia wszystkie warunki i ląduje
z powrotem w tym samym ticku.

**Plateau.** Generator wyrównuje `count` łuków do stałego promienia, z miękką
rampą na końcach, jeden mniej więcej na 900 px obwodu. Poziom brany z wysokości
już istniejącej w środku łuku, żeby półka była częścią krajobrazu, a nie wisiała
na wymyślonej wysokości.

**Obrót planety** do 0.02 rad/s, na tyle wolno, że prędkość powierzchni zostaje
poniżej bocznej tolerancji podwozia. Uwaga praktyczna: przy opadaniu z 30 px
planeta zdąży obrócić się o tyle, że płaska półka ucieka spod statku — to realne
utrudnienie lądowania, nie błąd.

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

**Styczna musi być pochodną kąta, nie `orthogonal()`.** Lock prowadzi statek
analitycznie po okręgu (`angle += omega * dt`), a znak omegi brał się z rzutu
prędkości na `up.orthogonal()`. `orthogonal()` obraca o 90 stopni przeciwnie do
ruchu wskazówek, co przy osi Y w dół ma **przeciwną skrętność** niż rosnący kąt
— więc statek po włączeniu locka zawracał i leciał po orbicie w drugą stronę.
Do tego prędkość zapisywana dla HUD szła jeszcze starym kierunkiem, więc
wskazania i ruch przeczyły sobie nawzajem. Styczna liczy się teraz jawnie jako
`Vector2(-up.y, up.x)`.

**Lock posiada pozycję, nie orientację.** `_integrate_forces` wychodziło w
trybie locka przed pętlą aplikującą siły silników, więc dysze obrotowe paliły
się i rysowały wydech, ale żaden moment nie docierał do ciała — statek zaparkowany
na orbicie nie dawał się obrócić, czyli nie dawał się ustawić do wyjściowego
odpalenia. Teraz w locku liczony jest sam moment (`_apply_engine_torque`), bez
sił. To nie przybliżenie: grupy obrotowe są z definicji parami sił o zerowej
wypadkowej, a każda komenda, która naprawdę by statek przesunęła, i tak zwalnia
locka.

Test pilnujący promienia tego nie widział, bo okrąg o zadanym promieniu jest
taki sam w obie strony. Smoke test porównuje więc znak momentu pędu przed
przejęciem ze znakiem faktycznego przyrostu kąta w locku, i osobno sprawdza, że
raportowana prędkość zgadza się z kierunkiem, w którym lock naprawdę przesuwa
statek.

### Elementy orbity na HUD (M1.5+)

Trajektoria rysowana pod F7 pokazuje kształt orbity, ale kształt to nie liczba:
pilot potrzebuje wiedzieć, o ile ma podnieść perycentrum, a nie „mniej więcej
tak". HUD ma więc dwa wiersze, PERI i APO.

Decyzje, które warto zapisać, bo nie są oczywiste:

- **Analitycznie, nie z symulacji naprzód.** Pole grawitacyjne nad powierzchnią
  jest dokładnie odwrotnością kwadratu, więc `mu = g * R^2` daje stożki
  dokładne, nie dopasowane: `Planet.orbit_extremes()` liczy energię właściwą i
  moment pędu i zwraca (perycentrum, apocentrum). Predyktor trajektorii
  całkuje naprzód i jest do rysowania linii; HUD nie musi czekać na horyzont
  symulacji, żeby podać liczbę.
- **Wysokości nad nominalnym promieniem, nie nad gruntem pod statkiem.** Apsyda
  wypada gdzie indziej na planecie, gdzie grunt ma inną wysokość, więc jedynym
  uczciwym wspólnym odniesieniem jest promień, którym planeta jest opisana.
- **Kolor perycentrum niesie treść:** zielone — orbita mija teren, bursztynowe —
  wchodzi w atmosferę i będzie się degradować, czerwone — kończy się w gruncie.
  To ostatnie jest zarówno ostrzeżeniem, jak i celownikiem: deorbit burn polega
  właśnie na sprowadzeniu perycentrum pod powierzchnię w wybranym miejscu.
- **Apocentrum poza `influence_radius` to ucieczka, nie liczba.** Grawitacja
  jest wygaszana na zewnętrznej dziesiątej części studni, więc stożek przestaje
  tam obowiązywać; HUD pisze ESCAPE zamiast podawać wartość, która byłaby
  nieprawdziwa.

Pilnuje tego test lecący tam, gdzie predykcja obiecała: statek wyrzucony
stycznie z 1.12 prędkości kołowej ma punkt startu dokładnie w perycentrum, a po
2772 tickach (pół okresu przy a = 1926 px) osiąga apocentrum — zmierzone 2415 px
wobec przewidzianych 2415. Błąd znaku albo złe `mu` przechodzą każdy test
wewnętrznej spójności i wywracają się na tym jednym.

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

**Auto-orbit jako opcjonalna funkcja komputera pokładowego (M2).** Nie każdy
komputer ją ma — to jest cały sens. Tani kadłub startowy wymaga wejścia na
orbitę ręcznie; znaleziony lub kupiony lepszy komputer robi to sam, i to jest
odczuwalna zmiana w tym, jak się lata, a nie kolejny +5% do statystyki.

Warunki załączenia: statek jest w polu grawitacyjnym planety lub księżyca
(wewnątrz `influence_radius`) i **poza atmosferą** — w powietrzu manewr byłby
walką z dragiem, a nie mechaniką orbitalną, i to jest ta sama granica, której
pilnuje już orbit lock. Po załączeniu komputer sam dobiera i wykonuje odpalenia
tak, żeby wejść na orbitę wokół tego ciała.

Otwarte pytania: czy celem jest orbita kołowa na aktualnej wysokości, czy
najtańsza paliwowo orbita zamknięta (podniesienie samego perycentrum ponad
atmosferę); czy funkcja zużywa paliwo widoczne dla gracza; jak się zachowuje,
gdy trajektoria jest hiperboliczna i wyhamowanie przekracza możliwości silników
— powinna wtedy odmówić z podaniem powodu, a nie palić paliwo bez skutku.
Uszkodzone silniki są tu ciekawym przypadkiem: auto-orbit korzysta z tych
samych grup sterowania, więc statek z połową dysz wykona manewr wolniej i mniej
dokładnie, zamiast mieć osobną ścieżkę „to się nie uda".

### Realizacja (M1.5)

**Wytrzymałość orbit.** Zmierzone przez `tools/orbit_endurance.gd`, 5 minut na
przypadek, semi-implicit Euler w 60 Hz, planeta R 1025 / g 31.4:

| orbita | wynik po 5 min |
|---|---|
| kołowa 2.0 R | dryf promienia 0.05% |
| eliptyczna 2.0 R (93% v_koł) | apocentrum +0.003%, perycentrum -0.001% |
| eliptyczna 3.0 R (85% v_koł) | apocentrum -0.0002%, perycentrum +0.0001% |

Czyli orbity się nie rozjeżdżają i nie trzeba nic robić z integratorem. Wniosek
z sekcji 8 („orbity lekko precesują, ale nie uciekają") potwierdzony liczbowo.

Uwaga metodologiczna zapłacona błędem: narzędzie musi odpalać przypadki z
pętli fizyki, nie z `_initialize()`, bo węzły dodane tam nie są jeszcze w
drzewie i planeta ma wtedy domyślne parametry, nie te z seeda. Pierwsze
uruchomienie pokazało „50% dryfu", co w rzeczywistości było statkiem wysłanym
na orbitę wokół planety o połowę mniejszej niż ta, która potem powstała.
Poza tym prędkość startowa musi dawać perycentrum ponad atmosferą — inaczej
mierzy się drag i zderzenie, nie integrator. Narzędzie liczy teraz przewidywane
perycentrum (`r0 * k^2 / (2 - k^2)`) i ostrzega, jeśli wpada w powietrze.

**Przewidywana trajektoria** jest na warstwie debug (F7), nie na stałe. Linia
przez środek ekranu jest zaśmieceniem, kiedy się jej akurat nie czyta; po
schowaniu punkty są czyszczone, żeby nie została zamrożona stara ścieżka.

Symulacja do przodu tą samą funkcją grawitacji i
tym samym semi-implicit Eulerem co fizyka, więc linia nie jest przybliżeniem
fizyki — jest fizyką puszczoną naprzód. Drag i ciąg są celowo pominięte: pytanie
brzmi „co się stanie, jeśli teraz puszczę stery". 320 kroków po 6 ticków = około
32 s horyzontu, przeliczane co 2 ticki. Koszt 0.304 ms na przeliczenie, czyli
0.152 ms na tick fizyki (0.9% budżetu klatki).

**Orbit lock.** Warunki: 2 s bez ciągu, prędkość radialna poniżej 6 px/s,
styczna w granicach 6% prędkości kołowej, i koniecznie **poza atmosferą** —
zablokowanie orbity w powietrzu zamroziłoby orbitę schodzącą i po cichu
skasowało aerobraking, czyli dokładne przeciwieństwo tego, do czego lock służy.
Po zablokowaniu prędkość jest nadal wyliczana i wystawiana prawdziwa, żeby HUD,
predyktor trajektorii i moment zwolnienia widziały realny ruch orbitalny.
Zwolnienie: ciąg główny albo trafienie. Silniki obrotowe nie zwalniają locka,
więc można się celować stojąc na orbicie.

**Aerobraking i ciepło.** Zmierzone: w górnej powłoce przy prędkości orbitalnej
statek traci 5.8% prędkości na 2 s — hamuje, ale łagodnie, zgodnie z zamysłem
profilu powłok.

Ciepło rośnie z mocą rozpraszaną przez powietrze, czyli `gęstość * v^2`, a nie z
`v^3`. Powód jest spójnościowy: powłoki stosują tłumienie liniowe, więc moc,
którą faktycznie odbierają statkowi, idzie jak `gęstość * v^2`. Wiązanie ciepła
z tą samą wielkością gwarantuje, że pasek ciepła i wytracanie prędkości nie
opowiadają dwóch różnych historii.

Ustawienie stałych jest kompromisem, który warto znać: stałe chłodzenie
(0.05/s) wyznacza próg, poniżej którego zejście nigdy nie grzeje. W efekcie
powolne lądowanie przez gęste powietrze jest darmowe, szybkie i głębokie wejście
zapełnia pasek w kilka sekund, ale **aerobraking w najwyższej powłoce przy
naszych prędkościach orbitalnych nie generuje ciepła w ogóle** — 3% gęstości
przy 156 px/s daje mniej niż chłodzenie. Jest to spójne (tam gdzie prawie nie
hamuje, prawie nie grzeje), ale rozmija się z zamysłem z sekcji 8, gdzie
aerobraking miał grzać. Jeśli ma grzać, trzeba albo pogrubić górną powłokę,
albo podnieść prędkości orbitalne. Do decyzji przy strojeniu feelingu.

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
- Interpolacja fizyki (`physics/common/physics_interpolation`) włączona. Bez niej
  transformacja statku zmienia się tylko w tickach fizyki (60 Hz), a kamera
  wygładza się w każdej klatce renderowania — statek ślizga się względem kamery
  o ułamek piksela w tę i z powrotem, co przy prędkości powyżej ~200 px/s czyta
  się jako rozmycie. Wraz z nią Godot wymusza tryb fizyczny na każdym Camera2D
  (stąd ostrzeżenie w konsoli, jest oczekiwane). Węzły podążające za statkiem
  muszą się aktualizować w `_physics_process`, nie w `_process`: odczyt
  transformacji z klatki renderowania zwraca pozycję nieinterpolowaną.
- Pixel-art: bazowa rozdzielczość 640x360, skalowanie przez tryb rozciągania `canvas_items` z aspektem `expand` (ustawienia projektu), filtr tekstur Nearest. SubViewport nie jest potrzebny: `canvas_items` renderuje w niskiej rozdzielczości i skaluje całość, a `expand` pozwala na szersze ekrany bez czarnych pasów. SubViewport dopiero wtedy, gdy HUD będzie musiał być w pełnej rozdzielczości.
- Silniki: GPUParticles2D, intensywność od ciągu, zmiana przy warpie i awariach.
  `inherit_velocity_ratio = 0.85` jest tu kluczowe: cząsteczki lecą w układzie
  świata z prędkością 70..110 px/s, więc na postoju wyglądają jak płomień, a
  przy 300 px/s jak obłoczek, który statek natychmiast zostawia za sobą, dryfując
  z prędkością bez widocznego związku z czymkolwiek. Przeniesienie 85% prędkości
  emitera trzyma smugę przy dyszy, a pozostałe 15% robi ciągnięcie — wygląda tak
  samo przy każdej prędkości.
- Tło: paralaksa gwiazd w shaderze, smugi przy skoku. Zrealizowane w M1.1:
  jeden pełnoekranowy quad na CanvasLayer -100 z `follow_viewport_enabled =
  false`. Quad nigdy się nie rusza, cały ruch robi uniform `world_offset`
  karmiony pozycją kamery, więc pole gwiazd jest nieskończone i nie ma czego
  streamować. Gwiazdy są hashowane z siatki, czyli odtwarzalne z samej pozycji:
  odlot i powrót pokazuje te same gwiazdy. Trzy warstwy (paralaksa 0.10 / 0.30 /
  0.65) dają czytelne poczucie głębi. Offset mnożony przez zoom kamery, inaczej
  gwiazdy dryfują w złym tempie przy oddaleniu.
- Oświetlenie 2D od gwiazdy, cień strony nocnej planety.

### Śmierć i restart (M1.7)

Kadłub to `hull_integrity` 0..1, ta sama skala co ciepło i kondycja silników.
Dzięki temu istniejące liczby obrażeń działają bez przeliczania: otarcie przy
100 px/s kosztuje 0.16, rozbicie przy 200 px/s 0.56, a cokolwiek powyżej około
310 px/s zabija od razu.

Wszystkie źródła obrażeń przechodzą przez jedno `take_damage()`. To jest cała
sztuczka: uderzenie w teren, przeciążenie podwozia i trafienie pociskiem dzielą
ścieżkę śmierci, zamiast każde wymyślać własną. Obrażenia po śmierci nie robią
nic — bez tego ostrzeliwany wrak respawnowałby się raz na trafienie.

**Statek nie jest zwalniany przy śmierci.** Wskazują na niego kamera, HUD,
smugi kondensacyjne i warstwa debug; ponowne instancjonowanie oznaczałoby
przepinanie tego wszystkiego przy każdej śmierci, w grze, której motto brzmi
„die often". Świat składa go z powrotem w miejscu przez `respawn()`, które
czyści też ciepło, podwozie i zaległą odmowę lądowania — inaczej nowy statek
dziedziczy problemy starego. Po przestawieniu trzeba wołać
`reset_physics_interpolation()`, bo inaczej interpolator rysuje smugę od miejsca
śmierci do miejsca odrodzenia.

Decyzję o tym, gdzie wraca statek, podejmuje świat, nie statek: statek jedynie
melduje, że skończył mu się kadłub. Respawn jest na orbicie kołowej na 2.0 R,
nad miejscem katastrofy, żeby pilot nie stracił orientacji.

**Pociski uzbrajają się po 0.2 s.** Lufa siedzi wewnątrz promienia kontaktowego
własnego kadłuba, więc bez chwili zwłoki każdy strzał zabijałby strzelca. To nie
jest jednak trwałe zwolnienie — pocisk, który okrąży planetę i wróci, trafia
normalnie.

Wybuch sam się zwalnia po wygaśnięciu cząsteczek i żłobi krater, jeśli wrak
uderzył blisko gruntu, więc śmierć zostawia ślad w terenie.

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
