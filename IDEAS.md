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
  `allowed_types`, `size`. `size` to **pojemność slotu** i nic więcej — sam
  slot jest dziurą w kadłubie i nie waży nic.
- `EngineData` (Resource w `resources/engines/`): `type`, `max_thrust`,
  `bulk`, `spool_time`, `reliability`, `fuel_cost`. To jest loot z M2.
- `EngineInstance`: para (dane, mount) plus `health`, `throttle`,
  `target_throttle`.

Typ opisuje charakter przepustnicy, nie przeznaczenie:

- **MAIN** rozpędza się liniowo, 1/`spool_time` na sekundę, w obie strony.
- **TORQUE** jest impulsowy: chwilowa przepustnica to zawsze 0 albo 1.
- **THRUSTER** odpowiada natychmiast i proporcjonalnie.

### Gabaryt (`bulk`) jako jedyna cena za dopasowanie

Skoro typ nie ogranicza montażu, potrzebna jest cena, inaczej „wszystko pasuje
wszędzie" jest darmowym buffem, a nie decyzją. Tą ceną jest jedna liczba,
`EngineData.bulk`, robiąca dwie rzeczy naraz:

1. **Jest masą**, jaką silnik dokłada do statku — **połową gabarytu**,
   `EngineMount.MASS_PER_BULK`. Nie `size` mountu: slot to dziura, waży to, co
   w niej siedzi. Cięższy silnik przesuwa środek masy i zmienia bezwładność,
   więc czuć go nawet wtedy, kiedy nie pracuje.

   Połowa, a nie mniejszy gabaryt, i to jest cała treść tej stałej. Te dwa
   zadania `bulk` są niezależne, więc odchudzenie silników przez ścięcie
   gabarytu ścięłoby razem z masą **cenę dopasowania** — a ta ekonomia jest
   zmierzona, nie przypadkowa: największe gniazdo bierze 98% losowań,
   najmniejsze 47%, 1,25% nie mieści się nigdzie. Dlatego rozdziela się je
   dokładnie tam, gdzie jest masa, a reguła gniazda dalej czyta liczbę
   nietkniętą.
2. **Musi się zmieścić**: `bulk <= size`, inaczej nie wchodzi.

Whitelista typów dałaby ten sam efekt binarnie i odebrałaby generatorowi
wymiar, na którym może grać. Przy `bulk` reguła „duże silniki idą w duże
gniazda" **wychodzi sama**, a zostaje miejsce na mały, lekki MAIN, który da się
wsadzić w dziób — wtedy jego powolna przepustnica jest świadomym kosztem, a nie
zakazem. Zmierzone na 400 losowaniach: gabaryty 0,31–5,12, największe gniazdo
bierze 98% znalezisk, najmniejsze 47%, a 1,25% nie mieści się nigdzie na tym
kadłubie. To ostatnie jest cechą, nie błędem — to loot na większy statek — ale
ekran wymiany **musi** powiedzieć dlaczego, bo samo „brak gniazda" nie jest
odpowiedzią, na której da się coś zrobić.

Afiksy `compact` (gabaryt w dół, ciąg w dół) i `oversized` (ciąg w górę,
gabaryt w górę) czynią z tego handel wymienny, a nie drabinę.

**Gniazdo głównego napędu ma tyle miejsca, ile wynosi sufit gabarytu w
generatorze** (`ShipFitout.MAIN_DRIVE_SOCKET` = `LIMITS["bulk"]` = 8,0), więc
żaden wylosowany silnik nie jest za duży na gniazdo główne — na żadnym
kadłubie. Powyższe 1,25% „nie mieści się nigdzie" było zmierzone przy
gnieździe 3,5; po obniżeniu masy silników (MAUX4.9) wyszło 2,6% na 40000
losowań, i to zawsze na najlepszych znaleziskach, bo w tabeli afiksów gabaryt
jest **walutą** za ciąg (`oversized`, `buffered`). Gniazdo wyliczone pod
seryjne silniki karę za dobry rzut, więc sufit generatora jest właściwą
miarą — nie największy seryjny silnik.

Kosztu to nie darowuje: gabaryt to masa (`EngineMount.MASS_PER_BULK`), masa to
ciąg na kilogram i przesunięty środek masy. Małe gniazda zostają jak były
— obrotowe 0,8, strafe 1,0, dziobowe wsteczne 2,5 — więc `compact` nadal ma
gdzie znaczyć, a ekran wymiany nadal ma czego odmawiać.

**Gabaryty statku testowego są dobrane tak, żeby środek masy wypadł dokładnie
na krzyżu dysz obrotowych.** Warunek redukuje się do jednego równania, bo dysze
obrotowe i para strafe leżą symetrycznie względem `y = 1.75` i wypadają z
sumy:

    8.25 * bulk_main - 13.75 * bulk_retro = -11.0

Stąd `bulk_main = 2.5` i `bulk_retro = 2.3`, mounty zostają na okrągłych
pozycjach, a `com` wypada na 1.75 co do cyfry.

**Prawa strona to −11,0, nie −5,5, odkąd silnik waży połowę gabarytu.** Moment
silników skaluje się ze stawką, moment kadłuba i komor nie, więc równowaga
między nimi się przesuwa — i to jest dokładnie ten sposób, w jaki ta sekcja
może się zepsuć po cichu. Pierwsze podejście zostawiło stare gabaryty: masa
spadła z 20,00 na 15,70, `com` wylądował na 1,925 — **0,175 od krzyża** — i
test wypisał siedem porażek, w tym 6,7 N siły bocznej na obrocie i 0,42 px/s
dryfu z nienaruszonej pary. Dokładnie to, co ten akapit obiecuje.

Przy połowie stawki samo retro problemu nie rozwiązuje: potrzebowałoby 2,600
gabarytu przy gnieździe 2,50, czyli nie wchodzi. Drążek jest po stronie
głównego napędu i para 2,5 / 2,3 rozwiązuje równanie dokładnie, zostawiając
główny napęd największym silnikiem na kadłubie.

Po zmianie: masa 20,00 → **15,50**, bezwładność 1368 → **792**, przyspieszenie
wprzód 45,0 → **58,1**, `com` dalej 1,75. Pierwsze podejście —
gabaryty „na oko" i przesunięcie mountów za środkiem masy — natychmiast
złamało parę obrotową (wagi 1,00 i 0,82, 0,046 N siły bocznej na obrót) i
zostało złapane przez istniejący test. Loot **będzie** tę równowagę psuł i o to
chodzi; statek fabryczny ma z niej startować.

### Działa i mody nie ważą nic, i to jest decyzja

Przez długi czas było to przeoczenie: `_recompute_mass_properties()` sumuje
kadłub, silniki, ładunek, komory i podwozie, a **hardpointów nie ma na tej
liście w ogóle**. Makieta edytora zanotowała przy okazji „MODS DO NOT IMPACT
MASS AT ALL" — co było już prawdą, ale z szerszego powodu, niż notatka mówiła:
nie ważył ani mod, ani sama broń.

Zostaje tak, świadomie. Cena zmiany została zmierzona i jest wysoka w jednym
konkretnym miejscu: autocannon na `NoseHardpoint` (0; −14,0) ma gabaryt 1,00,
więc ważony 1:1 przesunąłby `com` o **0,75** z krzyża dysz obrotowych. Powrotu
nie da się kupić retro — potrzebowałoby 2,60 przy gnieździe 2,50 — ani głównym
napędem, który musiałby mieć 4,91 przy gnieździe 3,5. Czyli każde ważenie dział
wymaga **przesunięcia mountu albo trzeciej dźwigni**, a nie przeliczenia jednej
liczby.

Co to kosztuje: `bulk` na broni znaczy mniej niż na silniku — miejsce w
ładowni i dopasowanie do gniazda, ale nie prowadzenie. Karta broni mówi
„gabaryt" i jest to półprawda. Warto to wiedzieć, zwłaszcza że panel faktów w
edytorze wyciągnął masę i przyspieszenie na wierzch.

Rozważane i odrzucone: stawka jak dla ładunku (0,35 — przesunięcie 0,27, dalej
poza krzyżem) i liczenie masy działa **w punkcie środka masy**, czyli tak, jak
robi to ładunek (`CARGO_BAY` = (0; 1,75) stoi w punkcie równowagi właśnie po to,
żeby ładowanie nie ruszało `com`). To drugie jest tanie i ma precedens w tym
samym pliku; leży na półce na wypadek, gdyby masa broni kiedyś zaczęła być
potrzebna.

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

### Raport konfiguracji

Zamontowanie modułu zmienia naraz masę, środek masy i każdą grupę sterowania,
a ciekawe awarie to nie „jest gorzej", tylko **„jest krzywo"**: obrót, który
spycha statek w bok, strafe silniejszy w jedną stronę, kierunek bez niczego za
sobą. Żadnej z nich nie widać w locie, dopóki pilot już z nią nie walczy.

`ConfigurationReport.of(ship)` to **migawka**, nie widok — trzyma liczby, z
których powstał, więc raport sprzed wymiany da się porównać z tym po. Sprawdza
trzy rzeczy:

- **Pusta grupa** — kierunek, za którym nie stoi żaden silnik. Zawsze FAULT.
- **Para obrotowa, która nie znosi własnych sił.** Zgłaszane jako
  **przyspieszenie, nie niutony** (`residual / masa`, px/s²): to jest ta część,
  którą pilot czuje, i zostaje porównywalna między statkami o różnej masie.
  Progi 1 px/s² (WARN) i 5 px/s² (FAULT) warto zestawiać z grawitacją
  powierzchniową ~30 px/s²: cały obrót przy 1 to szturchnięcie, przy 5 to dryf,
  z którym trzeba latać.
- **Lustrzane pary** (STRAFE_LEFT/RIGHT, CCW/CW) różniące się siłą: słabszy do
  silniejszego poniżej 0,8 to WARN, poniżej 0,5 FAULT. **Tylko lustrzane** —
  statek z dużym silnikiem głównym i małym cofającym jest normalny, nie zepsuty,
  więc FORWARD i BACK nigdy nie są zestawiane ze sobą.

`compare(before)` daje **różnice**, nie stan: kierunki, których autorytet się
ruszył o ponad 5%, i usterki, **których poprzednia konfiguracja nie miała**.
Istniejąca usterka nie jest winą właśnie montowanego modułu i powtarzanie jej
obwiniałoby niewłaściwą część. Moduł, który nie zmienia nic wartego nazwania,
nie produkuje żadnej linijki — ekran mówi to wprost, zamiast wymyślać
pocieszenie.

Raport powstał po zepsuciu dokładnie tego przy strojeniu gabarytów: środek masy
przesunął się o 0,8 px, para obrotowa poszła na wagi 1,00 i 0,82, każdy obrót
zostawiał boczne pchnięcie. Złapał to test, bo istniał; pilot wymieniający
silnik testu nie ma.

**I właśnie ten przypadek raport przemilcza — słusznie.** 0,046 N na 13,9 kg to
0,003 px/s², trzysta razy poniżej progu ostrzeżenia. To nie jest luka, tylko
podział pracy: test pilnuje **niezmiennika projektowego** i ma prawo żądać
dokładności co do zera, bo asymetria, której dziś nie czuć, jutro urośnie wraz
z modułem. Raport mówi pilotowi, **co poczuje**, i wypisanie mu dryfu tysiąc
razy słabszego od wiatru nauczyłoby go tylko ignorować raport. Dwie różne
robotę, dwa różne progi — i gdyby raport miał próg testu, byłby bezużyteczny,
a gdyby test miał próg raportu, nie złapałby niczego.

### Asysty na akordach: dwa modyfikatory, sześć funkcji

`Q`+`E` i `W`+`S` to dwie pary, które się znoszą, więc obie są wolnymi
modyfikatorami, a czwarty klawisz wybiera funkcję:

| akord | funkcja |
|---|---|
| `Q+E+W` / `Q+E+S` | dziób na kierunek lotu / przeciwnie |
| `Q+E+D` / `Q+E+A` | auto-orbita / auto-poziom |
| `W+S+A` / `W+S+D` | hold wysokości / deorbit |

Sześć funkcji komputera lotu bez ani jednego nowego klawisza.

**Klawisz czytany jako naciśnięcie, nie jako trzymanie, nie może być częścią
akordu.** Pierwsza wersja deorbitu siedziała na `Q+E+G`, a `toggle_gear`
obsługiwany jest przez `is_action_just_pressed` poza tłumieniem akordu — więc
podwozie wyskakiwałoby przy każdym deorbicie.

**Hold wysokości jest tłumiony prędkością wznoszenia.** Sama wysokość to
sprężyna, a sprężyna bez tłumienia oscyluje w nieskończoność; asysta musi też
trzymać przeciw grawitacji, inaczej całą siłę zużywa na odkrywanie, że statek
spada.

**Deorbit przestaje, gdy periapsis wejdzie w atmosferę.** Obniżanie dalej
zamienia zejście w uderzenie, a to jest dokładnie ta arytmetyka, która jest
nudna i łatwa do przestrzelenia ręcznie.

### Awarie silników

Trzy rzeczy, wszystkie po to, żeby uszkodzony silnik **zmieniał sposób
latania**, a nie tylko odejmował liczbę.

- **Uderzenie psuje to, w co trafiło.** Solver kontaktów i tak zna najgłębszy
  punkt styku, więc zapamiętuje go we frame'ie statku i obrażenia rozchodzą
  się stamtąd z zasięgiem 16 px (mniej więcej szerokość kadłuba). Lądowanie na
  dyszy jest innym błędem niż lądowanie na dziobie. Mnożnik 1,6 wobec obrażeń
  kadłuba: maszyneria jest kruchsza od konstrukcji, a statek, który zawsze
  ginie przed swoimi silnikami, nie ma modelu uszkodzeń wartego nazwy.
- **Niezawodność jako wypadanie**, liczone **na sekundę, nie na tick** —
  inaczej częstotliwość fizyki decydowałaby, jak zepsuty jest statek. Każdy
  silnik ma własny RNG zasiany nazwą mountu: wspólna losowość kazałaby
  wszystkim dyszom wypaść w tym samym ticku, co czyta się jak zacięcie gry, a
  nie jak awaria jednej maszyny. Ten sam statek psuje się dwa razy tak samo,
  więc zgłoszenie błędu da się odtworzyć.
- **Falowanie ciągu**, deterministyczna sinusoida z fazą na silnik, **nigdy
  powyżej nominału**. Ciąg, który czasem przekracza zadany, byłby premią w
  przebraniu awarii.

**Uszkodzenie zjada też niezawodność**: `reliability * lerp(0.7, 1, health)`.
Rozwalony silnik przy idealnej tabliczce jest wciąż w 70% niezawodny — nie w
zerze, bo silnik, który nigdy nie odpala, to silnik nieobecny, a ciekawa awaria
to ta, która odpala *czasami*.

### Strojenie: kara ma zmieniać lot, nie odbierać statek

Pierwsze wartości były za ostre i to było widać dopiero w graniu. Zmierzone przy
starym strojeniu: przy zdrowiu 0,65 silnik oddawał średnio **0,563** mocy, a z
tych 43,7 punktu straty **35 szło z samego mnożnika `× health`** — wypadanie i
falowanie razem dawały 8,6. Czyli pokrętło, po które sięga się odruchowo
(`RUINED_RELIABILITY`), rusza mniejszą część problemu.

Prawdziwym winowajcą było **tempo psucia**: przy `ENGINE_DAMAGE_SHARE = 1.6`
jedno twarde lądowanie przy 120 px/s zabierało najbliższy silnik do 62% zdrowia,
czyli ~53% ciągu. Jeden błąd wart pół silnika.

Po zmianie — share 0,5, ruined reliability 0,7, i **podłoga ciągu na 70%**:

| zdrowie | średni ciąg | najgorszy tick |
|---|---|---|
| 1,00 | 1,000 | 1,000 |
| 0,65 | 0,866 | 0,700 |
| 0,20 | 0,722 | 0,700 |
| 0,00 | 0,700 | 0,700 |

**Wypadnięcie jest teraz zapadnięciem, nie ciszą.** Podłoga obejmuje też
dropouty: silnik nigdy nie milknie, tylko siada do 70%. Niezmiennik, dla którego
model uszkodzeń istnieje, przeżywa — 70% z jednej strony wobec 100% z drugiej to
nadal krzywy statek.

Podłoga wymusiła jedno uporządkowanie: **`condition_factor()` jest jedynym
miejscem, które zna krzywę zdrowie → ciąg**. Alokator NNLS i raport konfiguracji
mnożyły wcześniej przez surowe `health` i po dodaniu podłogi planowałyby przeciw
silnikowi, który nie istnieje.

**Znaleziony błąd: refit leczył wszystko.** `rebuild_control_groups()` wyrzuca i
odtwarza każdy `EngineInstance`, więc przykręcenie czegokolwiek gdziekolwiek po
cichu naprawiało całą resztę — darmowy warsztat w ekranie wymiany. Kondycja jest
teraz przenoszona przez przebudowę, po nazwie mountu i tylko gdy siedzi w nim
ten sam silnik. Silnik przełożony do innego gniazda wstaje zdrowy — jedyny
przypadek, który to gubi; nazwijmy to czasem na stole.

Znalazł to test, który trzymał nieaktualną referencję po przebudowie i pokazał
wynik 0,600 tam, gdzie spodziewałem się 1,0.

**Raport konfiguracji musiał dostać osobne oczy na kondycję.** Jego własna siła
resztkowa liczona jest z ciągu nominalnego (bo grupy tak są budowane), więc
uszkodzenie nie ruszało w niej nic. Raport liczy teraz drugą resztkę, ważoną
`health`, i wypisuje **tylko nadwyżkę ponad nominalną** — inaczej obwiniałby
uszkodzenie za asymetrię, która była tam wcześniej. Zmierzone na statku z dyszą
na 60%: `damage makes CW push sideways at 3.9 px/s2`.

### Sandbox (`T`) i to, co od razu znalazł

Większości z M2 nie da się ocenić inaczej niż lotem, a losowanie aż wypadnie
gimballed drive nie jest testowaniem gimbala. Narzędzie spawnuje dowolny moduł
**przez prawdziwy generator** — narzędzie, które umie wyczarować przedmiot
niemożliwy, testuje grę, w którą nikt nie zagra — i podmienia kadłub na jeden
z sześciu presetów ze skalą.

Presety są rozrzutem, nie zestawem ładnych statków: długi cienki i szeroki
płaski psują się inaczej, a chodzi o to, żeby się dowiedzieć jak. Jeden
(`sliver`) jest celowo zły i raport ma go za takiego uznać.

Znalazł dwie rzeczy w pierwszym przebiegu:

- **Masa kadłuba była stałą 6,0 niezależnie od kształtu.** Cegła o czterokrotnie
  większej powierzchni ważyła dokładnie tyle co stockowy trójkąt. Przechodziło
  niezauważone, dopóki istniał jeden kadłub. Teraz masa to pole × gęstość, a
  gęstość dobrana tak, żeby stockowy obrys nadal wychodził na 6,0 — więc nic,
  co było pod niego strojone, się nie rusza.
- **`_hull_polygon()` czytał kształt kolizji, nie obrys.** Kształt jest *pochodną*
  obrysu, więc czytanie go w pierwszej kolejności było czytaniem kopii i
  rozjeżdżało się w chwili, gdy obrys zmienił się bez przebudowy.

Ostrzeżenia „obrót spycha statek w bok" przy każdym przebudowanym kadłubie **nie
są błędem** — to udokumentowana konsekwencja z sekcji 3: zmiana obrysu przesuwa
środek masy, a krzyż dysz zostaje na miejscu i para przestaje się znosić. Nowy
kadłub potrzebuje mountów dobranych pod siebie i raport mówi to wprost.

**Rysunek podąża za kształtem tylko w sandboxie.** W grze kadłub rysowany i
liczony to dwie różne rzeczy (sekcja 6); w narzędziu trzymane są razem, bo
inaczej przebudowa kształtu nie byłaby widoczna.

### Komputer lotu: rozdział ciągu przez najmniejsze kwadraty

Heurystyka wag sortuje silniki do grup po tym, jak czysto każdy pcha wzdłuż
komendy. To dobra odpowiedź dla symetrycznego statku w dobrym stanie i zła
poza tym: grupy budowane są z ciągu **nominalnego** i stałych udziałów, więc
półmartwa dysza dostaje pełny przydział, dostarcza mniej niż jej partnerka, i
statek obraca się, ślizgając w bok.

`ThrustAllocator` zadaje właściwe pytanie: każdy silnik dokłada znane
przyspieszenie, więc znajdź przepustnice najbliższe temu, o co poproszono, przy
ograniczeniu, że przepustnica jest między niczym a wszystkim. Czyli
`min |A t − b|`, `t ∈ [0,1]` — ograniczone najmniejsze kwadraty, nieujemne, bo
silnik nie umie ssać.

**Rzut gradientu, nie Lawson-Hanson.** Przy kilku silnikach zbiega w stałej,
małej liczbie przebiegów, każdy przebieg to ta sama arytmetyka i nie ma zbioru
aktywnego, który mógłby się zepsuć. Stały koszt na tick jest tu wart więcej niż
ostatnie miejsce po przecinku optymalności. Krok z górnego ograniczenia stałej
Lipschitza przez ślad `AᵀA` — luźne, co znaczy tylko, że kroki są ostrożne.

**Kondycja wchodzi przy rozwiązywaniu, nie przy przebudowie.** Kolumny są
nominalne (bo grupy takie są), a `health` mnoży je dopiero w solverze — inaczej
komputer kompensowałby uszkodzenie już na etapie, na którym z założenia nikt go
nie kompensuje.

Zmierzone na statku z dyszą pary obrotowej na 45%: **siła boczna przy obrocie
88 N → 36 N**, moment nadal 955 N·px. Na zdrowym statku bez zmian — moduł ma
być awansem, nie wymianą.

### Auto-orbit: obróć się na wektor, potem pal

Pierwsza wersja pchała po prostu w stronę korekty i nie zbiegała (rozrzut 55%).
Powód jest fizyczny: ciąg kadłuba jest skrajnie anizotropowy — **900 N z dziobu
wobec 290 N w bok** — więc asysta pchająca tym, co akurat wskazuje właściwą
stronę, ledwo ruszała orbitę.

Teraz obraca dziób na wektor korekty i pali dopiero przy zgodności powyżej 0,92.
To jest to, co robią prawdziwe autopiloty, i to jest to, co zbiega: elipsa 32%
schodzi do **1,1% rozrzutu**.

Asysty jeżdżą na akordach `Q+E+D` (orbita) i `Q+E+A` (poziom). `Q` i `E` są
modyfikatorem, czwarty klawisz wybiera funkcję — dlatego to się skaluje:
komputer ma jeszcze długą listę rzeczy do powiedzenia i żadna nie potrzebuje
własnego klawisza.

### Hamowanie poza grawitacją planety: ten sam wniosek, drugi raz

Hamulec ma dwa tryby, a granicą jest sfera wpływu planety.

**Pod planetą zostaje stary**: rozkład prędkości na osie, obrót nietknięty.
Nie z przyzwyczajenia — nisko dziób ma inną robotę, trzyma postawę nad terenem
i ustawia lądowanie, a hamulec, który by go z niej zabrał, byłby zagrożeniem.
Nisko i wolno słabsze silniki też wystarczają.

**Poza sferą wpływu statek obraca się retrograde i pali główny napęd.** Powód
jest ten sam, co przy auto-orbicie, i to jest ta sama anizotropia policzona
drugi raz: **900 N z dziobu wobec 500 N wstecz i 262 N w bok**. Hamowanie tym,
co akurat wskazuje właściwą stronę, oddaje dwie trzecie statku.

Zmierzone na stokowym kadłubie, 100 px/s do zera: po skośnej **6,1 s** zwrotem
i wypałem przeciwko **6,5 s** starym hamulcem, w bok **5,7 s**, a na wprost z
dopalaniem **3,4 s**. Zysk przy stu pikselach jest skromny i trzeba to powiedzieć
wprost: zwrot kosztuje około dwóch sekund stałego narzutu, a przy tej prędkości
prawo proporcjonalne (przyspieszenie równe prędkości, stała czasowa sekundy)
i tak rządzi końcówką. **Zysk rośnie z prędkością**, bo narzut jest stały,
a przewaga ciągu jest ilorazem: boczny hamulec nasyca się dopiero przy 13 px/s,
główny przy 45, więc z 1000 px/s to około 75 s przeciwko 21 s plus zwrot. To są
prędkości międzyplanetarne, czyli dokładnie te, dla których ten tryb istnieje.

Kolejność wymusza **bramka zgodności 0,98** (jedenaście stopni), ciąższa niż
0,92 auto-orbity: tamta asysta poprawia orbitę przez minuty i może zacząć pchać
w trakcie obrotu, a to jest klawisz, który pilot trzyma, kiedy chce, żeby
prędkość zniknęła. Utrzymanie kursu siada w granicy półtora stopnia, więc
bramka otwiera się raz i zostaje otwarta.

**Dopalanie nie wymagało ani jednej linijki.** Trzymany klawisz mnoży to, czego
przepustnice już żądają, a w trakcie wypału żąda ich główny napęd. Test to
sprawdza, zamiast zakładać.

Dwa przypadki brzegowe, oba znalezione przez test, nie przez myślenie:

- **Dryf poniżej 8 px/s idzie starym hamulcem.** Pierwsza wersja goniła
  znikający wektor: po zatrzymaniu silnik główny jeszcze schodzi z ciągu
  (`spool_time` 0,6 s), spycha statek w drugą stronę, prędkość wraca ponad próg
  i statek obraca się o 180° za trzema pikselami na sekundę. Asercja „kończy
  dziobem wzdłuż własnego toru" złapała to jako 0,281 zamiast 1,000. Próg jest
  ten sam, którego używa utrzymanie kursu, i z tego samego powodu: poniżej
  niego kierunek ruchu przestaje być kierunkiem.
- **Kadłub bez autorytetu obrotowego zostaje przy starym hamulcie.** Nie umie
  się obrócić, więc alternatywą byłoby niehamowanie w ogóle.

### Marker nawigacyjny: jedna szpilka, trzymana statycznie

Prawy klik na mapie wbija szpilkę, prawy klik na szpilce ją wyjmuje, prawy klik
gdzie indziej ją przenosi. **Jeden przycisk na trzy rzeczy, bo to jeden gest** —
lista wymagałaby sposobu na powiedzenie, którą się ma na myśli, czyli drugiego
gestu do wymyślenia i drugiej rzeczy do rysowania. Kiedy będzie powód na dwie,
będzie też powód, żeby je nazywać, i to jest inna funkcja.

Zapamiętany jest **punkt w świecie**, nie na mapie: szpilka musi przeżyć zmianę
zoomu, obrót widoku, zamknięcie mapy i ćwierć okrążenia układu, zanim wróci
w kadr. `SystemMap.from_map()` jest napisane jako **dokładna odwrotność**
`to_map()`, żeby zmiana w jednym bez drugiego pokazała się jako niedomknięty
obieg w teście, a nie jako szpilka w złym miejscu u pilota.

Na skanerze szpilka jest **zawsze**, i to jest różnica wobec planety: planeta
przestaje być znaczona, kiedy widać ją na ekranie, bo wówczas znacznik pokazuje
to, co pilot i tak widzi. Szpilka to miejsce, nie obiekt — wskaźnik, który
znika w chwili dolotu, zawodzi dokładnie tam, gdzie był używany. Poza ekranem
siedzi na pierścieniu z odległością, na ekranie leży na samym miejscu.

**Stan jest statyczny (`NavMarker`), nie na autoloadzie `Galaxy`** — i to
zmierzone, nie wybrane: autoload nie istnieje w biegu `godot --script`, więc
mapa albo skaner czytające `Galaxy` to mapa albo skaner, których test nawet nie
skompiluje. Probe to potwierdził (`Identifier not found: Galaxy`) zanim kod
poszedł dalej. To jest ta sama reguła, co bramki prezentacji: stan, który czytają
przyrządy, musi być osiągalny z testu headless, albo przyrządy nie mają testów.
`Palette` trzyma swoją wczytaną kopię tak samo.

**Kolor nie jest nowy.** Pierwsza wersja miała własną magentę i test paleta
ją wyrzucił: UI_STYLE mówi, że ekrany nie trzymają własnych kolorów, a w palecie
rola już była — `caution` to „uwaga, wybór kursora”, a szpilka jest niczym
innym. Trzynasty kolor na rolę, która ma swój, to dokładnie ten błąd, przed
którym paleta ma chronić. Rozróżnia kształt: trójkąt to ciało, romb to łup,
krzyżyk to szpilka.

Przeskok między systemami ją **wyrzuca**, bo zapamiętane są piksele układu, a te
same liczby nad inną gwiazdą to szpilka w złym miejscu — gorzej niż jej brak.
Misjumpy idą tą samą drogą (`crossed` z −1), więc jest jedno miejsce, gdzie to
się dzieje. Zapis ją niesie, czytany z wartością domyślną zamiast podbicia
wersji: pole, którego ktoś nie miał, to pole, które się domyślnie wypełnia, a
podbicie wersji wyrzuciłoby każdy istniejący zapis dla jednej szpilki.

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
    F7 / O  warstwa debug      F6 / P  konfigurator planety
    F5 / K  uszkodź dyszę      C  krater

Każdy klawisz debugowy ma wariant literowy obok funkcyjnego, i to nie jest
wygoda. Edytor Godota od 4.4 domyślnie osadza uruchomioną grę we własnej
zakładce (`game_embed_mode = Auto`), a tam F5 do F8 zostają skrótami edytora i
nie docierają do gry. Klawisz debugowy związany wyłącznie z funkcyjnym bywa
więc nieosiągalny w tym samym projekcie, zależnie od tego, czy gra chodzi w
osadzonym oknie, czy w osobnym.

Awarie silników pochodzą ze zderzeń, zużycia i ataków. Awaria to zmiana `health`,
nic specjalnego w silniku fizycznym.

