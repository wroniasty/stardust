# PLAN.md

Plan realizacji w milestone'ach. Każdy milestone kończy się czymś, w co da się grać albo co da się zobaczyć. Kolejność wynika z ryzyka: najpierw to, co może wywrócić architekturę, potem zawartość.

Kontekst i decyzje projektowe: IDEAS.md.

Obraz i dźwięk mają własny, równoległy plan: VISUALS.md. Ten plik nie odpowiada
za to, jak gra wygląda i brzmi — i dlatego jego kryteria zamknięcia nie mogą od
tego zależeć.

---

## Premisa

**Eksploracja i loot, z kierunkiem.** Zaczynamy na obrzeżach galaktyki i lecimy
do środka. W środku jest główne wyzwanie — co dokładnie, jeszcze nie wiadomo, i
to jest otwarte pytanie, nie luka.

Galaktyka dzieli się na **koncentryczne pierścienie, tier 1 na obrzeżu do 10 w
środku**. Im bliżej środka, tym wyższy tier: groźniejsi wrogowie i lepszy loot.
Liczba rośnie w tę stronę, w którą się leci — liczba malejąca w miarę
trudnienia byłaby liczbą czytaną od tyłu za każdym razem. Tier jest jedną liczbą policzoną
z promienia i wszystko inne — spawnery, rzadkość, cena — czyta ją zamiast mieć
własną skalę.

To jest pierwsze zdanie w tym pliku, które mówi, **czym gra jest**, a nie co ma
w sobie działać, i dlatego stoi przed milestone'ami: kolejność prac wynika z
ryzyka, ale ryzyko mierzy się względem czegoś.

### Co ta premisa psuje w dotychczasowych zapisach

Nie jest to lista życzeń — to są miejsca, w których nowa premisa stoi w
sprzeczności z decyzją podjętą wcześniej i uzasadnioną pomiarem. Każde trzeba
rozstrzygnąć świadomie, bo każde ma koszt.

**1. Start na obrzeżu działa i nie wymaga żadnej zmiany geometrii. Zmierzone —
za drugim razem.** `start_index()` wybiera dziś system najbliższy środkowi, więc
zmienić trzeba tę funkcję i jej uzasadnienie, i tyle.

Nowa zasada: **najdalszy system należący do największego spójnego kawałka**. To
jest ta sama dyscyplina, którą ta funkcja już ma — start wybiera się celowo, a
nie losowo, bo inaczej „sprawdź spójność grafu" nie jest sprawdzeniem. Pomiar na
pięciu seedach:

| seed | systemów | główny kawałek | najdalszy w nim | zasięg stamtąd | widzi rdzeń |
|---|---|---|---|---|---|
| 20260922 | 111 | 86 | 52,6 ly | 86 | tak |
| 1 | 117 | 92 | 51,3 ly | 92 | tak |
| 7 | 108 | 74 | 51,0 ly | 74 | tak |
| 31337 | 113 | 84 | 51,1 ly | 84 | tak |
| 99 | 115 | 89 | 55,5 ly | 89 | tak |

Czyli: **51–55 ly z 60**, dziewiąty albo dziesiąty pierścień, i z każdego z nich
startowy napęd sięga całego głównego kawałka — ze środkiem włącznie. To jest
obrzeże w każdym sensie, w jakim fabuła tego słowa używa.

Pierwszy pomiar, który tu stał, mówił coś przeciwnego i był pomiarem **innego
pytania**: brał najdalszy system w ogóle, czyli wyspę z definicji — dokładnie tę,
którą gradient gęstości ma tworzyć jako late game. Oczywiście nie sięga
niczego; po to tam jest. Zapisane, bo to jest pomyłka łatwa do powtórzenia:
„najdalszy" i „najdalszy, do którego da się dolecieć" to w tej galaktyce dwa
różne miejsca, i tylko drugie jest kandydatem na start.

Co z tego **zostaje** prawdą: ostatni pierścień to wyspy poza zasięgiem
startowego napędu i to się nie zmienia. Pod nową premisą jest nawet lepsze — to
są miejsca, które widać na skanerze od pierwszej minuty i do których nie da się
polecieć, dopóki nie kupi się napędu.

**2. Pierścienie równej szerokości dają bardzo nierówne tiery.** Z tej samej
tabeli: tier 10 (środek) to **jeden** system, tier 3 to osiemnaście. Jeden
system na najwyższym tierze jest zaletą, bo to finał, a finał ma być jednym
miejscem. Decyzja: **pierścienie równej szerokości zostają**, ale trzeba
wiedzieć, że liczba systemów na tier nie jest równa i nie ma być — najwięcej
latania przypada na środek drogi, nie na jej końce.

**3. „Skalowanie z odległości od startu" trzeba przepisać na „od środka".** Dziś
M5 mówi o odległości od startu. Przy starcie na obrzeżu to prawie to samo — ale
tylko prawie: lot **wzdłuż** obrzeża oddala od startu, nie zbliżając do środka, i
pod starą regułą podnosiłby zagrożenie bez powodu.

**4. Przelot przez gwiazdę jest dziś niemożliwy z założenia.** `star.gd` ma to
zapisane jako decyzję: statek lecący w gwiazdę umiera od ciepła kilka tysięcy
pikseli, zanim cokolwiek dotknie, i dlatego gwiazda nie ma kształtu kolizji.
Zbieranie stardustu „przelotem przez gwiazdę" wymaga więc albo moda, który
realnie przesuwa próg `BURN_HEAT`, albo przeniesienia zbierania do **korony** —
poza promień spalenia, ale w strumień. Drugie jest tańsze i nie kłóci się z
modelem ciepła, który już działa.

**5. Wyjątki od generatora a reguła seeda.** CLAUDE.md mówi: wszystko
proceduralne odtwarzalne z seeda, żadnych ręcznie stawianych planet. Scenka z
„gwiazdą śmierci" wygląda na złamanie tej reguły i **nie musi nią być**: jeśli
to, **który** indeks systemu staje się scenką, wynika z seeda galaktyki, to
galaktyka zostaje odtwarzalna. Ręcznie napisana jest *zawartość* scenki — tak
samo jak ręcznie napisany jest każdy zasób broni. Reguła mówi „nie stawiaj
planet ręką", a nie „nie pisz treści".

**6. Dwa paliwa rozcinają to, co dziś jest jedną liczbą.** `JumpDriveData.fuel_for()`
liczy koszt skoku w tym samym paliwie, którym się lata, `TankData` ma jedno
`fuel_capacity`, a `JumpController` obciąża `Ship.fuel`. Rozdzielenie dotyka
tych trzech miejsc i jednej asercji w teście.

**7. „Loot galore" a ładownia.** Dużo lootu przy małej ładowni to ciąg decyzji;
przy dużej — odkurzanie. Pojemność ładowni jest więc teraz **parametrem
projektowym tej premisy**, nie liczbą wziętą z kadłuba.

---

## M0: Szkielet projektu

Cel: pusty, ale poprawnie ustawiony projekt Godot 4.x z repo.

- [x] Projekt Godot 4.x (2D, standardowy build, GDScript), repo git, `.gitignore` dla Godota (`.godot/`, `*.import` opcjonalnie).
- [x] Struktura katalogów: `scenes/`, `scripts/`, `resources/`, `shaders/`, `addons/`.
- [x] Autoloady jako puste szkielety: `Galaxy`, `StreamingManager`, `LootGenerator`.
- [x] Scena `World` z pustym `Player` i miejscem na `System`.
- [x] Ustawienia renderowania: SubViewport w niskiej rozdzielczości i upscale (decyzja o docelowej rozdzielczości pikselowej, np. 640x360).
- [x] Skrypt uruchamiający projekt headless do sprawdzania błędów (`godot --headless --path . --quit`).

Gotowe, gdy: projekt się uruchamia, pusty ekran, brak błędów w konsoli.

---

## M1: Jedna planeta do zabawy i testów

Cel: piaskownica. Jeden statek, jedna planeta, można latać, spadać, rozbijać się i rozwalać teren. To milestone testowy dla feelingu fizyki i dla wydajności pikselowego terenu. Jeśli tu nie będzie fajnie, reszta nie ma sensu.

### 1.1 Statek

- [x] `Ship` jako RigidBody2D z `_integrate_forces`.
- [x] Komponent `Engine`: pozycja, wektor ciągu, typ, sprawność, niezawodność.
- [x] Grupy sterowania z geometrii: `EngineMount` plus `EngineData`, sześć komend liczonych z wkładu c_i, wagi z kary bocznej, autorytet na grupę, ostrzeżenia o pustych grupach.
- [x] Statek testowy: silnik główny, dwie pary obrotowe, dwa silniki strafe, silnik hamujący. Sterowanie: WSAD + QE.
- [x] Kill rotation (X) z progiem wygaszenia liczonym z autorytetu statku.
- [x] Brake (Z): rozkład prędkości na komendy, bez ruszania obrotu.
- [x] Debug draw silników: trójkąt z przepustnicą i typem, krzyżyk w środku masy, wspólny przełącznik F7.
- [x] Kamera podążająca za statkiem, lekki zoom zależny od prędkości.
- [x] GPUParticles2D na silnikach, intensywność od ciągu.
- [x] Debug overlay: prędkość, siły, stan silników.

### 1.2 Planeta

- [x] `Planet` jako koło z parametrami: promień, G, promień wpływu, promień atmosfery.
- [x] Grawitacja własną funkcją w statku: odwrotność kwadratu nad powierzchnią, płynne wygaszenie na granicy wpływu.
- [x] `linear_damp` i `angular_damp` projektu na 0.
- [x] Atmosfera jako Area2D z `linear_damp`, kilka koncentrycznych obszarów z gradientem, górna warstwa z minimalnym dragiem.
- [x] Prosty shader atmosfery: kolor, rim light, przewijany szum na chmury.

### 1.3 Teren z pikseli

- [x] Generacja bitmapy terenu z seedu (szum na powierzchni koła, góry i równiny).
- [x] Render terenu jako tekstura z paletą.
- [x] Kolizja statku z terenem przez samplowanie bitmapy w punktach kadłuba. Normalna z gradientu pikseli, odbicie, obrażenia zależne od prędkości uderzenia.
- [x] Modyfikacja terenu: usuwanie pikseli w promieniu (eksplozja) z aktualizacją tekstury.
- [x] Pomiar: czas aktualizacji tekstury przy modyfikacji, czas samplowania na klatkę.

### 1.4 Jedna broń

- [x] Klasa bazowa pocisku, jeden typ: projectile.
- [x] Hardpoint na statku, strzelanie, pocisk niszczy teren przy trafieniu.
- [x] Pocisk koliduje z terenem przez samplowanie.

### 1.5 Orbitowanie

- [x] Sprawdzenie, że orbita kołowa i eliptyczna utrzymują się przez kilka minut bez znaczącego dryfu.
- [x] Przewidywana trajektoria na HUD: symulacja naprzód 200 do 400 kroków, Line2D, znaczniki apoapsy i periapsy, marker punktu uderzenia w powierzchnię.
- [x] Stan orbity czytany z trajektorii (ORBIT / DECAYING / SUBORBITAL / ESCAPE), wskaźnik na HUD. Pierwotny orbit lock — przejście w analityczną orbitę kołową — usunięty, bo pomiar dryfu go nie uzasadniał (IDEAS.md sekcja 8).
- [x] Aerobraking: drag górnych warstw atmosfery hamuje statek na orbicie, prosty licznik ciepła kadłuba.

### 1.6 Lądowanie

- [x] Podwozie: 2 do 3 punktów kontaktu, wysuwanie klawiszem, drag przy wysuniętym.
- [x] Sprawdzenie warunków przy dotknięciu: prędkość pionowa, boczna, kąt, nachylenie terenu pod nogami (próbkowanie w układzie biegunowym).
- [x] Udane lądowanie: zamrożenie statku i przypięcie do planety, start z prędkością styczną.
- [x] Nieudane: obrażenia od nadwyżki prędkości, przewrócenie przez fizykę punktów kontaktu przy złym nachyleniu.
- [x] Generator terenu gwarantuje plateau do lądowania (parametr częstości).
- [x] HUD: wysokościomierz, prędkość pionowa, wskaźnik nachylenia pod statkiem, stan podwozia.
- [x] Opcjonalna rotacja planety (dzień i noc) i sprawdzenie, że wylądowany statek jedzie razem z nią.

### 1.7 Śmierć i restart

- [x] Kadłub ma HP, zderzenia i własne pociski zadają obrażenia.
- [x] Śmierć: efekt, natychmiastowy respawn na orbicie. Bez menu.


### 1.8 Narzędzia deweloperskie

- [x] Konfigurator planety (F6): parametry generatora w panelu, przebudowa planety i teleport na jej lądowisko. Wymusił rozdzielenie `roll_parameters()` od `rebuild()` w `Planet` (IDEAS.md sekcja 5).
- [x] `tools/cloud_preview.tscn`: zrzuty archetypów chmur do PNG.
- [x] `tools/check.ps1`: przebieg gry plus smoke test, wspólne wyłapywanie błędów silnika i shaderów.
- [x] `CreativeTool` (`T`): sandbox. Spawnowanie dowolnego modułu do ładowni/cargo przez prawdziwy generator, wymiana kształtu kadłuba na jeden z sześciu presetów ze skalą, naprawa/naładowanie/uszkodzenie statku, i raport konfiguracji na żywo. Powstał, bo większości z M2 nie da się ocenić inaczej niż lotem.

