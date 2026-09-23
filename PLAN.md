# PLAN.md

Plan realizacji w milestone'ach. Każdy milestone kończy się czymś, w co da się grać albo co da się zobaczyć. Kolejność wynika z ryzyka: najpierw to, co może wywrócić architekturę, potem zawartość.

Kontekst i decyzje projektowe: IDEAS.md.

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
- [x] Orbit lock: przejście w analityczną orbitę kołową przy spełnionych warunkach, wskaźnik "ORBIT", powrót do fizyki przy ciągu.
- [x] Aerobraking: drag górnych warstw atmosfery hamuje statek na orbicie, prosty licznik ciepła kadłuba.

### 1.6 Lądowanie

- [ ] Podwozie: 2 do 3 punktów kontaktu, wysuwanie klawiszem, drag przy wysuniętym.
- [ ] Sprawdzenie warunków przy dotknięciu: prędkość pionowa, boczna, kąt, nachylenie terenu pod nogami (próbkowanie w układzie biegunowym).
- [ ] Udane lądowanie: zamrożenie statku i przypięcie do planety, start z prędkością styczną.
- [ ] Nieudane: obrażenia od nadwyżki prędkości, przewrócenie przez fizykę punktów kontaktu przy złym nachyleniu.
- [ ] Generator terenu gwarantuje plateau do lądowania (parametr częstości).
- [ ] HUD: wysokościomierz, prędkość pionowa, wskaźnik nachylenia pod statkiem, stan podwozia.
- [ ] Opcjonalna rotacja planety (dzień i noc) i sprawdzenie, że wylądowany statek jedzie razem z nią.

### 1.7 Śmierć i restart

- [ ] Kadłub ma HP, zderzenia i własne pociski zadają obrażenia.
- [ ] Śmierć: efekt, natychmiastowy respawn na orbicie. Bez menu.

Gotowe, gdy: da się wystartować z powierzchni, wejść na orbitę i na niej zaparkować, zejść deorbitem na wybrane miejsce, wylądować na zboczu i zobaczyć, że to zależy od nachylenia i prędkości, rozwalić kawałek góry, rozbić się i od razu lecieć dalej. Ocena subiektywna: czy sterowanie daje radość. Jeśli nie, tu się kręci fizyką, nie idzie dalej.

Pytania do rozstrzygnięcia na koniec M1 (zapisać odpowiedzi w IDEAS.md):
- jednostki: promień planety, promień wpływu, prędkości (wartości robocze w IDEAS po M1.2, potwierdzić),
- ~~czy samplowanie bitmapy wystarcza, czy potrzebne są chunki z marching squares~~ — wystarcza, zmierzone w M1.3,
- ~~rozdzielczość bitmapy terenu na planetę~~ — 1.5 px na teksel, siatka biegunowa, zmierzone w M1.3,
- progi lądowania (prędkości, kąt, nachylenie) dla statku bazowego,
- czy planety się obracają,
- ~~tolerancje orbit lock i długość przewidywanej trajektorii~~ — ustalone w M1.5, wartości w IDEAS.

---

## M2: Silniki, awarie, loot

Cel: statek jako zestaw modułów, które są lootem.

- [ ] Komputer lotu: alokacja NNLS z rzeczywistymi ciągami i stanem silników, czysty obrót i czysty strafe mimo asymetrii i uszkodzeń. Zastępuje heurystykę wag z M1.1 tam, gdzie gracz znajdzie moduł.
- [ ] Gimbal na silniku MAIN: sterowany wektor ciągu zamiast stałego kierunku montażu.
- [ ] Raport konfiguracji przy montażu: autorytet w każdą stronę, asymetria par, puste grupy, ostrzeżenie o module, który psuje sterowanie.
- [ ] Awarie silników: spadek sprawności od zderzeń, niezawodność jako dropout i oscylacja ciągu.
- [ ] Lądowanie z uszkodzonymi silnikami: asymetria, oscylacje, sprawdzenie, że jest trudno, ale możliwe.
- [ ] Podwozie jako moduł (tolerancja nachylenia, próg prędkości) i moduły asystujące (auto-poziomowanie, hold wysokości, cyrkularyzacja, komputer deorbitu).
- [ ] Zużycie w czasie, naprawa (na razie klawisz debug).
- [ ] Silniki manewrowe i hamujące, statek z pełnym zestawem vs statek minimalny.
- [ ] Broń jako Resource: typ, obrażenia, kadencja, rozrzut, afiksy.
- [ ] `LootGenerator`: tabele rzadkości, afiksy, generacja broni i silników.
- [ ] Pozostałe typy broni: laser, dumb missile, homing missile, AoE, pulse.
- [ ] Skrzynki z lootem na powierzchni planety, podnoszenie, wymiana modułu w locie (prosty ekran).

Gotowe, gdy: znajduje się losowy silnik lub broń, montuje, czuć różnicę, a uszkodzony silnik zmienia sposób latania.

---

## M3: System gwiezdny i streaming

Cel: gwiazda, kilka planet, księżyce, stacja. Planety włączają się i wyłączają w zależności od odległości.

- [ ] Model danych systemu w `Galaxy`: gwiazda, planety, księżyce, stacje, orbity, seedy.
- [ ] Orbity analityczne od globalnego czasu.
- [ ] `StreamingManager`: poziomy 0..3 z histerezą, kolejka instancjonowania, generacja terenu w WorkerThreadPool.
- [ ] Zapis delty przy wyłączaniu planety (piksele, loot), odtwarzanie przy powrocie.
- [ ] Gwiazda: grawitacja, strefa obrażeń, oświetlenie 2D, cień nocnej strony planet.
- [ ] Orbitowanie księżyca w polu planety, proca grawitacyjna między ciałami, pociski pod wpływem grawitacji.
- [ ] Stacja orbitująca i stacja w deep space: dokowanie, naprawa, tankowanie.
- [ ] Test: przelot przez wszystkie planety systemu bez przycięć, powrót do zmodyfikowanej planety pokazuje zmiany.
- [ ] Decyzja o floating origin na podstawie rozmiaru systemu.

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
