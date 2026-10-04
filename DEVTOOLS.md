# DEVTOOLS.md

Plan narzędzi deweloperskich: stanowisko testowe (Workbench) i wtyczka edytora Godot. Równoległy do PLAN.md i VISUALS.md, nie blokuje żadnego milestone'u i nie zmienia zachowania gry.

Cel w jednym zdaniu: **wybrać dowolny kadłub, silniki i broń, włączyć stan statku (uszkodzenie, przegrzanie…), postrzelać, posłuchać odgłosów i zmieniać parametry zasobów w formularzach, widząc i słysząc skutek od razu.**

---

## 0. Zasady

1. **Narzędzie czyta grę, gra nie wie o narzędziu.** Nic w `scripts/` nie importuje niczego z `tools/workbench/` ani z `addons/`. Warstwa prezentacji już działa tak samo: słucha statku, niczego nie zapisuje (patrz `Soundscape`, `ShipSkin`).
2. **Ten sam kod co w grze.** Workbench składa prawdziwy `Ship` z `ship.tscn`, prawdziwe `Soundscape`, `EngineChoir`, `HullVoice`, `OrdnanceVoice`, `DebrisField`. Podgląd, który używa innego kodu rysującego niż gra, kłamie.
3. **Formularze z danych, nie z ręki.** Pola zasobów powstają z `get_property_list()` (typ, `@export_range`, enum), więc nowe pole w `WeaponData` pojawia się w formularzu bez ruszania narzędzia.
4. **Stany to „przypięcia" (pins), nie hacki.** Statek sam nadpisuje `hull_heat` i `air_density` w każdym ticku fizyki (`_update_heat`). Przypięcie wartości jest więc ponawiane po jego kroku, a zdjęcie przypięcia oddaje stan symulacji.
5. **Nic z tego nie trafia do gry.** `tools/` i `addons/stardust_devtools/` są wyłączone z eksportu (filtr eksportu), tak samo jak dziś `tools/`.
6. **Smoke test obejmuje narzędzie.** Workbench musi się kompilować i ładować w `tools/smoke_test.gd`, inaczej zgnije po pierwszej zmianie API statku.

---

## 1. Architektura

```
tools/workbench/
  workbench.tscn / .gd      scena: pusta scena + Ship + warstwa prezentacji + panele
  bench_stage.gd            tło, kamera swobodna, siatka, manekiny celów
  bench_pins.gd             przypięcia stanów (integralność, ciepło, powietrze, zdrowie silników...)
  bench_panel.gd            szkielet panelu z zakładkami
  panels/
    ship_panel.gd           kadłub, silniki per mount, broń per hardpoint, presety
    state_panel.gd          stany i zdarzenia
    fire_panel.gd           strzelanie, cele, statystyki
    sound_panel.gd          odsłuch tabel dźwięków i samplerów
    resource_form.gd        auto-formularz dowolnego Resource z get_property_list()
addons/stardust_devtools/
  plugin.cfg / plugin.gd    wtyczka edytora
  dock.gd                   dock: lista zasobów + inspektor + przyciski uruchom/wyślij
  bridge_editor.gd          EditorDebuggerPlugin (strona edytora)
tools/workbench/bridge_game.gd   EngineDebugger.register_message_capture (strona gry)
```

### Dlaczego dwie warstwy

Godot uruchamia grę jako **osobny proces** (albo osadzone okno gry), więc wtyczka edytora nie może po prostu sięgnąć do żywego `Ship`. Dlatego:

- **Workbench** (scena gry) jest samowystarczalny: ma własne formularze i działa z F5 / `godot tools/workbench/workbench.tscn`. To daje pełną wartość nawet bez wtyczki i jest łatwy do testowania.
- **Wtyczka** dokłada wygodę edytora: inspektor zasobów Godota z undo/redo, zapis `.tres`, przycisk „Uruchom Workbench", a żywe zmiany idą do uruchomionej gry kanałem debuggera (`EditorDebuggerPlugin` ↔ `EngineDebugger`).

### Scena bez świata

Workbench nie ma planety, `Galaxy` ani `StreamingManager`. Skutki, które trzeba obsłużyć:

- `nearest_planet()` zwraca `null`, więc `air_density` = 0 (próżnia). Gęstość powietrza idzie więc przez przypięcie, bo tylko tak da się odsłuchać „powietrze".
- Gwiazdy też nie ma, więc `star_flux` = 0. Przegrzanie przez przypięcie `hull_heat` albo `star_flux`.
- Autoloady (`Galaxy`, `StreamingManager`, `LootGenerator`) istnieją i tak, bo są w `project.godot`. Workbench ich nie woła.
- Grawitacja jest liczona w kodzie statku z planety, więc bez planety statek swobodnie dryfuje: to właściwe tło do testu silników.

