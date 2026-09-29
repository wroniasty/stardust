# mockups/

Makiety interfejsu. Rysowane ręcznie w SVG, w skali 1:1 do docelowych 640x360 —
otwiera się je w przeglądarce. Nie są zasobem gry: katalog ma `.gdignore`, więc
Godot nie importuje ich jako tekstur.

Źródło prawdy dla kolorów, metryki i reguł jest w **UI_STYLE.md**. Jeśli makieta
nie zgadza się z dokumentem, to dokument ma rację, a makieta jest do poprawy.

## Styl przyjęty

| plik | zawartość |
|---|---|
| [hud_landing.svg](hud_landing.svg) | HUD przy podejściu do lądowania w 1:1, plus prymitywy w powiększeniu 3x |
| [hud_flight_states.svg](hud_flight_states.svg) | cztery tryby: DEEP, ORBIT, LANDING, COMBAT (UI_STYLE.md sekcja 10) |
| [screens_editor_maps.svg](screens_editor_maps.svg) | edytor statku, mapa systemu, mapa galaktyki (UI_STYLE.md sekcja 11) |

## Próby stylistyczne

Nie są decyzją. Są materiałem do porównania — i do ściągania pojedynczych
pomysłów, nawet jeśli cały język odpadnie.

| plik | język | co z tego warto ukraść |
|---|---|---|
| [lcars_hud.svg](lcars_hud.svg) | Star Trek TNG, LCARS: kolanka, bloki, ciepła paleta | **pasek trybów u dołu** — tryb lotu dostaje nazwę zamiast być domyślny. Alarm jako zmiana całej ramy, bo w palecie samych pomarańczy nie da się ostrzec odcieniem |
| [lcars_editor_map.svg](lcars_editor_map.svg) | LCARS na ekranach konsolowych | „wszystko jest podpisanym blokiem" — gniazdo jako przycisk, raport jako rząd pociętych pasków. Na warsztacie LCARS wygrywa z wektorem |
| [starwars_screens.svg](starwars_screens.svg) | Star Wars: sprzęt przed grafiką, jednobarwny bursztyn, lampki, blacha | **rzędy kwadratowych lampek** jako stan sześciu silników naraz, czytany peryferyjnie. Komputer celowniczy jako osobny, wpuszczony ekranik o własnej rozdzielczości |
| [expanse_screens.svg](expanse_screens.svg) | The Expanse: zero ramek, linie włosowe, cienka typografia | **delta-v i ciąg w g jako nagłówek ekranu**, nie jako wiersz w tabelce. Plot z węzłami palenia wycenionymi osobno. Zakładka podkreślona zamiast wypełnionej |

Uwaga do dwóch ostatnich: Star Wars wymaga blachy, a blacha zjada pole pilota
jeszcze bardziej niż LCARS. Expanse jest odwrotnie — nie zjada nic, bo nie ma
paneli, ale cała jego czytelność stoi na cienkiej typografii w małych
rozmiarach, czyli na dokładnie tym, czego 640x360 nie udźwignie bez fontu
pikselowego zaprojektowanego pod to.

## Do czego to jest

Makieta ustala **układ, gęstość i hierarchię** przed napisaniem kodu, bo to
najtańsze miejsce na zmianę zdania. Nie ustala tego, jak rzecz wygląda w ruchu —
na to jest `tools/gallery.tscn` i odpalenie gry, i to one rozstrzygają spór
(VISUALS.md sekcja 5).

Liczby na makietach są zmyślone, ale ich **format** jest wiążący: szerokość
kolumny, liczba cyfr znaczących i jednostka są częścią projektu, nie ozdobą.
