class_name Palette
extends Resource
## Dwanaście nazwanych kolorów interfejsu, w jednym pliku.
##
## UI_STYLE.md section 3 counted the damage before this existed: the same
## four roles were written out in `flight_hud.gd`, `ship_editor.gd` and
## `loadout_screen.gd` as eleven different colours. Two panel fills, two
## borders, four greys for "label" and "value", and three ambers a pixel
## apart. Nobody did that on purpose; it is what happens when a role is
## spelled out at the place it is used.
##
## The names are roles, not colours, and that is the whole point of having
## them: a call site saying `_ink.caution` has said why it is amber.
##
## Two rules hold the set together, and both are in UI_STYLE:
##
## **Two accent channels.** `accent` is the ship -- thrust, energy, gear,
## hull. `nav` is the world -- planet, orbit, scanner, horizon. The pilot
## learns what a number is about before reading its label.
##
## **Warnings pay for their attention by being absent.** `caution` and
## `alarm` appear nowhere in the normal state: no decoration, no frame, no
## accent "because it looks nice". The only reason amber works on screen is
## that most of a flight has none of it.
##
## Rarity colours are not here. They belong to the item rather than to the
## interface and have their own dictionary on `ModuleData`.

## Scrim under a panel, and under a modal screen. Called `void` in
## UI_STYLE; renamed because `void` is a GDScript keyword.
@export var scrim: Color = Color(0.0196, 0.0275, 0.0431)

## Panel fill. The alpha belongs to the panel, not to the colour: a HUD
## instrument and a full-screen sheet want different amounts of world
## showing through.
@export var panel: Color = Color(0.0392, 0.0549, 0.0824)

## Panel edge, and the lines that divide one region from another.
@export var edge: Color = Color(0.1490, 0.1882, 0.2392)

## Scale marks, fine structure, the empty part of a bar.
@export var grid: Color = Color(0.2275, 0.2784, 0.3412)

## No data, or a position that is there but not in use.
@export var inert: Color = Color(0.2902, 0.3373, 0.3961)

## Label, unit, anything secondary.
@export var label: Color = Color(0.4706, 0.5373, 0.6118)

## The number itself, and any primary text.
@export var value: Color = Color(0.8471, 0.8941, 0.9412)

## The ship: thrust, energy, gear, hull.
@export var accent: Color = Color(0.3725, 0.8902, 0.7529)

## The world: planet, orbit, scanner, horizon.
@export var nav: Color = Color(0.4824, 0.6549, 1.0)

## Good, armed, fits.
@export var ok: Color = Color(0.3843, 0.8784, 0.5490)

## Close to a limit, and the cursor's own choice.
@export var caution: Color = Color(1.0, 0.7608, 0.2902)

## Over a limit, damaged, refused.
@export var alarm: Color = Color(1.0, 0.3569, 0.3020)

const FILE: String = "res://resources/ui/palette.tres"

static var _current: Palette = null


## The palette every screen draws from, loaded once.
##
## Falls back to a default-constructed one rather than to null, because the
## exported defaults above are the same twelve colours: a missing file
## should leave the game looking right, not leave it drawing in black.
static func current() -> Palette:
	if _current == null:
		_current = load(FILE) as Palette
	if _current == null:
		push_warning("no palette at %s; using the built-in one" % FILE)
		_current = Palette.new()
	return _current


## The same colour at a different opacity, for a panel fill over the world.
##
## A helper rather than twelve more entries: how much world shows through a
## panel is a property of that panel, and an instrument in the corner and a
## modal sheet want different answers from the same fill.
func over(which: Color, opacity: float) -> Color:
	return Color(which.r, which.g, which.b, opacity)