## 4. Broń i loot

Broń montowana w hardpointach statku (pozycja, kąt, dopuszczalne typy).

Typy: laser (hitscan), projectile, dumb missile, homing missile, AoE (różne), pulse. Kilka klas bazowych pocisków, reszta to dane.

Definicja broni jako Resource: typ, obrażenia, kadencja, rozrzut, zasięg, prędkość pocisku, koszt energii, lista afiksów. Generator losuje z tabel rzadkości i modyfikatorów w stylu Borderlands: bazowy szablon plus 0..N afiksów, rzadkość podnosi liczbę i siłę afiksów.

To samo podejście dla silników, skanerów, napędów skokowych i baków: każdy moduł statku jest lootem z parametrami.

Koszt energii, generator i moduły wpinane w samą broń mają własną sekcję 14:
kadencja mówi, jak szybko broń strzela, a energia mówi, jak długo.

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

### Realizacja (M2: broń jako Resource)

`WeaponData` powtarza podział, który sprawdził się przy silnikach: Resource
trzyma liczby, `Hardpoint` trzyma pozycję i kąt. Przełożenie broni na inny
montaż zmienia, gdzie celuje, i nic poza tym.

Decyzje warte zapisania:

- **Scena pocisku należy do broni, nie do hardpointu.** Montaż nie decyduje,
  czy strzela slugami, czy rakietami. Dzięki temu `Type.HOMING_MISSILE` będzie
  później po prostu inną sceną w tym samym polu.
- **Zasięg w pikselach, nie czas życia w sekundach.** Zasięg jest tym, co pilot
  ocenia, i tym, co afiks powinien zmieniać: pocisk lecący szybciej ma sięgać
  dalej, a nie żyć tyle samo sekund. `lifetime()` wylicza się z zasięgu i
  prędkości.
- **Afiksy są wpalone w liczby przy generacji**, a nie nakładane w locie jako
  modyfikatory. Wylosowany przedmiot już się nie zmienia, więc obok wartości
  musi przetrwać tylko lista nazw do wyświetlenia.
- **Lista dopuszczalnych typów jest na montażu** (`accepts`), pusta znaczy
  „dowolny". Sprawdzenie siedzi w `Hardpoint.can_fit()`, a nie w generatorze,
  żeby znalezioną broń dało się skonfrontować ze statkiem, który ma ją unieść.
- **`fit()` oddaje poprzednią broń**, więc wymiana modułu w locie nie potrzebuje
  osobnego kodu na „co zrobić ze starym".

Dwie bronie startowe są celowo przeciwstawne, żeby loot miał czym się różnić i
żeby testy miały co porównywać: autocannon 0.08 × 4/s (13 strzałów na kadłub,
0.32 dps) i siege slug 0.30 × 1/s (4 strzały, 0.30 dps, krater 30 px zamiast
14). Większe obrażenia na strzał **nie** dają większego dps — kupuje się za nie
przebicie i zasięg.

### Loot czyta tier: pochylenie tabeli, nie podłoga pod rzutem

Premisa w jednym pomiarze: **to samo ryzyko kupuje więcej, im głębiej się je
podejmie.** Tier wchodzi jako stan generatora, nie jako argument każdego
wejścia — jest ich dziewięć i każde rosłoby o parametr, który każdy wywołujący
musi pamiętać, a ten, który zapomni, po cichu rzuciłby rimowy loot w rdzeniu.
Świat ustawia go przy przylocie z **pozycji**, nie z indeksu systemu
(`tier_at()`, nie `tier_of()`), żeby misjump w ciemność między dwoma systemami
rdzenia dalej był rdzeniem.

**Pochylenie, nie podłoga.** Podłoga skasowałaby pospolite z rdzenia, a reguła z
sekcji 4 mówi, że rzadkość nie znaczy „ściśle lepszy" — rzadki przedmiot jest
bardziej *skrajny*, nie jednostajnie wyższy. Zabranie pospolitych zabrałoby
poziom odniesienia, względem którego czyta się skrajności. Wagi mnożą się więc
przez `TIER_LIFT^rung` raz na stopień rzadkości, co zostawia każdy stopień
możliwym i zmienia tylko to, jak często wypada.

Zmierzone, 40000 rzutów na tier:

| tier | pospolity | niepospolity | rzadki | epicki | legendarny |
|---|---|---|---|---|---|
| 1 | 54,8% | 26,9% | 13,1% | 4,2% | 1,0% |
| 3 | 47,9% | 28,1% | 16,1% | 6,1% | 1,8% |
| 5 | 40,7% | 28,3% | 19,2% | 8,8% | 3,0% |
| 7 | 33,3% | 27,3% | 22,5% | 11,7% | 5,2% |
| 10 | 22,6% | 24,3% | 25,7% | 17,5% | 9,8% |

Na obrzeżu tabela jest **nietknięta** — rim jest odniesieniem, czyli tym, co
jest wypisane w stałej. W rdzeniu legendarny wypada dziesięciokrotnie częściej,
a najczęstszą rzeczą, jaką zrzuca świat, jest **rzadki, nie pospolity**. Ta
inwersja jest cechą: stary test „rzadkość przerzedza się w górę" dotyczy teraz
jawnie obrzeża i tylko jego.

W przeliczeniu na skrzynkę (trzy przedmioty): 159 skrzynek na 1000 trzyma coś
epickiego lub lepszego na obrzeżu, **598 na 1000 w rdzeniu**.

### Realizacja (M2: LootGenerator)

Bazowy szablon plus 0..4 afiksy, wszystko z jawnego seeda — ta sama skrzynka
zawsze trzyma to samo, także po przeładowaniu gry.

**Rzadkość nie znaczy „lepszy".** Mocne afiksy mają koszt wpisany w tabelę:
`heavy` podnosi obrażenia i obniża kadencję, `rapid` odwrotnie, `overbored`
kupuje ciąg za niezawodność. Rzadki przedmiot jest więc **bardziej skrajny**, a
nie jednostajnie lepszy, i to pilot decyduje, czy to dla niego awans. Loot
sprowadzony do jednej skali to rosnąca liczba, nie wybór. Pilnuje tego test na
poziomie tabeli: każdy afiks z kosztem musi ruszać pole w niekorzystną stronę
(kierunki są w `HIGHER_IS_BETTER`, które przyda się też raportowi konfiguracji).

**Siła rzadkości to wykładnik, nie mnożnik.** Współczynnik poniżej 1 skalowany
liniowo przechodzi przez zero — przy sile 1.75 afiks `precise` (0.40) dałby
rozrzut −0.05. `pow(rolled, strength)` zostaje po właściwej stronie zera
niezależnie od tego, jak bardzo podniesiemy rzadkość.

**Granice domykane są na całym przedmiocie, nie tylko na polach ruszonych
przez afiks.** Powód wyszedł z testu: thrustery mają w bazie `spool_time = 0`,
bo ich typ ignoruje to pole, więc gotowy przedmiot wypadał poza deklarowany
zakres mimo poprawnego skalowania. Niezmiennik z przypisem jest niezmiennikiem,
którego nikt nie sprawdzi — teraz brzmi po prostu „wylosowany przedmiot mieści
się w granicach" i 800 losowań to potwierdza.

Wagi: 55 / 27 / 13 / 4 / 1. Zmierzone na 4000 losowań: 2161 / 1077 / 540 / 178 / 44.

Uwaga praktyczna: smoke test chodzi jako `--script`, gdzie **autoloady nie
istnieją**, więc sięga po generator przez `preload` i tworzy własną instancję.

### Realizacja (M2: skrzynki i wymiana w locie)

Pętla „znajdź, zamontuj, poczuj różnicę" domyka się po raz pierwszy, więc
decyzje o jej kształcie:

- **Skrzynki stoją na półkach do lądowania**, nie są rozrzucone losowo. Półki
  generator i tak buduje jako miejsca do lądowania, więc loot i lądowanie
  ciągną w tę samą stronę, zamiast kazać pilotowi siadać na klifie. Skrzynka
  jest dzieckiem planety, więc jeździ z gruntem i nie wymaga liczenia niczego
  co klatkę.
- **Rzadkość jedzie na module, nie obok niego.** Pierwotnie szła osobno, z
  argumentem „rzadkość to fakt o losowaniu, nie o maszynie" — prawdziwym i
  kosztownym: skrzynka, ładownia, cargo i edytor trzymały każde własną kopię,
  a sandbox stemplował każde znalezisko jako `rare`, bo jedna z tych kopii była
  zahardkodowaną stałą. Argument nie miał gdzie mieszkać, dopóki nie było
  wspólnej klasy bazowej; `ModuleData` jest nią teraz, więc `rarity` siedzi tam
  razem z nazwami i kolorami.

  Kolory (`ModuleData.RARITY_COLORS`): common `#8c9199` blado szary,
  uncommon `#d9e3f0` srebrny, rare `#599eff` niebieski, epic `#b86bff`
  fioletowy, legendary `#ffcc47` złoty. Sąsiednie stopnie muszą się dać
  odróżnić na ośmiopikselowej kropce i to jest pilnowane testem — najciaśniejsza
  para (rare/epic) ma 0,57 rozjazdu przy progu 0,35.

- **Skrzynka trzyma wylosowany przedmiot, nie obietnicę losowania.** Seed jest
  wydawany przy budowie świata, więc ta sama planeta zawsze oferuje te same
  znaleziska w tych samych miejscach. Rzadkość jedzie obok przedmiotu, bo ani
  `WeaponData`, ani `EngineData` jej nie nosi — rzadkość jest faktem o
  losowaniu, nie o module. Kolor pudełka to jedyne, co widać z orbity.
- **Ładownia ma jedno miejsce.** Pełna ładownia odmawia przyjęcia następnego
  znaleziska zamiast je gubić, więc ekran wymiany to zawsze jedna decyzja, a
  nie zarządzanie ekwipunkiem. Wymiana wkłada zdjęty moduł do ładowni, więc
  nic nie przepada i można się wycofać.
- **Ekran nie pauzuje gry.** „W locie" znaczy bez lądowania i dokowania, a nie
  bez upływu czasu; wymiana, która zatrzymuje świat, jest menu, a ciekawa
  wersja tej decyzji to ta podejmowana, kiedy coś już idzie nie tak. Panel
  jest mały, w rogu, każda akcja to jeden klawisz (Tab / strzałka w dół / F /
  Backspace). Przy okazji unika to pułapki, w którą wpadł konfigurator: dwa
  panele pauzujące grę to dwa sposoby na pozorną awarię klawiatury.
- **Montaż silnika przebudowuje grupy sterowania.** Inaczej silnik nie byłby
  lootem, tylko dekoracją: zmierzone w teście, dwukrotnie mocniejszy silnik
  podnosi autorytet FORWARD z 900 na 1800.

### MAUX1: edytor statku

Prototypowy ekran (klawisz `I`), na którym widać cały statek naraz. Kilka
decyzji, które nie są oczywiste:

- **Jedna jednostka na wszystko.** `bulk` jest teraz i na silnikach, i na
  broni, więc cargo mierzy pojemność jedną liczbą. Dwie jednostki znaczyłyby
  tabelę przeliczeń w kodzie i drugą liczbę do nauczenia dla pilota.
- **Cargo to pojemność, nie sloty.** „Czy to zabrać" staje się pytaniem o
  maszynę, a nie o wolną kratkę, a ładunek jest masą: 4 gabaryty w luku to
  statek 14,6 → 18,6 kg i wyraźnie leniwszy.
- **Luk cargo siedzi na środku masy pustego statku** (0, 1.75). Gdziekolwiek
  indziej ładowanie byłoby jednocześnie usterką wyważenia, a raport
  konfiguracji marudziłby za każdym razem, gdy gracz coś podniesie — i
  nauczyłby go ignorować raport. Ładunek ma być czuć jako ociężałość, nie
  jako ostrzeżenie.
- **Schemat jest generowany** z wielokąta kolizji kadłuba i pozycji mountów —
  z tych samych danych, na których statek lata. Ręcznie narysowany byłby
  nieprawdziwy w chwili, gdy ktoś przesunie mount; krzyż dysz obrotowych
  przesunął się dwa razy w trakcie prac nad `bulk`.
- **Nazwy gniazd idą na zewnątrz kadłuba.** Do środka spotykają się na osi i
  obie połowy każdej lustrzanej pary drukują się jedna na drugiej — widać to
  było na pierwszym zrzucie.
- **Panele są w pełni nieprzezroczyste.** Przy 0,95 tekst debug overlay
  przebijał się czytelnie: pięć procent jasnej zieleni na prawie-czerni jest
  dwa razy jaśniejsze niż sam panel.
- **Patrzeć można zawsze, zmieniać tylko na ziemi.** Ekran otwiera się
  wszędzie, bo planowanie refitu w drodze do domu jest sensowną rzeczą do
  robienia, ale przykręcenie modułu wymaga wylądowania — i to daje lądowisku
  powód istnienia inny niż „miejsce, gdzie się nie ginie". Wyrzucanie za burtę
  zostaje dostępne w locie: zrzucenie balastu pod presją to dokładnie ta
  decyzja, o którą chodzi. Ekran nie odmawia otwarcia — mówi, na czym stoisz.
- **Podgląd skutku przed montażem** liczy się przez montaż na próbę: wkręć,
  zmierz, odkręć. Rzecz, która musi być prawdziwa przede wszystkim, to że
  **zadanie pytania niczego nie zmienia** — i to jest osobna asercja w teście.
  Silniki porównywane są przez grupy sterowania (bo to mount decyduje, do
  czego silnik służy), broń przez własne liczby wobec tej już w gnieździe (bo
  ten sam pistolet jest tym samym pistoletem, gdziekolwiek go przykręcić).
  Wynik jest cache'owany na wyborze, nie liczony co klatkę.
- **Ekran pauzuje, szybka wymiana na Tab nie.** To dwa różne pytania zadawane
  pod różnym ciśnieniem: Tab to jedna decyzja w locie, edytor to przegląd. W
  wersji docelowej edytor ma być dostępny tylko po wylądowaniu — dziś otwiera
  się wszędzie, bo jest prototypem do testów.

