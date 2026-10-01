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
- [ ] Ewentualnie: teren między działkiem a celem. Kursor melduje wtedy zielony, choć pocisk trafi w zbocze — ale trafienie w zbocze jest prawdziwym skutkiem (robi krater), więc to raczej wygoda niż kłamstwo. Koszt: raycast na działko na klatkę.


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

## M3: System gwiezdny i streaming

Cel: gwiazda, kilka planet, księżyce, stacja. Planety włączają się i wyłączają w zależności od odległości.

- [x] Model danych systemu: `SystemBody` i `StarSystem` jako czyste dane (`RefCounted`, zero node'ów), `Galaxy` trzyma seed, zegar i cache systemów. Gwiazda, 3–5 planet, księżyce, stacje, wszystko z jednego seeda przez splitmix64. **System decyduje, jak duże i jak ciężkie; seed decyduje, jak wygląda** — promień i grawitacja są w deskryptorze, bo układ orbit ich potrzebuje; teren, pogoda i kolory zostają przy seedzie planety.
- [x] Orbity analityczne od globalnego czasu: koła, `position_at(t)` rekurencyjne w górę drzewa, zero stanu. Ciało wyłączone i włączone z powrotem jest tam, gdzie byłoby — nie ma czego doganiać, bo nic nie całkowało. Okresy z `mu = g·r²` rodzica, więc trzecie prawo Keplera wychodzi za darmo.
- [x] `StreamingManager`: poziomy z histerezą i kolejka instancjonowania. **Trzy stany, nie cztery** — `GONE / AWAKE / SURFACE`. Poziom 1 z projektu („planety jako sprite'y”) nie ma przy 640x360 żadnego reżimu: planeta ma 2000+ px średnicy, więc jest albo szersza od ekranu, albo poza nim. Ciało budzi się, zanim cokolwiek mogłoby o nie zapytać — najdalej patrzy skaner (20k px), i test to przypina do jego własnej liczby.
- [x] Jeden zamrożony zegar na wizytę, nie na ciało. Ciala stawiane raz, w tej samej chwili.
- [x] Generacja terenu w `WorkerThreadPool`. `PlanetTerrain` rozdzielony na `build()` (sama arytmetyka, wątek roboczy) i `finish()` (tekstura, główny wątek). Zmierzone na prawdziwym rendererze: **13,2–33,3 ms zeszło z klatki, 0,1–0,3 ms zostało**. Węzeł powstaje poza drzewem i wchodzi dopiero gotowy, więc nie ma półzbudowanej planety, którą ktoś mógłby o coś zapytać. Przylot (`force_awake`) buduje synchronicznie — raz zapłacona zadyszka zamiast statku postawionego obok planety, której jeszcze nie ma.
- [x] Delta lootu: skrzynka podniesiona zostaje podniesiona. Manager pamięta opróżnione półki per seed ciała, a pozostałe losuje bez zmian — zabranie jednej nie zmienia, czym są inne.
- [x] Delta terenu: skorupa zapamiętywana przy wyłączaniu planety i kładziona z powrotem przy budowie. Tylko dla światów, w które ktoś strzelał — nietknięty wraca identyczny z seeda, a trzymanie jego kopii to trzymanie seeda dwa razy. Spakowana ZSTD. Przywracanie robi wątek roboczy razem z generacją: na głównym kosztowało 15 ms, przez co planeta z kraterem zacinała mocniej niż nowa (21,4 → 7,5 ms najgorszej klatki).
- [ ] Gwiazda jako węzeł: grawitacja w tej samej grupie co planety, strefa obrażeń, oświetlenie 2D, cień nocnej strony planet. Masa jest już wyprowadzona z warunku Hilla, więc grawitacja gwiazdy nie zje studni planet.
- [ ] Orbitowanie księżyca w polu planety, **odchylenie toru** przy przelocie obok ciała (nie proca: ciała nie wędrują po orbitach, a darmowa energia w procy bierze się z ruchu ciała — handel przyjęty świadomie, IDEAS.md „Planety nie okrążają gwiazdy”), pociski pod wpływem grawitacji.
- [ ] Stacja orbitująca i stacja w deep space: dokowanie, naprawa, tankowanie.
- [x] **Mapa układu na `M`**. Rysowana z **modelu**, nie ze sceny — manager trzyma w świecie jedną planetę naraz, a mapa z żywych węzłów pokazałaby jedną kropkę i nazwała to układem. Orbity w skali, ciała jako znaczniki (planeta w skali to jedna dziesiąta piksela). Jasność znacznika mówi, czy ciało jest w świecie, czy dopiero w modelu — jedyne okno na to, co robi streaming. Nazwa i odczyt na kliknięcie, jak na schemacie w edytorze.
- [x] Zoom mapy (`+` / `-`), jako **zasięg w pikselach świata**, nie mnożnik: systemy mają od 41k do 302k px, więc ten sam mnożnik to inny widok w każdym z nich — x64 mieściło księżyc na ekranie w szerokim systemie i wyrzucało go poza ekran w wąskim. Poziomy to cały układ, 30000, 7500 i 2000 px; 7500 to „ta planeta i jej księżyce” w dowolnym systemie. Powiększanie wokół **wybranego ciała**, bo wokół gwiazdy pierwszy krok wypycha z ekranu to, co się przed chwilą kliknęło. Ciało dostaje swój prawdziwy okrąg powierzchni, gdy zrobi się większy od znacznika.
- [x] **Teleport na `Enter`** do ciała wskazanego na mapie — narzędzie deweloperskie, tej samej klasy co teleport między półkami w konfiguratorze. Cel jest budowany synchronicznie (`force_awake`), bo statku nie da się postawić przy planecie, której jeszcze nie ma, i ląduje na orbicie kołowej po tej stronie, z której przyleciał. Świat śledzi teraz, przy której planecie jest statek — nieświeża referencja znaczyłaby konfigurator edytujący planetę, którą pilot już opuścił.
- [x] **Przybliżona trajektoria na mapie**, przerywaną krzywą. Rdzeń całkowania wyciągnięty z `TrajectoryPredictor` jako `coast()` — linia na F7 i krzywa na mapie czytają **jedną przyszłość**, a nie dwie. Horyzont skalowany zasięgiem mapy, bo stały jest zły z obu stron: dwie minuty to dwunastopikselowy kikut na układzie 300k px i kilka orbit przy zoomie na planetę. Czerwona i z krzyżykiem, gdy kończy się w gruncie.
- [ ] Test: przelot przez wszystkie planety systemu bez przycięć, powrót do zmodyfikowanej planety pokazuje zmiany.
- [x] Decyzja o floating origin: **nie jest potrzebny**, zmierzone przez `tools/distance_bench.gd`. Systemy mają 41k–302k px promienia; przy 300k błąd przechowania współrzędnej to 0,005 px, obieg przez układ planety 0,010 px, a orbita nie zauważa odległości w ogóle (dryf 7 px/10 s tak samo w zerze i w milionie — to całkowanie, nie float). Jedyna rosnąca liczba to pełzanie nieprzymrożonego kadłuba na gruncie: 0,12 px/10 s w zerze, 0,45 przy 300k. Test pilnuje, żeby układ nie wyszedł poza zmierzony zakres.

Gotowe, gdy: lot planeta-planeta jest płynny, a wyłączona planeta pamięta stan.

---

## M4: Galaktyka, skaner, skok

Cel: wiele systemów, podróż skokiem bez bramek.

- [ ] Generacja galaktyki: Poisson disk sampling, seedy systemów, sprawdzenie spójności grafu.
- [ ] Mass lock gwiazdy i strefa skoku.
- [ ] Moduły: skaner (zasięg, jakość), napęd skokowy (zasięg), bak (paliwo). Wszystkie jako loot.
- [ ] HUD: wskaźniki systemów na krawędzi ekranu, kolor wg osiągalności, informacje wg jakości skanera.
- [ ] Maszyna stanów skoku: Idle, Charging, Transit, Arrival.
- [ ] Shader tranzytu, wymiana sceny systemu pod graczem w trakcie efektu.
- [ ] Pozycja przylotu na krawędzi celu od strony źródła.
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
