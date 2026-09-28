# mockups/

Makiety interfejsu. Rysowane ręcznie w SVG, w skali 1:1 do docelowych 640x360 —
otwiera się je w przeglądarce. Nie są zasobem gry: katalog ma `.gdignore`, więc
Godot nie importuje ich jako tekstur.

Źródło prawdy dla kolorów, metryki i reguł jest w **UI_STYLE.md**. Jeśli makieta
nie zgadza się z dokumentem, to dokument ma rację, a makieta jest do poprawy.

| plik | zawartość |
|---|---|
| [hud_landing.svg](hud_landing.svg) | HUD przy podejściu do lądowania w 1:1, plus prymitywy w powiększeniu 3x |
| [hud_flight_states.svg](hud_flight_states.svg) | cztery tryby: DEEP, ORBIT, LANDING, COMBAT (UI_STYLE.md sekcja 10) |
| [screens_editor_maps.svg](screens_editor_maps.svg) | edytor statku, mapa systemu, mapa galaktyki (UI_STYLE.md sekcja 11) |

Do czego to jest, a do czego nie: makieta ustala **układ, gęstość i hierarchię**
przed napisaniem kodu, bo to najtańsze miejsce na zmianę zdania. Nie ustala
tego, jak rzecz wygląda w ruchu — na to jest `tools/gallery.tscn` i odpalenie
gry, i to one rozstrzygają spór (VISUALS.md sekcja 5).

Liczby na makietach są zmyślone, ale ich **format** jest wiążący: szerokość
kolumny, liczba cyfr znaczących i jednostka są częścią projektu, nie ozdobą.
