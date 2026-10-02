class_name HullData
extends Resource
## Kadlub jako zasob: nazwa, obrys i rozstaw nog.
##
## The outline is simulation data, which is why this is not in scripts/fx.
## Everything physical about a ship comes out of it -- the collision shape,
## the contact points that sample the terrain, the mass, the centre of mass
## and the inertia -- and `Ship.hull_outline` is the field it lands in.
##
## What it deliberately does **not** carry is a texture. The picture is chosen
## by `resources/fx/looks/hull.tres`, keyed on `id`, so the hull a ship flies
## and the hull a player sees are one name resolved twice rather than two
## fields that can disagree.
##
## Today this is a third copy of the catalogue, after `CreativeTool.SHAPES`
## and the `hull` entries in `ShipFitout.all()`. That is deliberate and
## temporary: a smoke test asserts all three agree, so the duplication cannot
## drift while the other two are migrated onto this one (PLAN.md M3.5,
## "Kadluby jako zasoby").

## Stable, file-safe name. What the look table is keyed on, so renaming the
## display name does not silently change which picture a hull gets.
@export var id: StringName = &""

## What the pilot is shown. Matches the entry in CreativeTool.SHAPES or
## ShipFitout.all() this came from, including its language.
@export var display_name: String = "hull"

## The shape, in the ship's own frame, nose towards -Y.
@export var outline: PackedVector2Array = PackedVector2Array()

## Where the feet go, when this hull is flown as a preset. Empty for a shape
## the creative tool only ever reshapes an existing ship into.
@export var legs: Array[Vector2] = []

## Every hull, newest catalogue first. A directory listing rather than a
## const list, because a const list of paths is the fourth copy.
const DIRECTORY: String = "res://resources/hulls"


## Every hull resource on disk, by id. Sorted, so a menu built from this is
## in the same order every run.
static func all() -> Dictionary:
	var out: Dictionary = {}
	var names: PackedStringArray = ResourceLoader.list_directory(DIRECTORY)
	var sorted: Array = Array(names)
	sorted.sort()
	for file_name: String in sorted:
		if not file_name.ends_with(".tres"):
			continue
		var hull: HullData = load("%s/%s" % [DIRECTORY, file_name]) as HullData
		if hull != null:
			out[hull.id] = hull
	return out


## Half the longest span of the outline, matching Ship.hull_extent().
func extent() -> float:
	var widest: float = 0.0
	for point: Vector2 in outline:
		widest = maxf(widest, point.length())
	return widest


## The box the outline sits in, which is what a sprite canvas is cut from.
func bounds() -> Rect2:
	if outline.is_empty():
		return Rect2()
	var box: Rect2 = Rect2(outline[0], Vector2.ZERO)
	for point: Vector2 in outline:
		box = box.expand(point)
	return box