### Stany statku, które da się włączyć

| Stan | Pole / wywołanie | Uwaga |
|---|---|---|
| Uszkodzenie kadłuba | `hull_integrity`, `take_damage()` | emituje `hull_changed`; przy 0 `destroyed` |
| Zniszczenie / odrodzenie | `_destroy()` przez `take_damage`, `respawn()` | bez świata nikt nie reaguje na `destroyed`, bench ma własny handler |
| Przegrzanie | `hull_heat` | **przypięcie**: `_update_heat` zbija je co tick |
| Powietrze | `air_density` | **przypięcie**, jak wyżej |
| Strumień gwiazdy | `star_flux` | **przypięcie** |
| Zdrowie silnika | `EngineInstance.health` per silnik, `damage_engines_near()` | |
| Paliwo | `fuel`, `draw_fuel()` | pusty bak = silniki gasną |
| Energia | `energy`, `spend_energy()` | pusta pula = `shot_refused` |
| Podwozie | `gear.set_deployed()` | |
| Uderzenie w teren | sygnał `hull_impact(speed, damage)` | zdarzenie do wyzwolenia, bez terenu |
| Doładowanie | `boost_command` | |

---

## 2. Milestone'y

Kolejność wynika z wartości: najpierw to, co od razu daje odsłuch i strzelanie, wtyczka na końcu, bo korzysta z całego reszty.

### D0: Rozpoznanie

- [x] Rozpoznanie kodu: `Ship`, `ShipFitout.apply`, `Hardpoint.fire`, `Soundscape`, tabele `LookTable` / `SoundTable`, ścieżka `ship_path` węzłów prezentacji.
- [x] Ten plan.

### D1: Workbench: statek na pustej scenie

Cel: scena, w której wybierasz kadłub, silniki i broń i od razu lecisz.

- [x] `tools/workbench/workbench.tscn`: tło (gwiazdy), `Ship` z `ship.tscn`, kamera podążająca z zoomem, węzły prezentacji podpięte przez `ship_path` (dźwięk, chór silników, głos kadłuba, głos pocisków, szczątki).
- [x] Panel „Statek": lista presetów z `ShipFitout.all()`, wybór kadłuba z `HullData.all()` (zachowuje montaż), skala kadłuba.
- [x] Wybór silnika **per mount** z `resources/engines/*.tres` (zachowuje `scale`), wybór broni **per hardpoint** z `resources/weapons/*.tres`.
- [x] Odświeżenie po zmianie: `collect_parts()`, `rebuild_control_groups()`, przebudowa `ShipSkin`, bez zostawiania wiszących referencji.
- [x] Sterowanie jak w grze (`use_player_input`), przełącznik „statek wolny / zamrożony".

Gotowe, gdy: z menu można zmienić dowolny kadłub, każdy silnik i każde działo, polecieć i nic nie wywala błędów w konsoli.

### D2: Stany statku

- [ ] `bench_pins.gd`: słownik przypięć stosowany po kroku fizyki statku, z zaznaczeniem, które są aktywne.
- [ ] Panel „Stany": suwaki integralność / ciepło / gęstość powietrza / strumień gwiazdy / paliwo / energia, każdy z checkboxem „przypnij".
- [ ] Zdrowie silników: suwak per silnik, przyciski „uszkodź losowy", „napraw wszystkie".
- [ ] Zdarzenia: zniszczenie, odrodzenie, uderzenie (`hull_impact` z zadaną prędkością), podwozie, doładowanie, wyłączenie napędu.
- [ ] Odczyt na żywo obok suwaków: co statek naprawdę ma teraz (różni się od przypięcia, gdy symulacja nadpisała).

Gotowe, gdy: każdy stan z tabeli w sekcji 1 da się włączyć jednym ruchem i widać oraz słychać jego skutek (dym, światło, głos kadłuba, wygaszanie silnika).

### D3: Strzelanie i cele

- [ ] Panel „Ogień": przytrzymaj / przełącz auto-ogień, osobno dla spustu 0 i 1, aim myszą albo na stały punkt.
- [ ] Manekiny: nieruchome i krążące cele z licznikiem trafień i obrażeń, żeby zobaczyć `damage_per_second()` w praktyce.
- [ ] Odczyt: strzałów na sekundę, zużycie energii, zasięg, czas do wyczerpania puli.
- [ ] Pasek „modyfikatory": dorzucanie `ShotModData` do hardpointu (`add_mod`).

Gotowe, gdy: każda z siedmiu broni z `resources/weapons/` strzela w workbenchu, a odczyt zgadza się z `WeaponData.stat_rows()`.