Gotowe, gdy: da się wystartować z powierzchni, wejść na orbitę i na niej zaparkować, zejść deorbitem na wybrane miejsce, wylądować na zboczu i zobaczyć, że to zależy od nachylenia i prędkości, rozwalić kawałek góry, rozbić się i od razu lecieć dalej.

Ocena subiektywna ograniczona do **sterowania**: czy statek robi to, co każe
pilot, i czy da się wylądować świadomie, a nie przypadkiem. Jeśli nie, tu się
kręci fizyką, nie idzie dalej.

Czego to kryterium celowo **nie** obejmuje: czy gra wygląda i brzmi dobrze. To
jest pytanie dla VISUALS.md i nie może blokować M1. Pierwotne sformułowanie
mieszało jedno z drugim, przez co zamknięcie M1 zależało od warstwy, której w
M1 nigdy nie było.

Pytania do rozstrzygnięcia na koniec M1 (zapisać odpowiedzi w IDEAS.md):
- jednostki: promień planety, promień wpływu, prędkości (wartości robocze w IDEAS po M1.2, potwierdzić),
- ~~czy samplowanie bitmapy wystarcza, czy potrzebne są chunki z marching squares~~ — wystarcza, zmierzone w M1.3,
- ~~rozdzielczość bitmapy terenu na planetę~~ — 1.5 px na teksel, siatka biegunowa, zmierzone w M1.3,
- progi lądowania (prędkości, kąt, nachylenie) dla statku bazowego,
- czy planety się obracają,
- ~~tolerancje orbit lock i długość przewidywanej trajektorii~~ — lock usunięty (stan orbity jest wyliczany), długość trajektorii ustalona w M1.5, wartości w IDEAS.

---

## M2: Silniki, awarie, loot

Cel: statek jako zestaw modułów, które są lootem.

- [x] Komputer lotu jako moduł (`FlightComputerData` w `ComputerBay`): alokacja przez ograniczone najmniejsze kwadraty z rzeczywistym ciągiem i kondycją każdego silnika. Na uszkodzonym statku obrót zostawia 36 N zamiast 88 N siły bocznej.
- [x] **Gotowe konfiguracje statków** w sandboksie (`ShipFitout`): stock, stock z silnikami o 75% mocniejszymi, **gimbal podwójny (para sił)**, gimbal pojedynczy, przechwytujący, frachtowiec i goły kadłub. Preset niesie montaże, silniki, działa, obrys, ładownię i nogi; przebudowa jest **w miejscu**, bo podmiana sceny unieważniłaby kamerę, HUD-y, edytor i streaming manager.
- [x] **Para sił z dwóch wychylanych dysz**: dziób i rufa, obie wychylane w tę samą stronę — momenty się dodają, ciągi znoszą. Zmierzone: **4366 autorytetu CW** (więcej niż 3760 na stockowych dyszach) przy **1,4 px/s² resztkowego pchnięcia** zamiast 48,9 dla pojedynczego gimbala. Kadłub musi być symetryczny, bo para przestaje być parą, gdy środek masy przesunie się między ramionami.
- [x] **Strafe z pary gimbali.** Wychylone **tak samo** — momenty się dodają, siły boczne znoszą: to jest obrót, który już był. Wychylone **przeciwnie** — momenty się znoszą, siły boczne dodają: to jest strafe, i dwie dysze są wtedy całym statkiem. Zmierzone na presecie „para sił": **341 N STRAFE_LEFT**, dysze na -0,21 i +0,21 przy strafie, na -0,21 i -0,21 przy obrocie.
  Liczy się to **tylko dla pary** (`ShipControl.gimbal_partner`: przeciwne ciągi, przeciwne ramiona, podobne wielkości) i to jest sedno, nie ostrożność: pojedyncza dysza wychylona w bok pcha statek wzdłuż własnego ciągu dokładnie tak samo mocno jak przedtem. Preset zrobiony po to, żeby to pokazać, nazywa się „gimbal pojedynczy (dryfuje)" i dalej nie dostaje gimbala do grupy strafe — co test sprawdza wprost, bo ten preset ma zwykłe silniki boczne i raport słusznie o nic nie ma pretensji.
- [x] Grupy kontroli liczą **moment z gimbala**. Przedtem napęd główny na osi miał zerowy moment z dyszą prosto, więc CW/CCW nie miały żadnego członka i statek sterowany wyłącznie gimbalem **nie skręcał w ogóle**. Dodatkowo kara za bok nie dotyczy gimbala przy obrocie: pchnięcie do przodu to znana cena tego narzędzia, nie dowód, że jest złe. Zmierzone: 1638 autorytetu CW przeciw 3760 na dyszach, 2,93 rad/s po trzech sekundach i 58 px/s dryfu.
- [x] Gimbal: `gimbal_range` i `gimbal_rate` na `EngineData`, dysza wychylana proporcjonalnie do żądania obrotu. Kierunek wychylenia wyprowadzony z ramienia, nie deklarowany per mount.
- [x] Punkty kontaktu wyprowadzane z `hull_outline`: wierzchołki plus podział krawędzi krokiem 6 px (cztery teksele), liczone raz w `_ready()`. `HULL_POINTS` zniknęło.
- [x] `CollisionShape2D` liczony z tego samego obrysu przez `Geometry2D.convex_hull()`. Jedno źródło — to, w co trafia pocisk, nie może się rozjechać z tym, co dotyka gruntu.
- [x] `penetration_limit()` skaluje się rozpiętością kadłuba, `contact_iterations()` liczbą punktów kontaktu (4 na stockowym, sufit 10).
- [x] Wytyczne obrysu sprawdzane w raporcie konfiguracji: obwód ≤ 240 px, ≤ 12 wierzchołków, wypukłość, najcieńszy detal ≥ 12 px, rozstaw nóg ≥ 12 px.
- [x] Test: żadna przerwa wzdłuż obrysu nie jest szersza od kroku kontaktu, a zestaw punktów próbkuje grunt pod całym kadłubem, nie tylko w rogach.
- [x] Raport konfiguracji przy montażu: autorytet w każdą stronę, asymetria par lustrzanych, puste grupy, boczny dryf pary obrotowej jako przyspieszenie. `compare()` pokazuje w ekranie wymiany, co zrobił moduł — różnice, nie stan. Wytyczne obrysu kadłuba dojdą osobno.
- [x] Awarie silników: uderzenie psuje silniki **w miejscu trafienia**, niezawodność jako wypadanie (na sekundę, nie na tick) i falowanie ciągu, uszkodzenie zjada też niezawodność. Refit nie leczy. Raport konfiguracji nazywa uszkodzony silnik i podaje, ile przez niego dryfuje.
- [x] Akordy klawiszy zamiast kolejnych przycisków: `A+D` zatrzymuje obrót (zastąpiło `X`), `Q+E+W` celuje na kierunek lotu, `Q+E+S` przeciwnie. Akord zjada swoje klawisze, okno ustalenia 60 ms, stop wygrywa z resztą.
- [x] Skrzynki mają własną fizykę: wyrzucone lecą **tyłem ze śluzy** z prędkością statku plus popchnięcie, spadają w polu grawitacyjnym, odbijają się raz i kładą na gruncie. Nie wchodzą w skałę — kontakt mierzony promieniowo, nie próbkowaniem punktu. Skrzynka na półce jest „osiadła” i nie jest liczona, dopóki grunt pod nią nie zniknie.
- [x] Model uszkodzeń przepisany po zgłoszeniu z gry (nogi kosztowały więcej niż kadłub). Jedno zdarzenie, jeden rachunek: kontrola podwozia tylko odmawia, płaci kontakt. Tolerancja nóg nigdy poniżej kadłubowej, koszt jako **kwadrat** nadwyżki, ślizg styczny liczy się z wagą 0,5 — inaczej lot w zbocze czytał się jako muśnięcie. Liczby w IDEAS.md, sekcja „Model uszkodzeń”.
- [x] Lądowanie z uszkodzonymi silnikami: faza testu sadza statek z silnikami na 65% i niezawodnością 0,5 — da się wylądować.
- [x] Podwozie jako moduł (`GearData`): progi prędkości, przechyłu i nachylenia z części, geometria stóp zostaje na kadłubie. Asysty auto-poziom i auto-orbita siedzą na komputerze lotu.
- [x] Pozostałe asysty: hold wysokości (`W+S+A`, tłumiony prędkością wznoszenia, bo sama wysokość to sprężyna bez tłumienia) i komputer deorbitu (`W+S+D`, pali retrograde aż periapsis wejdzie w atmosferę i przestaje).
- [x] Auto-orbit jako opcjonalna funkcja komputera (`Q+E+D`): obraca dziób na wektor korekty, potem pali. Elipsa 32% schodzi do 1,1% rozrzutu. Komputer bez tej funkcji odmawia. Auto-poziom na `Q+E+A`.
- [x] Naprawa na klawiszu debug (`R`). Zużycie w czasie zostaje — dziś silniki psują się tylko od uderzeń.
- [x] Silniki manewrowe (`maneuver_pod`), hamujące (`braking_bell`) i sterowany (`gimballed_drive`) jako loot. Test porównuje pełny zestaw z minimalnym: rozebrany kadłub jest lżejszy, leci tak samo do przodu i nie umie nic innego — raport nazywa każdy utracony kierunek.
- [x] Broń jako Resource: typ, obrażenia, kadencja, rozrzut, zasięg, afiksy. Hardpoint to montaż z listą dopuszczalnych typów, `fit()` oddaje poprzednią broń.
- [x] `LootGenerator`: tabele rzadkości, afiksy, generacja broni i silników. Pięć poziomów rzadkości, 0..4 afiksy, siła jako wykładnik; każdy przedmiot z jawnego seeda.
- [x] `EngineData.bulk`: gabaryt silnika jako jego masa i zarazem warunek zmieszczenia się w slocie (`bulk <= size`). Typy zostają otwarte; ceną za dziwne dopasowanie jest fizyka, nie tabelka.
- [x] Skaner jako element HUD: trójkąty dla ciał niebieskich (kierunek, odległość do powierzchni, rozmiar ciała, wygaszenie poza polem grawitacyjnym) i romby dla lootu (kolor z rzadkości, osobny krótszy zasięg, znacznik także na ekranie). Zalążek — zasięgi stałe, w M5 własność modułu skanera.
- [x] Pozostałe typy broni: laser (hitscan), dumb rocket i seeker (`Missile`, ciąg po starcie, naprowadzanie jako szybkość obrotu), burst shell (AoE) i pulse repeater. Trzy zachowania niosą sześć typów, reszta to dane. Wszystkie siedem broni bazowych leży na jednej linii obrażeń na jednostkę energii (0,0132–0,0136).
- [x] Skrzynki z lootem na powierzchni planety, podnoszenie, wymiana modułu w locie (Tab, bez pauzy). Skrzynki stoją na półkach do lądowania, kolor z rzadkości.
- [x] Energia: `GeneratorData` jako moduł w `GeneratorBay` (masa i warunek zmieszczenia jak przy silnikach), pula liczona w `_physics_process`, szyna kadłuba 40/15/1.5 gdy generatora nie ma.
- [x] `energy_cost` faktycznie wydawany: strzał bez pełnego kosztu nie wychodzi, każdy wydatek resetuje timeout. Autocannon 6, siege slug 22 — obie na tej samej linii obrażeń na jednostkę energii.
- [x] `energy_cost` w tabelach lootu: afiksy `efficient` i `capacitor-fed`, wpisy w `HIGHER_IS_BETTER` i `LIMITS`. Generatory jako loot z własną tabelą (`deep`, `brisk`, `responsive`, `compact`).
- [x] HUD energii: pasek z podziałką co koszt najtańszej broni, osobny kolor dla „czeka" i „ładuje się", czerwona ramka przy odmowie strzału (sygnał `shot_refused`).
- [x] Statystyki statku liczone przy montażu: `stat_add`/`stat_mul` na wspólnej bazie `ModuleData`, agregat z rozbiciem na moduły w raporcie konfiguracji, nieznany klucz to `push_error`. Afiksy `dynamo` i `buffered` na silnikach.
- [x] Moduły broni: `mod_slots` (z rzadkości), `ShotModData` z `energy_multiplier > 1`, liczby wynikowe cache'owane przy zmianie modułów. Efekty jako dane czytane przy spawnie: `PIERCE` i `BLAST` zaimplementowane, `INCENDIARY` zadeklarowane i czeka na obrażenia w czasie.
- [x] Moduły broni, komputery i podwozia wypadają jako loot i wpinają się w edytorze. Schemat pokazuje zajętość gniazd broni (`NoseHardpoint 1/3`).
- [x] Pomiar energii: sustained bazowych broni 0,179 i 0,174 (±3%), każda sustainuje mniej niż burstuje, minigun 0,40 burst przy 0,20 sustained. Liczby z IDEAS sekcja 14 zgadzają się z zasobami.

Gotowe, gdy: znajduje się losowy silnik lub broń, montuje, czuć różnicę, uszkodzony silnik zmienia sposób latania, a spust ma swój koszt — seria się kończy i trzeba zdecydować, kiedy przestać strzelać.

**M2 zamknięty.** Wszystkie pozycje odhaczone, 433 asercje.



---

## M2.2: Celowanie myszką

Cel: strzela się tam, gdzie się patrzy, a kursor mówi, czy to coś da.

