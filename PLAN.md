# PLAN.md

Plan realizacji w milestone'ach. Każdy milestone kończy się czymś, w co da się grać albo co da się zobaczyć. Kolejność wynika z ryzyka: najpierw to, co może wywrócić architekturę, potem zawartość.

Kontekst i decyzje projektowe: IDEAS.md.

Obraz i dźwięk mają własny, równoległy plan: VISUALS.md. Ten plik nie odpowiada
za to, jak gra wygląda i brzmi — i dlatego jego kryteria zamknięcia nie mogą od
tego zależeć.

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
  `GalaxyMap` — czysta dana, 109–117 systemów, odstęp rosnący ku obrzeżu.
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
- [ ] Misjump: sektor międzygwiezdny bez gwiazdy, ryzyko od niedoboru paliwa i zasięgu.
- [ ] Zapis gry: seed plus delty, autosave przy skoku.

Gotowe, gdy: wylot z jednego systemu i wlot do drugiego czuje się jak jeden lot.

---

## M5: Wrogowie, zasoby, pętla gry

Cel: powód, żeby latać.

- [ ] AI wrogów: steering behaviours, maszyna stanów, kilka archetypów (patrol, agresor, uciekinier).
- [ ] Wrogowie na planetach i w przestrzeni, spawnery z timerami respawnu.
- [ ] Zasoby na planetach: zbieranie, wartość, sprzedaż na stacjach.
- [ ] Ekonomia paliwa: skąd się bierze, ile kosztuje.
- [ ] Poziom zagrożenia systemu, skalowanie lootu i wrogów z odległością od startu.
- [ ] Zasady śmierci: co gracz traci, co zostaje.
- [ ] Eventy w deep space: wraki, zasadzki, anomalie.

Gotowe, gdy: jest cel krótkoterminowy (loot, paliwo, przeżyć) i długoterminowy (dalej, lepszy statek).

---

## M6: Szlif

- [ ] Pojazd naziemny: wyjazd z wylądowanego statku, koła próbkujące teren, kamera, zbieranie zasobów z pojazdu.
- [ ] Typy atmosfer i planet (kolory, gęstości, wzory chmur, biomy powierzchni).
- [ ] Budynki, lądowiska, ruiny na powierzchni.
- [ ] Dźwięk: silniki, broń, zderzenia, skok.
- [ ] Menu, ustawienia, mapowanie klawiszy, pad.
- [ ] Mapa galaktyki jako dodatek (odkryte systemy).
- [ ] Optymalizacja i profilowanie na słabszym sprzęcie.
- [ ] Ewentualne przeniesienie gorących pętli do GDExtension.

---

## Zasady pracy

- Jeden milestone naraz. Nie zaczynać M2, dopóki M1 nie daje radości z latania.
- Każda decyzja techniczna po pomiarze trafia do IDEAS.md (sekcja otwartych pytań kurczy się, sekcje techniczne rosną).
- Prototypować brzydko, szlifować późno. Placeholdery graficzne do M5 włącznie.
- Wszystko z seedu od pierwszego dnia. Żadnych ręcznie ułożonych planet, nawet w M1.