**Wyrzucanie tworzy prawdziwą skrzynkę** z chwilą nietykalności (2 s). Bez
niej statek stojący nad zrzuconym modułem podnosi go w tej samej klatce, czyli
wyrzucanie jest operacją pustą. Odwracalne wyrzucenie to decyzja taktyczna
(„zrzucam balast, wrócę"); nieodwracalne to tylko sprzątanie ekwipunku.

### Pauza jest roszczeniem, nie flagą

Każdy ekran, który pauzuje, chce też zabezpieczenia przed zostawieniem gry
zapauzowanej bez niczego na ekranie — zapauzowane drzewo przestaje dostarczać
wejście i wygląda dokładnie jak martwa klawiatura. Oczywiste zabezpieczenie
brzmi: „jeśli mój panel jest zamknięty, a drzewo zapauzowane, odpauzuj".

**Jest poprawne przy jednym takim ekranie i destrukcyjne przy dwóch.**
Konfigurator planety wykonywał je co klatkę i zwalniał pauzę, którą właśnie
wziął edytor statku. Efekt: edytor otwierał się nad działającą grą, a statek
spadał z nieba, patrząc na własny schemat. Objaw był banalny („baner mówi
w locie, choć wylądowałem"), przyczyna nie.

`PauseGate` robi z pauzy **roszczenie trzymane przez nazwanego właściciela**;
gra rusza dopiero, gdy ostatnie zostanie zwolnione, i każdy ekran zwalnia
wyłącznie swoje. Statyczny stan, nie autoload — musi działać też w smoke
teście, a autoloady nie istnieją pod `--script`.

Morał ogólniejszy: **kod obronny, który sprząta po cudzych**, jest agresją
udającą ostrożność. Zabezpieczenie ma cofać własne skutki, nie wszystkie
znalezione.

### Kadr należy do pilota

Trzy poziomy zoomu (`+` / `-`) i obracanie widoku strzałkami, z `H` jako
wyjściem awaryjnym.

- **Poziomy mnożą krzywą prędkości, nie zastępują jej.** Odjazd kamery przy
  dużej prędkości istnieje po to, żeby było widać, dokąd się leci, i to jest
  prawdą niezależnie od wybranego kadru. Środkowy poziom to 1.0, więc kamera,
  której nikt nie dotknął, zachowuje się dokładnie jak wcześniej.
- **Obrót jest akumulowany, nie zawijany** do −π..π. Wygładzanie `Camera2D`
  interpoluje do wartości `rotation`; wartość skacząca z 6,2 na 0,1 posłałaby
  widok dookoła. `level_view()` dodaje `angle_difference`, więc zawsze idzie
  krótszą drogą — i to jest testowane jako *rozmiar ruchu*, nie rozmiar wyniku.
- **`H` kładzie planetę na dole**, a w pustce prostuje widok. Jedno wyjście z
  obrotu, którego pilot już nie chce, i zarazem kadr, którego i tak będzie
  chciał przy podejściu. Wzór jest ten sam, którego używa lądowanie do
  postawienia statku na nogach (`up.angle() + PI/2`), żeby „góra" znaczyła w
  tej grze jedną rzecz.
- **`ignore_rotation` musi być `false`**, inaczej Godot w ogóle nie stosuje
  obrotu węzła do widoku — i ignoruje przy okazji `rotation_smoothing_*`.
  Wygładzanie jest więc silnikowe, nie ręczne.

**Starfield nie obracał się sam** — jest na `CanvasLayer` w przestrzeni ekranu.
Shader dostał `view_rotation`, ale pierwsza wersja brała środek obrotu ze
skryptu i była o połowę za mała: `FRAGCOORD` jest w pikselach bufora
(1280x720), a `get_visible_rect()` przy rozciąganiu `canvas_items` zwraca bazowe
640x360. Sky obracało się wokół punktu w jednej czwartej ekranu, co zmieniało
gwiazdy, ale nie wyglądało jak obrót. Środek liczy się teraz z
`SCREEN_PIXEL_SIZE` wewnątrz shadera, gdzie nie ma jak się rozjechać.

Sprawdzone pomiarem, nie okiem: dwie klatki oddalone o 90°, **123 z 239 gwiazd**
trafia tam, gdzie przewiduje obrót, wobec 3 i 1 dla alternatyw — a 123/239 to
dokładnie ten ułamek, który może zostać w kadrze, gdy obraca się ramkę 16:9
(przeżywają tylko gwiazdy w okręgu wpisanym).

### Kamera nie ma zostawać w tyle

Zgłoszone z kokpitu: przyspieszanie w przestrzeni zsuwało statek ze środka
kadru w stronę lotu, nie wracał on na środek, a przy najbliższym kadrowaniu
wychodził poza ekran.

To nie jest kwestia strojenia, tylko to, co filtr pierwszego rzędu **robi**.
Kamera doganiająca cel ułamkiem pozostałej odległości na tik, puszczona za
celem o stałej prędkości, ustala się w **stałej** odległości za nim: prędkość
przez współczynnik. Przy 10 na sekundę to jedna dziesiąta sekundy lotu — 40 px
świata przy 400 px/s, 200 px przy 2000 px/s. I to jest odległość **w świecie**,
więc na ekranie mnoży się przez przybliżenie: przy najbliższym kadrowaniu
więcej niż pół wysokości ramki 640x360. Dokładnie to, co zgłoszono.

Opóźnienie jest więc **kasowane, nie zmniejszane**. Celowanie w miejsce, gdzie
statek będzie za jedną dziesiątą sekundy, stawia stan ustalony dokładnie na
statku: przy stałej prędkości, jakakolwiek by nie była, statek siedzi na
środku. Wygładzanie zostaje dla tego, do czego było — szarpnięcia zderzenia,
odbicia przy lądowaniu, kopnięcia zapalonego silnika — bo to są zmiany
prędkości, a tych kompensacja nie kasuje.

Wzór jest **dyskretnym bliźniakiem** wersji ciągłej (`v * dt * (1-c)/c` zamiast
`v / rate`), bo tylko wówczas stan ustalony leży na statku co do piksela — a
test, który może żądać środka kadru, jest wart więcej niż taki, który godzi
się na „blisko środka". Zmierzone: 0,0 px odchyłki po czterech sekundach przy
2090 px/s, na każdym z trzech kadrowań.

**Twardy zderzak**, bo skasowany stan ustalony nie jest obietnicą o stanach
przejściowych: statek nigdy nie stoi dalej niż 22% krótszej półosi od środka.
Liczony **w pikselach ekranu**, co jest całym sensem tej liczby — ta sama
odległość w świecie to inny ułamek kadru przy każdym kadrowaniu, i właśnie tak
statek wyszedł poza ekran przy najbliższym, wyglądając poprawnie przy
najszerszym. Zderzak przy okazji robi za skok po przeskoku między systemami:
luz jest wtedy ogromny przez jeden tik i przycina się natychmiast, zamiast
przeciągać kamerę przez pół galaktyki (niewidoczne pod zasłoną tranzytu —
dlatego by tam zostało).

Wygładzanie przeniosło się z silnika do `ShipCamera.follow()` i to jest drugi
powód, ważniejszy od pierwszego: wbudowane dzieje się **przy rysowaniu**, a
bieg bez okna nic nie rysuje — więc nie dawało się przetestować. Test własnej
wersji przewija cztery sekundy lotu bez jednej klatki.

**Zerowy kadr kasowałby zderzak po cichu.** Pierwsza wersja czytała
`get_viewport_rect()`, które poza drzewem jest błędem i zwraca zero — a zerowy
zderzak nie poluzowuje kamery, tylko przyspawa ją do kadłuba i odbiera jej
cały ciężar, który ta klasa ma dawać. Stołem odniesienia jest teraz
rozdzielczość projektowa z `ProjectSettings`: gra rysuje się w jednym rozmiarze
i powiększa całkowicie, więc krótsza oś projektu to uczciwa półramka przy
każdym oknie, a szersze okno pokazuje więcej świata, co może tylko pomóc.

### Akordy zamiast kolejnych klawiszy

Klawiatura jest prawie pełna, a komputer lotu ma jeszcze długą listę rzeczy,
które będzie chciał dostać do powiedzenia. Akordy kupują miejsce, ale **tylko
tam, gdzie kombinacja i tak nic nie znaczy**:

| akord | znaczenie |
|---|---|
| `A` + `D` | przestań się obracać (zastąpiło `X`) |
| `Q` + `E` + `W` | dziób na kierunek lotu |
| `Q` + `E` + `S` | dziób przeciwnie do kierunku lotu |

`A` i `D` to przeciwne momenty, które się znoszą — trzymanie obu nie ma
żadnego innego odczytu, a „wciskam oba hamulce" to uczciwy sposób na
powiedzenie „stój". `Q` i `E` znoszą się tak samo, co zostawia `W`/`S` wolne
do wskazania kierunku.

Trzy rzeczy, bez których to nie działa:

- **Akord zjada swoje klawisze.** Inaczej `Q+E+S` celowałby wstecz wzdłuż
  prędkości i *jednocześnie* odpalał silnik cofający — a to nie jest
  hamowanie, tylko rozpędzanie się w stronę, z której się przyleciało.
- **Okno ustalenia (60 ms).** Przetoczenie palca z `A` na `D` nakłada oba na
  kilkadziesiąt milisekund i bez tego czyta się jako „stój" w środku skrętu,
  który pilot właśnie wykonuje. Puszczenie działa natychmiast — rezygnacji
  trzeba wierzyć od razu.
- **Stop wygrywa.** Akordy sprawdzane są po kolei i `A+D` jest pierwszy:
  pilot, który w panice łapie oba, chce się zatrzymać niezależnie od tego, co
  robią jego pozostałe palce.

**Asysta kursu jest bang-bang, nie parą dobranych wzmocnień**: celuje w
najszybszy obrót, który da się jeszcze zatrzymać na pozostałym kącie
(`sqrt(2·α·błąd)`) — ten sam kształt „czasu do wyhamowania", którego używa
hamulec, i bez stałych, które zwietrzeją przy następnej zmianie dysz.
Prędkość mierzona jest **względem gruntu**, w tej samej ramce co sprawdzenie
lądowania i solver kontaktów, więc statek stojący na obracającej się planecie
czyta się jako nieruchomy, a nie jako dryfujący. Na orbicie różni się to od
prawdziwego prograde o prędkość powierzchni — kilka stopni; kiedy auto-orbit
z M2 będzie potrzebował lepiej, policzy to z elementów orbity.

Ograniczenie sprzętowe warte zapisania: `Q+W+E` to trzy klawisze w jednym
rzędzie i tańsze klawiatury potrafią zgubić trzeci (ghosting). Jeśli okaże
się to realnym problemem, akord da się przenieść na klawisze rozrzucone po
klawiaturze bez zmiany niczego poza tabelą w `ControlChords`.

### Karty modułów: dlaczego wiersze, a nie akapit

Ekrany trzymały po jednym formacie na rodzaj modułu — czytelnym i
nieporównywalnym. **Karta, która jest akapitem, da się przeczytać, ale nie da
się jej odjąć od drugiej karty.**

`ModuleData.stat_rows()` zwraca wiersze: etykieta, wartość, dokładność i
**kierunek**. Ten ostatni jest całym powodem, dla którego to są wiersze:
porównanie nie umie pokolorować różnicy, której znaku nie zna. Mniejszy
rozrzut to poprawa, mniejszy zasięg nie, a obie zmiany mają minus z przodu.

Na zasobie, nie w ekranie, który je rysuje — żeby karta, porównanie i
przyszły dymek czytały te same liczby i żadne z nich nie mogło po cichu
twierdzić czegoś innego o tym, czym jest broń.

Przy wymianie obie karty stoją **obok siebie**, bo porównanie, między którym
trzeba przewijać, to dwa odczyty wzięte w różnych chwilach. Jednoliniowy
werdykt zniknął dla broni: karta mówi to samo dokładniej, a dwa podsumowania
tej samej wymiany to jedno za dużo do sprawdzania.

Layout musiał ustąpić treści: najdłuższa karta w grze to legendarna rakieta,
siedemnaście wierszy, i przy starym podziale 0,72/0,28 ostatnie z nich
wjeżdżały na podpowiedzi klawiszy — akurat te liczby, na których podejmuje się
decyzję. Panel kart dostał 0,56 wysokości i twardą podłogę, o którą rysowanie
się zatrzymuje. Wiersze, które i tak nie wejdą, są **policzone i zgłoszone**
przy podpowiedziach klawiszy: karta bez ostatniej linii wygląda dokładnie jak
karta, która się w tym miejscu kończy, i pilot decydowałby wymianę na
liczbach, o których nikt mu nie powiedział.

Cała karta — nie tylko wiersze — mieszka na `ModuleData.card_lines()`, więc
szybka wymiana na Tab i edytor rysują to samo. Różnica między nimi jest w
tym, *ile* się mieści, nie w tym, *co* piszą.

Karta jest tabelą, więc pisze się ją czcionką o stałej szerokości
(`ModuleData.card_font()`). Wiersz dopycha etykietę spacjami do trzynastu
znaków i prawuje liczbę w ośmiu — w czcionce proporcjonalnej to po prostu
nieprawda, bo spacja jest węższa od litery, którą zastępuje, i kolumna
wartości wychodzi poszarpana. Font stoi obok formatów, które go zakładają,
żeby ekran nie mógł wziąć karty i po cichu zgubić tego, co czyni ją czytelną.

### Model systemu: co należy do systemu, a co do seeda planety

Podział, który trzeba było rozstrzygnąć przed pierwszą linią: **system decyduje,
jak duże i jak ciężkie jest ciało; seed decyduje, jak ono wygląda.** Promień i
grawitacja siedzą w `SystemBody`, bo układ orbit bez nich nie istnieje — orbita
musi ominąć powierzchnię, księżyc musi zostać w studni rodzica. Teren, pogoda,
kolory i półki do lądowania zostają przy `seed` i rolowane są dopiero, gdy planeta
powstaje. Dwa miejsca rolujce tę samą liczbę to dwa miejsca, które się rozjadą,
więc `Planet.RADIUS_RANGE`, `GRAVITY_RANGE` i `INFLUENCE_RATIO` dostały nazwy i
są czytane z obu stron.

**Orbity są kołami, i to jest wybór, nie niedopatrzenie.** Elipsa chce równania
Keplera rozwiązywanego przy każdym zapytaniu, żeby zależność od czasu była
uczciwa; sparametryzowanie jej anomalią średnią narysowałoby dobry kształt i
kłamało o prędkości, czyli najgorsze z obu. Koło jest dokładnie okresowe,
dokładne w dowolnej chwili i kosztuje jeden sinus. Okres liczony z `mu = g·r²`
rodzica, więc trzecie prawo Keplera wychodzi za darmo i daleka planeta naprawdę
jest wolniejsza.

`position_at(t)` jest rekurencyjne w górę drzewa i **nie ma żadnego stanu**. To
jest to, co robi streaming darmowym: ciało wyłączone na dziesięć minut i włączone
z powrotem jest dokładnie tam, gdzie byłoby — nie ma dryfu do nazbierania ani
aktualizacji do przegapienia, bo nic nigdy nie całkowało.

**Odstępy między orbitami są konstrukcją, nie szczęściem.** Pierwsza wersja
mnożyła promień przez 1,45–1,85 i przechodziła test na 300 seedach — ale dwie
sąsiadki, które obie wylosowały duży promień i obie dostały księżyc, potrzebują
więcej miejsca, niż zostawia najmniejszy krok. Generator, który unika kolizji na
większości seedów, to generator z błędem czekającym na seed. Teraz krok jest tym,
o co planeta prosi, a dostaje minimum: zasięg sąsiadki, własny zasięg i własną
najwęższą studnię. Miejsce na stację rezerwuje każda planeta, czy ją dostanie,
czy nie — stacje rozdawane są po ułożeniu orbit, a planeta, której stacja
wyrosła później, byłaby już postawiona za blisko.

**Cykl referencji.** `parent` i `children` trzymały się nawzajem, a `RefCounted`
liczy referencje i nie zbiera cykli — każdy wygenerowany system wyciekał, co
Godot wypisał przy wyjściu po tym, jak test wygenerował ich trzysta. Link w górę
jest teraz słaby (`WeakRef`, przez `parent_body()`): właścicielem jest lista
`bodies` w systemie, a wchodzenie w górę od dziecka nigdy nie musi niczego
utrzymywać przy życiu.

**Rozmiar systemu: 41k do 302k px** (300 seedów). Stałe są dobrane pod **czas
podróży** — skok między sąsiadkami ma być kwestią dziesięciu sekund pod ciągiem,
nie wyprawą — i to ograniczenie od strony rozgrywki wygrywa z wygodą
implementacji. Co prowadziło do pytania niżej.

### Gwiazda ważona przez swoje planety, nie losowana

Pierwsza wersja losowała masę gwiazdy niezależnie od układu. Pytanie
„niech grawitacja gwiazdy działa tak jak grawitacja planety" kazało to
zmierzyć i wyszło, że tak zbudowany system **nie działa**: w najgorszym
przypadku sfera Hilla planety wychodziła na **0,20** jej własnej zadeklarowanej
studni, a gwiazda ciągnęła na orbicie do **67 px/s²** — mocniej, niż planeta
ciągnie na własnej powierzchni (25–60).

Taka planeta nie trzyma niczego. „Wejdź w studnię planety" nie znaczyłoby nic,
bo statek i tak spada na gwiazdę; a predyktor trajektorii, który rysuje stożek
wokół **najbliższej planety** i ignoruje resztę, rysowałby fikcję wszędzie poza
samą powierzchnią.

Więc najpierw warunek, a masa z niego: każda planeta mieści swój **najszerszy
możliwy** krąg wpływu w sferze Hilla — najszerszy, bo układ nigdy nie widzi,
który planeta sobie wylosuje. Najciasniejsza planeta w systemie wyznacza limit,
a gwiazda dostaje dokładnie tyle:

    r_hill = a · (mu_p / 3 mu_*)^(1/3)  ≥  k · r_p

przekształcone na `mu_*`, z `k` równym najszerszej studni, jaką planeta może
wylosować. Po zmianie: ciąg gwiazdy **0,01 do 2,84 px/s²** na orbicie planety,
rok od 10 minut do 8 godzin. Masa zapisana jest jako `surface_gravity`, bo tak
mu jest zapisywane wszędzie indziej w grze — to sposób zanotowania masy, nie
obietnica, że da się na tym stanąć.

Okresy liczone są jednym przebiegiem na końcu, po zważeniu gwiazdy, żeby nic
nie nosiło okresu wyliczonego z masy, która potem się zmieniła.

### Konfiguracje statków, i czego nauczyła ta z gimbalem

Narzędzie kreatywne umiało zmienić kształt kadłuba, czyli połowę tego, czym jest
statek. Drugą połową jest **konfiguracja** — gdzie są montaże i co w nich siedzi
— i była dokładnie jedna: układ z `ship.tscn`. `ShipFitout` to tabela całych
statków: montaże, silniki, działa, obrys, ładownia i nogi. Przebudowa idzie **w
miejscu**, bo podmiana sceny unieważniłaby kamerę, HUD-y, edytor i streaming
manager — piaskownica, która unieważnia połowę referencji gry, uczy wyłącznie
tego, jak wygląda crash.

Skala silnika mnoży **ciąg i gabaryt naraz**. Tabela skalująca sam ciąg
rozdawałaby darmową moc, a to jedyna rzecz, której piaskownica nie może robić po
cichu (sekcja 14). Zasoby silników są współdzielone, więc skalowanie idzie na
kopii: inaczej pierwszy preset z mocniejszym napędem zmieniałby wszystkie
późniejsze statki w sesji.

**Statek z samym gimbalem nie skręcał.** Preset, o który prosił użytkownik — bez
dysz obrotowych, obrót z wychylanej dyszy głównej — okazał się statkiem, który
nie potrafi się obrócić, i to jest dokładnie ten rodzaj rzeczy, dla którego
piaskownica istnieje. Dwa powody, oba w `ShipControl.rebuild()`:

- **Moment liczony był z dyszą prosto.** Napęd główny na osi ma ramię równoległe
  do ciągu, więc iloczyn wektorowy wychodzi zero i grupa CW nie miała żadnego
  członka. Teraz każdy silnik niesie też **wychylenie** — ile momentu dodaje
  dysza na maksymalnym wychyleniu — i jest ono dodawane do wkładu osobno dla
  każdej komendy obrotu, bo gimbal wychyla się w **obie** strony, a jeden wektor
  wkładu umie wskazać tylko jedną.
- **Kara za bok odrzucała go i tak.** Silnik, który przy obrocie pcha też do
  przodu, dostawał ujemną wagę i wypadał. Dla gimbala to pchnięcie jest **znaną
  ceną narzędzia**, nie dowodem, że narzędzie jest złe. Przy obrocie kara go nie
  dotyczy; względny próg i tak go odrzuca, gdy na kadłubie są prawdziwe dysze,
  bo ich waga jest o rząd wielkości większa — i stockowy statek ma po zmianie
  dokładnie te same 3760 autorytetu CW co przedtem.

Zmierzone: pojedynczy gimbal daje **1638** autorytetu CW przeciw 3760 na
dyszach, i po trzech sekundach komendy **2,93 rad/s obrotu przy 58 px/s
dryfu**. Raport
konfiguracji nazywa ten dryf (`CW pushes the ship sideways at 48.9 px/s2`) i
dobrze robi — to jest handel, nie usterka, ale pilot ma o nim wiedzieć.

**Dwie dysze zamiast jednej: para sił.** Pojedynczy gimbal obraca i pcha, bo
jedna siła nie ma czego znieść. Dziób i rufa, obie wychylane **w tę samą
stronę**, dają momenty, które się dodają, i ciągi, które się znoszą — czysta
para sił. Nie wymagało to żadnej zmiany w kodzie: `_aim_gimbals` wyprowadza
kierunek wychylenia z ramienia, więc obie dysze dostają ten sam znak same z
siebie. Zmierzone: **4366 autorytetu CW** (więcej niż 3760 na stockowych
dyszach) przy **1,4 px/s² pchnięcia resztkowego** zamiast 48,9.

Kadłub takiego statku musi być **symetryczny**. Para jest parą tylko dopóki
ramiona względem środka masy są równe, a środek masy idzie za kształtem: na
trójkącie siedzi za środkiem geometrycznym i jedna dysza dostaje dłuższe
ramię. Reszta 1,4 px/s² to właśnie to — środek masy wypada 0,2 px od środka
kadłuba przez zatoki i działo.

**Czego dwie dysze nie potrafią: strafe'u** — i raport to melduje. Choć w
zasadzie potrafiłyby: wychylone **przeciwnie** dają czysty ciąg boczny, więc
dwie wychylane dysze wystarczyłyby na przód, tył, obrót i bok naraz. Brakuje
dwóch rzeczy, tych samych co przy obrocie: `_aim_gimbals` celuje wyłącznie pod
komendę obrotu, a grupy nie liczą wkładu bocznego z wychylenia. To jest
następny krok tej samej myśli, nie rzecz zrobiona.

Czego ta zmiana **nie** obejmuje: alokatora NNLS. Kolumna alokatora jest jedna
na silnik i niezależna od komendy, a moment z gimbala zależy od tego, w którą
stronę się skręca — czyli od decyzji, którą alokator dopiero podejmuje. Grupy
go widzą, alokator nie. Na statku z komputerem NNLS gimbal będzie więc
niedowykorzystany, i to jest następne pytanie do rozstrzygnięcia, a nie rzecz
załatwiona.

### Trajektoria na mapie: jedna przyszłość, nie dwie

`TrajectoryPredictor` całkował już tor statku dla linii pod F7. Mapa
potrzebowała tego samego, więc rdzeń wyszedł na zewnątrz jako statyczne
`coast()`: **dwie prognozy tego samego statku to dwie przyszłości do trzymania
w zgodzie**. Ta sama funkcja grawitacji i ten sam półjawny Euler co w solverze,
więc to nie jest przybliżenie fizyki — to jest fizyka, puszczona do przodu.
Ciąg i opór są pominięte celowo: pytanie brzmi „co będzie, jeśli teraz puścię".

**Horyzont skaluje się zasięgiem mapy**, nie jest stały, bo stały jest zły z obu
stron: dwie minuty lotu to dwunastopikselowy kikut na układzie o średnicy
trzystu tysięcy pikseli, i kilka pełnych orbit, kiedy mapa jest przybliżona do
jednej planety. Krok całkowania rośnie razem z horyzontem, i to jest w porządku
akurat tam, gdzie rośnie: daleko od ciał tor jest prostą, a prostej nie da się
źle scałkować.

**Przerywana, nie ciągła.** To prognoza, nie droga; ciągła linia obok ciągłych
pierścieni orbit czytałaby się jak kolejna orbita, a nie jak najbliższe kilka
minut tego statku. Kreski odmierzane są długością łuku **na ekranie**, nie w
świecie — kreska, która rozciąga się z zoomem, przestaje być kreską.

Czerwona i z krzyżykiem, kiedy kończy się w gruncie, co zamienia manewr
deorbitacyjny w celowanie (sekcja 8).

Jedna rzecz, którą widać na zrzucie i warto nazwać: **między planetami tor jest
prostą**, bo gwiazda nie jest jeszcze źródłem grawitacji w scenie (ma masę w
modelu, ale nie ma węzła). Prognoza nie kłamie — pokazuje dokładnie to, co
statek zrobi — i zakrzywi się sama tego dnia, w którym gwiazda dostanie węzeł.

### Przyrząd orbity: obrazek zamiast ośmiu wierszy

„PERI −1651 / APO 693" to dwie liczby, z których pilot za każdym razem musi
sobie zbudować obrazek — w trakcie podchodzenia do lądowania. Obrazek jest tym,
czego naprawdę chce, więc HUD go rysuje, a liczby zostają obok dla tych, które
naprawdę są liczbami.

**Dwa przyrządy, i to, który jest na ekranie, mówi gdzie jesteś.** W studni
pytanie brzmi „co robi ta orbita"; poza nią — „gdzie lecę i jak szybko". Stary
odczyt pokazywał liczby planety z dowolnego miejsca w układzie, bo *najbliższa*
planeta to zawsze jakaś planeta. To nie to samo pytanie co *czy jej grawitacja
tu sięga*, a poza zasięgiem stożek, który by narysowała, nie jest torem, po
którym statek leci.

**Grubsza zielona linia na orbicie.** „Czy jestem na orbicie" to pytanie tak/nie,
a sam kolor to odcień, który trzeba pamiętać; grubość czyta się bez pamięci.

**Planeta jest kropką, a grunt pierścieniem** — pierwsza wersja rysowała
wypełniony dysk w skali i to było błędem, który widać dopiero na zrzucie: na
krótkiej prostej apocentrum jest kilkaset pikseli nad gruntem, więc dysk
wypełniał tarczę i połykał dokładnie ten tor, który pilot czytał. Pierścień
mówi o skali to samo i zostawia środek widoczny — a tam właśnie mieszka stożek
podorbitalny.

Jeden wzór rysuje elipsę i hiperbolę: `r = p / (1 + e cos θ)`. Elipsa się
domyka, bo mianownik nigdy nie dochodzi do zera, hiperbola ucieka, bo dochodzi.
Tor przerywany jest tam, gdzie wychodzi poza studnię — linia docięta do krawędzi
czytałaby się jak orbita przylegająca do niej.

**Kadłub jako pasek na górze**, bo to jedyny odczyt, w którym trend znaczy
więcej niż wartość: nikt nie lata na 63 procentach, lata się na „jeszcze
większość" albo „prawie nic". Szerokość 160 px, żeby zmieścił się między dwiema
kolumnami overlayu debugowego, bo tam góra ekranu jest wolna nawet z F7.

Odmowa lądowania to **wykrzyknik i powód**. „WAVE OFF" było etykietą na newsie,
który kolor już niósł.

**Stan toru wrócił jako słowo**, i to jest cofnięcie własnej nadgorliwości. Wyrzuciłem wiersz „ORBIT" razem z „WAVE OFF", na argument, że gruba zielona linia mówi to samo. Pilot zgłosił, że sygnalizacja się nie pojawiła — i miał rację: kolor to odcień, który trzeba pamiętać, a jeden piksel grubości to odcień, który trzeba pamiętać **z próbką obok**. Słowo kosztuje pięć znaków panelu, który je ma. Dla toru podorbitalnego nadal nie ma słowa, bo to jest normalny stan statku startującego i lądującego — i czerwone perycentrum mówi to samo.

Pierwsze miejsce, w które je wstawiłem — lewy górny róg tarczy — było złe: słowo siadało na pierścieniu orbity, który opisywało, w tym samym kolorze. Teraz jest nad panelem po prawej, a znak odmowy nad nim po lewej.

**Trzy znaczniki, trzy kształty.** Zgłoszone z kokpitu: nie dało się odróżnić,
która kropka jest statkiem. Bo i nie dało — statek był kółkiem w tej samej
zieleni co apoapsis i o jedną piątą piksela mniejszym. Teraz statek to
**kwadrat w najjaśniejszym atramencie**: kształt mówi, który to który, kolor
mówi, co robi — ten sam porządek, co trójkąt, romb i krzyżyk na skanerze.

**Migotanie miało dwie przyczyny i pierwsza diagnoza złapała tylko jedną.**

Przy orbicie bliskiej kołowej wektor mimośrodu, który wskazuje apsydy, jest małą
różnicą dużych liczb: jego długość to szum, a **kierunek** to nic — i właśnie
kierunek jest całą treścią apsydy. Obie kropki skakały dookoła pierścienia co
tik. Stożek przy tym stał nieruchomo, bo okrąg wygląda tak samo niezależnie od
tego, gdzie się go wyceluje, i dlatego migotały wyłącznie kropki.

Druga połowa jest tańsza do wyjaśnienia: znacznik ma niespełna cztery piksele i
jest rysowany na płótnie 640x360, które okno skaluje trzy, cztery razy. Środek
przesunięty o jedną trzecią piksela rasteryzuje się inaczej, a przy 3x ląduje na
ekranie jako znaczek zmieniający kształt co klatkę. Elementy orbity faktycznie
tyle dryfują między tikami, bo grawitacja jest tu łatana wygaszeniem przy
krawędzi, a nie czystym odwrotnym kwadratem. Znaczniki **siadają więc na siatkę
piksela**, i nie ma czego migotać.

Próg „apsydy za blisko siebie" jest **wygaszeniem, nie przełącznikiem**: twardy
próg to własne migotanie, bo orbita siedząca dokładnie na nim strobowałaby
kropkami.

**Odliczanie do następnej apsydy** (`APO in 42s`) liczone Keplerem na tej samej
stożkowej, którą przyrząd rysuje — liczba i obrazek nie mogą się więc ze sobą
kłócić nawet tam, gdzie żadne z dwojga nie jest dokładnie prawdziwe. Jedna
linia, nie dwie: pytanie na orbicie brzmi „co będzie dalej", druga apsyda jest
pół orbity dalej, a wysokości powyżej i tak mówią, która jest która. Pusto,
kiedy nie ma czego odliczać — orbita kołowa nie ma apsydy, a ucieczka nie ma jej
przed sobą — bo zero czytałoby się jako „teraz".

Test na to łapie błąd znaku, który przeżyłby zwykłe sprawdzenie: apsydy są pół
orbity od siebie niezależnie od tego, w którą stronę czyta się kierunek lotu,
więc samo „pół okresu" niczego nie dowodzi. Potrzebny jest przypadek
niesymetryczny: statek wznoszący się musi dotrzeć do apoapsis **przed**
periapsis. Pierwsza wersja tego testu celowała prędkością do środka i twierdziła,
że statek się wznosi — zegar bardzo słusznie zaprzeczył.

### Mapa układu: rysowana z modelu, bo tylko model wie

Mapa (`M`) czyta `StarSystem`, nie scenę. To jest jej jedyny powód
istnienia: streaming trzyma w świecie jedną planetę naraz, więc mapa
zbudowana z żywych węzłów pokazałaby jedną kropkę i nazwała to układem.

**Orbity w skali, ciała nie.** Układ ma ćwierć miliona pikseli średnicy, a
planeta dwa tysiące — planeta w skali to jedna dziesiąta piksela. W skali jest
to, po co się na mapę patrzy: jak daleko coś jest. Kształty zamiast kolorów
(dysk, pierścień, mały pierścień, kwadrat), bo przy ośmiu pikselach kolor to
trzy piksele koloru.

**Jasność znacznika mówi, czy ciało jest w świecie.** To nie ozdoba: to różnica
między miejscem, w które można wlecieć, a miejscem, które powstanie, gdy się
tam dotrze — i jedyne okno na to, co robi streaming manager.

**Scrim 0,96, nie 0,72 jak w edytorze.** Edytorowi uchodzi mniej, bo kładzie na
świat pełne panele; mapa to cienkie linie na ciemnym polu i przy 0,86 HUD lotu
czytał się przez nią, a dwa zestawy liczb walczyły o to samo miejsce.

**Ten sam błąd co edytor, drugi raz.** Pierwsza wersja odpowiadała na kliknięcie
z tego, co zostawiło ostatnie `_draw`. To czyni klikanie niesprawdzalnym i
błędnym przed pierwszą klatką — dokładnie to, co `ship_editor.gd` ma zapisane w
komentarzu przy `_panels()`. Układ jest funkcją układu i prostokąta, i niczego
więcej; klik liczy go sobie od nowa.

**Zoom jest zasięgiem w świecie, nie mnożnikiem.** Pierwsza wersja miała
drabinkę potęg czwórki i jest to błąd wart zapamiętania: systemy mają od 41k do
302k px średnicy, więc **ten sam mnożnik to inny widok w każdym z nich**. Na
zrzucie x64 wyrzuciło księżyc pół ekranu poza krawędź, bo trafiło na system
szerszy, niż zakładałem. Zasięg w pikselach znaczy wszędzie to samo: 7500 px to
„ta planeta i jej księżyce" w dowolnym systemie, jaki generator zbuduje.

Powiększanie idzie wokół **tego, na co pilot wskazał**, nie wokół gwiazdy —
inaczej pierwszy krok wypycha z ekranu dokładnie to, co się przed chwilą
kliknęło. Z klawiszem `+` / `-` to jest kliknięte ciało; z **kółkiem to punkt
pod kursorem**, i to jest właściwie cała ta funkcja: kółko, które powiększa
względem środka, każe gonić oglądaną rzecz przez ekran, jeden obrót na raz.
Środek mapy przestał więc być ciałem i stał się punktem (`_focus` plus
`_focus_follows`), bo wskaźnik zwykle stoi w szczelinie między dwoma ciałami —
czyli dokładnie tam, gdzie chce się zajrzeć. Klik znowu przywiązuje środek do
klikniętego ciała i nadal śledzi je po orbicie; na końcu drabinki kółko nie robi
**nic**, bo bez tego oparcie się na nim przy pełnym powiększeniu przesuwałoby
widok przy nieruchomej skali. A ciało dostaje
swój prawdziwy okrąg powierzchni, gdy tylko zrobi się większy od znacznika: przy
skali układu planeta to jedna dziesiąta piksela i znacznik jest wszystkim, co
jest; przy 7500 px to jest to, na co się patrzy.

**Teleport (`Enter`) jest narzędziem deweloperskim** i jest tak opisany w
podpowiedziach. Do M4 nie ma sposobu przecięcia systemu innego niż przelecenie
go, a testowanie streaming managera w ten sposób to testowanie go raz na
godzinę. Cel budowany jest synchronicznie (`force_awake`) — to dokładnie ten
przypadek, dla którego ta metoda istnieje — a statek ląduje na orbicie kołowej
po tej stronie, z której przyleciał, żeby teleport nie obracał przy okazji pilota.

Przy okazji wyszła nieświeża referencja: `World.planet` było planetą zbudowaną
na starcie, co było w porządku, dopóki istniała tylko jedna. Ze streamingiem
znaczy to konfigurator edytujący planetę, którą pilot już opuścił, i krater
wykopany w niewłaściwym świecie. Świat śledzi teraz najbliższy żywy glob i
przepina do niego konfigurator.

### Streaming: trzy stany, nie cztery

Projekt (sekcja 9) rozpisywał cztery poziomy, z jedynką jako „gwiazda i planety
jako sprite'y". Przy 640x360 ten poziom **nie ma reżimu**: planeta ma ponad
dwa tysiące pikseli średnicy, a ekran pokazuje 640 px przy zoomie 1 i 1164 px
przy najszerszym. Planeta jest więc albo szersza od ekranu, albo całkiem poza
nim — nie ma odległości, z której jest widocznym krążkiem. Zostały trzy:
`GONE`, `AWAKE` (ciało z terenem, kolizją i grawitacją), `SURFACE` (plus to, co
na nim leży). Dorabianie środkowego poziomu, żeby zgadzało się z tabelką, byłoby
poziomem, który nic nie robi.

**Czym jest próg obudzenia.** Nie zasięgiem grawitacji, choć i on musi się
zmieścić (8 promieni przeciw 6, jakie planeta może wylosować na studnię), tylko
**zasięgiem wzroku**. Skaner melduje kontakty do 20 000 px, a kontakt, który nie
został zbudowany, to kontakt, którego skaner nie zamelduje — planeta pojawiająca
się z niczego wewnątrz zasięgu skanera to błąd, który widać. Stąd `SIGHT_RANGE`
i test wiążący go z własną liczbą skanera, zamiast komentarza obiecującego, że
ktoś o tym pamiętał.

**Pierwsza delta: loot.** Skrzynka podniesiona ma zostać podniesiona. Manager
trzyma opróżnione półki per seed ciała, a losowanie zawartości idzie po
wszystkich półkach niezależnie od tego, które są puste — dzięki temu zabranie
jednej skrzynki nie zmienia, czym są pozostałe. Delta terenu (piksele) to osobny
krok; dziś krater wykopany przed odlotem znika.

**Błąd, który znalazł test.** Gwiazda i stacje nie mają jeszcze sceny, a
pierwsza wersja wrzucała je do kolejki jak wszystko inne. Gwiazda stawała na
czele kolejki, zjadała jedyny budowlany slot klatki na odkrycie, że nie ma z
czego jej zbudować, i wracała przy następnym przebiegu po to samo — przez co
**pierwsza planeta nie budowała się nigdy**. Ciała bez sceny są teraz pomijane
przy przebiegu, a nie odrzucane w kolejce.

### Generacja terenu na wątku, i co się przy tym wydało

`PlanetTerrain.generate()` rozpadło się na dwa: `build()` — szum, wysokości,
półki, siatka zajętości i cache powierzchni, czysta arytmetyka na własnych
tablicach obiektu — i `finish()`, które robi obraz i teksturę. Tylko to drugie
musi być na głównym wątku. Zmierzone na prawdziwym rendererze:

| planeta | `build()` (wątek roboczy) | `finish()` (główny) |
|---|---|---|
| R 1025 px | 13,2 ms | 0,1 ms |
| R 1710 px | 33,3 ms | 0,2 ms |
| R 1644 px | 31,9 ms | 0,3 ms |

Czyli z klatki schodzi praktycznie całość. Węzeł planety powstaje **poza
drzewem**, siedzi tam, dopóki wątek liczy, i wchodzi dopiero gotowy — dzięki
temu nie ma stanu „połowa planety w świecie", którego trzeba by bronić przed
solverem kontaktu i skanerem. Przylot buduje synchronicznie: raz zapłacona
zadyszka jest lepsza niż statek postawiony obok planety, której jeszcze nie ma.

Zadanie raz wystartowane nie da się anulować, więc `clear()` **czeka** na
zakończenie zamiast porzucać węzeł: wątek piszący do tablic zwolnionego
obiektu to crash bez czytelnego stosu. Jeśli pilot odleciał w trakcie budowy,
gotowa planeta jest wyrzucana, a nie zatrzymywana — zatrzymana byłaby planetą
w świecie na odległości, o której manager już orzekł, że jest za daleka.

**Delta terenu i pomiar, który zmienił projekt.** Skorupa zapamiętywana jest
przy wyłączaniu planety, spakowana ZSTD, i tylko dla światów, w które ktoś
strzelał — nietknięty wraca identyczny z seeda, a kopia byłaby seedem trzymanym
dwa razy. Pierwsza wersja kładła ją z powrotem po dodaniu węzła do drzewa i
najgorsza klatka powrotu wyszła **21,4 ms** przeciw **6,0 ms** dla świata bez
krateru: `restore_crust()` przeskanowuje całą powierzchnię, co jest piętnastoma
milisekundami. Planeta z kraterem zacinała więc mocniej niż nowa, co jest
dokładnie na odwrót. Przywracanie poszło na wątek razem z generacją — **7,5 ms**.

Dwa drobiazgi, które kosztowały po debugowaniu: `decompress()` domyślnie czyta
FASTLZ, więc bufor ZSTD wraca **pusty, nie błędny**, i skorupa była po cichu
odrzucana. A `restore_crust()` wołane przed `finish()` nie może dotykać
tekstury, której jeszcze nie ma.

### Planety nie okrążają gwiazdy, i to jest świadomy handel

Ciała **wirują wokół własnej osi** (`spin_rate`, doba, grunt jadący pod
wylądowanym statkiem — wszystko jak dotąd) i **nie wędrują po orbicie**.

Powód jest konkretny: problem ruchomej ramki bierze się z **przyspieszającego
środka**. Planeta lecąca 300–600 px/s ciągnie za sobą wszystko w swojej studni,
a uspójnienie tego wymaga prędkości orbitalnej w `surface_velocity_at`,
dziedziczenia jej przy starcie i pilnowania, żeby wiszący statek i luźna
skrzynka nie zostały w tyle. Wirowanie nic takiego nie robi — środek stoi —
i dlatego zostaje bez zmian.

**Jeden zamrożony zegar na wizytę, nie na ciało.** Gdyby każde ciało zamrażało
się we własnej chwili obudzenia, dwie planety obudzone dziesięć minut od siebie
stałyby pod wzajemnie niespójnymi kątami, a planeta uśpiona i obudzona ponownie
**teleportowałaby się** — przy 600 px/s i dziesięciu minutach o 360 000 px.
Streaming manager zamraża jedno `system_time` przy wejściu do systemu i stawia
wszystko na ten sam moment. Między wizytami zegar biegnie dalej: wracasz,
planety stoją gdzie indziej, i nikt nie widział skoku, bo nie było go tam.

**Co to kosztuje: prawdziwą procę grawitacyjną.** Przelot obok nieruchomego
ciała to czyste odchylenie — prędkość na wyjściu równa się prędkości na
wejściu. Darmowa energia bierze się z tego, że ciało się porusza. Pozycja
„proca grawitacyjna między ciałami" z PLAN M3 znaczy więc „zakręcanie", nie
„przyspieszanie", i to jest cena przyjęta świadomie, a nie odkryta później.

Uboczny skutek do zapamiętania: **doba istnieje, rok nie**. Okresy orbitalne są
policzone i zapisane, bo bez nich nie da się ustawić pozycji przy wejściu do
systemu, ale w trakcie wizyty nic ich nie realizuje.

Drugi skutek, odkryty dopiero przy stawianiu gwiazdy: **sfera Hilla tu nie
obowiązuje**. Jest wyprowadzona dla ciała, które krąży. Patrz niżej, „Gwiazda:
ciągnie wszędzie, parzy blisko".

### Gwiazda: ciągnie wszędzie, parzy blisko

Gwiazda jest węzłem w tej samej grupie `gravity_sources` co planety. Żeby to
było możliwe bez udawania, że gwiazda jest planetą, studnia wyprowadziła się
do wspólnej klasy bazowej **`GravityWell`**: promień, grawitacja
powierzchniowa, zasięg, `gravity_at()` i wygaszanie na krawędzi. Planeta
dokłada do tego grunt, powietrze i pogodę. Podział przebiega dokładnie tam,
gdzie przebiega pytanie: kto chce samego ciągu, bierze `GravityWell`; kto chce
w co uderzyć, bierze `Planet` i dostaje wyłącznie planety.

**Kryterium Hilla było złym narzędziem i test to przepuścił.** Masa gwiazdy
była wyprowadzana z warunku, żeby sfera Hilla każdej planety mieściła jej
najszerszą możliwą studnię. Sfera Hilla jest jednak wyprowadzona w układzie
obracającym się razem z planetą, gdzie większość ciągu gwiazdy kasuje
przyspieszenie orbitalne — i wychodzi jakieś **siedem razy szersza** niż
promień, na którym ciągi są naprawdę równe. Nasze planety nie krążą, więc nie
ma czego kasować. Zmierzone na 200 systemach pod starą regułą: **na krawędzi
własnej, zadeklarowanej studni najbliższej planety gwiazda wygrywała 2:1** —
czyli dokładnie to, przed czym komentarz przy tej funkcji ostrzegał.

Kryterium jest teraz bezpośrednie: `mu_p / w² ≥ 2 · mu_* / (a − w)²`, przy
gwieździe mierzonej od bliższej strony orbity. Dwa do jednego, a nie jeden do
jednego: na granicy formalnej ciągi się znoszą, więc statek jest tam w
swobodnym spadku donikąd, a stożek rysowany przez HUD nic nie znaczy.

**Ale czytałem to z niewłaściwej strony, i to był drugi błąd.** Pierwsza
wersja brała najszerszą studnię, jaką planeta *może* wylosować, jako daną, i
pytała, jak lekka musi być gwiazda, żeby wszystkie przeżyły. Najciaśniejsza
planeta w układzie ustawiała wtedy masę dla całej reszty. Gwiazda straciła na
tym cztery piąte masy i wyszła fizycznie nieistotna: zmierzone w grze, w
miejscu, gdzie faktycznie się lata, **0,069 px/s² — cztery dziesiąte procenta
tego, co statek czuje**, a między orbitami, gdzie była jedynym ciągnącym
ciałem, 0,045 px/s², czyli 224 px znoszenia na sto sekund. Wszystkie asercje
przechodziły. Zgłosił to pilot słowami „wygląda na to, że gwiazda nie
przyciąga statku".

Czytane z drugiej strony nie kosztuje nic. **Gwiazda jest losowana jak każde
inne ciało, a każda planeta dostaje studnię, którą naprawdę utrzyma** —
ciasną dla świata wewnętrznego, pełną wylosowaną szerokość dalej. Tam gdzie
nawet `WELL_FLOOR` (trzy promienie, tyle żeby dało się okrążyć) nie wychodzi,
**układ odsuwa planetę na zewnątrz**, bo przesunięcie planety jest darmowe, a
odchudzenie gwiazdy nie.

Zmierzone na tych samych 300 systemach, po zmianie:

| | przed | po |
|---|---|---|
| ciąg gwiazdy na pierwszej orbicie | 0,069 px/s² | **0,87–2,47 px/s²** |
| między orbitami | 0,045 px/s² | **0,43–1,61 px/s²** |
| znoszenie po 100 s dryfu (w grze) | 224 px | **4673 px, 102 px/s** |
| studnie planet | 3,5–6 promieni, losowane | 3,0–6,0, wyprowadzone |
| orbity wewnętrzne | — | odsunięte najwyżej ×1,5 |

Najgorszy stosunek ciągu gwiazdy do grawitacji powierzchniowej planety to
nadal **4,8%**, więc wylądowany statek nadal nie czuje gwiazdy z boku.

**Gwiazda zeszczuplała przy okazji**, z 6000–11000 px na 2600–4800. Była
szeroka, bo szerokość niosła masę (`mu = g·R²`); teraz masę niesie
grawitacja, która jest losowana osobno (45–110 px/s² na powierzchni, więcej
niż jakakolwiek planeta). Przy 11000 px promienia gwiazda nigdy nie była
tarczą na ekranie 640×360, tylko ścianą, na którą się wpada. Przy 3000 widać
krzywiznę. Z tego samego powodu `FIRST_ORBIT` jest teraz w pikselach, a nie w
promieniach gwiazdy: wiązanie skali całego układu z tym, jak gruba wygląda
gwiazda, było pozostałością po czasach, gdy ciężka i szeroka znaczyło to samo.

**Kolor gwiazdy to odczyt, nie ozdoba.** Nie jest już losowany osobno —
wynika z masy, więc niebieska naprawdę jest tą ciężką. To jedyna rzecz, którą
o gwieździe widać z drugiego końca układu, i teraz mówi, jak mocno ten system
będzie ciągnął na transferze.

**Strefa obrażeń to pasek ciepła, a nie drugi mechanizm.** `hull_heat`
istniał od M1.6 i nic nie robił: napełniał się przy wejściu w atmosferę i
pilot mógł go zignorować. Gwiazda potrzebowała gdzie odłożyć obrażenia, a
wymyślanie drugiego „za gorąco" obok istniejącego paska byłoby dwoma
układami opowiadającymi tę samą historię. Więc: jeden pasek, dwa źródła
(tarcie i światło), jeden skutek — powyżej `BURN_HEAT` kadłub się pali.
Próg 0,75 leży powyżej wszystkiego, co osiąga zdecydowany aerobraking
(zmierzone: **0,447** na testowym zejściu), więc zwykłe lądowanie nic na tym
nie traci.

**Promień strefy jest wyprowadzony, nie zadeklarowany** — i pierwsza wersja
tego wyprowadzenia była błędna. Liczyłem punkt równowagi `flux · rate /
cooling`, zakładając, że kadłub stygnie o ułamek swojego ciepła. Stygnie o
stałą. Nic więc się nie ustala: światło albo przegania wyciek i pasek dochodzi
do końca, albo nie przegania i pasek **nie rusza się z zera**. Strefa ma ostrą
krawędź, na `sqrt(STAR_HEAT_RATE / HEAT_COOLING)` promieni gwiazdy, czyli 1,73.
Mieści się w orbicie każdej planety w 300 systemach z zapasem **×1,36** —
wewnętrzny świat musi być miejscem, do którego da się dolecieć.

Test zgadzał się z błędnym wzorem, bo **robił tę samą arytmetykę**. Znalazł to
dopiero lot na gwiazdę w uruchomionej grze. Test całkuje teraz `_update_heat`
samego statku zamiast go przepisywać: dwie minuty w środku strefy napełniają
pasek i zjadają kadłub, dziesięć minut tuż za nią nie rusza paska z zera.

### Akord trzyma swoje klawisze aż do puszczenia

`SETTLE` pilnuje **wchodzenia** w akord: przetoczenie palca z A na D nakłada
je na kilkadziesiąt milisekund i bez okna czytałoby się to jak „stop" w
środku skrętu. Wychodzenie było uznane za natychmiastowe — i to jest prawda o
akordzie, ale nieprawda o klawiszach.

Palce nie schodzą z akordu razem, tak samo jak na niego nie wchodzą. Przy
puszczaniu A+D jeden przeżywa drugi o kilkadziesiąt milisekund i przez ten
czas czyta się jako zwykła komenda obrotu: **statek zaczyna się kręcić
dokładnie w chwili, gdy pilot przestał kazać mu przestać.** Na geście paniki.

Lustrem `SETTLE` byłoby okno przy puszczaniu, a okno to zgadywanie. Za
krótkie — wolne puszczenie nadal zakręci statkiem; za długie — zjada
świadome wciśnięcie, które w nie trafi; i tak czy owak liczba jest zła dla
czyichś rąk. Więc nie ma tu liczby: **klawisz, który był częścią akordu,
zostaje zużyty, dopóki nie zostanie puszczony.** Tego nie da się źle
nastroić.

Co to kosztuje: przetoczenie się z A+D w świadomy skręt wymaga ponownego
wciśnięcia klawisza, zamiast samego podniesienia jednego palca. Jedno
stuknięcie, przeciw gestowi paniki, który sam się cofał.

Ubocznie: dedykowane klawisze postawy (HOME/END/INSERT) tego problemu nie
mają z definicji — jeden klawisz nie ma z czym się rozjechać. To jest drugi
argument za tym, żeby istniały obok akordów.

### Dopalanie: wyjście z dziury, które coś kosztuje

Statek da się postawić tam, skąd silniki go nie podniosą — ciężki świat,
pełna ładownia, uszkodzony napęd, albo wszystko naraz — i bez tego jedyną
odpowiedzią jest respawn. Silnik dostaje więc dwie liczby: **mnożnik ciągu**
i **mnożnik spalania**. Jedynka znaczy „ten silnik nie ma trybu awaryjnego";
mają go tylko duże napędy, bo manewrówka na trzykrotnym przeciążeniu to nie
manewrówka, tylko bomba.

Mnożnik spalania jest celowo dużo bardziej stromy niż mnożnik ciągu. Dopalanie
nie jest lepszym silnikiem z wadą, tylko tym samym silnikiem wydawanym
szybciej: **trzy razy ciąg za dwanaście razy spalanie**.

Zmierzone na stokowym statku (masa 16,6, pula 100):

| | bez | z dopalaniem |
|---|---|---|
| sam napęd główny | 54,2 px/s² | **162,7 px/s²** |
| czas palenia na pełnej puli | — | **8,3 s** |
| napęd zbity do 50% zdrowia | 27,1 px/s² | 81,3 px/s² |

Planety ciągną 25–60 px/s² przy powierzchni, więc zdrowy stokowy statek przy
54,2 **ledwo nie wystartuje z najcięższych światów** — dokładnie ta pułapka, o
którą chodziło — a z dopalaniem ma zapas 2,7×. Napęd zbity do połowy nie
podniesie się znikąd, a z dopalaniem podniesie się z każdego świata. Zbity do
jednej trzeciej nie podniesie się z najcięższego nawet z dopalaniem, i to jest
w porządku: wrak ma zostać wrakiem.

**Paliwa jeszcze nie ma, więc płaci pula energii.** `fuel_cost` istniał od M2
jako pole dla ekonomii paliwa z M5; mnożnik spalania mnoży właśnie je, a
wychodzi to dziś z puli, bo to jedyny zasób, który statek naprawdę ma.
Dopalanie konkuruje więc z bronią — każde wydanie odsuwa ładowanie puli — i to
jest słuszna konkurencja, a nie efekt uboczny.

**Zatrzask, nie próg.** Pierwsza wersja miała tylko minimum do zapalenia (10%
puli). Test pokazał, że to za mało: spalanie odsuwa ładowanie co klatkę, więc
pilot trzymający klawisz nad pustą pulą dostawał **impuls ciągu mniej więcej
co sekundę**, w miarę jak pula przepełzała nad próg i była opróżniana.
Nieprzewidywalny ciąg przy lądowaniu jest gorszy niż żaden. Więc: jedno
wciśnięcie to jedno palenie. Zapala się, pali do puszczenia klawisza albo do
dna, a potem nie zapali się ponownie, dopóki klawisz nie zostanie puszczony.
To czyni z niego rezerwę, którą się wydaje, a nie kran, na którym można wisieć.

### Ekran pomocy czyta InputMap, a nie własną listę

Lista klawiszy przepisana do ekranu pomocy jest listą błędną od drugiej łatki
— i to w najgorszy sposób, bo pilot w nią wierzy. Na ekranie zapisane jest
więc tylko **co dana akcja znaczy**; który klawisz ją wywołuje, bierze się z
tej samej tablicy, którą gra pyta o stan klawiatury. Akordy idą z tej samej
tablicy, z której czyta je dopasowywacz.

Jednej rzeczy ekran nie sprawdzi o sobie sam, więc sprawdza ją test: **każda
akcja w InputMap ma wpis w opisach.** Dodaj klawisz bez opisu i zestaw pada.
Przy pierwszym uruchomieniu wypadły cztery akcje, o których nie wiedziałem, że
istnieją (`ship_fire_secondary`, trzy edytorskie) — co jest dokładnie tą
klasą błędu, którą ten test ma łapać.

Uboczna lekcja: **stałe klawiszy Godota warto sprawdzić, a nie zgadnąć.**
Wpisałem HOME/END/INSERT z pamięci i trafiłem w ALT, CAPSLOCK i NUMLOCK —
sąsiednie liczby. Zobaczyłem to dopiero na zrzucie z ekranu pomocy, który
nazywa klawisze tak, jak nazywa je silnik. Ekran pomocy złapał błąd w
bindingach, zanim złapał go pilot.

### Gwiazda świeci, planeta ma noc

Tarcza gwiazdy była płaskim wypełnionym kołem. Przy promieniu dwóch do pięciu
tysięcy pikseli i ekranie szerokim na 640 pilot **nigdy nie widzi tarczy** —
tylko kawałek powierzchni wypełniający widok. Płaskie wypełnienie czyta się
więc jak zepsuty render, i nie ma w nim niczego, co powiedziałoby, czy się
leci. Faktura w skali ekranu jest tu całą robotą; kształt tarczy prawie nie
ma znaczenia, bo widać zawsze tylko jej skrawek.

Powierzchnia to teraz shader: granulacja (fbm z czterech oktaw, cele
wielkości 85 px świata, znoszone powoli w dwóch kierunkach), **pociemnienie
brzegowe** jako jedyna wskazówka, że to kula, i czysta krawędź. Kolor tarczy
jest **podciągnięty w stronę bieli o 45%**: prawdziwa gwiazda jest biała tam,
gdzie patrzy się w nią prosto, a barwa wychodzi dopiero na brzegu i w koronie.
Malowana swoim nominalnym kolorem czytała się jak ceglany mur.

**Korona jest addytywna i to jest cała poprawka.** Pierwsza wersja rysowała
cztery półprzezroczyste koła zwykłym alfa-blendingiem. Jasny kolor zmieszany
alfą z czernią daje przyciemnioną wersję tego koloru, więc biała gwiazda
nosiła szarą smugę — czytało się to jak dym, nie jak światło. Światło się
dodaje. Przy okazji gwiazdy tła nadal prześwitują przez halo, zamiast być
przez nie wymazane.

**Noc na planecie: dwa różne progi, i to jest wybór rozgrywki, nie fizyki.**
Kierunek na gwiazdę jest podawany do shaderów gruntu, powietrza i chmur jako
wektor **w ramce tego quada**, odświeżany co klatkę — bo doba to dokładnie
to: planeta obraca się pod gwiazdą, a terminator po niej wędruje. Nic się nie
przechowuje, więc planeta obudzona przy dowolnym odczycie zegara ma tę porę
dnia, którą powinna mieć.

Progi nocy są trzy i są celowo niespójne z fizyką: **grunt 0,50, chmury 0,30,
powietrze 0,22.** Grunt jaśniejszy od powietrza nad nim jest dla prawdziwej
planety odwrotnością prawdy, a tutaj jest słuszny: po gruncie się ląduje, a
powierzchnia, której nie da się odczytać, to powierzchnia, w którą się
wbija. Powietrze może gasnąć do końca, bo nikt na nim nie ląduje — i to
właśnie w nim noc się czyta, jako jasny sierp cieniejący w ciemność.
Zmierzone: noc przy 0,40 wszędzie dawała grunt na poziomie (17, 12, 29), nie
do wylądowania.

Chmury nie mogły dostać wspólnej odpowiedzi, bo **każda warstwa obraca się
własnym tempem**; jeden kierunek na wszystkie oznaczałby terminator
przesuwający się po pokrywie w miarę rozjeżdżania się warstw. Każda warstwa
ma więc własny materiał. Kierunek „na zewnątrz planety" dla pojedynczej
chmury jedzie w **kolorze instancji** — wszystkie cztery kanały custom data
są zajęte, a alternatywa, czyli odczytanie własnej transformacji instancji w
stopniu wierzchołków, to zakład o to, w jakiej przestrzeni wyrażony jest
`MODEL_MATRIX`. Zakładów w shaderze nie przyjmuję.

Przy okazji, lekcja o narzędziu, nie o grze: **`ShipCamera` wygładza pozycję
z szybkością 10/s**, więc zrzut ekranu zrobiony klatkę po teleportacji
pokazuje miejsce, z którego statek odleciał. Wyglądało to dokładnie jak
gwiazda, która się nie renderuje, i kosztowało godzinę zgadywania. Probe
robiący zrzuty musi dać kamerze dojść.

### Światła 2D: co światło może, a czego nie

Plan mówił „oświetlenie 2D właściwymi światłami (`Light2D`) dla statku,
skrzynek i pocisków". Po przeczytaniu, jak światła 2D w Godocie faktycznie
działają, wyszło, że to **dwie różne rzeczy**, i tylko jedna z nich jest
światłem.

**Czego światło 2D nie potrafi: terminatora.** Światło w 2D nie wie, w którą
stronę zwrócona jest powierzchnia — bez map normalnych `DirectionalLight2D`
rozjaśnia wszystko jednakowo, więc nie zrobi granicy dnia i nocy. Do tego
potrzebny byłby `CanvasModulate`, a ten **przyciemnia całe płótno**, łącznie z
shaderami planety, które już liczą własne światło. Odkręcenie tego oznaczałoby
mnożenie ich przez 1/tint, czyli przepalanie jasnych kolorów. Dlatego dzień i
noc dla rzeczy w świecie liczy ta sama reguła co dla gruntu
(`GravityWell.daylight_at`), tylko **jako skalar, nie per piksel**: planeta ma
tysiące pikseli średnicy i potrzebuje odpowiedzi w każdym, a statek ma
trzydzieści i jest po prostu po jednej albo po drugiej stronie.

Szerokość terminatora przestała przy okazji być stałą w trzech shaderach i
jest teraz jedną stałą w GDScript (`GravityWell.TERMINATOR`), wpychaną do
materiałów jako uniform. Liczba zapisana w czterech plikach to terminator,
który się przesuwa zależnie od tego, na co patrzysz; test pilnuje, że shader
planety cieniuje do tej samej, co statek.

**Co światło 2D potrafi, i po co tu jest: kałużę jasności.** To dostają
rzeczy, które świecą — pocisk, wybuch, dysza. Dodawane (`BLEND_MODE_ADD`), bo
światło w kosmosie to coś, co dochodzi na wierzch, a mieszanie wypłukałoby
kolor z tego, na co pada. Tekstura to gradient robiony w kodzie, nie plik: ten
projekt nie ma sprite'ów, a spadek promieniowy to cztery linijki.

**Halo, czyli co się stało, gdy światło padło na powietrze.** Pierwsza wersja
dawała wokół statku świecącą kulę — zgłoszone z kokpitu. Przyczyna: kwadrat
atmosfery zakrywa całą okolicę planety, więc **każde** światło w pobliżu
rozświetlało tarczę nieba zamiast cokolwiek oświetlić. Lampa poświecona w
powietrze nie robi świecącej kuli; atmosfera i chmury są teraz `unshaded` —
nie są powierzchnią, tylko tym, co przed nią wisi, a własne światło dnia
liczą same. Grunt, kadłub i skrzynki światło przyjmują, bo na nie światło
pada.

**Druga przyczyna: każda dysza świeciła tak samo.** Osiem równych lamp na
jednym kadłubie to halo, a nie statek z silnikami — manewrówka 160 N nie ma
czego szukać tam, gdzie świeci napęd 900 N. Blask skaluje się teraz ciągiem:
zasięg pierwiastkiem, moc liniowo, więc mały silnik robi **małą jasną
plamkę**, a nie szeroką bladą. Zmierzone na stokowym statku: 160 N daje 0,09
mocy i 46 px zasięgu przeciw 0,50 i 110 px napędu głównego. Spadek
promieniowy podniesiony z 2,2 na 3,4, bo łagodny spędza większość promienia
na jasności ledwo widocznej — i to właśnie jest wygląd halo.

Zmierzone: błysk wybuchu rozświetla grunt i kadłub w promieniu 260 px i gaśnie
kwadratowo w 0,45 s (liniowo czytałoby się jak ściemniacz, nie jak detonacja);
dysza na krótkiej prostej, 22 px nad gruntem, wyraźnie oświetla zbocze obok
statku. Kadłub nad nocną stroną ma 0,42 jasności przeciw 1,00 nad dzienną —
przedtem świecił tak samo i czytał się jak naklejka na obrazku.

Cieniowany jest `self_modulate` kadłuba i podwozia, nie `modulate` statku: pióropusz,
smugi i błyski wystrzału robią własne światło, a płomień gasnący o zmierzchu
byłby gorszy niż brak cieniowania.

Koszt, zmierzony: osiem świateł dysz stokowego statku to **0,24 ms na klatkę**
po stronie CPU (7,93 przeciw 7,69 ms), przy najgorszej klatce wyższej o 0,17
ms. Kosztu GPU ten pomiar nie obejmuje — to osiem małych addytywnych
prostokątów przy 640x360.

### Wariantowość: z cech, nie z trzeciego rzutu kostką

Przedmioty mają powstawać jako **baza plus afiksy**, a wygląd ma z tego
wynikać. Model afiksów stoi od M2 i jest dobry: mnożnik na jednym polu,
opłacony pogorszeniem innego, magnitudo losowane i skalowane rzadkością,
rzadkość znaczy „bardziej skrajny", nie „lepszy".

Czego w nim brakuje, zmierzone zamiast obgadane. Pula afiksów jest wspólna
dla kategorii i nie wie, czego baza nie ma, a `_scale` mnoży pole przez
współczynnik — więc afiks na polu zerowym **ląduje, zajmuje slot i nie robi
nic**. Na 8400 losowaniach legendarnych silników:

| baza | martwe afiksy |
|---|---|
| gimballed_drive | 0% |
| main_drive, braking_bell | 9% |
| torque_jet, manewrówki, retro | 19% |
| razem | **14%** |

Do tego trzy rodzaje modułów są nazywane na trzy sposoby: broń zapisuje
`affixes`, generator składa `display_name`, a silnik wyrzuca zwrotkę z
`_apply_affixes` i zostaje przy „thruster engine 664". Afiksy są w liczbach,
ale gracz nigdy się nie dowiaduje, które.

**Wygląd jest odczytem, nie ozdobą** — ta sama reguła, co przy kolorze
gwiazdy wynikającym z masy. Sprite i efekt wybiera to, czym przedmiot jest:
po wielkości (trzy pióropusze dobierane mocą silnika) albo po afiksie
(„steerable" dostaje dyszę na przegubie). Niezależne losowanie wyglądu dałoby
tę samą liczbę wariantów i żadnej informacji — a wariant, który nic nie
znaczy, gracz przestaje widzieć po godzinie.

Rozpisane w PLAN.md jako M3.5; format zasobów w ASSETLIST.md.

### Pociski spadają, a kursor nic za pilota nie liczy

Wszystko w świecie podlegało grawitacji — statek, skrzynki, linia
przewidywanej trajektorii — **oprócz pocisków**, które leciały idealnie
prosto. Jedyna rzecz w grze zwolniona z reguły, o którą cała gra chodzi.

Zmierzone, strzał poziomy z 848 px nad gruntem (grawitacja lokalna 13,3
px/s²), na dystansie 1600 px:

| broń | prędkość | spadek | poprawka |
|---|---|---|---|
| pulse repeater | 900 px/s | 18,7 px | 0,7° |
| autocannon | 600 px/s | 42,4 px | 1,5° |
| burst shell | 520 px/s | 57,1 px | 2,0° |
| dumb rocket | 180 px/s | 522,8 px | 18,1° |

Czyli: szybkie działko na krótkim dystansie prawie nic nie traci, wolna
rakieta staje się bronią nawesną. Charakter broni wychodzi z jednej liczby,
której nikt nie musiał wpisywać.

**Kursor celowania nie kompensuje, i to jest decyzja.** Melduje, czy działko
może się wycelować w dany punkt — pytanie o mocowanie i o nic więcej — i nie
rysuje żadnej przewidywanej drogi. Poprawka na grawitację należy do pilota.
Kursor rozwiązujący łuk zamieniłby każdy strzał w celowanie w znacznik, który
gra już policzyła, a cały powód, dla którego pociski spadają, to dać pilotowi
coś, w czym może być dobry. Test pilnuje obu stron: że to, gdzie musi
celować lufa, nie zmienia się od obecności planety, i że `aim_hud.gd` nigdy
nie pyta o grawitację.

### Pocisk kosztuje 7 mikrosekund, a nie 0,9 milisekundy

Zgłosiłem był, że piętnaście pocisków w powietrzu kosztuje ~0,9 ms na pocisk
na klatkę. **Ta liczba była zła o ponad dwa rzędy wielkości**, i warto
zapisać, dlaczego — bo błąd był w metodzie, nie w arytmetyce.

Mierzyłem `Performance.TIME_PROCESS` plus `TIME_PHYSICS_PROCESS` w zwykłym
oknie z vsync. W pętli ograniczonej vsyncem te liczniki nie mierzą, ile pracy
wykonano — mierzą, gdzie silnikowi akurat wypadło zaksięgować czekanie. Ten
sam pomiar dał **42 ms przy zerze pocisków** i 8,9 ms przy czterdziestu, co
samo w sobie było sygnałem, że mierzę szum, a ja i tak podałem z tego wniosek.

Zmierzone porządnie — zegar ścienny, `--fixed-fps`, vsync wyłączony, 400
klatek na przypadek, liczba pocisków ustawiana, nie wnioskowana:

| pociski | klatka (µs) | przyrost na pocisk |
|---|---|---|
| 0 | 1624 | — |
| 10 | 1787 | 16 µs |
| 40 | 1977 | 8,8 µs |
| 160 | 2948 | 8,3 µs |

Koszt jest **liniowy, około 7–8 µs na pocisk na klatkę**. Piętnaście pocisków
to 0,12 ms, czyli **0,7% klatki**. Sto sześćdziesiąt to 1,3 ms, czyli 8%. Nie
ma tu czego naprawiać.

Osobno sprawdzone, bo pod złym pomiarem siedziała jedna prawdziwa liczba —
najgorsza klatka 75 ms przy strzelaniu w grunt. Zegarem: **strzelanie w grunt
nie kosztuje nic ponad bezczynność** (1533 przeciw 1549 µs średnio), a
najgorsza klatka wynosi 5,6–5,9 ms *we wszystkich* przypadkach, łącznie z
bezczynnym zawisem. Żłobienie kraterów nie robi zacięcia; te 5,6 ms to coś
okresowego w silniku i jest tam bez nas.

Rozbicie po składnikach (`tools/frame_bench.gd` wyłącza po jednym): test
zamiatany terenu i światło pocisku dokładają razem jakieś 1,5 µs na pocisk.
Reszta to koszt samego węzła.

**Lekcja metodologiczna, ta sama co zwykle w tym projekcie:** narzędzie, które
zgadza się samo ze sobą, nie jest pomiarem. `TIME_PROCESS` zgadzał się sam ze
sobą i był bez związku z rzeczywistością. Pomiar kosztu klatki idzie teraz
przez `tools/frame_bench.gd`, który tę metodę ma zapisaną w komentarzu.

### Stacje: dokowanie bez klawisza, naprawa za czas

Stacja nie jest studnią grawitacyjną i model mówił to od początku: dokuje się
do niej, nie orbituje wokół niej, a źródło tak małe dodawałoby solverowi
tylko szumu. Ma zamiast tego **promień, w którym trzeba być, i prędkość, pod
którą trzeba być** — ten sam kształt co lądowanie, i celowo: pilot już umie
przylatywać gdzieś powoli.

**Dokowanie jest automatyczne, bez klawisza.** Pilot powiedział już, czego
chce, przelatując nad stacją w tempie spacerowym; prompt do wciśnięcia byłby
drugim sposobem powiedzenia tego samego. Odlot to ten sam gest co start z
gruntu — poproś o ciąg i masz go.

Odmowa podaje **powód**, nie „nie": `za daleko` albo `za szybko`. Z tego samego
powodu, co przy lądowaniu — „nie" nie jest odpowiedzią, na której da się
lecieć, a pilot potrzebuje wiedzieć, której z dwóch liczb nie spełnia.

**Naprawa kosztuje czas, nie kliknięcie.** 0,12 kadłuba i 0,18 zdrowia
silnika na sekundę, pula szybciej niż z własnego generatora — bo bycie
podpiętym do czegoś większego od siebie właśnie to znaczy. Zmierzone: pół
kadłuba w 1,6 s, komplet w okolicach dziesięciu. Długo na tyle, żeby to była
decyzja („czy stać mnie teraz na postój"), krótko na tyle, żeby nikt nie
czekał dwa razy. **To jest pierwszy raz, kiedy uszkodzenie da się cofnąć bez
respawnu** — a uszkodzenie, które da się naprawić tylko przez respawn, jest
albo śmiertelne, albo darmowe.

**Zatrzask przy odlocie, trzeci raz ten sam kształt.** Chwilę po odłączeniu
statek nadal jest w zasięgu i ma zerową prędkość — czyli dokładnie warunek
dokowania — więc dok łapał go z powrotem w następnej klatce i nie dało się
odlecieć. To ten sam błąd co akord trzymający klawisze i co zapłon dopalania
nad pustą pulą, i to samo rozwiązanie: **zatrzask, nie zegar**. Dok, który
się właśnie puściło, nie przyjmie statku, dopóki ten nie opuści jego zasięgu.
Warunek końca to „odleciałeś", więc nie potrzeba żadnej liczby.

Ubocznie: `builds_as_node` mówi teraz „wszystko poza gwiazdą" zamiast
wyliczać kto może. Gwiazda jest wyjątkiem z przeciwnego powodu niż stacje
były — nie dlatego, że nie ma sceny, tylko dlatego, że nigdy nie znika.

### Studnie są łatane, nie sumowane — bo planety stoją

Zgłoszone z kokpitu: **nie da się wejść na orbitę planety.** Zmierzone, trzy
minuty lotu wokół Calai b, całkowane tak jak liczy to solver:

| orbita | bez gwiazdy | z gwiazdą (suma) |
|---|---|---|
| 1,6 promienia | trzyma ±0,1% | **uderza w grunt** |
| 2,6 promienia | trzyma ±0,0% | **ucieka ze studni** |
| 4,0 promienia | trzyma ±0,0% | **ucieka ze studni** |

Przyczyna nie jest kwestią nastrojenia siły. W prawdziwym układzie statek na
orbicie planety prawie nie czuje gwiazdy, bo **planeta spada ku gwieździe
razem z nim** i zostaje tylko różnica w poprzek orbity, czyli pływ. Nasze
planety są przybite do miejsca (patrz „Planety nie okrążają gwiazdy"), więc
zwykła suma daje statkowi pełny ciąg gwiazdy, a planecie żaden. To nie jest
perturbacja — to **stałe pchnięcie w jedną stronę**. Przy 1,43 px/s² i okresie
54 s wychodzi z tego ponad 2000 px przesunięcia na jedno okrążenie, więcej niż
promień orbity.

Dlatego studnie są **łatane, a nie dodawane**. Wewnątrz studni ciała ciągnie
to ciało, a te na zewnątrz nie — co jest tym, jak wygląda „planeta cię niesie"
w świecie, w którym planeta fizycznie nieść nie może. Szwem jest wygaszanie,
które każda studnia i tak ma na swojej krawędzi: ciało oddaje statek dokładnie
tak szybko, jak puszcza, więc pole jest ciągłe i nic nie kopie przy przejściu.
Zmierzone po zmianie: orbity trzymają ±0,1%, a największy skok pola między
próbkami co 0,5% studni to 0,25 z 5,28 px/s² — gradient, nie urwisko.

To jest też odpowiedź na „zmniejszmy strefę wpływu gwiazdy, żeby nie obejmowała
planet": jednym promieniem się nie da, bo planety są na różnych odległościach,
a promień mniejszy od pierwszej orbity usunąłby gwiazdę dokładnie stamtąd,
gdzie ma ciągnąć. Strefa gwiazdy ma więc **dziury w kształcie studni planet**,
co daje ten sam skutek i nie wymaga żadnej liczby.

Skutek uboczny, przyjęty świadomie: **procy grawitacyjnej nadal nie ma**, i
teraz nie ma jej podwójnie — przelot obok planety jest czystym dwuciałowym
odchyleniem, bez nawet tego śladu trzeciego ciała, który dawała suma.

**HUD orbitalny tylko nad gruntem.** Przez jeden commit panel gospodarzyła
studnia ciągnąca najmocniej, więc między orbitami pokazywał gwiazdę — i pod
łatanymi studniami był nawet prawdziwy, bo statek naprawdę spada tam wokół
gwiazdy po dokładnym stożku. I bezużyteczny: wisiał cały czas, bo nie ma w
układzie miejsca poza zasięgiem gwiazdy, a odczyt, który jest zawsze, to
odczyt, którego nikt nie czyta. Diagram orbity zarabia na siebie, gdy jest
dokąd dolecieć; w przelocie między planetami pytanie brzmi „w którą stronę i
jak szybko", a to jest robota widżetu transferu.

**Mapa rysuje zasięgi.** Atmosfera jako niebieski okrąg, studnia jako
kreskowany — jedno i drugie to rzeczy, pod które się planuje, a nie na które
się patrzy: studnia to miejsce, gdzie transfer przestaje być prostą i staje
się przylotem, a atmosfera to miejsce, gdzie zaczyna się aerobraking i kończy
trwała orbita. Pokazują się dopiero, gdy są większe od znacznika ciała, czyli
w skali układu nigdy.

Żeby to było możliwe, **wysokość atmosfery przeniosła się do modelu**, obok
promienia, grawitacji i studni. Nie dlatego, że potrzebuje jej układanie
orbit, tylko dlatego, że atmosfera jest wielkością orbitalną — to ona dzieli
orbitę trwałą od zanikającej — a mapa rysuje światy, których nikt jeszcze nie
zbudował. Zakresy losowania mają teraz nazwy (`Planet.AIRLESS_CHANCE`,
`Planet.AIR_RATIO`) i jedno losowanie (`Planet.roll_air`), bo dwa miejsca
losujące tę samą wielkość to dwa miejsca, które się rozjeżdżają.

### HUD orbitalny: jak ta reguła wyglądała, zanim gwiazda z niej wypadła

(Historia jednego commitu; obowiązującą regułę opisuje sekcja wyżej.)

Panel orbity pytał wcześniej o **najbliższą planetę** i znikał, gdy statek
wyszedł z jej studni. Między orbitami zostawał sam wskaźnik kierunku — choć
statek spadał wtedy wokół gwiazdy i miał normalny stożek do narysowania.

Reguła jest teraz jednozdaniowa: **gospodarzem jest studnia, która ciągnie w
tym punkcie najmocniej.** Nie wymaga wyjątku na gwiazdę. Wewnątrz studni
planety wygrywa planeta, bo `WELL_DOMINANCE` tego pilnuje przy układaniu
systemu; na zewnątrz zostaje gwiazda i tylko gwiazda.

Przekazanie wypada w **wygaszaniu na krawędzi**, nie na nominalnej granicy
studni. Dominacja 2:1 jest liczona na czystym odwrotnym kwadracie, ale pole
jest wygaszane przez ostatnią dziesiątą część studni, żeby przekroczenie
granicy nie było kopnięciem. W tej ostatniej dziesiątej planeta naprawdę już
puszcza, więc statek naprawdę spada wokół gwiazdy — i panel to mówi. Test
przypina obie strony: do 0,89 studni planeta, przy 0,995 gwiazda.

Żeby to było możliwe, cała arytmetyka orbit — `OrbitState`, `orbit_extremes`,
`orbit_shape`, `conic_radius`, `circular_orbit_speed` — przeniosła się do
`GravityWell`. Jedyne dwa pytania, na które gwiazda odpowiada inaczej niż
planeta, to „gdzie kończy się grunt" i „gdzie kończy się powietrze"; dla
gwiazdy oba wskazują na jej powierzchnię. `has_ground()` decyduje, czy panel
pokazuje nachylenie i podwozie, czy nazwę ciała: nachylenie 0,0° nad gwiazdą
czytałoby się jak płaski grunt, co jest gorszą odpowiedzią niż żadna.

### Floating origin: nie jest potrzebny, i to jest zmierzone

Plan zostawiał otwartą decyzję „floating origin na podstawie rozmiaru systemu",
a ja sam w komentarzu powtórzyłem obiegową mądrość, że float32 zaczyna drżeć
powyżej ~100k jednostek. Nikt tego tutaj nie zmierzył, więc powstał
`tools/distance_bench.gd`: cała scena przesuwana na 0, 40k, 100k, 300k i 1000k
px od początku układu, wszystko mierzone w ramce planety.

| odległość | błąd przechowania | obieg przez ramkę | pełzanie kadłuba /10 s | dryf orbity /10 s |
|---|---|---|---|---|
| 0 | 0,0001 px | 0,0001 px | 0,124 px | 6,85 px |
| 40k | 0,0004 | 0,0031 | 0,193 | 7,17 |
| 100k | 0,0079 | 0,0050 | 0,164 | 7,34 |
| 300k | 0,0054 | 0,0099 | 0,456 | 7,28 |
| 1000k | 0,0074 | 0,0280 | 0,451 | 6,70 |

Trzy wnioski:

- **Współrzędne nie drżą.** Setne części piksela przy milionie pikseli. Nawet
  przy 300k obieg punktu przez ramkę planety kosztuje 0,010 px.
- **Orbita nie zauważa odległości w ogóle.** Dryf promienia jest taki sam w
  zerze i w milionie, czyli to **całkowanie**, nie float. Gdyby kiedyś
  przeszkadzało, poprawia się to integratorem, a nie ruchomym początkiem.
- **Jedyna rosnąca liczba** to pełzanie statku leżącego na gruncie, trzymanego
  przez solver kontaktu: 0,12 px/10 s w zerze, 0,45 przy 300k. I to dotyczy
  **nieprzymrożonego** kadłuba — udane lądowanie ustawia `freeze` i przypina
  statek do planety, więc tam nie kumuluje się nic.

Decyzja: **bez floating origin**. Test pilnuje granicy — jeśli stałe układu
kiedyś wyprowadzą system poza zmierzony zakres, suite to zgłosi, zamiast
pozwolić grze działać na dowodach, których nikt nie zebrał.

Czego **nie** zmierzyłem i warto to powiedzieć: renderowania. Headless nic nie
rysuje, więc widoczne migotanie sprite'ów przy dużej odległości to osobne
pytanie — kamera odejmuje własną pozycję, więc liczby na wejściu shadera są
małe, ale to argument, nie pomiar.

### Seeker: cel bierze się z kursora, nie z odległości

Rakieta samonaprowadzająca brała najbliższy statek. To jest broń kłócąca się
z kursorem: pokazujesz **za** wrak na tego z tyłu, a pocisk leci we wrak.
Cała teza celowania myszką brzmi „strzela się tam, gdzie się patrzy", więc
cel bierze się z `Ship.aim_point`, a nie z pozycji wyrzutni — wyrzutnia nie ma
zdania o tym, który z dwóch statków miałeś na myśli.

**Promień chwytu jest w pikselach ekranu**, przeliczany przez transformację
kanwy (`Ship.lock_reach()`). Stały promień w świecie byłby najbardziej
wyrozumiały przy maksymalnym przybliżeniu — czyli tam, gdzie pilot ma
najwięcej precyzji i najmniej potrzebuje pomocy. Rozmiar celu
(`hull_extent()`) dochodzi na wierzch, bo we frachtowiec naprawdę łatwiej
wycelować niż w myśliwiec.

**Brak celu to brak celu.** Kursor na pustce nie daje zaczepienia i rakieta
leci prosto — a leci prosto *tam, gdzie pokazałeś*, bo wyrzutnia i tak
obraca się za kursorem. To nie jest przypadek do zaklejenia awaryjnym
„weź najbliższego": to jest dokładnie to, o co prosi pokazanie w próżnię.
Kursor zostaje bursztynowy dla rakiet, i to nadal jest prawda.

Przy okazji test zrobił się ostry. Stary sprawdzał tylko „coś, co nie jest
strzelcem", bo `queue_free()` jest odroczone i zwolnione kadłuby wiszą w
grupie do końca klatki. Skoro cel wybiera kursor, można powiedzieć **który**
— i po cofnięciu zmiany padają cztery asercje zamiast żadnej.

### Skrzynki: dlaczego własna całka, a nie RigidBody2D

Skrzynka jest `Area2D` i musi nią zostać — podniesienie to wejście statku w
obszar. Fizyka doszła obok, jako własna całka w `_physics_process`, z trzech
powodów, z których każdy sam by wystarczył:

- **Teren nie ma collidera.** Jest bitmapą próbkowaną w kodzie; statek liczy
  kontakt sam (sekcja 7) i skrzynka musi tak samo.
- **Grawitacja jest własna.** Pole 1/r² sumowane z grupy `gravity_sources`,
  nie `gravity_scale`.
- **Skrzynka jest dzieckiem planety**, żeby jeździć z obracającym się
  gruntem. Rigid body pod obracającym się rodzicem to dwa silniki kłócące się
  o tę samą transformację.

Rozwiązanie kontaktu jest wersją tego ze statku dla jednego punktu bez
bezwładności: wypchnięcie ze skały **przed** poprawką prędkości (odwrotna
kolejność zostawia skrzynkę klatkę w ziemi, co czyta się jako zapadnięcie),
prędkość mierzona **względem gruntu** (`surface_velocity_at`), odbicie 0,25 i
tarcie 0,55 — skrzynka to pudło, ma podskoczyć raz i stanąć, a nie toczyć się
z góry.

**Osiadła kontra luźna.** Skrzynka postawiona przez generator świata jest już
tam, gdzie ma być, więc nie jest całkowana wcale. Wyrzucenie robi ją luźną,
przyziemienie osadza z powrotem — i osadzenie ustawia ją *na* gruncie i *do
pionu*, bo skrzynka na zboczu ma wyglądać, jakby leżała na zboczu. Osiadła
pilnuje tylko jednej rzeczy: czy grunt pod nią nadal istnieje. Eksplozje
kopią teren, a skrzynka wisząca nad świeżym kraterem to pudło stojące w
powietrzu.

**Czego nie ma: podkroku.** Napisałem substepping „żeby szybka skrzynka nie
przeskoczyła gruntu", a potem to zmierzyłem: przy 1200 px/s kupował
**dwie dziesiąte piksela** penetracji. Kontakt jest mierzony promieniowo —
ile skrzynka ma nad gruntem *pod sobą* — a nie pytaniem „czy ten punkt jest w
skale", więc żeby minąć skorupę, trzeba by przelecieć jej ponad dwieście
pikseli między klatkami, czyli 13 000 px/s. Kod, który kupuje dwie dziesiąte
piksela, to kod do skasowania. Granica warta zapisania: lot **bokiem** nad
iglicą węższą niż jeden krok dalej by ją minął; nic w grze nie rzuca skrzynką
choćby blisko tak mocno.

**Ile to kosztuje.** Zmierzone, bo pytanie padło: osiadła skrzynka 1,61
µs/tick, luźna 3,49 µs/tick. Przy czterech skrzynkach to 0,04% budżetu
klatki — nic. Ale rozbicie pokazało, że z 1,61 µs osiadłej **1,3 µs szło na
pytanie „czy grunt pode mną jeszcze jest?"**: `Planet.nearest` 0,61 plus
`height_above_terrain` 0,69, zadawane 60 razy na sekundę o zdarzenie, które
zdarza się, gdy spadnie pocisk.

Zamienione na sygnał. `Planet.carve()` emituje `carved(point, radius)`,
skrzynka słucha gruntu, na którym leży, i sprawdza prześwit tylko wtedy.
Osiadła skrzynka ma teraz `set_physics_process(false)` i `set_process(false)`
— **nie jest na klatce w ogóle**, co jest dokładnie tym, co „osiadła" miała
znaczyć od początku. Zmierzone po zmianie: 400 osiadłych skrzynek, zero na
klatce. Odliczanie `grace` też się wyłącza, gdy dojdzie do zera; `_process`
chodzi na każdej klatce renderowania, czyli częściej niż fizyka.

Luźna ścieżka została bez zmian: 3,49 µs, z czego ~1,3 to skanowanie grupy
(`Planet.nearest` plus suma grawitacji). Przy 100 jednocześnie spadających
skrzynkach to 0,35 ms i nie ma czego optymalizować — luźna skrzynka jest
stanem przejściowym, trwa sekundy.

### Schemat statku: boks zamiast kropki

Kropka umie powiedzieć tylko „tutaj". Cała reszta musiała iść w podpis obok,
więc schemat stockowego kadłuba niósł jedenaście napisów — ścianę tekstu,
którą trzeba przeczytać, zanim się cokolwiek znajdzie.

Boks ma wnętrze, a wnętrze może mówić. Cztery rzeczy naraz, żadna napisana:

- **ramka** — czy niesiony moduł tu wejdzie (i która jest wybrana strzałkami),
- **wypełnienie** — czy coś siedzi, w kolorze rzadkości tego czegoś; legendarny
  silnik i pospolity mają ten sam kształt i są inną decyzją,
- **glif** — jakie to gniazdo: strzałka wzdłuż **siły** (nie pióropusza — edytor
  pyta „w którą stronę to pcha"), celownik, ogniwo, układ scalony, noga,
- **glif w hardpoincie** — *co* jest zamontowane: ○ puste, + działo, | wiązka,
  ↑ rakieta. Trzy rodziny zamiast sześciu typów, bo przy jedenastu pikselach
  różnica między pulsem a działkiem jest nierysowalna, i nie o to się pyta.

Nazwa wraca na kliknięcie — i dla gniazda wybranego strzałkami, bo inaczej
chodzenie po celach klawiaturą byłoby chodzeniem po ciemku.

Dwie rzeczy wyszły dopiero przy rysowaniu. **Łuk przemiatania szedł od środka
gniazda**, więc jego dwie krawędzie przecinały boks i spotykały się na glifie:
mount pokazywał łuk i przestawał pokazywać, co ma w środku. Łuk zaczyna się
teraz za boksem. **Wewnętrzne zatoki** (generator, komputer, podwozie) siedzą w
odległości 1,75 i 2 px na kadłubie, bo są objętościami w środku, nie punktami
na nim — przy skali schematu to 6 px na boks o boku 11. Rozsuwane są przy
rysowaniu, w dół, i to jest rozsunięcie **tylko na schemacie**: węzły niosą
masę, więc przesunięcie jednego dla porządku na obrazku przesunęłoby środek
masy. Rysowanie i klikanie czytają tę samą, już rozsuniętą pozycję — inaczej
kliknięcie trafiałoby w sąsiada, co test pokazuje, gdy się rozsuwanie wyłączy.

Test ustawia płótno na rozmiar, w jakim gra naprawdę rysuje. Headless daje
płótnu rozmiar okna (640x640), a przy prawie dwa razy większej wysokości
zatoki rozchodzą się same i test przechodziłby na układzie, którego nikt nie
ogląda.

### Kamera podejścia: dlaczego dwa warunki, a nie jeden

Blokada „planeta na dole" włącza się sama, kiedy **podwozie jest wysunięte
i wysokość nad terenem spada poniżej 300 px**. Dwa warunki, bo mówią co
innego.

**Podwozie to deklaracja zamiaru.** Sama wysokość nie wystarcza: przelot nisko
nad grzbietem to nie podejście, a kamera, która przechylałaby się przy każdej
mijanej górze, jest chorobą morską. Pilot ma już klawisz, którym mówi „ląduję"
— to ten sam klawisz.

**Wysokość to postęp tego zamiaru**, więc waga jest ciągła, nie przełącznikiem:
przy trzystu ledwie napiera na widok, na krótkiej prostej trzyma go. Liczona
względem **terenu**, nie promienia nominalnego — to jest ta wysokość, którą
pilot czyta z panelu lądowania, podejmując decyzję.

Ręka pilota wygrywa: dopóki strzałka jest wciśnięta, blokada pauzuje na tę
klatkę. To nie jest tryb, z którego się wychodzi i do którego wraca — puszczasz
strzałkę, blokada znowu ciągnie.

Tempo (`LOCK_RATE`) siedzi pod własnym wygładzaniem `Camera2D`, więc czuć
szereg dwóch — celowo wolniej niż naciśnięcie `H`, bo o ten obrót nikt nie
prosił, a widok, który sam skacze, to widok, który płoszy.

Przy okazji `Planet.height_above_terrain()` dostało nazwę: trzy miejsca
rozpisywały tę samą różnicę ręcznie, co jest trzema okazjami do zmierzenia
nie tego, co trzeba. `altitude_at()` (promień nominalny) zostaje dla orbit,
gdzie góry są szumem na liczbie rzędu tysięcy.

### Celowanie: co należy do broni, a co do gniazda

Pytanie „zakres obrotu na hardpoincie czy na broni" ma odpowiedź **oba**, bo to
dwie różne wielkości, a projekt ma już na to wzorzec.

- **`WeaponData.traverse_range` i `traverse_rate`** — pierścień i silnik samej
  broni. Na broni z tego samego powodu, dla którego gimbal siedzi na
  `EngineData`: to część maszyny. Działko na sztywno ma tu zero, gdziekolwiek
  je przykręcić, a wieżyczka zabiera swój łuk ze sobą.
- **`Hardpoint.traverse_limit`** — ile pozwala kadłub. Działko wpuszczone we
  wnękę kończy miejsce, zanim skończy je własny pierścień. To fakt o kadłubie,
  nie o broni.

Obowiązuje **mniejszy z dwóch**, czyli dokładnie ten sam kształt co `bulk <=
size`: co moduł potrafi, wobec tego, na co pozwala gniazdo. Szybkość obrotu
jest wyłącznie broni — kadłub nie sprawia, że silnik wieżyczki kręci szybciej.

Kierunek spoczynkowy jest z kolei czysto gniazda i ustawia się go w edytorze:
gdzie działko siedzi, należy do kadłuba.

**Kursor pokazuje najlepsze, nie najgorsze.** Przy trzech działkach na jednym
spuście pytanie pilota brzmi „czy naciśnięcie teraz coś da", więc jedno działko,
które trafi, to odpowiedź „tak". Spust odpala potem **tylko te, które mogą
trafić** — trzy gniazda na jednym spuście to trzy szanse, że któreś bierze, a
nie trzy pociski we własny kadłub.

Dwa rozstrzygnięcia, które nie są oczywiste:

- **Poza zasięgiem to szary, nie zielony.** Zielony kursor na celu, do którego
  pocisk nie doleci, jest kłamstwem.
- **Pocisk samonaprowadzający nigdy nie melduje „zielony"** i nigdy „szary" —
  zawsze bursztynowy, bo może zawrócić na wszystko, więc zawsze warto go
  wystrzelić i nigdy nie jest dokładnie wycelowany.

**Własny kadłub nie jest przeszkodą.** Celowanie w poprzek statku to
normalna rzecz do zrobienia wieżyczką, więc amunicja przez własny kadłub
przelatuje. Pocisk jest martwy, **dopóki nie wyjdzie poza obrys** tego, kto go
wystrzelił — nie przez stały czas, bo stały czas jest zakładem o rozmiar
kadłuba, a sandbox potrafi teraz zbudować taki, przez który wolna rakieta leci
pół sekundy. Raz opuszczony obrys uzbraja na stałe, więc pocisk wracający
dookoła planety trafia; wejście z powrotem w kadłub to już wina pilota.

Działka podążają za kursorem **niezależnie od spustu**. Wieżyczka, która
zaczyna obrót dopiero przy strzale, nigdy nie celuje tam, gdzie trzeba, w
chwili, w której trzeba.

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

### Konfigurator planety (narzędzie deweloperskie, F6)

Ocena świata wymaga do niego dolecenia, a dolot do świata, który się właśnie
zmieniło, kosztuje minutę startu, transferu i lądowania. W praktyce znaczy to,
że nikt nic nie zmienia i piaskownica ma szerokość jednej planety. F6 zamienia
pytanie „jak się lata przy 3 g i rzadkim powietrzu" w dziesięć sekund:
suwaki parametrów, przycisk, nowa planeta, statek stoi na jej lądowisku.

Overlay debugowy (F7 / O) dostał drugą kolumnę z **kompletem parametrów
planety** — wszystkim, co generator wylosował, plus tym, co z tego zbudował
(pasmo skorupy, strop powietrza, prędkość ucieczki i kołowa, długość doby,
siatka terenu, pełny piętnastowartościowy zestaw pogody). Cała planeta bierze
się z jednego seeda, więc kiedy świat lata dziwnie, pytanie zawsze brzmi
„którą z tych liczb dostał", a odczytanie jej z ekranu bije dopisanie printa i
restart. Kolumna jest po prawej, więc zostaje czytelna przy otwartym panelu po
lewej: zmieniasz parametr, przebudowujesz, widzisz wynik bez zamykania czegokolwiek.

Konsekwencja architektoniczna, warta zapisania niezależnie od narzędzia:
`generate()` rozpadło się na **`roll_parameters()`** (wypełnia pola z seeda) i
**`rebuild()`** (buduje skorupę, atmosferę i pogodę z tego, co w polach stoi
teraz). Bez tego podziału ustawienie pojedynczego parametru ręcznie wymagałoby
znalezienia seeda, który by go wylosował. Ten sam podział jest potrzebny w M3:
streaming zapisuje i odtwarza parametry planety, zamiast losować je od nowa.

Druga: `PlanetTerrain` zapamiętuje teraz kąty półek, które wypoziomował
(`plateau_angles`), zamiast zostawiać je do odnalezienia przez skanowanie
nachylenia. Teleport celuje w miejsce zbudowane po to, żeby na nim lądować, a
nie w pierwszy płaski punkt, jaki znajdzie. W M3 to samo pole wskaże, gdzie
mogą stanąć bazy.

Dwie pułapki zapłacone od razu, obie niewidoczne dla testów:

- Narzędzie pauzuje drzewo, więc świat przestaje dostawać input — klawisz
  otwierający musi należeć do narzędzia (`PROCESS_MODE_ALWAYS`), inaczej
  otwartego panelu nie da się zamknąć. **I to jest cena tej pauzy:** przy
  otwartym panelu F5 i F7 są martwe, bo obsługuje je świat. Wygląda to jak
  awaria klawiatury, więc panel krzyczy nagłówkiem, że gra stoi, zamyka się
  też Escape'em, a `_process` narzędzia odpauzowuje drzewo, gdyby kiedykolwiek
  zostało spauzowane z zamkniętym panelem.
- Escape musi być łapany w `_input`, nie w `_unhandled_key_input`: panel jest
  pełen kontrolek, a GUI zjada `ui_cancel` na długo przed tym, zanim zdarzenie
  uznane zostanie za nieobsłużone.
- `SpinBox` zwraca `float`, a `plateau_count` jest `int`. Przypisanie przez
  `set()` do statycznie typowanego pola jest wtedy błędem, nie zaokrągleniem.

Sprawdzone przebiegiem na prawdziwej scenie świata, bo smoke test jej nie
ładuje: po przebudowie statek siada 20 px nad gruntem, 0.0001 rad od środka
półki, i po 200 tickach jest w stanie LANDED. Klawisze zmierzone osobno: F6
otwiera, Escape zamyka, wymuszona pauza przy zamkniętym panelu cofa się sama.

Metodologiczna nauczka z tego samego przebiegu: sonda wstrzykiwała wyłącznie
`pressed = true` bez zwolnienia klawisza, przez co jedno naciśnięcie docierało
dwukrotnie i przełączało panel tam i z powrotem. Wyglądało to dokładnie jak
błąd w narzędziu i doprowadziło do fałszywej diagnozy. Syntetyczne zdarzenie
klawisza musi mieć parę wciśnięcie/zwolnienie, a akcje wiązane przez
`keycode` (jak wbudowane `ui_*`) nie zadziałają, jeśli ustawi się tylko
`physical_keycode`.

### Realizacja (M1.2)

`Planet` to Node2D, nie Area2D z `gravity_point`: wbudowany falloff jest sztywny
i nie da się go wygasić na skraju studni. Planety rejestrują się w grupie
`gravity_sources`, a statek sam sumuje `gravity_at()` każdego ciała w zasięgu.

Wygaszenie na granicy: pełna odwrotność kwadratu do 0.9 promienia wpływu, potem
`smoothstep` do zera. Bez tego statek dostawałby kopniaka przy przekraczaniu
granicy. Pod powierzchnią g jest przytrzymane na wartości powierzchniowej,
inaczej odwrotność kwadratu eksploduje w stronę środka.

Opór liniowy liczy sam statek (`Ship._apply_air_drag`), ciągnąc prędkość ku
prędkości powietrza (`surface_velocity_at`), nie ku zeru: atmosfera obraca się
z planetą, a `linear_damp` Area2D tłumi zawsze do zera w układzie świata.
Powłoki zostają jako źródło gęstości i oporu kątowego (liniowy override wyłączony).

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

### Obrys kadłuba a solver (M2)

Solver kontaktów jest bezkształtny: impuls liczy się z ramienia do środka masy,
pętla leci po liczbie punktów, a masa, środek masy i moment bezwładności
wychodzą z wielokąta i modułów. Nie uogólniają się natomiast **wejścia** —
`HULL_POINTS` to ręcznie wypisana lista sześciu punktów tego jednego trójkąta.
Przy modularnych kadłubach z M2 to jest pierwsza rzecz, która pęknie.

**Decyzja: obrys kolizyjny to przybliżenie, nie grafika.** Kadłub rysowany i
kadłub liczony to dwie różne rzeczy; obrys ma pasować na tyle, żeby nie
wyglądało dziwnie, a poza tym być tani i przewidywalny dla solvera. Z tego
wynikają wytyczne, a nie odwrotnie — zamiast uczyć solver radzić sobie z
dowolnym kształtem, ograniczamy kształty.

**Punkty kontaktu wyprowadzane z obrysu:** wierzchołki plus podział krawędzi ze
stałym krokiem, liczone raz przy `configure()`. Krok wynika z terenu, nie z
gustu: teren ma 1,5 px na teksel, więc przy kroku ~6 px (cztery teksele) żadna
istotna forma terenu nie zmieści się między punktami. Dziś największa przerwa
to ~11 px i na trójkącie 16×22 px to uchodzi — na kadłubie 60 px już nie,
bo iglica węższa niż przerwa przechodzi między punktami i kadłub siada na niej
niezauważony albo przez nią przenika.

**Wytyczne projektowania obrysu** (do sprawdzenia w raporcie konfiguracji,
który M2 i tak przewiduje):

| reguła | wartość | dlaczego |
|---|---|---|
| obwód obrysu | ≤ ~240 px | przy kroku 6 px to ≤ 40 punktów: bench daje 0,123 ms na 6 punktów, czyli ~0,8 ms na 40 z 16,6 ms budżetu klatki |
| liczba wierzchołków | ≤ ~12 | podział krawędzi i tak wypełni resztę; więcej wierzchołków to tylko więcej przypadków brzegowych |
| wypukłość | obrys wypukły lub prawie | `ConvexPolygonShape2D` dla pocisków bez dekompozycji; wklęsłości zostają w grafice |
| najcieńszy detal | ≥ 2× krok (≥ 12 px) | cokolwiek cieńszego jest dla próbkowania terenu niewidzialne, więc nie należy do obrysu |
| rozstaw nóg | ≥ 12 px | poniżej tego pojedynczy schodek między tekselami czyta się jako urwisko (zmierzone w M1.6) |

**Kształt dla pocisków liczony, nie rysowany drugi raz.** `CollisionShape2D`
powstaje z tego samego obrysu jako jego otoczka wypukła (`Geometry2D.convex_hull`).
Jedno źródło prawdy, a rozjazd między tym, w co trafia pocisk, a tym, co dotyka
gruntu, przestaje być możliwy.

**Stałe, które muszą przestać być bezwzględne.** `MAX_PENETRATION` (24 px w
marszu po terenie) nasyci się na większym kadłubie spadającym szybciej, a
korekta pozycji po cichu poprawi za mało — musi skalować się rozmiarem statku.
`CONTACT_ITERATIONS` = 4 ma w komentarzu „plenty for six points"; zbieżność
sekwencyjnych impulsów spada z liczbą kontaktów, więc albo iteracje rosną z
liczbą punktów, albo liczba punktów ma twardy limit (i wtedy limit jest tym,
co wymusza obwód z tabeli).

## 7. Lądowanie

Lądowanie jest mechaniką skillową. Trudność wynika z parametrów (G, stan silników, atmosfera, teren), nie ze skryptów.


**Kontakty liczy się względem gruntu, nie względem świata.** Solver brał
prędkość kadłuba w układzie świata, więc tarcie dążyło do zatrzymania statku
**w świecie** — a grunt pod nim jedzie, bo planeta się obraca. Efekt: statek
stojący na powierzchni ślizgał się po niej, i to tym szybciej, im szybciej
kręci się planeta (przy `MAX_SPIN_RATE` to 20 px/s, a konfiguratorem można
ustawić dziesięć razy tyle).

Poprawka jest jednolinijkowa w zamyśle: prędkość w punkcie kontaktu to
`_velocity_at(...) - planet.surface_velocity_at(punkt)`, i to zarówno dla
składowej normalnej, jak i stycznej. Tarcie zaczyna wtedy dociągać statek do
prędkości gruntu, czyli robi to, co tarcie.

Dlaczego testy tego nie widziały: jedyny test obrotu planety sprawdzał statek
**zamrożony po udanym lądowaniu**, którego pozycję przelicza osobny kod
(`polar_to_world`), a nie solver. Ścieżka, na której statek po prostu leży na
skale — podwozie schowane, lądowanie odrzucone, kontakt trzyma go solverem —
nie miała żadnego pokrycia. Doszła faza GROUND_RIDE: zrzut na obracającą się
planetę ze schowanym podwoziem i pomiar dryfu w ramce planety. Bez poprawki
0.0165 rad poślizgu na 0.0400 rad obrotu gruntu, z poprawką 0.0031.

Przy okazji wyszło, że test „a landed ship comes to rest" mierzył prędkość
względem świata. Po poprawce statek stojący na planecie *ma* prędkość w
świecie (8.0 px/s na tym seedzie) i to jest poprawne, więc test mierzył od
tamtej chwili złą rzecz: przepuściłby ślizgający się statek i odrzucił
prawidłowo niesiony. Mierzy teraz prędkość względem gruntu, co pozwoliło
zacieśnić próg z 20 do 5 px/s — wychodzi 0.2.
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
- nadwyżka prędkości = odmowa lądowania; **rachunek wystawia dopiero kontakt**, który po niej następuje (patrz niżej),
- przekroczenie nachylenia lub kąta = przewrócenie: tryb fizyki punktów kontaktu (każda noga to punkt z siłą podparcia i tarciem, nie wchodzi w teren), statek toczy się w dół zbocza i obija, silniki dostają, gracz może ratować ciągiem.

### Model uszkodzeń: jedno zdarzenie, jeden rachunek

Zgłoszone z gry: lądowanie na podwoziu **odrobinę** za szybko kosztowało 70%
kadłuba albo śmierć, a rozpędzona kolizja z gruntem 18%. Dokładnie na odwrót
niż powinno, i z trzech niezależnych powodów.

**Podwójne obciążenie.** Odrzucone lądowanie płaciło dwa razy za jedno
przybycie: raz w kontroli podwozia (za samą odmowę), raz w kontakcie, który
nastąpił w tym samym ticku. Przy 120 px/s to było 0,75 + 0,24 — czyli zgon.
Teraz kontrola podwozia tylko odmawia, a liczy to, co naprawdę dotknęło.

**Nogi były droższe od kadłuba.** Stawka podwozia (0,01 na px/s) była 2,5 raza
wyższa od kadłubowej (0,004), przy progu niższym o 15 px/s. Absorbowanie tego
jest jedynym powodem, dla którego nogi istnieją. Teraz **tolerancja nóg nigdy
nie schodzi poniżej kadłubowej** (`max(próg_kadłuba, limit_podwozia)`) — ich
stat decyduje o tym, czy lądowanie zostanie *przyjęte*, a w obrażeniach może
tylko podnieść poprzeczkę, nigdy jej obniżyć.

**Krzywa liniowa i tylko składowa normalna.** Liniowa robiła z każdego
przybycia to samo zdarzenie, tylko bardziej — a śmierć wypadała przy 310 px/s,
czyli powyżej prędkości ucieczki. Teraz koszt to **kwadrat nadwyżki** nad
tolerancją, z odpisem całego kadłuba przy 100 px/s nadwyżki (kadłub) i 260
(nogi). Do tego lot w zbocze jest **głównie ślizgiem**: składowa normalna
bierze ułamek prędkości, reszta idzie wzdłuż skały, więc model czytający samą
normalną nazywał katastrofę muśnięciem. Styczna liczy się z wagą 0,5.

Zmierzone po zmianie (ten sam seed, ta sama planeta):

| co | prędkość | przed | po |
|---|---|---|---|
| na nogach, odrobinę za szybko | 70 px/s | ~29% | **0,3%** |
| na nogach, twardo | 120 px/s | ~99% (zgon) | **4,3%** |
| na brzuchu, podwozie schowane | 120 px/s | 24% | **30%** |
| płasko w zbocze | 120 px/s | ~18% | **63%** |
| płasko w zbocze | 160 px/s | ~28% | **72%** |

Ślizg po skale nalicza się co tick kontaktu, więc długie tarcie o zbocze boli
bardziej niż jedno uderzenie — i tak ma być: każde odbicie to osobne
uderzenie, a statek koziołkujący po górze powinien się rozpadać.

### Prędkość względem powietrza to nie prędkość

Zgłoszone z kokpitu: smugi pędu leżały na ekranie, kiedy statek stał na
nogach. Zmierzone: **zaparkowany statek melduje 21 px/s** na planecie testowej.

Nie kłamie. On naprawdę się porusza — `_hold_landed_pose()` przestawia go co tik
wzdłuż obracającego się gruntu, a bryła zamrożona jako `FREEZE_MODE_KINEMATIC`
melduje to przestawianie jako prędkość. Błąd był gdzie indziej: **czterech
czytelników pytało „jak szybko", a każdy z nich miał na myśli „jak szybko
względem powietrza"** — a powietrze kręci się razem z planetą.

Czytelnicy: zasłona pędu, smugi kondensacyjne, nagrzewanie kadłuba i kierunek
rozmycia. Stąd `Ship.air_velocity()` / `airspeed()` jako jedna funkcja zamiast
tego samego odejmowania wpisanego w cztery miejsca — względem
`nearest_planet()`, czyli dokładnie tego ciała, z którego bierze się
`air_density`: prędkość mierzona względem jednej planety i gęstość wzięta z
drugiej to liczba o niczym.

Przyrząd V/S robił to poprawnie od początku — odejmuje `surface_velocity_at()` i
ma na to komentarz „to ta sama wielkość, której używa sprawdzenie lądowania,
więc nie mogą się nie zgadzać". Trzeba było rozciągnąć tę regułę na resztę,
a nie wymyślać nową.

Przy okazji wyszła rzecz, która jest fizyką, nie usterką: lot zgodnie z
obrotem planety grzeje mniej niż lot pod prąd. Za darmo, bo to ta sama
odjęta wielkość.

**Dwa stany spoczynku, nie jeden**, i to jest ta połowa, którą łatwo przegapić.
Statek wylądowany (zamrożony, przestawiany) czyta teraz 0,0 px/s. Kadłub
leżący na skale bez lądowania (żywa bryła trzymana przez solver kontaktów)
czyta **4,3 px/s** i zawsze będzie coś czytał — solver oddycha. Test nie
wymaga od niego zera, tylko tego, żeby żaden czytelnik nie wziął tego za ruch:
próg to własna stała zasłony (`REFERENCE_FLOW * FAINTEST / STRONGEST` = 4,7
px/s). Margines jest cienki i jest zapisany tutaj właśnie dlatego.

### Stan "wylądowany"

Po udanym lądowaniu statek zamrożony (`freeze = true`, tryb kinematyczny) i przypięty do node'a planety. Planety mogą się obracać (dzień i noc); wylądowany statek obraca się razem z nią. Start = odmrożenie z prędkością styczną powierzchni.

W stanie wylądowanym: naprawa, tankowanie, zbieranie zasobów, handel na lądowisku, autosave.

**I silniki zgaszone**, co brzmi jak oczywistość, a było błędem zgłoszonym z
kokpitu. `_integrate_forces` jest miejscem, gdzie liczą się przepustnice i gdzie
woła się `advance()`, a statek na nogach nigdy tam nie dociera: wychodzi na samej
górze, a ciało jest poza tym zamrożone, więc serwer fizyki nie ma powodu go
wołać. Silnik trzymał więc przepustnicę, którą miał w chwili, gdy nogi przejęły
ciężar — płomień palił się dalej, pętla grała dalej i **nic z drążka tego nie
czyściło, bo nie drążek to postawił**.

Zdarzało się „czasem", i to jest wskazówka, a nie przypadek: `_try_land` odmawia,
kiedy pilot żąda ciągu, więc potrzeba przyziemienia w ciągu tego pół sekundy,
które główny napęd schodzi z ciągu po puszczeniu klawisza. Czyli dokładnie tak
wygląda ostrożne lądowanie na silniku.

Przepustnice są **zerowane**, a nie czytane z `commands`, i to jest decyzja, nie
mechanika: statek na nogach ma silniki wyłączone. Pilot opierający się na
klawiszu obrotu przy zaparkowanym statku dostaje tyle samo co wcześniej — nic —
a żądanie ciągu jest jedyną rzeczą, która coś robi: startuje.

### Skąd trudność

- silne G: stosunek ciągu do ciężaru bliski 1, mało zapasu na hamowanie,
- uszkodzony silnik główny oscyluje i przerywa,
- asymetryczna awaria silnika obrotowego ciągnie w bok przy każdym odpaleniu,
- rzadka atmosfera nie hamuje, gęsta hamuje mocno,
- planety górzyste mają mało płaskich miejsc.

### Generacja terenu pod lądowanie

Generator gwarantuje miejsca do lądowania: po szumie przebieg wyrównujący wybrane odcinki (plateau), częstość zależna od typu planety. Lądowiska przy bazach płaskie z definicji. Kratery po eksplozjach tworzą nowe zbocza; lądowanie na skraju krateru jest ryzykowne.

### Realizacja (M2, moduły broni i pomiar)

`ShotModData` dziedziczy po `ModuleData`, a liczby wynikowe **cache'uje
Hardpoint**: `effective()` i `energy_cost()` przeliczają się przy zmianie
modułu albo broni, nigdy przy strzale. Gdy nic nie jest wpięte, `effective()`
zwraca samą broń — najczęstszy przypadek nie alokuje nic.

**Kolejność nie ma znaczenia, bo wszystko jest mnożnikiem**, a mnożenie tego
nie rozróżnia. To nie jest deklaracja, tylko konsekwencja kształtu danych — i
jest zmierzona testem: 14,09 w obu kolejnościach.

Efekty pocisku są danymi czytanymi przy spawnie. `PIERCE` przesuwa pocisk za
krater i odejmuje jedno przebicie (inaczej następny tick trafiłby w tę samą
ścianę). `BLAST` robi zapytanie kształtem do serwera fizyki i rani to, czego
nie trafił, z odległością liniowo do 25% obrażeń — pytanie „co da się zranić"
zadane tak samo jak przy kontakcie, czyli bez osobnej grupy. `INCENDIARY` jest
na razie tylko wartością enuma.

**Rzadkość kupuje sloty**, nie tylko większe liczby: `mod_slots = min(rzadkość, 3)`.

### Pomiar: arytmetyka z tej sekcji przeżyła kontakt z zasobami

| | burst | sustained | w IDEAS |
| --- | --- | --- | --- |
| autocannon | 0,320 | **0,179** | 0,18 |
| siege slug | 0,300 | **0,174** | 0,17 |
| „minigun" 20/s | 0,400 | **0,200** | 0,40 / 0,20 |

Rozjazd sustained między bazowymi broniami: **3%** przy dopuszczalnych 10%.
Każda broń sustainuje wyraźnie mniej, niż burstuje. Minigun kupuje szczyt
(1,25× autocannona) i prawie nie rusza średniej — dokładnie „minigun, który
się zatyka".

To jest test, który powie, kiedy nowa broń albo nowy generator zaczną
spłaszczać bronie do jednej liczby.

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

### Stan orbity, nie tryb orbity

Pierwotny projekt (M1.5) miał **orbit lock**: po ~2 s bez ciągu, przy prawie
kołowej orbicie, statek przechodził w kinematyczny okrąg liczony analitycznie.
Uzasadnienie brzmiało „ręczne utrzymanie idealnej orbity kołowej jest nudne",
czyli zakładało, że orbita ucieka i trzeba ją poprawiać.

**To założenie obaliliśmy własnym pomiarem w tym samym milestonie.**
`tools/orbit_endurance.gd`, 5 minut lotu: orbita kołowa 2.0 R dryfuje 0,05%,
eliptyczna 0,003%. Nie ma czego poprawiać. Mechanizm został usunięty.

Co kosztował, zanim to do nas dotarło:

- **Druga implementacja ruchu, która musi się zgadzać z pierwszą.** Dwa błędy
  znalezione przez gracza w dwóch kolejnych sesjach i oba tego samego kształtu:
  odwrócony kierunek lotu (styczna liczona z inną skrętnością niż kąt, którym
  lock przesuwał statek) i martwe dysze obrotowe (`_integrate_forces` wychodziło
  przed pętlą sił, więc zaparkowany statek nie dawał się obrócić).
- **Cichą zmianę fizyki.** Lock brał aktualny promień i *prędkość kołową*, więc
  kasował do 6% błędu prędkości i do 6 px/s prędkości radialnej — sam po cichu
  cyrkularyzował orbitę.
- **Zawężenie pojęcia orbity.** Tolerancje przyjmowały tylko orbity prawie
  kołowe, więc porządna elipsa nigdy nie dostawała etykiety ORBIT.
- **Sześć miejsc w smoke teście z `orbit_lock_enabled = false`**, żeby nie
  wchodził w drogę innym fazom. Funkcja, którą trzeba wyłączać, żeby testować
  resztę, rzadko zarabia na siebie.

Teraz „czy jesteśmy na orbicie" jest **czytane z trajektorii**, nie włączane.
`Planet.orbit_state(point, velocity)` klasyfikuje stożek na podstawie apsyd:

| stan | warunek | HUD |
|---|---|---|
| ORBIT | perycentrum nad atmosferą, apocentrum w studni | `ORBIT`, zielony |
| DECAYING | perycentrum w atmosferze | `ORBIT DECAYING`, bursztyn |
| SUBORBITAL | perycentrum pod stropem terenu | (cicho), czerwony |
| ESCAPE | apocentrum poza studnią, albo statek już poza nią | `LEAVING`, szary |

Dwa szczegóły, które nie są oczywiste:

- **Poza `influence_radius` nie ma orbity.** Grawitacja jest tam zerowa, więc
  stożek byłby fikcją narysowaną wokół ciała, które nie ciągnie.
- **Trajektoria otwarta lecąca na zewnątrz ma perycentrum w przeszłości, nie w
  przyszłości.** Dlatego SUBORBITAL wymaga albo ruchu do środka, albo orbity
  zamkniętej — inaczej start z powierzchni na prędkości ucieczki meldowałby, że
  za chwilę uderzy w grunt.

SUBORBITAL celowo nie trafia na linię statusu: to normalny stan statku, który
startuje albo podchodzi do lądowania, więc pisanie tego byłoby szumem na
wierszu, który ma nieść nowiny. Kolor perycentrum i tak to pokazuje.

Testy poszły za tym: zamiast fazy sprawdzającej, czy lock przejmuje i oddaje
sterowanie, jest pięć przypadków klasyfikacji (po jednym na stan plus wyjście
poza studnię) i trzy odczyty ciągłe — kołowa i eliptyczna orbita muszą czytać
się jako ORBIT tick po ticku przez cały przelot, a aerobraking musi *sam* zacząć
czytać się jako DECAYING, kiedy drag zje perycentrum.

Orbita zamknięta zostaje stanem spoczynku w sensie rozgrywkowym (autosave,
skanowanie, planowanie) — tylko że jest nim dlatego, że statek tam jest, a nie
dlatego, że silnik przestał go liczyć.

Jeśli kiedyś dojdzie przyspieszenie czasu, te 0,05% na 5 minut zrobi się
widoczne i wtedy wrócą rails — ale jako „propaguj stożek analitycznie", nie
„przyklej do okręgu", i pisane pod ten cel.

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

### Skaner: znaczniki ciał niebieskich na obrzeżu ekranu (M2, zalążek)

Przy 640x360 planeta albo wypełnia widok, albo nie ma jej wcale — a „nie ma
jej wcale" obejmuje zarówno „jest tuż za plecami", jak i „jest pół układu
stąd". Skaner zamienia to na kierunek i liczbę.

- **Czyta grupę `gravity_sources`**, nie własną listę. To ta sama definicja
  „ciała niebieskiego", której używa fizyka, więc księżyce i gwiazdy z M3
  pojawią się bez zmiany w tym pliku.
- **Znacznik tylko dla ciał, których środek jest poza ekranem.** To, co widać,
  nie potrzebuje strzałki.
- **Pierścień jest prostokątem, nie okręgiem**, bo ekran jest prostokątem;
  okrąg zostawiałby puste rogi i tłoczył się przy krótszych bokach.
- **Rozmiar znacznika mówi, jak duże jest ciało, nie jak blisko.** W 2D nie ma
  perspektywy — promień planety na ekranie to jej promień razy zoom, niezależnie
  od odległości — więc odległość nie ma tu nic do powiedzenia. Niesie ją jasność
  (pełna w polu grawitacyjnym, przygaszona poza nim) i liczba. Pierwsze podejście
  liczyło „rozmiar pozorny" i było po prostu błędnym rozumowaniem przeniesionym
  z 3D: oba ciała wpadały w to samo ograniczenie i znaczniki wychodziły
  identyczne.
- **Liczba to odległość do powierzchni, nie do środka.** Na planecie o promieniu
  1000 px to są dwie zupełnie różne wielkości, a pilot działa na tej pierwszej.
- **Kolor to `surface_color` ciała rozjaśniony do czytelności**, żeby znacznik i
  planeta, którą się w końcu zobaczy, były rozpoznawalnie tym samym obiektem.
- **Geometria jest oddzielona od rysowania.** `contacts(to_screen, view)` zwraca
  dane, `_draw_marker()` je maluje. Dzięki temu testuje się bez kamery i bez
  wyrenderowanej klatki, a `to_screen` (canvas transform) niesie pozycję, zoom i
  — kiedy dojdzie kamera lądowania z VISUALS V4 — obrót kamery. Liczenie kąta
  ręcznie w przestrzeni świata cicho by się wtedy rozjechało.

#### Loot na skanerze

Skrzynki dostają **romb**, nie trójkąt, żeby nigdy nie czytały się jak mała
planeta, i **własny, dużo krótszy zasięg** (4000 px wobec 20000): skrzynka po
drugiej stronie układu nie jest decyzją, tylko szumem. Kolor to rzadkość — ta
sama tabela, którą pomalowane jest samo pudełko. Lista jest sortowana od
najbliższej i przycinana, żeby ograna planeta nie zamieniła krawędzi ekranu w
płot.

Dwie rzeczy różnią loot od ciał niebieskich i obie są celowe:

- **Skrzynka dostaje znacznik także wtedy, kiedy jest na ekranie.** Planeta
  przestaje go potrzebować, gdy ją widać; skrzynka to 12 px pudełka na tle
  całej planety terenu, a wskaźnik znikający w chwili, gdy zwracasz się ku
  rzeczy, którą wskazywał, zawodzi dokładnie wtedy, kiedy jest używany. Na
  ekranie jest to pusty romb **obejmujący** skrzynkę. Pierwsza wersja miała
  9 px i kolor rzadkości — czyli była mniejsza od pudełka i w dokładnie tym
  samym kolorze co ono. Rysowała się bezbłędnie i była niewidoczna; teraz ma
  30 px i wychodzi poza poświatę.
- **Kolizje etykiet są rozstrzygane, nie ignorowane.** Dwa znaczniki w prawie
  tym samym kierunku drukowały liczby jedna na drugiej, co czyta się jak jedna
  zła liczba, a nie jak dwie dobre (złapane na zrzucie: planeta i skrzynka po
  jej drugiej stronie, obie na górze pierścienia, `12249`). Pierwsza etykieta
  zajmuje miejsce; ciała rysują się przed lootem, a loot od najbliższego, więc
  z kolizji wychodzi odczyt bardziej wart posiadania. Znaczniki zostają
  zawsze — gubi się tylko liczba.

Zasięgi są na razie stałymi. W M5 stają się własnością modułu skanera: lepszy
skaner widzi dalej, i to jest kolejna rzecz, którą można znaleźć w skrzynce.

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

**Realizacja (M4).** 1,5, ale liczone względem **wszystkiego**, co gwiazda
trzyma (`outer_radius()`), a nie względem ostatniej planety. Głęboka stacja
potrafi stać dalej niż najdalszy świat, a blokada kończąca się przed nią
pozwalałaby skoczyć z doku — czyli z jedynego miejsca w układzie, z którego
wyjście powinno znaczyć „najpierw wylecieć".

Skoro cały układ leży wtedy wewnątrz z definicji, **nie ma drugiej reguły dla
planet**: wszędzie tam, gdzie planeta mogłaby cię przytrzymać, gwiazda już
trzyma. Jedna liczba, jedno pytanie, jedno miejsce w kodzie.

Zmierzone na 300 seedach: promień blokady wychodzi od 72 tys. do 504 tys.
pikseli, czyli siedmiokrotny rozrzut. To jest cecha, nie wada — ciasny
układ jest wygodną bazą, rozległy jest uciążliwy do opuszczenia — i jest do
przyjęcia tylko dlatego, że w próżni nie ma oporu: 900 N na 16,6 kg to
54 px/s², więc pierwsza minuta ciągłego palenia to już około 97 tys. pikseli.
Wspinaczka z największego układu to kilka minut palenia, a nie dwadzieścia
minut lotu ze stałą prędkością.

`is_mass_locked(point)` i `jump_clearance(point)` to **jedna odpowiedź**, nie
dwie: pierwsze jest tym, na czym rozgałęzi się maszyna stanów, drugie tym, co
odlicza odczyt, i granica, co do której by się nie zgadzały, to HUD mówiący
„czysto" obok napędu odmawiającego ładowania.

**Na mapie układu** zasięg rysowania sięga teraz blokady z niewielkim
zapasem, a nie ostatniej orbity: mapa ucinająca jedyne kółko, którego szuka
ktoś planujący wylot, zamienia „ile jeszcze" z powrotem w zgadywankę.
Pierścień jest **jednokolorowy**. Pierwsza wersja zapalała go na zielono po
wyjściu, co postawiło zielony pierścień obok zielonego znacznika statku i
zrobiło z faktu o układzie kontrolkę stanu. To, gdzie stoi statek względem
linii, już mówi, czy jest czysto; kolor niesie sam odczyt.

### Skaner

`Galaxy.systems_within(current_pos, scanner_range)` zwraca kandydatów. HUD rysuje wskaźniki na krawędzi ekranu w kierunku każdego. Trzy niezależne parametry, każdy z osobnego modułu statku (czyli z lootu):

- zasięg skanera: które systemy w ogóle widzisz,
- zasięg napędu: dokąd fizycznie doskoczysz,
- paliwo: koszt = f(dystans, masa statku), z aktualnego stanu baku.

Systemy widoczne, ale nieosiągalne, pokazywane szaro. Jakość skanera decyduje, ile wiesz przed skokiem: kierunek i dystans, potem typ gwiazdy, liczba planet, poziom zagrożenia, stacje. Opcjonalnie czas skanowania i szum sygnału.

**Realizacja (M4): trzy moduły, trzy liczby, i jedna wspólna cena.**

`ScannerData` (zasięg w ly + `depth`), `JumpDriveData` (zasięg, ładowanie,
spalanie na ly) i `TankData` (pojemność). Rozdzielone, bo o to chodzi:
pilot ma móc **widzieć dalej, niż doskoczy**, albo **doskoczyć dalej, niż
go stać**. Jeden moduł trzymający wszystkie trzy liczby zamieniłby zasięg w
jedną statystykę idącą w górę.

`depth` kupuje się **rzadkością, nie afiksem** — tak jak funkcje komputera
pokładowego. „Mówi, ile tam jest światów" nie jest dokładniejszą wersją
„mówi namiar"; to inny przyrząd, a nie większy, więc nie ma liczby, do
której afiks mógłby dążyć.

**Skaner przeglądowy nie jest tym, co znajduje planety w bieżącym
układzie**, i to jest decyzja, nie przeoczenie. `ScannerHud.scan_range`
jest w pikselach, a `StreamingManager` gwarantuje, że nic nie śpi w jego
zasięgu — moduł mogący tę liczbę podnieść byłby modułem obiecującym
kontakty, których świat jeszcze nie zbudował. Dwa czujniki zostają dwoma
czujnikami: jeden patrzy w układ, drugi na zewnątrz.

**HUD (M4).** `JumpHud`, osobny węzeł od `ScannerHud` — ta sama krawędź
ekranu, ale inny przyrząd, więc i inny znak: szewron zamiast trójkąta, bo
dwa rodzaje rzeczy na jednym pierścieniu trzeba odróżnić przy trzech
pikselach. Trzy wejścia i żadne z nich nie jest tym samym, co inne:

- zasięg skanera → **które** systemy w ogóle są rysowane,
- `depth` → **co** jest pod nimi napisane (sam dystans / nazwa / + liczba
  światów / + doków),
- zasięg napędu i stan baku → **jakim kolorem** (szary poza zasięgiem,
  bursztyn w zasięgu bez paliwa, nawigacyjny, gdy stać).

**Trzy rozróżnialne obrazy braku**, nie pusty ekran: „brak skanera",
„mass lock, jeszcze N px" i normalna praca. HUD, który nic nie rysuje w
trzech różnych sytuacjach, powiedział pilotowi trzy razy to samo i za
każdym razem co innego.

Sześć znaczników naraz, najbliższe — ta sama reguła, co przy skrzynkach:
dziewięć nazw dookoła ramki 640x360 zlewa się w jedną szarą plamę.
Etykieta, która weszłaby na już napisaną, jest **pomijana, nie
przesuwana**: nazwa obok cudzego szewronu jest gorsza niż szewron bez
nazwy, który przynajmniej nadal mówi „coś tam jest". Wybrany cel pisze
się pierwszy, więc zawsze wygrywa. Przy krawędzi bocznej etykieta idzie
**obok** znacznika, a nie pod nim — wyśrodkowana szła przez własny
szewron, bo „do środka" znaczy tam w bok.

**Paliwo** to nowy zasób i odpowiada regule z sekcji 14: energia mierzy
walkę w sekundach i sama się odnawia wszędzie, paliwo mierzy zasięg w
skokach i bierze się tylko z doku. Koszt skoku jest liniowy w dystansie i
w masie kadłuba — arkadowo, nie poprawnie, bo to cała reguła, którą pilot
ma trzymać w głowie. Niedobór **nie jest odmową**: `draw_fuel()` oddaje
tyle, ile miał, a brakujący ułamek to szansa na misjump. Brak baku to co
innego niż mały bak — pojemność zero, bez szyny kadłuba, bo statek bez
baku nie jest statkiem o krótkim zasięgu, tylko statkiem, który zostaje.

To zamyka też ostatni otwarty punkt M3: dok uzupełnia teraz paliwo, a nie
tylko energię, i `fully_serviced()` czeka na pełny bak.

**Co to kosztowało stockowego darta, zmierzone.** Trzy moduły na kadłubie
to +3,4 gabarytu, czyli masa 16,6 → 20,0 (+20%). Wszystkie trzy siedzą na
środku masy kadłuba, tam gdzie już siedziały ładownia i generator — gniazdo
gdziekolwiek indziej to błąd wyważenia przykręcony w stoczni. Skutek
uboczny tej reguły: masa dokładnie na środku masy **nie dokłada nic do
momentu bezwładności**, więc alokator musi mniej opierać się na dławikach
obrotowych, żeby nie zakręcić statkiem — autorytet strafe spadł z 280,4 do
264,4 N. Razem: zgaszenie bocznego dryfu 100 px/s to 5,9 s na gołym
kadłubie i 7,4 s z pełnym wyposażeniem skokowym (plus rozkręcenie dysz).
Pierwotny budżet testu, 8 s, był na to za ciasny i został podniesiony do
11 s — z zapisanym pomiarem, nie „dopóki nie przeszło".

### Sekwencja skoku

Maszyna stanów w kontrolerze statku:

1. **Idle**: poza mass lock, cel wybrany przez wycelowanie dziobem w wskaźnik (stożek ±15°) i przytrzymanie klawisza.
2. **Charging**: 2 do 4 s, przerywane obrażeniami lub puszczeniem klawisza, częściowe spalenie paliwa, awaryjny napęd może przerwać sam.
3. **Transit**: shader pełnoekranowy (smugi, radialne rozmycie, przesunięcie koloru), 1.5 do 2 s. Pod efektem: zapis delty starego systemu, zwolnienie sceny, generacja nowej z seedu w wątku, instancjonowanie.
4. **Arrival**: pozycja = `target.outer_radius * (source_pos - target_pos).normalized()`, kierunek zachowany, prędkość zredukowana. Efekt wygasa, lecisz dalej.

**Realizacja (M4).** `JumpController` to cztery stany i jedna reguła na
każde przejście, i **nic poza tym**: nie rusza statku, nie zwalnia systemu,
nic nie rysuje. Kiedy stary system ma zniknąć, mówi o tym sygnałem, a robi
to świat — jedyne miejsce, które wie, z czego system się składa. Ten podział
jest powodem, dla którego da się to w ogóle testować: skok to jedyna akcja w
grze, która niszczy scenę, w której zachodzi.

Sama wymiana okazała się darmowa: `StreamingManager.bind()` od początku
zaczynał od `clear()`, a komentarz przy nim mówił wprost „test albo skok
między systemami". Statek nie jest dzieckiem żadnego systemu, więc przeżywa
obie strony.

**Paliwo palone w trakcie ładowania**, nie na starcie i nie na końcu. Stąd
częściowe spalenie przy przerwaniu bierze się samo, bez drugiej reguły, a
bak jest czytelny w trakcie. Rata jest **przycinana do reszty opłaty** —
granica tiku rzadko dzieli czas ładowania, więc ostatni tik 2,4-sekundowego
spoolu przy 60 Hz liczył pełną stawkę za ułamek sekundy i skok wychodził 0,8%
droższy, niż kosztował. Mało, i dokładnie taki błąd, który zostaje na zawsze,
gdy nikt na niego nie patrzy.

**Cel zatrzaśnięty** w chwili rozpoczęcia ładowania. Dziób służy do wybrania
celu, nie do trzymania go — skok anulowany przez trzystopniowy dryf byłby
skokiem, którego nikt nie ukończy w zakręcie. Przerywa puszczenie klawisza
albo trafienie.

**Celowanie liczy się w układzie świata, nie ekranu.** Pierwsza wersja
pytała przez `canvas_transform` i dawała dobrą odpowiedź z złego powodu:
galaktyka i system leżą na tej samej płaszczyźnie, więc „dziób w to celuje"
to pytanie o dwa kursy i kamera nie ma tu nic do powiedzenia.

**Zasłona tranzytu** (`TransitVeil` + `shaders/transit.gdshader`) to jedyny
efekt w tej grze, który ma **zadanie, a nie wygląd**: pod nią znika stary
system i powstaje nowy, więc kształt krzywej jest projektem, nie gustem.
Rośnie przy ładowaniu (do 0,22 — widać, że napęd się kręci, a dalej da się
lecieć i anulować), jest **pełna przed wymianą** i trzymana do końca
tranzytu, gasnie dopiero na przylocie — i to jest powód, dla którego
Arrival jest stanem, a nie chwilą.

Rozmycie radialne liczone **do środka**, nie na zewnątrz: próbkowanie w
stronę środka ciągnie środek kadru po krawędziach, czyli w tę stronę, w którą
widok ciągnie statek, który gdzieś leci. Smugi to jedna wartość na kąt,
stała wzdłuż promienia — przy 180 sektorach wyszły kliny po dwadzieścia
pikseli i ekran czytał się jak tablica testowa, a nie jak prędkość; przy 900
są smugami. Kolor idzie w chłód, bo ciepło i czerwień ta gra ma już zajęte
na rzeczy, które idą źle.

### Paliwo jako ryzyko

Skok z niedoborem paliwa nie jest zablokowany, tylko ryzykowny. Brakujący procent to szansa na misjump: pusty sektor międzygwiezdny (typ "systemu" bez gwiazdy: wraki, piraci, porzucony tanker z paliwem) albo dotarcie z uszkodzonym napędem. Analogicznie skok na styku zasięgu.

**Realizacja (M4).** Ryzyko to **gorszy z dwóch** czynników, nie ich suma:
brakujący ułamek opłaty i to, jak blisko krawędzi zasięgu napędu leży cel
(liczone dopiero od 85% — napęd poproszony o dziewięć dziesiątych tego, co
umie, jest używany, a nie nadużywany). Suma zrobiłaby obrzeże mapy
nielotnym z powodu, którego nikt nie odczyta z HUD-u.

Rzut zapada **w połowie tranzytu**, nie na starcie: całe ładowanie jest
opłacone, zanim ktokolwiek się dowie, i to jest to, co sprawia, że zakład
kosztuje niezależnie od wyniku. Odkąd niedobór jest ryzykiem, ładowanie
**nie przerywa się na pustym baku** — bierze, ile jest.

Najważniejsza konsekwencja jest architektoniczna: **adresem przestał być
indeks, a stała się pozycja w latach świetlnych.** Nie da się być „w systemie
numer -1"; da się być w punkcie. `Galaxy.at` jest prawdziwym adresem,
`Galaxy.here` wygodą (-1 w przerwie), a skaner działa w pustce bez żadnej
zmiany, bo zawsze pytał o punkt, nie o pozycję na liście.

`StarSystem.deep_space()` — bez gwiazdy, bez ciał, bez mass locka. Brak
gwiazdy to jedyna łaska tego miejsca: nic cię nie trzyma, trzyma cię bak, i
to jest inny rodzaj uwięzienia. Okazało się mniejszą robotą, niż brzmi:
`StreamingManager` sprawdzał `star != null` od M3, bo system bez gwiazdy i
tak kiedyś musiał się pojawić.

Sektor jest **kluczowany pozycją** (zaokrągloną do dziesiątej części roku
świetlnego), więc ten sam skok w przepaść dwa razy daje tę samą pustkę o tej
samej nazwie — miejsce, do którego da się wrócić.

Z dwóch wyników, które wymienia ta sekcja, zrobiony jest sektor. „Dotarcie
z uszkodzonym napędem" czeka na to, aż moduły będą miały stan techniczny
— dziś ma go tylko silnik. Zawartość pustki (wraki, piraci, porzucony
tanker) idzie z M5, bo pusty sektor bez niczego w środku to kara bez treści.

### Generacja galaktyki

Jeden seed galaktyki. Systemy rozłożone przez Poisson disk sampling, odległości zbliżone do zasięgów skoku. Seed systemu = hash(galaxy_seed, index), seed planety = hash(seed_systemu, index). Sprawdzenie spójności grafu (BFS) dla bazowego zasięgu napędu, żeby startowy statek nie utknął. Wyspy poza grafem jako late game za lepszym napędem. Dane w autoloadzie `Galaxy` z gridem do zapytań o sąsiedztwo.

Save = seed galaktyki plus słownik delt.

**Realizacja (M4).** Miarą tego kawałka jest to, jak **mało** zapisuje. Sto
kilkanaście systemów, ich gwiazdy, planety, księżyce, teren i nazwy wracają z
jednej liczby, więc plik trzyma tylko dwie rzeczy, których ziarno nie
wyprodukuje: co gracz zmienił w świecie i co gracz ma. Dzień, w którym zapis
będzie musiał zapamiętać, **gdzie jest planeta**, jest dniem, w którym
generator przestał być prawdą — i dlatego kształt pliku jest sprawdzany
testem na równi z jego treścią.

Moduły pakowane przez `get_property_list()`, a nie przez ręczną listę pól.
Ręczna lista zapomina to pole, które ktoś dodał w zeszłym tygodniu, a
zapomina zawsze liczbę z rzutu — więc zapis oddawałby legendarny napęd z
pospolitymi wartościami i wyglądałoby to dobrze aż do pierwszego odczytania
karty.

`var_to_str`, nie JSON: zapis jest pełen `Vector2` i tablic typowanych, a
JSON każdy z nich zamienia w coś innego. Pule są **przycinane przy
wczytaniu**, nie ufane — zapis sprzed wymiany baku nie może oddać więcej,
niż mieści ten, który jest teraz. Zapis o nieznanym kształcie jest
**odrzucany, nie zgadywany**; pół-odczytany zapis to uszkodzony wszechświat,
który wygląda dobrze do chwili, gdy pilot ląduje tam, gdzie już nic nie ma.

Autosave przy przylocie — i przy misjumpie, który jest przylotem najbardziej
wartym zapisania, bo pilot za chwilę może się dowiedzieć, że nie odleci.
Wznowienie dzieje się **przed zbudowaniem świata**: pierwsza wersja
odtwarzała stan po starcie, co otwierało system startowy, generowało jego
teren i wyrzucało go — widoczne mknięcie złego miejsca w funkcji, której
całym zadaniem jest postawić pilota tam, gdzie był.

### Realizacja (M4): liczby zmierzone, nie zgadnięte

`GalaxyMap` — czysta dana, jak `StarSystem`: galaktyka istnieje, zanim
powstanie jakikolwiek węzeł. Dwie przestrzenie współrzędnych zostały
rozdzielone tak, jak mówi ta sekcja: `GalaxyMap` to lata świetlne i sto
kilkadziesiąt punktów, `StarSystem` to piksele i jedna gwiazda. Skaner i
napęd pytają pierwszego, wszystko, co lata — drugiego.

**Poisson disk ze zmiennym promieniem.** Bridson, ale odstęp rośnie z
odległością od środka: `SPACING * lerp(1, RIM_SPREAD, (r/R)^3)`. Gradient
jest całym sensem, nie ozdobą — równomierna sypanka daje galaktykę, która
wszędzie jest taka sama, i wówczas „wyspy poza grafem jako late game" nie
mają się gdzie wydarzyć. Test odrzucający kandydata patrzy na **większe** z
dwóch żądań: system przy obrzeżu chce więcej miejsca niż ten w rdzeniu, a
sprawdzanie tylko żądania nowego pozwoliłoby go ścisnąć systemowi
położonemu wcześniej.

**Pierwsza wersja była liniowa** (`lerp(1, 1.9, r/R)`) i dała 80 systemów
zamiast spodziewanych dwustu, a rdzeń ściśnięty do promienia kilkunastu lat
świetlnych. Sześcian przesuwa rozrzedzanie na sam brzeg: szeroki rdzeń po
~6–7 ly i obrzeże po ~11 ly.

Liczby bezwzględne z tego akapitu zmieniły się później — przy promieniu 60
wychodziło 109–117 systemów, przy 140 wychodzi 620–629 — a **wszystkie
ułamki zostały te same**, bo gradient zależy od `r/R`. Promień podniósł się
dlatego, że nie mieściła się w nim drabina tierów; powody i pomiar w
„Drabina tierów: szczebel musi być głębszy niż skok".

**Zasięg skoku ma sens tylko jako wielokrotność odstępu, i to też zostało
zmierzone.** Taki graf nie zaczyna się spinać, dopóki zasięg nie wynosi
około 1,75 lokalnego odstępu — przy 1,5 startowa galaktyka to było od
jednej siódmej do jednej czwartej samej siebie:

| zasięg (× odstęp rdzenia) | największy spójny kawałek | wyspy |
|---|---|---|
| 1,25 | 12–34% | 74–98 |
| 1,50 | 53–58% | 47–52 |
| **1,75 (`BASE_REACH`)** | **73–79%** | **25–29** |
| 2,00 | 90–94% | 7–11 |
| 2,33 | 98–100% | 0–2 |

Stąd `BASE_REACH = SPACING * 1.75`: startowy napęd dostaje trzy czwarte
galaktyki, a pozostała ćwiartka to obrzeże w wyspach. Lepszy napęd kupuje
**gdzie polecieć**, a nie krótszą drogę tam, gdzie się już było — i to jest
różnica, którą trzeba było zmierzyć, żeby ją utrzymać.

Zasięg mieszka w `GalaxyMap`, a nie na zasobie napędu, bo to przeciwko
niemu sprawdzany jest układ: `largest_component(BASE_REACH)` to galaktyka,
w której gracz naprawdę lata. Dwie liczby, które mogłyby się rozjechać,
byłyby testem galaktyki, której nikt nie odwiedza.

**Start w środku**, nie losowo: nowa gra, która ląduje na wyspie przy
obrzeżu, to nowa gra bez skoku, a „sprawdź spójność grafu" nie jest
sprawdzeniem, jeśli jedyny system, który musi w nim być, wybiera się
potem.

### Start na obrzeżu: najdalszy system, do którego da się dolecieć

Gra ma zaczynać się na obrzeżu i prowadzić do środka (PLAN.md, „Premisa"), więc
zdanie wyżej — „start w środku, bo rdzeń jest gęsty" — przestaje obowiązywać.
Zostaje natomiast jego **druga połowa**, i to ona niesie nową zasadę: start
wybiera się celowo, nie losowo, bo gra, która ląduje na wyspie, to gra bez skoku.

Nowa zasada brzmi więc: **najdalszy system należący do największego spójnego
kawałka**. Zmierzone na pięciu seedach, startowy zasięg 10,5 ly:

| seed | systemów | główny kawałek | najdalszy w nim | zasięg stamtąd | widzi rdzeń |
|---|---|---|---|---|---|
| 20260922 | 111 | 86 | 52,6 ly | 86 | tak |
| 1 | 117 | 92 | 51,3 ly | 92 | tak |
| 7 | 108 | 74 | 51,0 ly | 74 | tak |
| 31337 | 113 | 84 | 51,1 ly | 84 | tak |
| 99 | 115 | 89 | 55,5 ly | 89 | tak |

**51–55 ly z 60** — dziewiąty albo dziesiąty pierścień — i z każdego z nich
startowy napęd sięga całego głównego kawałka razem ze środkiem. Geometria nie
wymaga żadnej zmiany: gradient, `RIM_SPREAD` i `BASE_REACH` zostają takie, jakie
pomiary z tej sekcji ustawiły.

**Pomyłka warta zapisania**, bo łatwa do powtórzenia. Pierwsza wersja tego
zapisu mierzyła najdalszy system **w ogóle** i wyciągnęła z tego, że obrzeże jest
niegrywalne jako start: ten system sięga jednego systemu, siebie. To prawda i
jest bez znaczenia — najdalszy system w ogóle jest wyspą **z definicji**,
dokładnie tą, którą gradient ma tworzyć jako late game. W tej galaktyce
„najdalszy" i „najdalszy, do którego da się dolecieć" to dwa różne miejsca,
odległe od siebie o siedem lat świetlnych i o całą grywalność.

Co zostaje prawdą: ostatni pierścień to wyspy poza zasięgiem startowego napędu.
Pod nową premisą to jest nawet lepsze niż pod starą — są widoczne na skanerze od
pierwszej minuty i nieosiągalne, dopóki nie kupi się zasięgu.

**I jeszcze jedno, czego ten pomiar też nie złapał.** „Najdalszy w spójnym
kawałku" postawił start tam, gdzie najbliższy system leży 9,8 ly przy zasięgu
10,5 — czyli na **93% zasięgu**. `JumpController.STRAIN_FROM` nalicza ryzyko
misjumpu od 85%, więc pierwsza czynność nowej gry miała **56% szansy na
wyrzucenie gdzie indziej**. Nie z braku paliwa: pełny bak pokrywa ten skok
blisko sześciokrotnie, co też zostało zmierzone, zanim podejrzenie o paliwo
upadło. Reguła napięcia była poprawna; nigdy wcześniej nie była wycelowana w
pozycję startową.

Stąd ostateczna zasada: **najdalszy system w głównym kawałku, którego pierwszy
skok mieści się w wygodnej części zasięgu** (`BASE_REACH * STRAIN_FROM`, czyli
8,92 ly). Na pięciu seedach daje start 44–47,5 ly z 60, tier 3, ryzyko
pierwszego skoku **0%** i jedno do trzech wyjść. Lejek zostaje, hazard znika.

Trzy podejścia, trzy różne podejrzenia — spójność, paliwo, napięcie — i tylko
trzecie było prawdziwe. Warte zapisania, bo wszystkie trzy brzmiały tak samo z
zewnątrz: „z obrzeża nie da się polecieć".

Pomiar nie mówi nic o tym, czy tiery po równej szerokości są dobre — mówi tylko,
że liczą nierówno: od jednego systemu w środku do osiemnastu w ósmym
pierścieniu. Pod starą premisą jeden system w tier 1 byłby wadą, bo tam byłby
start; pod nową jest zaletą, bo to finał.

### Drabina tierów: szczebel musi być głębszy niż skok

Zgłoszone z kokpitu dwoma zdaniami — nie zaczynamy w tier 1, a czasem jedyną
drogą naprzód jest skok o dwa tiery — i okazało się jedną arytmetyką.

**Pierwsza połowa: dno drabiny.** Pasy były rozłożone na całym dysku, a
najdalszy system, do którego startowy napęd dolatuje, stoi w czterech piątych
promienia — bo obrzeże dysku jest z założenia za rzadkie, żeby się spinało.
Start wypadał więc w tier 3 na **każdym** zmierzonym seedzie, a drabina, na
której nikt nie stoi na pierwszym szczeblu, ma osiem szczebli i złą etykietę.
Test nawet to zapisywał — `tier_of(home) <= 3` — czyli usterka była wpisana do
zestawu tak, jakby była projektem.

Poprawka: skala mierzy **drogę**, nie dysk. `tier_span()` to promień systemu
startowego, więc tier 1 jest tam, gdzie się zaczyna, z definicji — a nie
dlatego, że tak wyszło.

**Druga połowa: głębokość szczebla.** To nie jest pomiar, tylko dowód w jednej
linijce. Skok zbliża do środka o najwyżej `BASE_REACH`, pas ma szerokość
`tier_span() / TIERS`, więc skok przecina najwyżej jedną granicę dokładnie
wtedy, gdy pas jest szerszy od skoku. Przy promieniu 60 pas miał 6,0 ly, a skok
10,5 — przeskoki były nieuniknione, nie pechowe.

Pomiar na pięciu seedach, graf przy `BASE_REACH`:

| skala | pas | tier startu | krawędzi przez dwa szczeble | systemów bez łagodnego wyjścia |
|---|---|---|---|---|
| dysk, R=60 | 6,0 ly | 3 | 16–22 | 3–7 |
| droga, R=60 | 4,4–4,7 ly | 1 | 36–48 | 4–9 |
| dysk, R=140 | 14,0 ly | 2–3 | 0 | 0 |
| **droga, R=140** | **10,9–11,4 ly** | **1** | **0** | **0** |

Drugi wiersz jest tu najważniejszy: sama zmiana skali **pogarsza** przeskoki,
bo zwęża pasy. Obie połowy są potrzebne naraz, i dopiero razem dają zera.

**Jedna liczba mówi to wszystko na raz: drabina miała dziesięć szczebli, a
droga sześć kroków.** Ze startu do środka było 6 skoków na 45 latach
świetlnych. Nie da się wejść na dziesięć szczebli w sześciu krokach,
jakkolwiek narysować pasy — to nie był problem strojenia, tylko liczenia. Przy
R=140 droga ma 109–113 ly i 14–18 skoków.

**Ile to kosztuje.** 620 systemów zamiast 111 i 48 ms na rozłożenie galaktyki.
Liczba systemów też nie jest wyborem: ustal dziesięć tierów, skok 1,75 odstępu
i brak wymuszonych przeskoków, a liczba wychodzi z arytmetyki. Wszystko, co
było zmierzone jako **ułamek**, przeżyło zmianę bez ruchu — bo gradient zależy
od `r/R`, a nie od `r`: największy spójny kawałek dalej ma 76–79%, rdzeń dalej
6 ly odstępu, obrzeże 11,4 ly, skaner dalej widzi 5–7 systemów ze startu. Tyle
że teraz to jest 1% galaktyki, a nie 5%.

**Podłoga pod pasem.** `tier_span()` to `max(droga, TIERS * BASE_REACH)`. Przy
140 droga wychodzi 109–113 przy podłodze 105, więc podłoga nie zadziałała na
żadnym seedzie — i dokładnie wtedy warto ją napisać, bo seed, który wypadnie
krócej, to ten, którego nikt nie wygenerował. Z nią obie własności drabiny są
prawdziwe **z konstrukcji**, a nie ze szczęścia.

**Co z wyspami.** Wszystko poza drogą — ćwiartka galaktyki — przycina się do
tier 1. To jest świadome: tier mówi, jak daleko jest się na drodze, a wyspa nie
leży na drodze. Tym, co robi z niej late game, jest napęd potrzebny, żeby tam
dolecieć, a nie tier tego, co w niej stoi. To druga oś i należy do M5.

### Mapa galaktyki: trzy źródła widoczności, i nic poza nimi

`GalaxyChart` (`N`) stoi warstwę wyżej niż mapa układu: tamta rysuje
`StarSystem` w pikselach, ta `GalaxyMap` w latach świetlnych, i nigdy nie
dzielą liczby. Wspólne mają to, co jest tu regułą: obie rysują z **modelu**,
nie ze sceny. Instancjonowany jest jeden system naraz i nigdy nie będzie
inaczej, więc mapa z żywych węzłów byłaby mapą jednej kropki.

Widać trzy rzeczy i nie ma czwartej:

1. **Systemy, w których byliśmy.** Wiedza. Nie da się jej odtworzyć z seeda,
   więc mieszka w `Galaxy.deltas` — i nie znika nigdy.
2. **Systemy w zasięgu skanera teraz.** Przyrząd. Znika, kiedy statek się
   oddali, bo to nie jest wiedza, tylko odczyt.
3. **Środek galaktyki.** Premisa. Gra polega na locie do środka; mapa, która
   każe najpierw odkryć, gdzie jest środek, chowa nie drogę, tylko sens.

Rozdzielenie 1 i 2 jest jedyną rzeczą, którą trzeba było tu naprawdę
przetestować. Mapa, która raz narysowany kontakt zapisuje jako „odwiedzony",
przechodzi każdy test oprócz jednego: przelecieć na drugi koniec galaktyki i
spojrzeć wstecz. Ten test jest w zestawie — z rdzenia, gdzie żaden skaner nie
sięga obrzeża, system startowy musi dalej być na mapie, a kontakt sprzed
skoku musi z niej zniknąć.

**Ile tego widać na starcie.** Pięć seedów, skaner seryjny (zasięg 14 ly):

| seed | systemów | tier startu | do środka | kontaktów | na mapie | ciemnych |
|---|---|---|---|---|---|---|
| 20260922 | 620 | 1 | 111,9 ly | 5 | 7 | 613 |
| 1 | 621 | 1 | 113,5 ly | 5 | 7 | 614 |
| 7 | 624 | 1 | 109,2 ly | 5 | 7 | 617 |
| 424242 | 629 | 1 | 112,7 ly | 3 | 5 | 624 |
| 99999 | 621 | 1 | 112,7 ly | 4 | 6 | 615 |

Czyli **około 1% galaktyki na pierwszej klatce nowej gry**, z czego jedna
kropka to cel odległy o 110 lat świetlnych i czternaście skoków. To jest
dokładnie ten obrazek, o który chodzi w premisie: jesteś tutaj, koniec jest
tam, reszta jest ciemna.

**Klucz w `deltas`.** Wizyta zapisuje się pod **seedem systemu**
(`StarSystem.derive(galaxy_seed, index)`), nie pod indeksem. Powód jest
prozaiczny i trudny do odkręcenia później: ten sam słownik dostaje
`StreamingManager` i szuka w nim swoich ciał po seedzie, więc dwa schematy
kluczy w jednym magazynie to kolizja czekająca na mały indeks. Przy okazji
zapis gry nie potrzebował ani nowego pola, ani podbicia wersji — delty i tak
szły do pliku w całości. To jest pierwszy wpis w `deltas`, który nie dotyczy
ciała niebieskiego; schemat kluczy, którego M5 potrzebuje na pokonanych
majorów i porzucone drony, zaczyna się tutaj.

Samo zapamiętywanie dzieje się w `Galaxy.enter()`, jednym wywołaniu zamiast
dwóch przypisań. `here` i `at` to ten sam adres powiedziany dwa razy, a wizyta
jest tą rzeczą, której nikt nie zapisze w trzecim miejscu ustawiającym tę parę
— i dokładnie tak gnije mgła wojny. System, w którym statek stoi, liczy się
jako odwiedzony bez zapisu, co jest jedną regułą zamiast zapisu na każdej
ścieżce przylotu i błędu na tej jednej, którą się pominęło.

**Drabina zoomu.** Cztery szczeble, podane jako zasięgi w latach świetlnych, a
nie jako mnożniki — ta sama decyzja co w mapie układu i z tego samego powodu:
mnożnik sam w sobie nic nie znaczy. Na płótnie 640x360 (`room` = 156 px):

| szczebel | zasięg | px na ly | odstęp systemów w rdzeniu |
|---|---|---|---|
| 0 | 148 ly (cała galaktyka) | 1,05 | 6,3 px |
| 1 | 56 ly (pół drogi, pięć tierów) | 2,79 | 16,7 px |
| 2 | 21 ly (dwa tiery) | 7,43 | 44,6 px |
| 3 | 10,5 ly (jeden tier) | 14,86 | 89,1 px |

Najciaśniejszy to `BASE_REACH`, a nie okrągła liczba, bo „sąsiad" **znaczy**
tyle, co w zasięgu jednego skoku seryjnym napędem. Od chwili, gdy pas tiera
został zwymiarowany na jeden skok, ten sam szczebel znaczy też „jeden tier"
— i to jest zbieg okoliczności warty utrzymania, bo daje drabinie jednostkę,
którą da się nazwać przy każdym szczeblu.

**Najszerszy szczebel celuje w galaktykę, nie w statek.** Każdy ciaśniejszy
trzyma się statku. Zasięg, który mieści całą galaktykę, wycentrowany na
statku stojącym **na obrzeżu**, zostawia połowę galaktyki poza kadrem — a
pokazanie całości to jedyne zadanie tego szczebla.

**Jeden przycisk, dwa gesty.** Lewy przeciąga albo wybiera, zależnie od tego,
ile przejechał (próg 3 px). Osobny przycisk do przeciągania to przycisk,
którego nikt nie znajdzie, a przeciąganie na prawym koliduje ze szpilką, którą
mapa układu już tam położyła. Kółko zoomuje na kursorze tą samą arytmetyką co
mapa układu — transformacja odwrotna przeczytana dwa razy — łącznie z wczesnym
wyjściem na końcu drabiny, bez którego oparcie się o kółko przesuwałoby widok
w bok przy nieruchomej skali.

**Tiery narysowane jako pierścienie**, bo tier *jest* pasem promienia i
rysowanie go czymkolwiek innym byłoby wymyśleniem drugiego pojęcia. Dziesięć
bladych okręgów robi przy okazji to, co robiłaby legenda: widać, że pasy są
równej szerokości i że środek jest jednym małym kółkiem. Pierścienie idą po
**drodze**, nie po dysku, więc zewnętrzny przechodzi przez system startowy, a
obrys całej galaktyki jest narysowany dalej — i przestrzeń między nimi to
ćwiartka galaktyki, którą gradient zostawia w wyspach. Najuczciwszy obrazek
„late game za lepszym napędem", jaki ten ekran umie dać bez słowa tekstu.

**Klawisz dewelopera: `F4` zdejmuje mgłę.** Cały projekt tego ekranu to mgła,
więc jedyna rzecz, której nie da się sprawdzić patrząc na niego, to czy ciemna
połowa w ogóle **jest** — każdy błąd we mgle jest błędem, którego nie widać.
Odkryte systemy rysują się jako przygaszone kropki w `inert`, nie jako
kontakty: podgląd ma pokazać całość, a nie skłamać, że się ją zna.

Kształt rozróżnia, kolor mówi o roli — ta sama reguła co na skanerze.
Odwiedzony system to wypełniony kwadrat, kontakt to pusty romb, środek to romb
w pierścieniu, statek to krzyż w kółku (ten sam, co na mapie układu: rzecz,
którą pilot ma znaleźć natychmiast, nie zmienia kształtu między ekranami).
Nazwy tylko od szczebla 2 w dół, bo sto jedenaście podpisów na 640x360 to jedna
szara smuga — z wyjątkiem trzech, które są odpowiedzią na pytanie, a nie
spisem treści: tu jesteśmy, tam idziemy, to właśnie kliknięto.

Czego tu nie ma, a pewnie będzie: krawędzi grafu skoków między znanymi
systemami (planowanie trasy na kilka skoków), markera nawigacyjnego w skali
galaktyki — szpilka `NavMarker` jest w pikselach systemu i ginie przy skoku,
więc „pin na mapie galaktyki" to druga szpilka, nie ta sama — oraz oznaczenia,
które systemy są już wyczyszczone, bo to jest pytanie do M5.1.

---

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
- Pixel-art: bazowa rozdzielczość 640x360, skalowanie przez tryb rozciągania `canvas_items` z aspektem `expand` (ustawienia projektu). SubViewport nie jest potrzebny, a `expand` pozwala na szersze ekrany bez czarnych pasów. **Filtr nie jest już jeden na całą grę** — patrz niżej, „Rozdzielczość: jednostka układu, nie budżet texeli".
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

### Rozdzielczość: jednostka układu, nie budżet texeli

Pytanie brzmiało „czy 24x32 na statek to dość detalu", a odpowiedź okazała się
nie być decyzją o sprite. Jest to decyzja o tym, czym w ogóle jest 640x360.

**Zostaje jednostką układu i przestaje być budżetem texeli.** Powód jest w
trybie skalowania, który projekt ma od M0: `canvas_items` renderuje w
rozdzielczości okna, a dokumentacja Godota mówi o nim wprost, że nie ma już
odpowiedniości 1:1 między pikselem sprite'a a pikselem ekranu. Sprite z
większą liczbą texeli naprawdę pokazuje więcej. Statek dostaje przy 1080p
72x96 prawdziwych pikseli i miał dotąd 24x32 na ich wypełnienie.

**Grafika świata rysowana jest w skali 3x** (`Art.FACTOR`) i wyświetlana w 1/3.
Trójka, bo 1080p to dokładnie trzykrotność 640x360, więc na najczęstszym
ekranie jeden texel to jeden piksel i nic nie jest przepróbkowywane.

**Przesądził obrót, nie rozdzielczość.** Statek obraca się swobodnie i nie
robimy pre-renderowanych klatek obrotu, więc nie istnieje kąt, przy którym
niskorozdzielczy sprite siada na siatce pikseli — i tak jest przepróbkowywany
co klatkę. Pytanie nie brzmi „czy zachować pixel art", tylko „z ilu texeli
przepróbkowujemy".

**Z tego wynika filtr, i to jest część, która mogłaby zaskoczyć.** Zmierzone:
kamera chodzi od 1.7 do 0.385 (`ZOOM_LEVELS` razy człon prędkości), okno mnoży
to przez 2 przy 720p i przez 6 przy 4K, więc jeden texel trafia na od ćwierci
do trzech i pół piksela ekranu — trzynastokrotny zakres na jednym sprite, w
jednej sesji. `Nearest` nie ma odpowiedzi na żadnym końcu. Świat dostaje
`LINEAR_WITH_MIPMAPS`, a mipmapy muszą być włączone przy imporcie
(`[importer_defaults]` w `project.godot`), bo bez nich filtr cicho degraduje
do zwykłego dwuliniowego i statek skrzy się przy oddalaniu.

**Interfejs zostaje prawdziwym pixel artem**: 1:1, `Nearest`, skala 1.0. Nie
obraca się i nie zjeżdża, więc jedyne miejsce, w którym prawo siatki z
UI_STYLE.md §2 jest dosłownie prawdziwe, jest też jedynym, dla którego je
napisano. To, co wyglądało na sprzeczność w tym prawie, było światem
pożyczającym regułę panelu.

Koszt tej decyzji to przeliczenie rozmiarów grafiki świata w ASSETLIST.md.
Zapłacony w momencie, w którym nie istniał ani jeden docelowy zasób
graficzny, czyli najtaniej, jak się dało. Czego **nie** kosztuje: fontu.
Przy jednej skali na całą grę font bitmapowy trzeba by rysować jako 24 px
zamiast 8, co jest zupełnie inną robotą; podział na świat i interfejs
zostawia go dokładnie tam, gdzie był.

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

### Garnizon: pierwsza rzecz, która czyta tier

Do tej pory `tier_of()` opisywał sam siebie. Galaktyka miała kształt, drabinę i
mapę, a tier 9 trzymał dokładnie to, co tier 1 — lot do środka był dojazdem.
`Garrison` jest arytmetyką, która robi z drabiny powód.

Czysta dana, jak `StarSystem` i `GalaxyMap`: roster istnieje, zanim powstanie
jakikolwiek węzeł, a ten sam seed daje tych samych wrogów w tych samych
miejscach. Nic tu nie lata i nie strzela — to jest robota spawnera i AI, które
oba **czytają** tę listę. `deltas` są podawane z zewnątrz, nie pobierane, z tego
samego powodu co wszędzie: autoload nie istnieje w biegu `--script`.

**Dwie zasady powrotu, i pierwsza nie kosztuje nic.**

Roster wyprowadzony z seeda **jest** regułą „minor wraca, kiedy ty wracasz,
nigdy w trakcie pobytu". Nic się nie zapisuje, nic nie tyka zegara, a system
wyczyszczony i opuszczony jest tym samym systemem, kiedy się do niego wróci.
Spawner dosypujący wrogów w trakcie pobytu robi system, z którego się ucieka,
a nie taki, który się czyści — i dlatego reguła brzmi tak, jak brzmi.

Odwrotność — „major pokonany nie wraca nigdy" — to jedyna rzecz, której seed
nie odtworzy, więc jedyna, która tu się zapisuje. Major **niepokonany** nie
zapisuje się wcale i wraca cały, bo inaczej wlatywanie i uciekanie jest zawsze
tańsze niż walka. Minor zastrzelony też nie zapisuje się wcale, i to nie jest
przeoczenie: model już mówi, że wróci, więc notatka o jego śmierci byłaby
notatką, którą następny roster albo zignoruje, albo — gorzej — posłucha, co po
cichu zamieniłoby każdy system w taki, który zostaje wyczyszczony.

**Schemat kluczy w `deltas`**, którego M5.1 potrzebowało i który zaczął się przy
mapie galaktyki. Jedna reguła: **wpis leży pod seedem tej rzeczy, której
dotyczy**. Dziś są trzy rodzaje — ciało niebieskie (`crust`, wykopany teren),
system (`seen`, czy tu byliśmy) i członek garnizonu (`beaten`). Seed członka
idzie **dwustopniowo**: garnizon dostaje własny seed z systemu (indeks 1000,
poza zakresem, którego używają ciała), a członkowie numerują się od niego. Jeden
stopień z dużym indeksem też by zadziałał i zostawiłby garnizon bez własnej
tożsamości, którą następna rzecz wisząca na systemie musiałaby wymyślić jeszcze
raz. Kolizja seeda z ciałem niebieskim jest sprawdzana testem na całej
galaktyce — wspólny klucz znaczyłby, że wykopany krater wskrzesza elitę.

### Garnizon wisi na ciele, nie na systemie

Pierwsza wersja rozsypywała wrogów po systemie jako jedną płaską listę, każdy
z abstrakcyjnym postem — powierzchnia, orbita albo luźno w przestrzeni. To jest
tłum, nie obrona: odpowiada na „ilu” i nigdy na „czego”.

Wrogowie stoją **przy planetach i stacjach**, bo to są miejsca warte stania, i
tylko bardzo rzadko w ciemności między nimi. Stąd losowanie w dwóch krokach, a
kolejność jest projektem:

1. **Czy to ciało jest w ogóle bronione?** Większość nie jest, i system cichych
   światów z jednym trzymanym księżycem czyta się jako miejsce, w którym coś
   jest. Świat zawsze pilnowany to sceneria.
2. **Dopiero wtedy: kto go trzyma i jak daleko.** O obrońcach nieobronionego
   świata nie losuje się nic — co znaczy też, że da się zapytać „czy tam jest
   niebezpiecznie” bez rozwijania walki, której nikt nie toczy. Skaner
   przelatujący system zadaje pierwsze pytanie o każde ciało i drugie prawie o
   żadne, więc muszą być rozłączne — i muszą się zgadzać, czego pilnuje test na
   wszystkich 3980 ciałach galaktyki.

**Trzymają teren, nie polują.** Garnizon ma **terytorium**: powłokę wokół swojego
ciała, której pilnuje. Pogoń przez pół systemu to walka, z której nie da się
wyjść, a gra, w której każdy kontakt jest zobowiązaniem, jest grą w unikanie
kontaktów. Trzymanie terenu robi z tego samego wroga decyzję: oblecieć czy
wejść. Terytorium mierzy się względem **studni**, a nie powierzchni, bo studnię
rysuje mapa i zakrzywia się w niej trajektoria — granica, która nie pokrywałaby
się z niczym widocznym, byłaby ścianą odkrywaną przez uderzenie w nią.

Podłoga 2500 px wzięła się z pomiaru: dok nie ma grawitacji i ma sto kilkadziesiąt
pikseli promienia, więc jego zasięg wychodził na kilkaset — **piętnastu obrońców
w pierścieniu o promieniu 443 px to kupa, nie pikieta.**

**Agresywni i pasywni, i co budzi tych drugich.** Agresywny garnizon otwiera
ogień do wszystkiego w swoim terytorium. Pasywny musi zostać **sprowokowany**, a
które prowokacje liczą, losuje się razem z ciałem: są światy, którym nie
przeszkadza, że się na nie patrzy, i przeszkadza, że się na nich ląduje. Pilot
dowiaduje się, który to — ze skanera albo przez pomyłkę.

Strzał liczy się **zawsze** i nie jest losowany. Obrońca, który daje się
rozebrać na części z grzeczności, nie jest obrońcą. Pozostałe trzy — zbliżenie,
lądowanie, kopanie — są ciekawe, bo każda mówi coś innego o tym, po co to miejsce
jest: świat, któremu przeszkadza zbliżenie, coś ukrywa; taki, któremu przeszkadza
dopiero kopanie, na czymś siedzi. `MINED` jest już losowane i czeka na kopanie z
M5.2 — wcześniej kosztuje tyle, co nic, a później kosztowałoby myślenie o
formacie zapisu.

**Co to rozstawia.** Seed 20260922, 620 systemów, 3980 ciał innych niż gwiazdy:

| tier | ciał | bronionych | obrońców na trzymane | strzela pierwszy | terytorium |
|---|---|---|---|---|---|
| 1 | 1270 | 18% | 4,4 | 24% | 6366 px |
| 3 | 483 | 28% | 7,1 | 32% | 6675 px |
| 5 | 362 | 40% | 9,2 | 50% | 6671 px |
| 7 | 249 | 47% | 11,3 | 69% | 5804 px |
| 10 | 42 | 62% | 15,3 | 65% | 6637 px |

11132 obrońców w galaktyce, 49 luźnych grup na 620 systemów (8%), najcięższy
garnizon **24 w powietrzu**. Ta ostatnia liczba jest budżetem na **garnizon**, a
nie na system: terytorium jest jednostką, którą się walczy, a system rdzenia
trzyma ich kilka i bije się je po kolei.

**Rdzeń też ma ciche światy** — 62%, nie 100%. Pierwsze podejście dało 76% i to
było za dużo: gdyby trzymane było wszystko, „bronione” przestaje być czymś, co
mapa może zaznaczyć.

Reguła „tłum rośnie szybciej niż wróg w nim” przeniosła się na trzymane ciało i
**znowu została złamana przy pierwszym podejściu**: 2,7 przeciwko 3,2. Policzone
na ciele, a nie na systemie, liczby musiały pójść w górę — teraz 3,5 przeciwko
3,2.

**Major jest agresorem z definicji, nie z rzutu**: elita, która przelatuje obok
i wraca na patrol, to elita, której gracz nigdy nie spotkał. Jest warta 2,5
minora swojego tiera — „przyprowadź kogoś albo miej plan”, a nie „wróć
później” — i ma podłogę rzadkości łupu, bo to jest powód, żeby go nie ominąć.

### Prowokacja i ogień: co budzi garnizon i czym strzela

Reguła `provoked_by()` powstała razem z modelem i przez jeden commit **nikt jej
nie pytał** — terytorium było liczbą w słowniku. To jest ta połowa, która daje
jej pytającego, i ta, przez którą przekroczenie granicy cokolwiek znaczy.

Ponieważ garnizon **trzyma teren zamiast gonić**, strzelanie jest całą pierwszą
walką: działko, które strzela, jest skończone, a myśliwiec na posterunku w
większości. Ruch, który zwykle jest fundamentem AI, zrobił się tu mniejszą sprawą
niż zwykle.

**Jak obudzony garnizon zasypia: nie zasypia.** Raz poruszony zostaje poruszony
do opuszczenia systemu. Nie kosztuje nic do zrobienia i nic do zapisania, bo
wyjście i powrót i tak odtwarza roster z seeda — „ta wizyta" jest naturalną
granicą. Alternatywą był timer zapominania, a timer znaczy, że pilot prowokuje
świat, odlatuje na dwadzieścia sekund i wraca do garnizonu, który postanowił mu
uwierzyć.

**Działonowy musi wyprzedzać cel, i pierwsza wersja tego nie robiła.** Uzasadnienie
brzmiało: pilot, który się rusza, ma być trudny do trafienia, a wyprzedzanie należy
do AI. Oba zdania prawdziwe, a razem dały garnizon, który nie trafia w nic —
zmierzone w biegu: pociski przechodzące **143 px za statkiem, który nic nie robił,
tylko spadał**. W tej grze nic nigdy nie stoi: spada statek, spadają skrzynki,
spadają same pociski. Wyprzedzenie pierwszego rzędu, czyli odległość przez
prędkość wylotową razy prędkość celu. Obroną pilota jest **zmienianie** prędkości,
a nie samo jej posiadanie — i to jest lepsza lekcja niż ta, której uczyło pudło.

**Rozrzut 4° wyrzucony tym samym pomiarem.** Cztery stopnie to stożek szeroki na
126 px na końcu zasięgu obrońcy, przy kadłubie szerokim na 24 — działo, które
miało być niecelne, było po prostu działem, które nie trafia nigdy. Dwa stopnie,
czyli tyle, co seryjny autocannon, żeby pilot czytał ogień obrońcy względem
czegoś, co już zna.

Zmierzone na końcu, zaparkowany 400 px od jednego obrońcy z obrzeża przez 14 s:
**5 pocisków, 4 trafienia, kadłub 1,000 → 0,918.** Jeden obrońca to około 0,006
kadłuba na sekundę; presja ma pochodzić z tego, że w zasięgu bywa ich kilku,
nie z tego, że jeden boli.

**Warstwy fizyki rozdzielone**, żeby garnizon nie rozstrzelał sam siebie przy
okazji strzelania do pilota: obrońcy stoją na własnej warstwie, ich pociski
szukają tylko warstwy statku, a pociski gracza szukają obu. Czy obrońcy mogą
kiedyś ranić siebie nawzajem, to pytanie na dzień, w którym coś będzie umiało
zwrócić ich przeciwko sobie — odpowiadanie na nie teraz byłoby wymyślaniem
systemu frakcji dla nikogo.

### Reszta, jeszcze nieruszona

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
- `HUD`: wskaźniki skoku, stan silników, paliwo, energia.

## 14. Energia

Statek ma dwie ekonomie i celowo się nie mieszają:

- **Energia** reguluje tempo walki, w sekundach. Odnawia się sama, nigdy się jej
  nie kupuje i nie da się jej odłożyć na później.
- **Paliwo** reguluje zasięg, w minutach i skokach. Nie odnawia się samo, bierze
  się ze stacji i planet (M5), a jego brak kończy się dryfowaniem.

Silniki palą paliwo, broń i elektronika żrą energię. Rozdział jest po to, żeby
seria strzałów nigdy nie zabrała pilotowi możliwości hamowania: statek, który po
walce nie umie wylądować, jest wrogi, nie trudny.

Wzorem jest mana z różdżek Noity, nie kondensator z symulatora.

### Generator

`GeneratorData` (Resource, czyli moduł, czyli loot):

- `capacity` — maksymalna energia,
- `recharge_rate` — jednostek na sekundę,
- `recharge_delay` — sekundy ciszy, po których doładowanie się zaczyna,
- `bulk` — jak przy silnikach: masa, którą dokłada, i warunek zmieszczenia się w
  slocie.

Cały model to: wydatek zeruje licznik ciszy, po `recharge_delay` sekundach bez
wydatku pula rośnie o `recharge_rate` na sekundę do `capacity`.

**Timeout liczy się od ostatniego wydatku, nie od ostatniej serii.** Każdy strzał
przesuwa moment startu doładowania, więc w trakcie ognia generator nie ładuje się
w ogóle. Doładowanie ciągłe (regen, który tyka zawsze) zostało odrzucone, bo przy
nim broń o drenażu niższym niż `recharge_rate` strzelałaby bez końca, a energia
byłaby podatkiem, nie decyzją. Stan „broń milczy" jest tu celem, nie efektem
ubocznym.

**Strzał albo wychodzi cały, albo nie wychodzi.** Brak energii na pełny koszt to
odmowa, a nie słabszy pocisk: pół strzału jest nieczytelne i rozjeżdża każdy
afiks liczony na obrażeniach.

**Kadłub ma własną, nędzną szynę.** Statek bez generatora dostaje pulę wbudowaną
w kadłub (wartości robocze 40 / 15 / 1.5) i strzela, tylko bardzo źle. Powód ten
sam, co przy ładowni odmawiającej przyjęcia lootu zamiast go gubić (sekcja 4):
zła wymiana modułu ma być kiepskim wyborem, a nie stanem, z którego nie ma
wyjścia.

### Realizacja (M2, pierwsza warstwa)

`GeneratorData` siedzi w `GeneratorBay` — węźle o tym samym kształcie co
`EngineMount`: slot to dziura w kadłubie i nic nie waży, a to, co w nim
siedzi, jest masą i musi się zmieścić. Wnęka stoi **na środku masy pustego
statku**, tak jak luk cargo, więc cięższy generator czuć jako ociężałość, a
nie jako usterkę wyważenia w raporcie.

Zmierzone: statek fabryczny 14,6 → **16,6 kg** po wstawieniu ogniwa o
gabarycie 2,0, środek masy bez zmian.

Trzy rzeczy potwierdzone testem, bo wszystkie trzy są konsekwencjami tego
jednego zdania o zerowaniu licznika:

- **Pełny strzał albo żaden.** Odmowa nie zabiera nic z puli.
- **Trzymanie spustu nigdy nie pozwala się ładować**, choćby nie wiem jak
  długo — sprawdzone czterema sekundami ognia o drenażu bliskim zeru.
- **Pułap to cisza, nie rating.** Ogniwo 100/40/0,8 daje **30,3 j/s**, nie 40.

Wydatek jest na **prawdziwej ścieżce strzału**, nie tylko w teście
jednostkowym: faza broni sprawdza, że seria czterech pocisków zabrała
dokładnie 24 jednostki i że nic nie wróciło. Usunięcie bramki z pętli ognia
wywala tę asercję.

**Obie bazowe bronie wyszły na 0,0133 i 0,0136 obrażeń na jednostkę energii** —
to jest niezmiennik pilnowany testem z tolerancją 10%, dokładnie tak jak koszty
afiksów. Energia nie ma po cichu wskazywać zwycięzcy.

Przy okazji pojemność cargo przestała być stałą: `hull_cargo_capacity` to
własność kadłuba, a zamontowana maszyneria **wypiera część ładowni** —
generator zabiera pół swojego gabarytu. Mniej niż całość, bo maszyneria pakuje
się w miejsca, w których i tak nie stanęłaby skrzynka.

### Realizacja (M2, druga warstwa)

**Wspólna baza `ModuleData`.** `bulk`, `stat_add` i `stat_mul` powtarzały się
w trzech plikach; teraz są w jednym, a `Ship.module_bulk()` to jedno rzutowanie
zamiast trzech gałęzi. Pliki `.tres` nie wymagały zmian — właściwość z klasy
bazowej ustawia się tak samo.

**Agregat liczony przy montażu**, w tym samym miejscu, w którym przebudowują się
grupy sterowania. `stat(klucz, baza)` zwraca `(baza + suma add) * iloczyn mul`,
a `stat_sources` pamięta, który moduł co ruszył — raport konfiguracji wypisuje
to z nazwą węzła, bo bonus, którego pilot nie widzi, jest losowością.

Zmierzone: silnik z afiksem `dynamo` podnosi recharge z **40 na 54,6**, płacąc
ciągiem. Statek zostaje wolniejszy, pilot strzela dłużej — to jest ta decyzja.

**Nieznany klucz to błąd, ale test sprawdza bramkę, nie alarm.** `knows_stat()`
jest osobno od `push_error`, bo test, który wywołuje `push_error`, jest testem
wywalającym build — `check.ps1` skanuje przebieg pod kątem błędów. Sam
`push_error` zostaje w produkcji.

**Pasek energii** stoi na dole, nad pierścieniem skanera. Pierwsza wersja była
10 px od dołu i szła dokładnie przez znaczniki skanera i ich odległości — dwa
odczyty w tych samych pikselach to żaden odczyt. Podziałka jest co koszt
**najtańszej** zamontowanej broni, nie pierwszej: inaczej kreski obiecywałyby
mniej strzałów, niż statek naprawdę ma. Odmowa to czerwona podwójna ramka przez
0,35 s — przy siedmiu pikselach wysokości sama zmiana koloru ginie w strzelaninie.

Drobiazg wart zapamiętania: **GDScript nie zna `%g`** w operatorze formatowania
i przy jego napotkaniu oddaje niezmieniony napis formatu. Raport przez chwilę
wypisywał `energy_capacity %s %s%.3g` i wyglądało to jak niewypełniony szablon,
a nie jak błąd.

### Strojenie: ładunek i rzadkość

Dwa pomiary, które wyszły źle i zostały poprawione.

**Ładunek zamieniał statek w cegłę.** Przy przeliczniku 1:1 pełna ładownia
(11 gabarytów) dokładała **75% masy i zabierała 43% przyspieszenia** — noszenie
czegokolwiek było odmową, nie decyzją. Ładunek waży teraz **0,35 na gabaryt**,
czyli pełna ładownia kosztuje 19% przyspieszenia.

Zamontowane moduły zachowują pełną masę i to jest celowe: montaż jest wymianą,
więc zmiana netto jest mała, a środek masy stoi tam, gdzie stoi, właśnie przez
te konkretne gabaryty. Warunek `com = 1.75` wymusza zresztą sztywną relację
`masa_kadłuba = 6 × przelicznik_modułów`, więc samo zmniejszenie masy modułów
nie zmieniłoby proporcji kadłub:moduły (41:59) — przeskalowałoby cały statek.
Żeby ruszyć tę proporcję, trzeba przesunąć mounty, a to osobna decyzja.

Budżet „nie-cegła" jest teraz testem: pełna ładownia ma kosztować więcej niż 5%
i mniej niż 30% przyspieszenia.

**Rzadkość podnosiła rozrzut, nie średnią.** Wykładnik `RARITY_STRENGTH`
stosował się i do zysku, i do ceny afiksu, więc legendary miał *droższe* koszty
tak samo jak większe zyski. Zmierzone na 1500 losowaniach, każde porównane z
własną bazą (ten sam seed, rzadkość common — baza jest wtedy dosłownie tym
samym przedmiotem bez afiksów):

| rzadkość | średnia | mediana | najlepszy | gorszych od bazy |
|---|---|---|---|---|
| common | ×1,00 | ×1,00 | ×1,00 | 0% |
| uncommon | ×1,06 | ×1,00 | ×1,71 | 29% |
| rare | ×1,18 | ×1,03 | ×2,97 | 36% |
| epic | ×1,43 | ×1,28 | ×4,91 | 29% |
| legendary | ×1,94 | ×1,67 | ×8,29 | 19% |

Wykładnik stosuje się teraz **tylko do nazwanego zysku**; cena idzie po
wylosowanej wartości. „Bardziej skrajny, nie jednostajnie lepszy" zostaje —
jedna piąta legendarnych silników nadal ma mniejszy ciąg od bazy, bo zapłaciły
za coś innego — ale skrajność krąży teraz wokół **wyższej** średniej, a nie tej
samej.

Metodologiczna uwaga warta zapamiętania: pierwszy pomiar porównywał każde
losowanie z **jedną** bazą, podczas gdy generator losuje z siedmiu. Dysza
obrotowa wychodziła wtedy jako „×0,18 ciągu" i średnie były bez sensu.

### Jak się to składa

Strzelanie do wyczerpania puli daje przepływ energii, który składa się jak opory
równoległe:

    1 / E_sustained = 1 / E_drain + 1 / recharge_rate + recharge_delay / capacity

gdzie `E_drain = energy_cost * rounds_per_second` to drenaż przy ciągłym ogniu.
Stąd trzy wnioski, które w tej mechanice są najważniejsze:

- **Broń ustala burst, generator ustala sustained.** Kadencja i obrażenia na
  strzał opisują szczyt i długość serii; średnia w dłuższej walce należy do
  generatora i do obrażeń na jednostkę energii. To znaczy, że znaleziony
  generator jest odczuwalnym awansem każdej broni naraz, a nie +5% do
  statystyki.
- **Pojemność płaci za timeout.** Składnik `recharge_delay / capacity` to jedyne
  miejsce, w którym pojemność występuje: większa pula nie podnosi pułapu, tylko
  rzadziej każe płacić ciszę. Dlatego mała pula z szybkim doładowaniem i duża z
  wolnym to naprawdę różne statki, a nie dwie drogi do tej samej liczby.
- **Kadencja kupuje przepustowość, ale tylko do pułapu.** Przy bazowym
  generatorze pułap to `1 / (1/40 + 0.8/100)` = 30 jednostek na sekundę, mimo
  `recharge_rate` równego 40 — resztę zjada timeout.

Wniosek dla pilota: **opłaca się opróżniać pulę, nie stukać w spust.** Krótka
seria płaci ten sam timeout od mniejszej ilości energii, więc mikroburst wychodzi
gorzej od pełnej serii i mechanika nie zamienia się w zawody w klikaniu.

Wartości robocze, generator bazowy 100 / 40 / 0.8:

| broń | koszt | seria z pełnej puli | burst dps | sustained dps |
| --- | --- | --- | --- | --- |
| autocannon 4/s, 0.08 | 6 | 16 strzałów w 4.0 s | 0.32 | 0.18 |
| siege slug 1/s, 0.30 | 22 | 4 strzały w 4.0 s | 0.30 | 0.17 |

**Bazowe bronie mają celowo zbliżone obrażenia na jednostkę energii** (0.0133 i
0.0136). Energia nie ma po cichu wskazywać zwycięzcy — autocannon i slug różnią
się charakterem (przebicie, zasięg, krater), nie wydajnością, i tak to zostało
ustawione w sekcji 4. Nowa bazowa broń dobiera koszt z linii `damage / 0.0133` i
odchyla się od niej świadomie. Afiksy i moduły są tym, co tę linię łamie.

Przypadek brzegowy, bo od niego wyszedł cały pomysł: broń 20 strzałów/s po 1.5
jednostki i 0.02 obrażeń drenuje 30 u/s, więc wypala pełną pulę w 3.3 s (66
strzałów) i milczy następne 3.3 s. Burst dps 0.40 to 1.25× autocannona, sustained
0.20 to 1.12×. Szybkostrzelność kupuje szczyt i prawie nie rusza średniej —
dokładnie tak ma wyglądać „minigun, który się zatyka".

### Stały pobór

Asysty (auto-poziomowanie, hold wysokości, cyrkularyzacja, komputer deorbitu,
auto-orbit z sekcji 8) pobierają stały prąd, który **odejmuje się od
`recharge_rate`, a nie resetuje timeoutu**. Włączona asysta ma skracać serie, nie
zabraniać strzelania. Implementacyjnie to jedna odjęta liczba; na HUD widać ją
jako wolniejsze napełnianie, nie jako drugi pasek.

### Moduły ruszają statystyki, których „nie dotyczą"

To jest sedno buildu i powód, dla którego loot przestaje być listą zakupów:
silnik z afiksem `dynamo` daje +8 do `recharge_rate` i zabiera 12% ciągu. Pilot,
który woli strzelać, lata wolniejszym statkiem. Odwrotnie, `buffered` kupuje
pojemność masą. To ta sama zasada, co przy rzadkości: przedmiot ma być bardziej
skrajny, nie jednostajnie lepszy.

Mechanizm:

- Każdy moduł ma `stat_add` i `stat_mul` (StringName → float). **Dwa słowniki, a
  nie jeden z konwencją zależną od nazwy klucza.** Reguła „pojemności dodajemy,
  koszty mnożymy" wymaga pamiętania, o które pole chodzi, a tabele lootu są
  danymi, których przy pisaniu nikt nie sprawdza.
- Kolejność jest stała: baza plus suma `stat_add`, potem iloczyn `stat_mul`. Suma
  najpierw, żeby mnożnik działał na cały statek, a nie na to, co zdążyło się już
  zmontować.
- **Agregat liczony przy montażu, nigdy co klatkę** — w tym samym miejscu, w
  którym już przebudowują się grupy sterowania (`Ship.rebuild_control_groups()`).
  Statystyka przeliczana co klatkę jest statystyką, której nie da się pokazać w
  raporcie.
- **Nieznany klucz to `push_error`, nie cisza.** Literówka w tabeli afiksów,
  która po prostu nic nie robi, przejdzie każdy test, jaki napiszemy.
- **Raport konfiguracji (M2) wypisuje statystyki z rozbiciem na moduły.** Bonus
  międzystatowy, którego pilot nie widzi, jest losowością, nie decyzją. Ten
  warunek należy do mechaniki, nie do UI.

### Moduły broni (różdżkowe)

Broń ma `mod_slots` (robocze 0..3, rzadkość podnosi) i listę wpiętych
`ShotModData`.

Rozróżnienie wobec afiksów jest tu istotne: **afiks jest cechą przedmiotu, moduł
jest decyzją pilota.** Dlatego afiksy zostają wpalone w liczby przy generacji
(sekcja 4), a moduły nie mogą — pilot je wpina i wypina. Liczby wynikowe
przeliczają się raz, przy zmianie modułu, i przy strzale są czytane z cache'u.

**Każdy moduł podnosi koszt energii.** `energy_multiplier > 1` jest
niezmiennikiem tabeli, pilnowanym testem tak samo jak koszty afiksów. Slot mówi,
ile modułów się zmieści; energia mówi, ile się z nimi ustrzela. Autocannon z
dwoma modułami (×1.35 i ×1.25) kosztuje 10.1 zamiast 6, więc seria spada z 16
strzałów na 9. Slug obwieszony eksplozją i podpaleniem strzela trzy razy i
zostawia statek bezbronny — to jest ciekawy build, nie błąd balansu.

Moduły robią dwie rzeczy:

- ruszają liczby (kadencja, obrażenia, rozrzut, krater, zasięg, prędkość),
- dodają pociskowi zachowanie: eksplozja przy kontakcie, podpalenie, przebicie,
  rozszczepienie, odbicie.

Zachowania są **danymi czytanymi przez pocisk przy spawnie, nie osobnymi
scenami**. Sekcja 4 już tak stoi („kilka klas bazowych pocisków, reszta to
dane") i moduły nie mają powodu tego łamać: inaczej każda kombinacja modułów
jest nowym plikiem.

**Kolejność modułów nie ma znaczenia** — świadome odejście od Noity. Kolejność
jest mechaniką warsztatu z przeciąganiem, a ekran wymiany jest małym panelem w
rogu, bez pauzy, z jedną akcją na klawisz (sekcja 4). Jeśli stacje kiedyś dostaną
prawdziwy warsztat, można to otworzyć ponownie.

Broń ciągła (laser) liczy się jak bardzo szybki pulse: koszt za impuls. Jedna
reguła energii dla wszystkiego i zero drugiej ścieżki w kodzie.

### Czytelność

Pasek energii ma powiedzieć trzy rzeczy i żadna z nich nie jest liczbą jednostek:

- ile zostało **strzałów** — pasek ma podziałkę co `energy_cost` zamontowanej
  broni, więc pilot liczy kreski, a nie procenty,
- czy timeout jeszcze leci (pasek czeka), czy już się ładuje (pasek rośnie),
- odmowa strzału musi być widoczna i słyszalna od razu, inaczej wygląda jak
  zacięty klawisz.

Jak to wygląda, należy do VISUALS.md. Że te trzy rzeczy muszą być czytelne bez
wpatrywania się w liczby, należy do mechaniki: energia, której nie widać, jest
losowym zanikaniem broni.

### Odrzucone

- **Dopalanie z kadłuba (overdraw).** Strzelanie za HP zamienia każdą walkę w
  powolne umieranie i przenosi koszt tam, gdzie pilot go nie widzi.
- **Energia jako paliwo silników.** Patrz podział na początku sekcji.
- **Regen ciągły** i **strzał za częściową energię.** Oba usuwają stan „broń
  milczy", który jest tu jedyną prawdziwą karą.

## 15. Otwarte pytania

- Jednostki: ile jednostek ma promień typowej planety i typowego systemu? Decyduje o potrzebie floating origin.
- ~~Czy teren planety zawija się czy jest to bitmapa w układzie biegunowym?~~ Rozstrzygnięte w M1.3: bitmapa biegunowa, 1.5 px na teksel, tylko pas skorupy. Szczegóły i pomiary w sekcji 6.
- Ile chunków terenu jednocześnie w scenie przy podejściu do planety?
- Ekonomia paliwa: czy paliwo to zasób z planet, ze stacji, czy jedno i drugie?
- Tarcza (jeśli będzie): z tej samej puli co broń, czy z własnej? Wspólna daje
  decyzję „strzelać czy przeżyć", osobna daje dwa niezależne paski.
- Uszkodzony generator: traci `recharge_rate`, `capacity`, czy wydłuża timeout?
  Awarie silników z M2 dadzą wzór, którym można to zrobić tak samo.
- Czy pułap sustained nie spłaszcza broni za mocno — do zmierzenia na trzech
  bazach, kiedy energia będzie już w kodzie (sekcja 14).
- Kondensator jako moduł: jednorazowy zrzut całej puli na impuls ciągu albo
  tarczę, z długim doładowaniem?
- Śmierć: co gracz traci, co zostaje (statek, loot, odkryte systemy)?
- Zapis: autosave przy skoku i lądowaniu, czy permadeath z meta-progresją?