- [x] **Zakres obrotu: broń i hardpoint, bo znaczą co innego.** `WeaponData.traverse_range` i `traverse_rate` to pierścień i silnik samej broni — jadą z nią przy przenoszeniu, tak jak gimbal jedzie z silnikiem. `Hardpoint.traverse_limit` to ile pozwala kadłub: działko we wnęce kończy miejsce, zanim skończy je własny pierścień. Obowiązuje **mniejszy z dwóch** — ten sam kształt co `bulk <= size`.
- [x] Kierunek spoczynkowy gniazda ustawiany w edytorze (`,` / `.`), bo gdzie działko siedzi, należy do kadłuba, nie do broni.
- [x] `Ship.aim_point` w świecie, brany z myszy przez canvas transform — celowanie przeżywa obrót i zoom kamery.
- [x] Działka podążają za kursorem niezależnie od spustu. Wieżyczka, która zaczyna się obracać dopiero przy strzale, nigdy nie celuje tam, gdzie trzeba.
- [x] Kursor w trzech stanach: szary (nie da się), bursztynowy (da się, jeszcze się obraca), zielony (strzelaj). Kolor z **najlepszego** działka na spuście — pytanie brzmi „czy naciśnięcie coś da". Pocisk samonaprowadzający jest zawsze bursztynowy. Poza zasięgiem to szary, bo zielony kursor na nieosiągalnym celu kłamie.
- [x] Dwa spusty: lewy i prawy przycisk myszy, `Hardpoint.trigger` przypisuje gniazdo, `G` w edytorze przełącza. Naciśnięcie spustu odpala te działka, które **mogą trafić**, nie wszystkie do niego podpięte.
- [x] Łuk rysowany na schemacie w edytorze, z kolorem spustu. Działko na sztywno pokazuje pojedynczą kreskę — brak łuku też jest informacją.
- [x] `traverse_range` i `traverse_rate` w tabelach lootu, z afiksami `turreted` (szerszy łuk za kadencję) i `quick-slewing` (szybszy obrót za obrażenia).
- [x] Wybór celu dla pocisków naprowadzanych **z pozycji kursora**, nie „najbliższy statek". Promień chwytu liczony w pikselach ekranu i przeliczany przez kamerę, więc celowanie jest tak samo wyrozumiałe przy każdym zoomie; rozmiar celu dochodzi na wierzch. Kursor na pustce to **brak zaczepienia** — rakieta leci prosto tam, gdzie pokazałeś, zamiast łapać cokolwiek było bliżej.
- [x] Własny kadłub nie jest przeszkodą: amunicja przelatuje przez własny statek. Pocisk jest **martwy, dopóki nie wyjdzie poza obrys** tego, kto go wystrzelił — nie przez stały czas, bo to zakład o rozmiar kadłuba; przy 150 px/s przez 72-pikselowy kadłub stara łaska 0,2 s kończyła się w połowie drogi. Raz opuszczony obrys uzbraja na stałe, więc pocisk, który wróci dookoła planety, trafia.
- [x] ~~Teren między działkiem a celem~~ — **nie robimy, i to jest decyzja.** Kursor odpowiada na pytanie „czy ta lufa może się wycelować", nie „czy pocisk doleci". To jest ta sama granica, którą pilot postawił przy grawitacji: kursor nic nie kompensuje, poprawka należy do pilota. Trafienie w zbocze jest zresztą prawdziwym skutkiem — robi krater — więc byłaby to wygoda, nie naprawa kłamstwa. Koszt byłby raycastem na działko na klatkę, płaconym po to, żeby odebrać pilotowi decyzję.


---

## M2.3: Karty informacyjne modułów

Cel: kliknąć w rzecz i zobaczyć, z czego się składa — a przy wymianie zobaczyć różnicę, nie dwa osobne odczyty.

- [x] `ModuleData.stat_rows()` — moduł mówi, z jakich liczb się składa, a nie jak się nazywa jego opis. Wiersz to etykieta, wartość, dokładność i **kierunek** (`better`: +1 / −1 / 0). Kierunek jest po to, żeby porównanie mogło pokolorować różnicę: mniejszy rozrzut to poprawa, mniejszy zasięg nie.
- [x] Nadpisane w każdym rodzaju modułu, plus `blurb()` na jedno zdanie, którego liczba nie powie.
- [x] Karta w edytorze: nazwa, rzadkość, zdanie, wiersze. Kliknięcie zamontowanego modułu na schemacie pokazuje jego kartę, nawet z pustą ładownią.
- [x] Przy wymianie **dwie karty obok siebie**, a w lewej różnica przy każdym wierszu (`dps +0.364 lepiej`, `energia +10.7 gorzej`). Porównanie, między którym trzeba przewijać, to dwa odczyty wzięte w różnych chwilach.
- [x] Jednoliniowy werdykt zniknął dla broni — karta mówi to samo dokładniej. Został dla silników, bo tam liczy się wpływ na cały statek, którego karta nie zna.
- [x] Gniazda na schemacie jako **kwadratowe boksy z ikonami** zamiast kropek z podpisami. Ramka mówi, czy tu pasuje niesiony moduł, wypełnienie — czy coś siedzi i jakiej jest rzadkości, glif — jakie to gniazdo (strzałka ciągu, celownik, ogniwo, układ scalony, noga), a w hardpoincie **co jest zamontowane**: ○ puste, + działo, | wiązka, ↑ rakieta. Nazwa jednego gniazda na kliknięcie, nie jedenaście naraz. Wewnętrzne zatoki są rozsuwane przy rysowaniu — na schemacie, bo przesunięcie węzłów przesunęłoby środek masy.
- [x] Ta sama karta w szybkiej wymianie na Tab. Karta mieszka na `ModuleData`, nie w ekranie, który ją rysuje — dwa ekrany formatujące własną to dwie rzeczy po cichu niezgodne co do tego, czym jest broń.
- [x] Karty pisze się czcionką o stałej szerokości (`ModuleData.card_font()`). Wiersz dopycha spacjami, a w czcionce proporcjonalnej to po prostu nieprawda: kolumny liczb nie dawały się czytać w dół.
- [x] Wiersz, który nie mieści się w panelu edytora, jest liczony i zgłoszony przy podpowiedziach klawiszy. Karta bez ostatniej linii wygląda dokładnie jak karta, która się tam kończy.

---

## MAUX1: Edytor statku (prototyp)

Cel: jeden ekran, na którym widać cały statek i wszystko, co się na nim wozi.
Klawisz `I`. Otwiera się wszędzie, ale montaż wymaga wylądowania.

Szybka wymiana na Tab zostaje tym, czym jest: jedno gniazdo, bez pauzy,
decyzja podjęta w locie. To jest druga połowa.

- [x] `bulk` na `WeaponData`: jedna jednostka dla każdego rodzaju modułu, żeby cargo nie potrzebowało tabeli przeliczeń, a pilot drugiej liczby do nauczenia. Afiks `lightweight` (gabaryt w dół za cenę obrażeń).
- [x] Ładownia cargo jako **pojemność w gabarytach**, nie zestaw slotów. Ładunek jest masą: pełne cargo to wolniejszy statek. Luk cargo siedzi na środku masy pustego statku, więc ładowanie jest odczuwalne jako ociężałość, a nie jako ostrzeżenie w raporcie.
- [x] Wyrzucanie za burtę tworzy **prawdziwą skrzynkę**, do której można wrócić, z chwilą nietykalności, żeby nie podnieść jej z powrotem w tej samej klatce.
- [x] Ekran: cargo + ładownia jako jedna lista, schemat statku, info o module, podświetlenie pasujących gniazd, montaż, chowanie, wyrzucanie.
- [x] Schemat **generowany** z wielokąta kadłuba i pozycji mountów, nigdy rysowany ręcznie — ręczny byłby nieprawdziwy w chwili, gdy mount się przesunie (a przesunęły się dwa razy przy okazji `bulk`).
- [x] Podgląd skutku przed montażem: wybranie gniazda pokazuje, co zrobi `ConfigurationReport.compare()`, zanim cokolwiek zostanie wkręcone. Silniki przez grupy sterowania, broń przez porównanie z tym, co już w gnieździe.
- [x] Mysz: klikanie po liście i po kropkach schematu, obok klawiatury.
- [x] Patrzeć można zawsze, zmieniać tylko na ziemi: ekran otwiera się wszędzie (planowanie refitu w drodze do domu jest sensowne), ale montaż wymaga wylądowania. Wyrzucanie za burtę zostaje dostępne w locie.
- [x] Pojemność cargo jako własność kadłuba (`hull_cargo_capacity`) minus to, co wypiera zamontowana maszyneria — generator zabiera pół swojego gabarytu z ładowni.

Gotowe, gdy: da się znaleźć moduł, obejrzeć go obok tego, co już jest zamontowane, wsadzić w konkretne gniazdo i wyrzucić to, czego się nie chce — bez zgadywania, gdzie co pasuje.

---

## MAUX2: Dopalanie i ekran pomocy

Poza kolejnością milestone'ów: jedno wyszło z gry (statek nie do podniesienia
z ciężkiego świata), drugie z tego, że klawiszy zrobiło się trzydzieści parę.