### D4: Odsłuch i podgląd grafiki

- [ ] Panel „Dźwięk": lista wszystkich `SoundTable` z `resources/fx/sounds/` i ich pasków (`every_strip()`), przycisk odtwórz, wybór drogi (`CONDUCTED` / `AIRBORNE` / `INTERFACE`) i gęstości powietrza.
- [ ] Odsłuch tabeli jak w grze: „co zagra silnik typu X z affixem Y" przez `pick(subject, key)`.
- [ ] Pętle silnika: suwak przepustnicy puszcza `engine_loop` z krzywą jak w `EngineChoir`.
- [ ] Podgląd grafiki: wszystkie paski z `LookTable` (to, co dziś robi `art_gallery`) w tej samej scenie, z punktem zaczepienia.

Gotowe, gdy: nie trzeba już odpalać `soundcheck.tscn` ani `art_gallery.tscn` osobno.

### D5: Auto-formularz zasobu i edycja na żywo

- [ ] `resource_form.gd`: formularz z `get_property_list()` dla `HullData`, `EngineData`, `WeaponData`, tabel i pasków. Obsługa `float` / `int` / `bool` / `String` / `Color` / `Vector2` / enum / zakresy / `AudioStream` / `PackedVector2Array` (obrys: edycja punktów).
- [ ] Zmiana w formularzu działa **od razu** na działającym statku (odświeżenie przez `emit_changed()` + przebudowa tylko tego, czego dotyczy).
- [ ] Zapis do `.tres` jawnym przyciskiem; pole „brudne" oznaczone, „cofnij do pliku" dostępne.
- [ ] Debounce przy procedurach z seeda, żeby przeciągnięcie suwaka nie przebudowywało dźwięku sto razy na sekundę.

Gotowe, gdy: zmiana `rounds_per_second` albo `max_thrust` suwakiem jest widoczna w następnym strzale / ciągu bez restartu i da się ją zapisać do pliku.

### D6: Wtyczka edytora

- [ ] `addons/stardust_devtools/`: `plugin.cfg`, `plugin.gd`, włączona w `project.godot`.
- [ ] Dock „Stardust": lista zasobów po katalogach (`hulls`, `engines`, `weapons`, `fx`, `audio`), klik otwiera zasób w inspektorze Godota.
- [ ] Przycisk „Uruchom Workbench" (`EditorInterface.play_custom_scene`).
- [ ] Kanał edytor → gra: `EditorDebuggerPlugin` wysyła zmianę właściwości zasobu, gra stosuje ją przez `bridge_game.gd`. Zweryfikować w dokumentacji (`godot-docs`), czy działa też z osadzonym oknem gry.
- [ ] Kanał gra → edytor: odczyt stanu statku (przypięcia, zdrowie) w docku.
- [ ] Undo/redo przez `EditorUndoRedoManager`; zapis przez `ResourceSaver` z zachowaniem UID.

Gotowe, gdy: zmiana wartości w inspektorze Godota jest od razu słyszalna lub widoczna w uruchomionym Workbenchu.

### D7: Domknięcie

- [ ] Workbench w `tools/smoke_test.gd`: ładuje scenę, składa każdy preset, przełącza każdy stan, wystrzeliwuje każdą broń, bez błędów silnika.
- [ ] `tools/check.ps1` przechodzi.
- [ ] Wyjątek w filtrze eksportu dla `tools/` i `addons/stardust_devtools/`.
- [ ] Sekcja w README: jak uruchomić.

---

## 3. Otwarte pytania

- Czy żywa edycja z edytora ma iść kanałem debuggera, czy wystarczy przeładowanie `.tres` po zapisie? Kanał jest dokładniejszy, zapis prostszy. Rozstrzygnąć w D6 po sprawdzeniu osadzonego okna gry.
- Jak edytować obrys kadłuba (`PackedVector2Array`) w formularzu: lista punktów czy rysowanie myszą na podglądzie? Zacząć od listy.
- Czy przypięcia mają się zapisywać między uruchomieniami (plik w `user://`)? Prawdopodobnie tak, żeby po restarcie wracać do tej samej konfiguracji testowej.

## 4. Czego ten plan świadomie nie robi

- Nie edytuje planet, terenu ani galaktyki: od tego jest `planet_configurator`.
- Nie zastępuje `CreativeTool` (`debug_creative`), który działa w prawdziwym świecie z prawdziwym terenem. Workbench jest pustą sceną laboratoryjną; `CreativeTool` zostaje do testów z planetą.
- Nie dodaje niczego do `PLAN.md`: to osobny tor.
