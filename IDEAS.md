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

1. **Jest masą**, jaką silnik dokłada do statku. Nie `size` mountu: slot to
   dziura, waży to, co w niej siedzi. Cięższy silnik przesuwa środek masy i
   zmienia bezwładność, więc czuć go nawet wtedy, kiedy nie pracuje.
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

**Gabaryty statku testowego są dobrane tak, żeby środek masy wypadł dokładnie
na krzyżu dysz obrotowych.** Warunek redukuje się do jednego równania, bo dysze
obrotowe i para strafe leżą symetrycznie względem `y = 1.75` i wypadają z
sumy:

    8.25 * bulk_main - 13.75 * bulk_retro = -5.5

Stąd przy `bulk_main = 3.0` wychodzi `bulk_retro = 2.2`, mounty zostają na
okrągłych pozycjach, a `com` wypada na 1.75 co do cyfry. Pierwsze podejście —
gabaryty „na oko" i przesunięcie mountów za środkiem masy — natychmiast
złamało parę obrotową (wagi 1,00 i 0,82, 0,046 N siły bocznej na obrót) i
zostało złapane przez istniejący test. Loot **będzie** tę równowagę psuł i o to
chodzi; statek fabryczny ma z niej startować.

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