- [x] **Dopalanie silników głównych.** `EngineData` dostaje mnożnik ciągu i mnożnik spalania; jedynka znaczy „bez trybu awaryjnego", więc mają go tylko duże napędy. Stokowo **3× ciągu za 12× spalania**: 54,2 → 162,7 px/s² przy grawitacji planet 25–60, na **8,3 s** pełnej puli. Paliwa jeszcze nie ma, więc płaci pula energii — dopalanie konkuruje z bronią. **Zatrzask, nie próg**: sam próg dawał impuls ciągu co sekundę nad pustą pulą, bo spalanie odsuwa ładowanie; teraz jedno wciśnięcie to jedno palenie.
- [x] **Dedykowane klawisze postawy**: prograde HOME, retrograde END, zatrzymanie obrotu INSERT, hamowanie także DELETE obok Z. Akordy zostają — są tym, co ręce pilota mają pod palcami bez schodzenia z klawiszy ruchu; klawisz wygrywa, bo jest jednoznaczny.
- [x] **Akord trzyma swoje klawisze aż do puszczenia.** Zgłoszone z kokpitu: przy puszczaniu A+D jeden klawisz przeżywa drugi i statek zaczyna się kręcić w chwili, gdy pilot przestał kazać mu przestać. `SETTLE` pilnował tylko wchodzenia w akord. Lustrem byłoby okno przy wychodzeniu, a okno to zgadywanie — więc klawisz zużyty przez akord zostaje zużyty do puszczenia. Test pada bez poprawki.
- [x] **Ekran pomocy na `?` / `F1`**, czytany z InputMap, nie z przepisanej listy. Test pilnuje, że każda akcja ma opis — przy pierwszym uruchomieniu wypadły cztery akcje, o których nie wiedziałem.
- [x] **Dopalanie widać.** Problem nie był w przycinaniu, tylko w tym, **którą liczbę czytała grafika**: wszystko, co rysowało wydech, brało `effective_output()`, czyli ułamek przepustnicy, który z definicji kończy się na jedynce. Fizyka od początku mnożyła go przez `boost_factor()` w `current_force()` — prezentacja nie. Jest teraz `EngineInstance.exhaust_flow()`, jawnie mogące przekroczyć jeden, i to ono napędza płomień, światło i cząstki. Przy trzykrotnym ciągu: płomień **trzy razy dłuższy**, szerszy o pierwiastek z trzech (dopalanie to włócznia, nie chmura), klatki trzy razy szybsze, światło dyszy 1,50 zamiast 0,50. `amount_ratio` cząstek dalej nasyca się na jedynce, bo to ułamek i naprawdę nie może być większy.
- [x] ~~Przemapowanie klawiszy~~ — **należy do M6** („Menu, ustawienia, mapowanie klawiszy") i tam zostaje; trzymanie tego w dwóch milestone'ach to jedna pozycja, o którą dwa plany się spierają. Ekran pomocy jest na to gotowy, bo nazwy czyta z mapy wejścia, a nie ze stałych.

---

## MAUX3: Z kokpitu

Poza kolejnością milestone'ów, wszystko zgłoszone z lotu.

- [x] **Hamulec ma dwa tryby, granicą jest sfera wpływu planety.** Poza nią
  statek obraca się retrograde i pali główny napęd; trzymane jednocześnie
  dopalanie działa bez jednej dodatkowej linijki, bo mnoży to, czego
  przepustnice już żądają. Pod planetą zostaje stary rozkład na osie z
  nietkniętym obrotem — nisko dziób trzyma postawę nad terenem i hamulec nie ma
  prawa mu jej zabrać. Zmierzone, 100 px/s do zera: skośnie **6,1 s** przeciwko
  **6,5 s**, w bok **5,7 s**, na wprost z dopalaniem **3,4 s**; przy
  prędkościach międzyplanetarnych różnica rośnie, bo zwrot to stałe dwie
  sekundy, a przewaga ciągu to iloraz. Bramka zgodności 0,98, dryf poniżej
  8 px/s idzie starym hamulcem. Szczegóły i dwa przypadki brzegowe w IDEAS.md,
  „Hamowanie poza grawitacją planety".
- [x] **Prędkość względem powietrza, nie względem układu.** Zgłoszone z
  kokpitu: smugi pędu na ekranie przy statku stojącym na nogach. Zaparkowany
  statek melduje 21 px/s, bo `_hold_landed_pose()` przestawia go co tik wzdłuż
  obracającego się gruntu, a zamrożona bryła kinematyczna melduje to jako
  prędkość. Nie kłamie — błąd polegał na tym, że czterech czytelników
  (zasłona pędu, smugi, nagrzewanie, kierunek rozmycia) pytało „jak szybko",
  a każdy miał na myśli „jak szybko względem powietrza". `Ship.airspeed()`
  rozciąga na nich regułę, którą V/S miał od początku. Oba stany spoczynku
  zmierzone i przypięte testem. Szczegóły w IDEAS.md, „Prędkość względem
  powietrza to nie prędkość".
- [x] **Kamera nie zostaje w tyle.** Zgłoszone z kokpitu: przy przyspieszaniu w
  przestrzeni statek zsuwał się ze środka kadru i nie wracał, a przy
  najbliższym kadrowaniu wychodził poza ekran. To stały błąd filtru pierwszego
  rzędu (prędkość przez współczynnik — 200 px świata przy 2000 px/s, a na
  ekranie razy przybliżenie), więc jest **kasowany**, nie strojony: 0,0 px
  odchyłki przy 2090 px/s na każdym kadrowaniu. Plus twardy zderzak liczony w
  pikselach ekranu, który przy okazji robi za skok po przeskoku. Wygładzanie
  przeniosło się z silnika do `ShipCamera.follow()`, bo wbudowane dzieje się
  przy rysowaniu i nie dało się go przetestować. Szczegóły w IDEAS.md,
  „Kamera nie ma zostawać w tyle".
- [x] **Marker nawigacyjny.** Prawy klik na mapie układu wbija szpilkę, prawy
  klik na szpilce ją wyjmuje, prawy klik gdzie indziej ją przenosi — jeden
  przycisk, bo to jeden gest. Skaner trzyma ją zawsze: na pierścieniu z
  odległością, kiedy jest poza ekranem, i na samym miejscu, kiedy nie jest.
  Planeta przestaje być znaczona, gdy już ją widać; szpilka nie może, bo to
  miejsce, a nie obiekt. Trzyma się w `NavMarker` ze stanem statycznym, nie w
  `Galaxy` — autoload nie istnieje w biegu `--script`, więc mapa i skaner, które
  by go czytały, nie dadzą się nawet skompilować w teście. Przeskok między
  systemami ją wyrzuca (piksele układu nie podróżują), zapis ją niesie, a stary
  plik bez tego pola wczytuje się bez niej.
- [x] **Przyrząd orbity: trzy znaczniki, trzy kształty, i zegar.** Statek jest
  kwadratem w najjaśniejszym atramencie zamiast kółkiem w kolorze apoapsis;
  kropki apsyd gasną wygaszeniem, kiedy orbita robi się kołowa (wektor, który
  je wskazuje, jest wówczas czystym szumem), a wszystkie trzy siadają na
  siatkę piksela — bez tego znaczek na cztery piksele rasteryzuje się co
  klatkę inaczej i na przeskalowanym oknie to widać. Doszedł wiersz
  `APO in 42s` liczony Keplerem na tej samej stożkowej, którą tarcza rysuje.
  Szczegóły w IDEAS.md, „Przyrząd orbity".
- [x] **Gwiazda wrze.** Powierzchnia jest próbkowana przez zniekształcenie,
  które samo się porusza, więc granula pęcznieje, dzieli się i gaśnie **w
  miejscu** zamiast przesuwać się za okno — poprzednia wersja przesuwała jedno
  pole szumu, powoli, i to jest dokładnie to, co zdradza płaski obraz. Kolor
  jest teraz **temperaturą**, nie jasnością: rampa od chłodniejszych pasów przez
  własny odcień gwiazdy do białego, z przepaleniem na szczytach. Pasy biorą
  kolor **klasy niżej** z `Star.COLOURS`, bo mnożenie odcienia przez czerwień
  działa dla żółtej gwiazdy i robi z błękitnego olbrzyma błoto. Pięć klas
  sprawdzone zrzutem, nie rozumowaniem.
- [x] **Silniki gasną po wylądowaniu.** Zgłoszone z kokpitu: czasem płomień
  zostawał zapalony bez żadnego inputu. Statek na nogach nigdy nie dociera do
  `_integrate_forces`, więc nikt nie schodził mu z przepustnicy, którą miał w
  chwili przyziemienia. „Czasem", bo trzeba trafić w pół sekundy spool-downu
  po puszczeniu klawisza — czyli w ostrożne lądowanie na silniku. Szczegóły w
  IDEAS.md, „Stan «wylądowany»”.
- [x] **Zoom kółkiem na mapie, zakotwiczony na kursorze.** Punkt pod kursorem
  zostaje pod kursorem — to jest cały warunek i test pilnuje go dwa razy pod
  rząd, bo ciekawa awaria to ta, która wychodzi dopiero, kiedy środek już raz
  się przesunął. Środek mapy jest teraz punktem, nie ciałem; klik przywiązuje
  go z powrotem do klikniętego ciała i dalej je śledzi. Szczegóły w IDEAS.md,
  „Mapa układu".
- [x] **Kod i teksty w grze po angielsku.** Reguła z CLAUDE.md była od dawna, a
  51 plików jej nie dotrzymywało; przy okazji na angielski poszło wszystko, co
  czyta pilot. Dokumenty projektowe (ten plik, IDEAS, VISUALS, UI_STYLE)
  zostają po polsku. Test złapał dziewięć miejsc, w których sam dopasowywał się
  do polskiego tekstu — nazwy presetów i prefiks „też:” na karcie modułu.
  Glify polskie zostają w `make_font.gd`: to czcionka, a nie proza.

---

## MAUX4: Edytor statku, druga wersja

Z makiety. Pięć obszarów zamiast trzech, i — co ważniejsze — **porzucenie
listy tekstowej na rzecz ikon**: dzisiejszy edytor opowiada słowami to, co
powinien pokazywać kształtem.

### Układ, którego żąda makieta

| gdzie | co | dziś |
|---|---|---|
| lewa góra | **Ładownia jako ikony** z ramką w kolorze rzadkości | lista tekstowa |
| lewy środek | **dwa widżety**: spare parts i stardust na pokładzie | nie istnieją |
| lewy dół | **rozbiórka przedmiotu na spare parts**, uzysk z typu, gabarytu i rzadkości | nie istnieje |
| środek | schemat statku, **wszystkie gniazda klikalne**, uchwyt do obracania hardpointu, dwa przyciski grupy | schemat jest, obracanie na `,` / `.`, grupa na `G` |
| prawa krawędź | **kolumna gniazd modułowych** | gniazda wewnętrzne leżą na schemacie |
| dół lewy | **fakty o statku**: ciąg, masa, przyspieszenie, hamowanie, generator, napęd skokowy, paski paliwa i ładunków hyperdrive | częściowo w `ConfigurationReport` |
| dół środek i prawo | **dwie karty obok siebie** — kliknięty przedmiot z ładowni i kliknięty zamontowany — z przyciskiem zamiany między nimi | jedna karta naraz |

### Dwie rzeczy, które makieta przy okazji wyłapała

**„MODS DO NOT IMPACT MASS AT ALL" już było prawdą — i okazało się, że z
szerszego powodu, niż notatka mówiła.** Hardpointów nie ma w sumie masy w
ogóle, więc nie waży ani mod, ani sama broń. **Rozstrzygnięte: zostaje tak**,
tyle że teraz jako decyzja. Pomiar i odrzucone warianty w IDEAS.md, „Działa i
mody nie ważą nic, i to jest decyzja". Przy okazji silniki schudły o połowę —
patrz sekcja 3 tegoż.

**Kolumna gniazd modułowych rozwiązuje problem, który kod sam o sobie
zapisał.** Komentarz przy `_free_near()` tłumaczy, że gniazda wewnętrzne —
generator, komputer, podwozie — stoją w rzeczywistości kilka pikseli od siebie
i trzeba je na schemacie rozpychać sztucznie. Wyciągnięcie ich do kolumny
kasuje całą tę maszynerię: schemat zostaje dla tego, co **ma** miejsce na
kadłubie (silniki, działa), a reszta dostaje listę, której geometria niczego
nie udaje.

### Czego nie da się zrobić przed M5.2

Trzy pozycje z makiety to **nie jest UI, tylko prośba o zasoby, których nie
ma**: spare parts, stardust i hyperdrive charges są pozycjami M5.2. Rozbiórka
przedmiotu na części jest przy okazji tym, czego M5.2 i tak potrzebuje —
odpływem na śmieciowy loot — więc jest po stronie zasobów, nie ekranu.

Reszta makiety stoi na tym, co już jest: sylwetki gniazd (`_draw_slot_glyph`,
`_draw_weapon_glyph`) są gotowym słownikiem ikon dla ładowni, kolory rzadkości
siedzą na `ModuleData`, treść kart na `card_lines()`, a porównanie dwóch
konfiguracji na `ConfigurationReport.compare()`.

### Kolejność

- [x] **4.1 Rama na sześć obszarów.** Sam układ, rysowany z tego, co dziś jest
  rysowane. Osobno, bo przestawianie paneli i zmiana ich zawartości naraz to
  dwie zmiany, które nie dadzą się obejrzeć oddzielnie.
- [x] **4.2 Ładownia jako ikony.** Sylwetka według rodzaju, ramka w kolorze
  rzadkości, bez ani jednego słowa. Nazwa schodzi na kartę pod spodem — ona i
  tak jest tam, gdzie pilot patrzy po kliknięciu.
- [x] **4.3 Kolumna gniazd modułowych.** Weszła razem z ramą, bo rama z
  obszarem, którego nikt nie używa, to dokładnie to puste pudełko, przed którym
  ostrzega UI_STYLE. `slot_positions()` dzieli teraz gniazda na dwa rodzaje:
  przykręcone do kadłuba rysują się tam, gdzie są, a objętości w środku dostają
  kolumnę. `_free_near()` zostaje dla tych pierwszych i nie ma już czego
  rozpychać.
- [x] **4.4 Dwie karty i przycisk zamiany.** Przycisk dostaje **własną przerwę**
  między kartami, nie leży na nich: narysowany na wierzchu zasłaniał ostatnie
  słowo wiersza porównania, a koniec „+0,095 better" to dokładnie to, co ktoś
  czyta, sięgając po niego.
- [x] **4.5 Fakty o statku**: masa, ciąg, przyspieszenie, hamowanie, generator
  i zasięg skoku z `ConfigurationReport`, plus **trzy paski** — kadłub, paliwo,
  skoki. Paski dostają tylko te trzy odczyty, bo tylko one mają koniec: liczba
  mówi ile, pasek mówi ile **zostało**, a tego nie pyta się o masę. Kadłub
  bierze progi z `UiWarning`, bo kadłub bursztynowy w kokpicie i biały tutaj to
  dwa przyrządy kłócące się o ten sam kadłub.
- [x] **4.6 Uchwyt do obracania hardpointu myszką**, z zatrzaskiem co
  `AIM_STEP` — klawisze zostają i obie kontrolki muszą lądować na tych samych
  kątach, bo dwie kontrolki niezgodne co do tego, czym jest poprawny kąt, to
  dwie kontrolki. Dwa przyciski grupy zamiast przełącznika: zapalony mówi, na
  którym spuście gniazdo jest **teraz**, a przełącznik mówił tylko, że coś się
  zmieniło.
- [x] **4.7 Każdy komponent klikalny: do ładowni albo za burtę.** Brakowało
  połowy: wszystko dawało się przykręcić i nic zdjąć inaczej niż wkręcając coś
  w to miejsce. **Nigdy donikąd** — gdy w ładowni nie ma miejsca, moduł zostaje
  i mówi dlaczego. Za burtę wolno wszędzie, wyrzucanie balastu pod presją to
  dokładnie ta decyzja, którą warto mieć.

  Przy okazji wyszło, że makietowe **„ALL SLOTS SELECTABLE" to nie uwaga o
  rysunku, tylko o sterowaniu.** Wybór gniazda szła dotąd za tym, co pasuje do
  trzymanego modułu, więc gniazda, które modułu nie przyjmą, **nie dało się
  wybrać w ogóle** — a tym samym obrócić, przepiąć ani rozkręcić. Wszystko, co
  gniazdo potrafi, a co nie ma nic wspólnego z zawartością ładowni, było
  nieosiągalne dokładnie dla tych gniazd, gdzie to miało znaczenie. Kliknięte
  gniazdo wygrywa teraz z kursorem strzałek, a podgląd montażu celuje w to samo
  gniazdo, co przycisk — inaczej ekran obiecywałby jedno, a robił drugie.
- [x] **4.8 Widżety spare parts i stardust.** Dwa odczyty, nie dwa paski:
  te zasoby nie mają własnej pojemności — ładownia jest ich pojemnością i jest
  narysowana nad nimi. Pasek bez końca to pasek, który kłamie o tym, gdzie
  jest koniec.
- [x] **4.9 Rozbiórka na spare parts.** Dźwignia **obok liczby**, bo liczba
  jest całą decyzją. Miejsce pokazane zawsze, bo to jest cena. **Nie jest
  bramkowana staćem na ziemi**, inaczej niż montaż: miejsce już **jest** ceną
  (w próżni dostaje się niewiele ponad połowę), a reguła, która i wycenia, i
  zabrania, kazałaby płacić dwa razy za jedną decyzję. Komunikat mówi też o
  **stracie**: ładownia jest pojemnością również dla części, więc rozbiórka
  bez miejsca na to, co z niej wyjdzie, wyrzuca różnicę — zmierzone 18 z 28
  przy pełnej ładowni. Koszt, o którym nikt nie mówi, jest błędem, choćby był
  najstaranniej zapisany.
- [x] **4.10 Pasek ładunków hyperdrive** — wszedł z 4.5 jako trzeci pasek w
  faktach o statku, razem z kadłubem i paliwem.

Gotowe, gdy: refit czyta się kształtem, nie zdaniami, a decyzja „to czy tamto"
ma obie strony na ekranie naraz.

---

## M3: System gwiezdny i streaming

Cel: gwiazda, kilka planet, księżyce, stacja. Planety włączają się i wyłączają w zależności od odległości.

- [x] Model danych systemu: `SystemBody` i `StarSystem` jako czyste dane (`RefCounted`, zero node'ów), `Galaxy` trzyma seed, zegar i cache systemów. Gwiazda, 3–5 planet, księżyce, stacje, wszystko z jednego seeda przez splitmix64. **System decyduje, jak duże i jak ciężkie; seed decyduje, jak wygląda** — promień i grawitacja są w deskryptorze, bo układ orbit ich potrzebuje; teren, pogoda i kolory zostają przy seedzie planety.
- [x] Orbity analityczne od globalnego czasu: koła, `position_at(t)` rekurencyjne w górę drzewa, zero stanu. Ciało wyłączone i włączone z powrotem jest tam, gdzie byłoby — nie ma czego doganiać, bo nic nie całkowało. Okresy z `mu = g·r²` rodzica, więc trzecie prawo Keplera wychodzi za darmo.
- [x] `StreamingManager`: poziomy z histerezą i kolejka instancjonowania. **Trzy stany, nie cztery** — `GONE / AWAKE / SURFACE`. Poziom 1 z projektu („planety jako sprite'y”) nie ma przy 640x360 żadnego reżimu: planeta ma 2000+ px średnicy, więc jest albo szersza od ekranu, albo poza nim. Ciało budzi się, zanim cokolwiek mogłoby o nie zapytać — najdalej patrzy skaner (20k px), i test to przypina do jego własnej liczby.
- [x] Jeden zamrożony zegar na wizytę, nie na ciało. Ciala stawiane raz, w tej samej chwili.
- [x] Generacja terenu w `WorkerThreadPool`. `PlanetTerrain` rozdzielony na `build()` (sama arytmetyka, wątek roboczy) i `finish()` (tekstura, główny wątek). Zmierzone na prawdziwym rendererze: **13,2–33,3 ms zeszło z klatki, 0,1–0,3 ms zostało**. Węzeł powstaje poza drzewem i wchodzi dopiero gotowy, więc nie ma półzbudowanej planety, którą ktoś mógłby o coś zapytać. Przylot (`force_awake`) buduje synchronicznie — raz zapłacona zadyszka zamiast statku postawionego obok planety, której jeszcze nie ma.
- [x] Delta lootu: skrzynka podniesiona zostaje podniesiona. Manager pamięta opróżnione półki per seed ciała, a pozostałe losuje bez zmian — zabranie jednej nie zmienia, czym są inne.
- [x] Delta terenu: skorupa zapamiętywana przy wyłączaniu planety i kładziona z powrotem przy budowie. Tylko dla światów, w które ktoś strzelał — nietknięty wraca identyczny z seeda, a trzymanie jego kopii to trzymanie seeda dwa razy. Spakowana ZSTD. Przywracanie robi wątek roboczy razem z generacją: na głównym kosztowało 15 ms, przez co planeta z kraterem zacinała mocniej niż nowa (21,4 → 7,5 ms najgorszej klatki).
- [x] **Gwiazda jako węzeł: ciąg i żar.** Studnia wyprowadzona do wspólnej klasy `GravityWell` (promień, grawitacja, zasięg, `gravity_at`), z której planeta i gwiazda dziedziczą — kto chce samego ciągu, bierze `GravityWell`, kto chce w co uderzyć, bierze `Planet` i dostaje wyłącznie planety. Gwiazda idzie w górę razem z systemem i nigdy nie schodzi: jej ciąg obejmuje cały układ, więc gwiazda wyładowana przez streaming to układ, który traci grawitację dokładnie wtedy, gdy się na niej leci.
- [x] **Masa gwiazdy liczona bezpośrednim kryterium, nie Hilla.** Sfera Hilla jest wyprowadzona w układzie obracającym się z planetą; nasze planety stoją, więc nie ma czego kasować i sfera wychodzi siedem razy za szeroka. Zmierzone pod starą regułą: na krawędzi własnej studni najbliższej planety gwiazda wygrywała **2:1**. Teraz `mu_p/w² ≥ 2·mu_*/(a−w)²`. Stary test przepuszczał błąd, bo pytał o Hilla — pyta teraz o to, co faktycznie obowiązuje.
- [x] **Studnie planet wyprowadzane, gwiazda losowana** — bo kryterium czytane od strony „jak lekka musi być gwiazda" zostawiło ją fizycznie nieistotną: **0,069 px/s² tam, gdzie się lata, cztery dziesiąte procenta tego, co statek czuje.** Zgłoszone przez pilota, nie przez test. Każda planeta dostaje studnię, którą utrzyma (3,0–6,0 promieni), a układ odsuwa ją na zewnątrz, gdy nie mieści się `WELL_FLOOR`. Po zmianie: **0,87–2,47 px/s² na pierwszej orbicie, 0,43–1,61 między orbitami, 4673 px znoszenia na 100 s dryfu w grze** (było 224). Gwiazda zeszczuplała do 2600–4800 px i ma losowaną grawitację 45–110; kolor wynika teraz z masy, więc niebieska naprawdę jest ciężka. Test ma dolną granicę ciągu, nie tylko górną.
- [x] **HUD orbitalny gospodarzy ta studnia, która ciągnie najmocniej** — nie najbliższa planeta. Między orbitami panel znikał, choć statek spadał wokół gwiazdy. Arytmetyka orbit przeniosła się do `GravityWell`; `has_ground()` decyduje, czy panel pokazuje nachylenie i podwozie, czy nazwę ciała.
- [x] **Strefa obrażeń to pasek ciepła, nie drugi mechanizm.** `hull_heat` istniał od M1.6 i nic nie robił; teraz powyżej 0,75 kadłub się pali, z tarcia i ze światła tak samo. Zmierzony szczyt zdecydowanego aerobrakingu to 0,447, więc lądowanie nic nie traci. Promień strefy wyprowadzony z samych tempa grzania i stygnięcia: **1,73 promienia gwiazdy**, z zapasem ×1,36 do najbliższej orbity w 300 systemach. Pasek ciepła dochodzi do HUD pod paskiem kadłuba, z kreską na progu, i pokazuje się dopiero gdy jest co pokazać.
- [x] **Gwiazda jako światło.** Powierzchnia to shader: granulacja (fbm, cele 85 px świata, znoszone powoli), pociemnienie brzegowe jako jedyna wskazówka, że to kula, czysta krawędź. Barwa tarczy podciągnięta o 45% w stronę bieli — malowana nominalnym kolorem czytała się jak ceglany mur. **Korona addytywna**: alfa-blending jasnego koloru na czerni dawał szarą smugę, czyli dym zamiast światła, a teraz gwiazdy tła prześwitują przez halo.
- [x] **Cień nocnej strony planet.** Kierunek na gwiazdę idzie do shaderów gruntu, powietrza i chmur w ramce ich własnego quada, co klatkę — doba to planeta obracająca się pod gwiazdą, więc nie ma czego przechowywać. Trzy różne progi nocy (grunt 0,50, chmury 0,30, powietrze 0,22), celowo niezgodne z fizyką: po gruncie się ląduje, a przy 0,40 wszędzie noc wychodziła nie do wylądowania. Każda warstwa chmur ma własny materiał, bo każda obraca się własnym tempem; kierunek chmury jedzie w kolorze instancji, żeby nie zakładać, w jakiej przestrzeni jest `MODEL_MATRIX`.
- [x] **Studnie łatane, nie sumowane.** Zgłoszone z kokpitu: nie dało się wejść na orbitę planety — orbita na 1,6 promienia uderzała w grunt w trzy minuty, na 2,6 i 4,0 uciekała ze studni. Przyczyna wprost z tego, że planety stoją: w realnym układzie planeta spada ku gwieździe razem ze statkiem i zostaje tylko pływ, a u nas statek dostaje pełny ciąg gwiazdy, a planeta żaden — to stałe pchnięcie, nie perturbacja. Teraz wewnątrz studni ciągnie tylko jej ciało, a szwem jest wygaszanie, które studnia i tak ma na krawędzi. Po zmianie orbity trzymają **±0,1%**, a pole przy przejściu jest ciągłe (największy skok 0,25 z 5,28 px/s²).
- [x] **HUD orbitalny tylko nad ciałami z gruntem.** Pod łatanymi studniami panel gwiazdy był nawet prawdziwy, ale wisiał zawsze — nie ma w układzie miejsca poza zasięgiem gwiazdy — a odczyt, który jest zawsze, to odczyt, którego nikt nie czyta.
- [x] **Mapa rysuje zasięg atmosfery i studni.** Wysokość atmosfery przeniosła się przy okazji do modelu: to wielkość orbitalna (dzieli orbitę trwałą od zanikającej), a mapa rysuje światy, których nikt jeszcze nie zbudował.
- [x] **Oświetlenie 2D** — i wyszło, że to dwie różne rzeczy. Światło 2D bez map normalnych nie wie, w którą stronę zwrócona jest powierzchnia, więc **terminatora nie zrobi**, a `CanvasModulate` przyciemniłby też shadery planety, które liczą własne światło. Dzień i noc dla statku i skrzynek liczy więc ta sama reguła co dla gruntu (`GravityWell.daylight_at`), jako skalar: kadłub nad nocną stroną ma **0,42 przeciw 1,00** nad dzienną. Terminator przestał być stałą w trzech shaderach i jest jedną stałą wpychaną do nich jako uniform.
- [x] **Prawdziwe `Light2D` tam, gdzie coś świeci**: pocisk, rakieta, wybuch, dysza. Addytywne, tekstura robiona w kodzie (ten projekt nie ma sprite'ów). Koszt ośmiu świateł dysz: **0,24 ms na klatkę** po stronie CPU.
- [x] **Halo wyleczone**, zgłoszone z kokpitu. Dwie przyczyny: światło padało na kwadrat atmosfery, który zakrywa całą okolicę planety, więc rozświetlało tarczę nieba zamiast powierzchni (atmosfera i chmury są teraz `unshaded` — to nie są powierzchnie); i każda dysza świeciła tak samo mocno, więc osiem równych lamp na jednym kadłubie. Blask skaluje się teraz ciągiem: **160 N daje 0,09 mocy i 46 px zasięgu przeciw 0,50 i 110 px napędu głównego**. Spadek promieniowy 2,2 → 3,4.
- [x] **Księżyc jako studnia w polu planety** — wypadło za darmo przy łataniu studni i zmierzone: nisko nad księżycem to księżyc jest ciałem, które „posiada" statek, a dwie minuty na orbicie wokół niego trzymają ±0,1%, z planetą tuż obok.
- [x] **Odchylenie toru statku przy przelocie** — też już działa, zmierzone na przelocie 708 px obok księżyca: **80,6° przy 90 px/s, 27,9° przy 160, 8,8° przy 280**. I widać przyjęty handel: prędkość na wyjściu równa prędkości na wejściu (90 → 91, 280 → 278). Zakręcanie jest, darmowej energii nie ma, bo ciało stoi.
- [x] **Pociski pod wpływem grawitacji.** Jedyna rzecz w grze zwolniona z reguły, o którą cała gra chodzi. Zmierzone na 1600 px z 848 px wysokości: pulse repeater spada 18,7 px (0,7° poprawki), autocannon 42,4 px (1,5°), dumb rocket 522,8 px (18,1°) — charakter broni z jednej liczby. **Kursor celowania nic nie kompensuje i to jest decyzja**: melduje tylko, czy lufa może się wycelować, poprawka należy do pilota.
- [x] **Pociski nie są drogie — poprzedni pomiar był zły.** Podałem 0,9 ms na pocisk na klatkę; prawdziwa liczba to **7–8 µs**, czyli ponad dwa rzędy wielkości mniej. Błąd był w metodzie: `Performance.TIME_PROCESS` w oknie z vsync nie mierzy wykonanej pracy, tylko gdzie silnikowi wypadło zaksięgować czekanie (ten sam pomiar dawał 42 ms przy zerze pocisków). Zmierzone zegarem ściennym bez vsync: koszt **liniowy**, 15 pocisków to 0,7% klatki, 160 to 8%. Strzelanie w grunt nie kosztuje nic ponad bezczynność, a najgorsza klatka (5,6 ms) jest taka sama także w bezruchu. Metoda zapisana w `tools/frame_bench.gd`.
- [x] **Stacja orbitująca i stacja w deep space: dokowanie i naprawa.** Rysowana (pierścień, szprychy, piasta, lampa nawigacyjna), losowana z seeda, streamowana jak każde inne ciało — `builds_as_node` mówi teraz „wszystko poza gwiazdą" zamiast wyliczać, kto może. Dokowanie **bez klawisza**: w zasięgu 2,6 promienia i pod 30 px/s statek sam się przywiązuje, bo przelot w tempie spacerowym już jest decyzją. Odmowa podaje powód (`za daleko` / `za szybko`), nie „nie". Naprawa za czas: pół kadłuba w 1,6 s, komplet w dziesięć — pierwszy raz, gdy uszkodzenie da się cofnąć bez respawnu. Odlot to ten sam gest co start z gruntu, z zatrzaskiem: dok nie przyjmie statku ponownie, dopóki ten nie opuści zasięgu (bez tego łapał go z powrotem w następnej klatce).
- [x] Tankowanie: dok uzupełnia paliwo. Było otwarte z własnej definicji — nie
  da się zatankować zasobu, którego nie ma — i zamknęło się samo w M4, kiedy
  bak stał się modułem. Dok tankuje wolniej, niż ładuje energię, i
  `fully_serviced()` czeka na pełny bak. Blokadą było M4, nie M5.
- [x] **Wymiana modułów w doku.** `ShipEditor.can_refit()` przyjmuje teraz LANDED **albo** DOCKED — obietnica zapisana w komentarzu tej funkcji, zanim było do czego dokować. Szybka wymiana na Tab **zostaje dostępna w locie** i to jest decyzja, nie przeoczenie: `LoadoutScreen` nie pauzuje właśnie dlatego, że jeden niesiony moduł w jedno zgodne gniazdo przy działającym świecie to decyzja podejmowana, kiedy coś idzie źle. Edytor to druga rzecz — wszystkie gniazda naraz na zapauzowanym schemacie — i to jest robota w warsztacie.
- [x] **Mapa układu na `M`**. Rysowana z **modelu**, nie ze sceny — manager trzyma w świecie jedną planetę naraz, a mapa z żywych węzłów pokazałaby jedną kropkę i nazwała to układem. Orbity w skali, ciała jako znaczniki (planeta w skali to jedna dziesiąta piksela). Jasność znacznika mówi, czy ciało jest w świecie, czy dopiero w modelu — jedyne okno na to, co robi streaming. Nazwa i odczyt na kliknięcie, jak na schemacie w edytorze.
- [x] Zoom mapy (`+` / `-`), jako **zasięg w pikselach świata**, nie mnożnik: systemy mają od 41k do 302k px, więc ten sam mnożnik to inny widok w każdym z nich — x64 mieściło księżyc na ekranie w szerokim systemie i wyrzucało go poza ekran w wąskim. Poziomy to cały układ, 30000, 7500 i 2000 px; 7500 to „ta planeta i jej księżyce” w dowolnym systemie. Powiększanie wokół **wybranego ciała**, bo wokół gwiazdy pierwszy krok wypycha z ekranu to, co się przed chwilą kliknęło. Ciało dostaje swój prawdziwy okrąg powierzchni, gdy zrobi się większy od znacznika.
- [x] **Teleport na `Enter`** do ciała wskazanego na mapie — narzędzie deweloperskie, tej samej klasy co teleport między półkami w konfiguratorze. Cel jest budowany synchronicznie (`force_awake`), bo statku nie da się postawić przy planecie, której jeszcze nie ma, i ląduje na orbicie kołowej po tej stronie, z której przyleciał. Świat śledzi teraz, przy której planecie jest statek — nieświeża referencja znaczyłaby konfigurator edytujący planetę, którą pilot już opuścił.
- [x] **Przybliżona trajektoria na mapie**, przerywaną krzywą. Rdzeń całkowania wyciągnięty z `TrajectoryPredictor` jako `coast()` — linia na F7 i krzywa na mapie czytają **jedną przyszłość**, a nie dwie. Horyzont skalowany zasięgiem mapy, bo stały jest zły z obu stron: dwie minuty to dwunastopikselowy kikut na układzie 300k px i kilka orbit przy zoomie na planetę. Czerwona i z krzyżykiem, gdy kończy się w gruncie.
- [x] **Test: przelot przez cały układ.** Objazd wszystkich światów, dziura wystrzelona w każdym, powrót na pierwszy — czyli przypadek, w którym menedżer musiał w międzyczasie zapomnieć i odbudować wszystko. Trzy światy, trzy dziury, wszystkie na miejscu. „Bez przycięć" **zmierzone**, nie oceniane: krusta liczy się na wątku roboczym, a to, co naprawdę płaci klatka, to `_start_build` plus `_collect_finished` (instancja, przygotowanie, wysyłka tekstury, wizualia) — **najgorszy przypadek 1,5 ms** przy pułapie 12 ms w teście. Test złapał przy okazji własną słabość: sprawdzenie „dziura jest tam, gdzie była" przechodzi też wtedy, gdy strzał nic nie zrobił, więc teraz osobno pilnuje, że każdy świat da się rozkopać.
- [x] Decyzja o floating origin: **nie jest potrzebny**, zmierzone przez `tools/distance_bench.gd`. Systemy mają 41k–302k px promienia; przy 300k błąd przechowania współrzędnej to 0,005 px, obieg przez układ planety 0,010 px, a orbita nie zauważa odległości w ogóle (dryf 7 px/10 s tak samo w zerze i w milionie — to całkowanie, nie float). Jedyna rosnąca liczba to pełzanie nieprzymrożonego kadłuba na gruncie: 0,12 px/10 s w zerze, 0,45 przy 300k. Test pilnuje, żeby układ nie wyszedł poza zmierzony zakres.

Gotowe, gdy: lot planeta-planeta jest płynny, a wyłączona planeta pamięta stan.
**Spełnione** i zmierzone: 1,5 ms najgorszego kosztu po stronie klatki przy
wejściu światu do sceny, trzy światy objechane i wszystkie trzy pamiętają, co
im się zrobiło.

---

## M3.5: Katalog przedmiotów i warianty

Cel: baza przedmiotu jest zasobem, afiksy wiszą przy bazie, a wygląd wynika z
cech. Bierze się po domknięciu M3, bo dotyka lootu, edytora i grafiki naraz.

Powód jest zmierzony, nie estetyczny. Afiksy już są — baza plus 0–4 wg
rzadkości, mnożnik na polu opłacony pogorszeniem innego — ale pula jest
wspólna dla całej kategorii i nie wie, czego baza nie ma.

- [x] **Afiksy per baza, nie per kategoria.** Pula bazy to teraz afiksy,
  które mają na niej co ruszyć — wyliczone, nie wypisane, więc nowy afiks
  nie wymaga dopisywania do siedmiu plików. **22 pary baza-afiks wypadły.**
  Zmierzone przed i po: 14% puli silnikowej i 13% broniowej było martwe na
  przeciętnej bazie; `steerable` na dyszy bez gimbala, `responsive` na
  silniku bez rozruchu, `wide` na działku bez wybuchu.
  Przy okazji wyszedł **przypadek odwrotny, którego notatka nie miała**:
  afiks, którego **koszt** pada na pole zerowe, nie jest wymianą tylko
  prezentem. `rapid` kupuje kadencję rozrzutem, a wiązka nie ma rozrzutu —
  pięć z trzynastu afiksów broniowych było na beam lance darmowych.
  Rzadkość, która nie ma czym zapełnić slotów, dostaje **mniej afiksów**,
  nie martwe: na ograniczonej bazie naprawdę jest mniej do zróżnicowania.
- [x] **Nazwy spójne dla wszystkich rodzajów.** `affixes` i `display_name`
  zeszły na `ModuleData`, a nazwa jest **składana w `title()`**, nie
  wypalana przy generowaniu. To nie jest porządki dla porządków: wypalonego
  napisu nie da się skrócić, bo po fakcie nic nie wie, które słowa były
  afiksami — a bez tego punkt o długości nie ma rozwiązania.
  Silniki dostały własne nazwy w zasobach („main drive", „torque jet")
  zamiast nazywać się po swoim enumie i ciągu. Komputer też przestał
  sklejać własne zdanie: jego funkcje **są** jego afiksami, więc podlega
  tej samej regule i temu samemu przycinaniu.
  Odblokowało trzy rzeczy zapisane wcześniej jako zablokowane: wiązanie
  wyglądu po afiksie dla silników **już nie jest bezczynne**, test afiksów
  działa teraz na silnikach, a `LootCrate.label()` pyta jedno miejsce
  zamiast trzech.
- [x] **Długość nazwy.** Zmierzone, i to pytanie **nie miało odpowiedzi,
  dopóki nie było fontu**: przy kroju proporcjonalnym „ile znaków wchodzi"
  zależy od tego, które znaki. Teraz 6 px na znak, karta w ładowni ma
  210 px — czyli **33 znaki** (poprzednia notatka myliła kartę z panelem
  HUD, który ma 158). Tytuł bierze tyle afiksów, ile wejdzie, w kolejności
  rzutu; reszta schodzi do osobnego wiersza karty („też: …"), więc żaden
  afiks nie znika. **Nie** „dwa najmocniejsze", bo nic nie szereguje
  afiksów: tabela jest ułożona tematycznie, a wylosowana lista jest w
  kolejności rzutu, więc ani jedno, ani drugie nie jest rankingiem.
  Test pilnuje limitu z obu stron — że tytuł tej długości się mieści i że
  o cztery znaki dłuższy już nie.
- [x] **Kadłuby jako zasoby.** Z trzech kopii katalogu do jednej.
  `CreativeTool.SHAPES` już nie istnieje, a presety `ShipFitout` nazywają
  kadłub (`"hull": &"freighter"`) zamiast wypisywać obrys. Przy okazji
  **ładownia i rozstaw nóg zeszły na kadłub**, bo to są fakty o kształcie:
  frachtowiec wozi czterdzieści dwa, bo jest skrzynią, a przechwytujący
  cztery, bo nie jest. Trzy presety latające tym samym dartem nie mogą się
  już co do tego różnić ręcznie.
  Test, który trzymał trzy kopie w zgodzie, zamienił się w test, że preset
  nie może nazwać kadłuba, którego nie ma — podpora zamieniona na regułę.
  **Czego świadomie nie zrobiłem:** pola `Ship.hull`. Statek znajduje swój
  obrazek przez `HullData.matching(hull_outline)`, bo obrys i tak jest
  jedynym źródłem prawdy o fizyce, a pole byłoby drugim, które trzeba
  pamiętać ustawić. Narzędzie kreatywne skaluje obrys i wtedy żaden kadłub
  nie pasuje — i to jest poprawna odpowiedź, nie dziura.
- [x] **Wygląd wiązany z cechą** (ASSETLIST.md, „Wygląd wynika z cech").
  `LookTable` wybiera obrazek po kluczu, po afiksie albo po progu na
  nazwanej statystyce, i mieszka w warstwie prezentacji — żaden zasób
  przedmiotu nie niesie tekstury, więc generator lootu nic o tym nie wie.
  Działa na ekranie: silnik dostaje pióropusz wg `max_thrust`, dysza wg
  `type`. Wiązanie po afiksie dla silników jest **napisane i bezczynne**,
  bo `EngineData` nie przechowuje afiksów — odblokuje je checkbox o
  nazwach wyżej, i jest test, który to zauważy.
- [x] **Sprite'y animowane**, pasek klatek w jednym pliku, tempo liczone ze
  stanu. `SpriteStrip` to format, `StripSprite` to węzeł, a `drive(ułamek)`
  jest jedynym miejscem, w którym tempo powstaje: pióropusz przy ćwierci
  przepustnicy miga cztery razy wolniej, bo silnik pracuje na ćwierć. Ikony
  HUD i edytora zostają statyczne.
- [x] Test: żaden afiks nie ląduje na polu, którego baza nie ma
  (`_check_affix_pools`, 1500 losowań plus sama reguła); każdy przedmiot ma
  nazwę mieszczącą się na karcie (`_check_item_names`, 1200 losowań, limit
  sprawdzany z obu stron przeciwko prawdziwemu panelowi i prawdziwemu
  fontowi); każdy kadłub z katalogu ma sprite (`_check_art`).

Gotowe, gdy: z siedmiu baz silnika i jednej puli afiksów wychodzi setka
rozróżnialnych silników, każdy o nazwie, która mówi, co robi, i wyglądzie,
który to potwierdza. **Spełnione.** Nazwa składa się z afiksów i bazy dla
każdego rodzaju tak samo, afiksy trafiają tylko tam, gdzie mają co ruszyć,
a dysza i pióropusz wynikają z typu i mocy.

---

## M4: Galaktyka, skaner, skok

Cel: wiele systemów, podróż skokiem bez bramek.

- [x] Generacja galaktyki: Poisson disk sampling, seedy systemów, sprawdzenie spójności grafu.
  `GalaxyMap` — czysta dana, 620 systemów, odstęp rosnący ku obrzeżu. (Promień
  podniósł się później z 60 na 140 ly, bo nie mieściła się w nim drabina tierów
  — M5.0; wszystkie ułamki poniżej przetrwały zmianę bez ruchu.)
  Zasięg bazowy zmierzony, nie zgadnięty: graf spina się dopiero przy ~1,75
  lokalnego odstępu, co daje 73–79% w jednym kawałku i 25–29 wysp na później.
  Szczegóły i tabela pomiarów w IDEAS.md sekcja 10.
- [x] Mass lock gwiazdy i strefa skoku. 1,5 × `outer_radius()`, więc liczone
  względem wszystkiego, co gwiazda trzyma — w tym głębokiej stacji, która
  potrafi stać dalej niż najdalsza planeta. Jedna reguła na cały układ,
  `is_mass_locked()` i `jump_clearance()` jako jedna odpowiedź, pierścień na
  mapie układu. Szczegóły w IDEAS.md sekcja 10.
- [x] Moduły: skaner (zasięg, jakość), napęd skokowy (zasięg), bak (paliwo). Wszystkie jako loot.
  `ScannerData` / `JumpDriveData` / `TankData` na wspólnym `ModuleBay`, z
  własnymi tabelami afiksów i bazami. `depth` skanera kupuje rzadkość, nie
  afiks. Paliwo jako pula na statku, liniowe w dystansie i masie, niedobór
  nie jest odmową. Stockowy kadłub dostaje wszystkie trzy — +20% masy,
  zmierzone. Szczegóły w IDEAS.md sekcja 10.
- [x] HUD: wskaźniki systemów na krawędzi ekranu, kolor wg osiągalności, informacje wg jakości skanera.
  `JumpHud` — osobny od `ScannerHud`, bo to drugi czujnik, nie ten sam
  dalej. Trzy niezależne wejścia: zasięg skanera wybiera, co widać,
  `depth` — co jest podpisane, zasięg napędu i stan baku — w jakim kolorze.
  Trzy rozróżnialne obrazy braku zamiast pustego ekranu. Sześć znaczników
  naraz, nazwy, które się nie nakładają. Szczegóły w IDEAS.md sekcja 10.
- [x] Maszyna stanów skoku: Idle, Charging, Transit, Arrival.
  `JumpController` — własna decyzja i własny zegar, zero wiedzy o tym, z
  czego składa się system. Paliwo palone **w trakcie ładowania**, więc
  przerwanie kosztuje bez drugiej reguły; przerywa puszczenie klawisza i
  trafienie. Cel zatrzaśnięty na starcie ładowania, bo dziób służy do
  wybrania celu, a nie do trzymania go.
- [x] Shader tranzytu, wymiana sceny systemu pod graczem w trakcie efektu.
  `StreamingManager.bind()` i tak zaczyna od `clear()`, więc skok to związanie
  nowego systemu w połowie tranzytu plus przestawienie statku, który nie jest
  dzieckiem żadnego z nich. Sprawdzone w prawdziwym świecie, nie tylko w
  teście. `TransitVeil` + `shaders/transit.gdshader`: rozmycie radialne do
  środka, smugi i przesunięcie koloru w chłód. Kształt krzywej jest projektem,
  nie gustem — pełna przed wymianą i trzymana do końca tranzytu.
- [x] Pozycja przylotu na krawędzi celu od strony źródła.
  `outer_radius * (źródło - cel)` wprost z IDEAS.md: lecisz na północny
  wschód, wychodzisz przy południowo-zachodniej krawędzi celu z gwiazdą
  przed dziobem. Kurs zachowany, prędkość ścięta do ¼ — nie do zera, bo
  zatrzymanie statku unie ważniłoby kurs, który się właśnie zachowało.
- [x] Misjump: sektor międzygwiezdny bez gwiazdy, ryzyko od niedoboru paliwa i zasięgu.
  Ryzyko to **gorszy z dwóch** czynników, nie suma. Adresem stała się
  **pozycja w latach świetlnych**, a nie indeks na mapie — bez tego nie da się
  być w miejscu, którego na mapie nie ma. `StarSystem.deep_space()`: bez
  gwiazdy, bez ciał, bez mass locka. Zawartość sektora (wraki, piraci,
  porzucony tanker) idzie z M5, bo tam mieszka. Szczegóły w IDEAS.md sekcja 10.
- [x] Zapis gry: seed plus delty, autosave przy skoku.
  `SaveGame` — ziarno, adres, zegar, delty i to, co ma na sobie statek.
  Moduły pakowane z listy właściwości, nie z ręcznej listy pól, bo ręczna
  zapomina to, co ktoś dodał w zeszłym tygodniu. Wznowienie przez
  `-- resume`; menu, które zrobi z tego rzecz zwykłą, jest w M6.

Gotowe, gdy: wylot z jednego systemu i wlot do drugiego czuje się jak jeden lot.

**Zamknięte.** Dziewięć pozycji, plus ostatnia zaległa z M3 (tankowanie w
doku), która odblokowała się sama w chwili, gdy bak stał się modułem.

---

## M5: Wrogowie, zasoby, pętla gry

Cel: powód, żeby latać — i kierunek, w którym się leci.

### 5.0 Tier, start i kierunek

- [x] **Tier systemu z promienia**, 1 na starcie do 10 w środku, policzony w
  `GalaxyMap.tier_of()` i czytany przez wszystko inne. Jedna liczba, bo trzy
  osobne skale (wrogowie, loot, ceny) rozjeżdżają się po pierwszym strojeniu, a
  wtedy „trudniejszy system" i „lepszy łup" przestają znaczyć tego samego
  miejsca.
- [x] **Drabina, po której da się wejść po jednym szczeblu.** Zgłoszone z
  kokpitu: nie zaczynaliśmy w tier 1, a czasem jedyną drogą naprzód był skok o
  dwa tiery. Jedna arytmetyka, dwie połowy. Pasy mierzą teraz **drogę**
  (`tier_span()` = promień systemu startowego), więc tier 1 jest tam, gdzie się
  zaczyna, z definicji — a promień galaktyki podniósł się z 60 na **140 ly**,
  bo szczebel musi być głębszy niż skok (dowód w jednej linijce, nie pomiar).
  Zmierzone na pięciu seedach: 16–22 krawędzie przez dwa szczeble i 3–7
  systemów bez łagodnego wyjścia → **0 i 0**. Koszt: 620 systemów zamiast 111,
  48 ms na galaktykę, i droga ze startu do środka ma 14–18 skoków zamiast 6 —
  co samo w sobie było powodem, bo na dziesięć szczebli nie da się wejść w
  sześciu krokach. Szczegóły i tabele w IDEAS.md sekcja 10.
- [x] **Start na obrzeżu: najdalszy system w największym spójnym kawałku.**
  Pomiar na pięciu seedach w „Co ta premisa psuje", punkt 1. Po podniesieniu
  promienia: 109–113 ly ze 140, **tier 1**, pełny zasięg do rdzenia i pierwszy
  skok w łatwej części zakresu.
- [ ] **System środkowy jest końcem gry.** Tier 10 to jeden system na tym
  seedzie i to akurat jest zaletą: finał ma być jednym miejscem.
  `GalaxyMap.centre_index()` już go wskazuje — zostaje to, co w nim stoi.
- [x] **Mapa galaktyki na `N`.** `GalaxyChart`, warstwę wyżej niż mapa układu:
  tamta rysuje `StarSystem` w pikselach, ta `GalaxyMap` w latach świetlnych, i
  nigdy nie dzielą liczby. Widać **trzy rzeczy i nie ma czwartej**: systemy, w
  których byliśmy (wiedza, w `deltas`), systemy w zasięgu skanera *teraz*
  (przyrząd, znika razem z ruchem) i środek galaktyki (premisa — mapa, która
  każe najpierw odkryć, gdzie jest środek, chowa nie drogę, tylko sens).
  Zmierzone: na pierwszej klatce nowej gry widać 5–7 systemów z 620, czyli
  około 1% galaktyki, i jedną kropkę odległą o 110 lat świetlnych. Cztery
  szczeble zoomu od całej galaktyki do „ten system i sąsiedzi" (najciaśniejszy
  to `BASE_REACH`, bo sąsiad **znaczy** tyle, co w zasięgu jednego skoku), kółko
  zoomuje na kursorze, lewy przycisk przeciąga albo wybiera zależnie od tego,
  ile przejechał. Tiery narysowane jako pierścienie, bo tier **jest** pasem
  promienia, a obrys całej galaktyki idzie dalej — przestrzeń między nimi to
  wyspy. `F4` zdejmuje mgłę (dev): cały projekt tego ekranu to mgła, więc
  jedyną rzeczą, której nie da się sprawdzić patrząc na niego, jest to, czy
  ciemna połowa w ogóle jest. Szczegóły i tabele w IDEAS.md sekcja 10.

### 5.1 Wrogowie

- [ ] AI wrogów: steering behaviours, maszyna stanów, kilka archetypów (patrol, agresor, uciekinier).
- [x] **Minor i major, i dwie różne zasady powrotu.** `Garrison` — czysta dana,
  jak `StarSystem`. Pierwsza połowa reguły nie kosztuje nic, bo roster z seeda
  **jest** regułą „minor wraca, kiedy ty wracasz, nigdy w trakcie pobytu". Druga
  — major pokonany nie wraca — to jedyna rzecz, której seed nie odtworzy, więc
  jedyna zapisana. Niepokonany nie zapisuje się wcale i wraca cały.
- [x] **Garnizon wisi na ciele, nie na systemie.** Losowanie w dwóch krokach:
  najpierw **czy to ciało jest bronione**, i dopiero wtedy **kto je trzyma**.
  Większość światów jest niczyja (18% na obrzeżu, 62% w rdzeniu) — świat zawsze
  pilnowany to sceneria. Rozdzielenie kroków jest po to, żeby dało się zapytać
  „czy tam jest niebezpiecznie" bez rozwijania walki, której nikt nie toczy;
  test pilnuje, że oba kroki się zgadzają na wszystkich 3980 ciałach galaktyki.
  Wrogowie stoją przy planetach i stacjach, w ciemności między nimi bardzo
  rzadko (8% systemów).
- [x] **Terytorium zamiast pościgu.** Garnizon trzyma powłokę wokół swojego
  ciała, mierzoną względem **studni** — bo studnię rysuje mapa, a granica
  niewidoczna na żadnym przyrządzie to ściana odkrywana przez uderzenie w nią.
  Podłoga 2500 px z pomiaru: dok bez grawitacji dawał piętnastu obrońców w
  pierścieniu 443 px, czyli kupę zamiast pikiety.
- [x] **Agresywni i pasywni, i co budzi tych drugich.** Zestaw prowokacji
  losowany **z ciałem**: strzał zawsze, plus co najmniej jedno ze zbliżenia,
  lądowania i kopania. `Garrison.provoked_by()` jest jednym predykatem, żeby
  spawner i AI nie doszły do różnych wniosków o tym samym świecie. Wykrywanie
  samych prowokacji należy do spawnera i AI — pozycje poniżej; `MINED` czeka na
  kopanie z M5.2 i jest już losowane, bo później kosztowałoby myślenie o
  formacie zapisu.

  **Model gotowy i przypięty dwudziestoma sześcioma asercjami.** Zmierzone
  tabele w IDEAS.md sekcja 12. Najcięższy garnizon to 24 w powietrzu — i to
  jest budżet na **garnizon**, nie na system, bo terytorium jest jednostką,
  którą się walczy.
- [x] **Loot czyta tier.** Pochylenie tabeli rzadkości przez `TIER_LIFT^rung`,
  stan na generatorze ustawiany przez świat z **pozycji** statku, nie z indeksu
  systemu — misjump w ciemność między dwoma systemami rdzenia dalej jest
  rdzeniem. Zmierzone: legendarny 1,0% na obrzeżu i 9,8% w rdzeniu, a
  najczęstszą rzeczą ze świata rdzenia jest **rzadki, nie pospolity**. Żaden
  stopień nie znika: podłoga pod rzutem skasowałaby poziom odniesienia, względem
  którego czyta się skrajności. Tabela w IDEAS.md sekcja 4.
- [x] **Spawner: garnizon stoi w świecie.** `Foe` — **nie `Ship`**, i to jest ta
  decyzja: kadłub gracza to 2759 linii montażu, paliwa, ciepła i solwera ciągu,
  a rdzeń trzyma dwa tuziny obrońców. Wróg to liczba wytrzymałości, kształt do
  trafienia i miejsce do stania. Precedens projekt zapisał sam: `LootCrate` ma
  własną całkę zamiast `RigidBody2D`.

  **Streaming nie był potrzebny** — i to jest najlepszy dowód, że przeniesienie
  garnizonu na ciała było słuszne. Życie obrońcy to dokładnie życie jego ciała,
  więc spawner to dwa sygnały (`body_awake`, `body_asleep`), a nie druga
  maszyneria bliskości. Zdjęcie garnizonu **wyjmuje węzły z drzewa od razu**, nie
  tylko `queue_free()`: odroczone zwolnienie zostawiało je przez resztę klatki w
  świecie fizyki, czyli dało się ostrzeliwać garnizon, który przestał istnieć.

  Trzy ścieżki obrażeń (pocisk, podmuch, wiązka) pytały `collider as Ship`, a
  znaczyły „czy to da się zranić". Jedno `Damage.deal()`, kaczo-typowane: `Foe` i
  `Ship` nie mają ze sobą nic wspólnego poza tym, że da się do nich strzelać.

  Pętla zamknięta od końca do końca: minor ginie i wraca przy następnej wizycie,
  major ginie, trafia do `deltas` i **nie wraca**. Łup leci z `rarity_floor`
  rostera przez istniejące skrzynki. Zmierzone: obrońca pada w 7 strzałach
  seryjnego działka.
- [x] **Wykrywanie prowokacji i ogień.** Zbliżenie, lądowanie i strzał pytają
  teraz `provoked_by()`; kopanie czeka na M5.2 i jest już losowane. Obudzony
  garnizon **nie zasypia** do opuszczenia systemu — nic nie kosztuje i nic nie
  zapisuje, bo powrót i tak odtwarza roster z seeda.

  Dwie liczby wyleciały po pomiarze w biegu. **Działonowy musi wyprzedzać cel**:
  bez tego pociski szły 143 px za statkiem, który tylko spadał — w tej grze nic
  nie stoi, więc „gdzie jest" nigdy nie jest „gdzie będzie". I **rozrzut 4° to
  stożek 126 px przy kadłubie 24 px**, czyli działo, które miało być niecelne,
  nie trafiało nigdy; dwa stopnie, tyle co seryjny autocannon. Zmierzone: 400 px
  od jednego obrońcy z obrzeża przez 14 s to 5 pocisków, 4 trafienia, kadłub
  1,000 → 0,918. Szczegóły w IDEAS.md sekcja 12.
- [ ] **AI: trzymać teren, nie gonić.** Steering i maszyna stanów, trzy
  archetypy, i jedna rzecz, której żaden z nich nie robi — pogoń poza
  terytorium. Obudzony pasywny garnizon musi też mieć sposób, żeby znowu
  zasnąć, albo „pasywny" znaczy „agresywny po pierwszym błędzie".
- [ ] **Lotniskowiec wypuszcza swoich.** Kadencja i limit żywych są w rosterze;
  brakuje czegoś, co je wypuszcza — i reguły, że zestrzelony lotniskowiec
  kończy strumień, bo na tym stoi klauzula „nic nie bierze się znikąd".
- [ ] Zasady śmierci: co gracz traci, co zostaje. **Pokonany major zostaje
  pokonany** — śmierć tego nie cofa, bo to jedyny nieodwracalny postęp, jaki
  gracz ma poza sprzętem.
- [x] Jedno i drugie to stan, którego seed nie odtworzy, więc mieszka w
  `Galaxy.deltas`. **Schemat kluczy jest**: wpis leży pod seedem tej rzeczy,
  której dotyczy. Trzy rodzaje — ciało niebieskie (`crust`), system (`seen`),
  członek garnizonu (`beaten`). Seed członka dwustopniowo, przez własny seed
  garnizonu, żeby nie kolidować z ciałami; kolizja sprawdzana testem na całej
  galaktyce, bo wspólny klucz znaczyłby, że wykopany krater wskrzesza elitę.
  Zapis nie potrzebował ani nowego pola, ani podbicia wersji.

### 5.2 Zasoby: mało rodzajów, dużo decyzji

Nie symulacja rynku. Trzy rzeczy, które się zużywają, i jedna, z której się je
robi. Każdy zasób więcej to jeden powód mniej, żeby zdecydować, który zabrać.

- [x] **Zasoby jako sztuki w ładowni.** `Stores` — osobna klasa, bo `ship.gd` ma
  2759 linii, a rudy dorzucą kilka rodzajów. Liczą się w **sztukach**, nie w
  ułamkach, i **dzielą objętość z modułami**: ładownia pełna rudy to ładownia
  bez miejsca na napęd, który się właśnie znalazło. Gabaryt wyprowadzony z
  tego, ile mieści pełna ładownia (sto części albo dwieście pięćdziesiąt
  stardustu), bo to jest liczba, którą pilot trzyma w głowie. Ważą tyle, co
  każdy ładunek.
- [x] **Przetwarzanie: jedna liczba na trzy miejsca.** `Refinery` — zadokowany
  1,0, wylądowany 0,85, w przestrzeni 0,55, czytane z `FlightMode`, więc nie ma
  drugiego stanu, który mógłby się rozjechać z tym, czy nogi są na ziemi. Stocznia
  jest odniesieniem, czyli liczbą z karty; reszta to znana zniżka, nie zagadka.
  Pierwszy przepis: stardust na ładunek hyperdrive (30 w stoczni, 55 w locie).
- [x] **Spare parts** — naprawa kadłuba i modułów, i **rozbiórka**, która je
  daje. Uzysk z gabarytu (nagłówek — złom to materiał), rzadkości i rodziny
  materiału. Człon rzadkości jest **celowo mały**: gdyby legendarny rozpadał
  się na górę części, najlepszą rzeczą do zrobienia z najlepszym przedmiotem w
  grze byłoby przetopienie go. Zmierzone: pospolity retro daje 17 części,
  legendarny 28, a trzy śmieci to jedna naprawa kadłuba (25) — czyli ładownia
  pospolitych, których nikt nie chce, jest warta zabrania do domu. Trzy
  rodziny materiału zamiast wiersza na typ, jak trzy sylwetki broni na
  schemacie. Naprawa **częściowa**, jak każdy niedobór w tej grze: dziesięć
  części przy rachunku na dwadzieścia pięć kupuje dwie piąte kadłuba, a nie nic.
  Silnik kosztuje według gabarytu, bo to, co wchodzi w napęd, to nie blacha,
  która wychodzi z wraku.
- [x] **Paliwo w dwóch postaciach**: stałe (silniki) i **hyperdrive charges**
  (skok). Kształt rozcięcia okazał się ważniejszy od samego rozcięcia:
  **ładunek to pozwolenie na skok, nie miara odległości** — jeden skok bierze
  jeden, jakkolwiek daleko, a za odległość płaci się ryzykiem jak dotąd. Dzięki
  temu „zostały cztery skoki" to liczba, którą planuje się trasę, a nie taka,
  którą się dzieli. Pusty magazynek **nie jest ścianą**: napęd odpala na
  paliwie silnikowym przy starej regule niedoboru, więc „niedobór nie jest
  odmową" zostaje w mocy, a ładunek kupuje **czysty** skok. Wydawany przy
  rozkręcaniu, nie przy przylocie — jest niepodzielny, więc przerwanie kosztuje
  cały, i to jest ta lekcja, którą ta reguła ma dawać.
- [ ] **Stardust** — surowiec, z którego robi się jedno i drugie.
- [ ] **Raw ore**, kilka rodzajów. Złoża leżą na powierzchni i pod nią, losowane
  z seeda planety — więc odtwarzalne, a wykopane znikają przez `deltas`, tak jak
  już znika teren.
- [ ] **Przetwarzanie na statku**: każdy raw ore idzie na jeden z zasobów, a
  **wydajność zależy od miejsca** — zadokowany, wylądowany, w przestrzeni.
  Jedna liczba na trzy stany, bez cen i bez podaży: to ma być powód, żeby
  gdzieś usiąść, a nie arkusz kalkulacyjny.
- [ ] **Stardust z korony gwiazdy** przy odpowiednim modzie. Nie „przez
  gwiazdę" — powód w punkcie 4 analizy.
- [ ] Pojemność ładowni jako parametr tej premisy (punkt 7).

### 5.3 Drony zamiast pojazdu

- [ ] **Dron jako moduł**, kilka na statku. `ModuleBay` jest już jedną klasą
  slotu z `accepts()`, więc nowy rodzaj nie wymaga nowej mechaniki gniazd.
- [ ] Rodzaje: atmosferyczne i kosmiczne — dron, który nie radzi sobie wszędzie,
  jest wyborem; dron uniwersalny jest tylko drugim statkiem.
- [ ] Zadania: kopanie, **tractor beam** do przenoszenia lootu, **skaner
  orbitalny** — postawiony na orbicie prześwietla powierzchnię i odkrywa złoża.
  To ostatnie wiąże się z `ScannerData.Depth`, który już ma cztery poziomy
  głębokości, i z `deltas`, bo „odkryte" to wiedza gracza, nie własność planety.
- [ ] **Ograniczony czas** i co się dzieje po nim: dron wraca się doładować albo
  spada / zostaje tam, gdzie był, i trzeba po niego polecieć. Porzucony dron to
  też `deltas`.
- [ ] Różne sposoby sterowania — otwarte, bo to jest pytanie o to, ile uwagi
  gracz ma wolnej, a nie o to, co dron potrafi.

### 5.4 Wyjątki od generatora

- [ ] **Scenki jako wyjątki, wybierane z seeda.** Czasem system jest inny: mały
  układ z samą „gwiazdą śmierci", pilot mówi „This is no moon...", startują dwa
  myśliwce. To nie łamie reguły seeda — powód w punkcie 5 analizy.
- [ ] Eventy w deep space: wraki, zasadzki, anomalie. Ta sama maszyneria, mniejszy kaliber.
- [x] **Gniazdo głównego napędu bierze wszystko, co generator umie wylosować.**
  Decyzja: zamiast wykluczać parę baza-afiks, poszerzyć gniazda.
  `ShipFitout.MAIN_DRIVE_SOCKET` = sufit gabarytu generatora (8,0), ten sam na
  każdym kadłubie — w tym na interceptorze, który miał 3,0 i odmawiał nawet
  seryjnego gimballed drive (3,2). Test pilnuje **relacji**, nie liczby:
  podniesienie `LIMITS["bulk"]` bez poszerzenia gniazd od razu wróciłoby
  martwym lootem. Pomiar, który do tego doprowadził, poniżej — i to, co z
  niego **nie** wynika (`buffered` na gimballed drive, małe gniazda) też.
  Zgłoszone z kokpitu, a potem zmierzone dwa razy, bo **obniżenie masy silników
  o połowę (MAUX4.9) przesunęło gabaryty baz** i częściowo rozstrzygnęło sprawę
  przypadkiem. Afiks mnoży gabaryt przez 1,20–1,55. Przed tą zmianą, 4000
  losowań silnika na seryjnym kadłubie z gniazdem 3,5: `oversized` wypadał w
  8,5% losowań, z czego 51% nie wchodziło w gniazdo nosowe (2,5), a **25% nie
  wchodziło nigdzie**.
  - Wszystkie gniazda seryjnego kadłuba przyjmują wszystkie trzy typy
    (`allowed_types = 7`), więc „gniazdo wsteczne" nie jest gniazdem retro —
    jest po prostu najmniejszym gniazdem. Oversized retro nie jest martwy,
    tylko ląduje w gnieździe głównym i ciągnie w złą stronę.
  - Rachunek baza po bazie: main drive 2,5 (po zmianie masy; przedtem 3,0)
    razy 1,20 to 3,0 — wchodzi, razy 1,55 to 3,88 — nie. Retro 2,3 (przedtem
    2,2) razy 1,55 to 3,57 — minimalnie nie wchodzi. **Gimballed drive 3,2
    razy cokolwiek nie wchodzi nigdy.**
  - Martwe egzemplarze to 3,1% wszystkich losowań silnika (123/4000): 83
    gimballed drive, 30 main drive, 10 retro. `oversized` odpowiada za 86 z
    nich, resztę robi `buffered` (też płaci gabarytem).
  Dwie odrzucone alternatywy, dla potomności. **Wykluczyć parę baza-afiks**
  w generatorze, który już to umie (`affix_bites`, dziś po tym, że afiks nic
  nie zmienia) — działałoby, ale odbiera grać „znalazłem potężny silnik,
  muszę przebudować statek": generator przestałby takie rzuty produkować.
  **Klamrować gabaryt w `_clamp_all`** — gorsze, bo darowałoby koszt, czyli
  zrobiłoby z `oversized` czysty zysk.
  Zostało to, co nie trafi w żadne gniazdo z innego powodu (`buffered` na
  gimballed drive mieści się w suficie, więc tu nie ma czego trafiać; małe
  gniazda nadal odmawiają). Taki przedmiot jest surowcem — rafineria liczy go
  po gabarycie (`Refinery.parts_for_engine`), więc od M5.2 „nie wchodzi
  nigdzie" znaczy „jest złomem", a nie „jest śmieciem".
- [ ] **Główne wyzwanie w środku galaktyki** — co to jest, jest otwarte. Wiadomo
  tylko, że stoi na końcu drogi, którą reszta tego milestone'u buduje.

Gotowe, gdy: jest cel krótkoterminowy (loot, paliwo, przeżyć), długoterminowy
(dalej do środka, lepszy statek) i widać, że tier rośnie, kiedy się leci do
środka.

---

## M6: Szlif

- [ ] ~~Pojazd naziemny: wyjazd z wylądowanego statku, koła próbkujące teren,
  kamera, zbieranie zasobów z pojazdu~~ — **zastąpione dronami** (M5.3). Pojazd
  robi jedno miejsce naraz i tylko tam, gdzie się wylądowało; dron robi to samo
  kopanie, a przy okazji orbitę, próżnię i przenoszenie lootu — i może być ich
  kilka. Koła próbkujące teren były też jedyną pozycją w planie wymagającą
  drugiego modelu fizyki.
- [ ] Typy atmosfer i planet (kolory, gęstości, wzory chmur, biomy powierzchni).
- [ ] Budynki, lądowiska, ruiny na powierzchni.
- [ ] Dźwięk: silniki, broń, zderzenia, skok.
- [ ] Menu, ustawienia, mapowanie klawiszy, pad.
- [ ] ~~Mapa galaktyki jako dodatek (odkryte systemy)~~ — **zrobiona w M5.0**.
  Premisa przeniosła ją z dodatku do rzeczy podstawowej: gra, której celem jest
  „dolecieć do środka", potrzebuje ekranu, na którym ten środek widać.
- [ ] Optymalizacja i profilowanie na słabszym sprzęcie.
- [ ] Ewentualne przeniesienie gorących pętli do GDExtension.

---

## Zasady pracy

- Jeden milestone naraz. Nie zaczynać M2, dopóki M1 nie daje radości z latania.
- Każda decyzja techniczna po pomiarze trafia do IDEAS.md (sekcja otwartych pytań kurczy się, sekcje techniczne rosną).
- Prototypować brzydko, szlifować późno. Placeholdery graficzne do M5 włącznie.
- Wszystko z seedu od pierwszego dnia. Żadnych ręcznie ułożonych planet, nawet w M1.
