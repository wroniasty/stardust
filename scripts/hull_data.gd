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

## Where the feet go. Empty on a shape nobody has worked out a stance for,
## in which case a ship reshaped into it keeps the feet it had.
@export var legs: Array[Vector2] = []

## How much the hold takes. Zero means the hull does not say, and whatever
## is flying it keeps its own.
##
## A property of the hull rather than of a fitout, because it is a fact
## about the shape: the freighter carries forty-two because it is a box,
## and the interceptor four because it is not.
@export var cargo_capacity: float = 0.0

## Every hull, newest catalogue first. A directory listing rather than a
## const list, because a const list of paths is the fourth copy.
const DIRECTORY: String = "res://resources/hulls"


## Every hull, by id, loaded once.
##
## Cached because the skin asks on every refit and the alternative is a
## directory scan plus ten loads each time. Cleared by nothing: the
## catalogue is files on disk, and those do not change while the game runs.
static var _catalogue: Dictionary = {}


## Every hull resource on disk, by id. Sorted, so a menu built from this is
## in the same order every run.
static func all() -> Dictionary:
	if not _catalogue.is_empty():
		return _catalogue
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
	_catalogue = out
	return out


## The named hull with this exact outline, or null when the shape is one
## nobody named.
##
## How a ship finds its own picture, and deliberately the cheap half of
## M3.5's "kadluby jako zasoby": the expensive half is collapsing
## CreativeTool.SHAPES and the ShipFitout presets onto these resources, and
## until that happens a field on the ship would be a fourth copy of the
## catalogue for three callers to forget to set.
##
## Exact, not approximate. A hull the creative tool scaled is a different
## shape that would need a different picture, so it matches nothing and
## falls back to being drawn as a polygon -- which is what a sandbox should
## show for a shape it invented.
static func matching(outline: PackedVector2Array) -> HullData:
	if outline.is_empty():
		return null
	for id: Variant in all():
		var hull: HullData = all()[id]
		if hull.outline == outline:
			return hull
	return null


## Every hull in id order, as a list.
##
## Ordered, because a menu built from this has to offer the same thing in
## the same place every run -- and `all()` is a dictionary, whose order is
## the directory's, which `ResourceLoader` does not promise.
static func catalogue() -> Array[HullData]:
	var ids: Array = all().keys()
	ids.sort()
	var out: Array[HullData] = []
	for id: Variant in ids:
		out.append(all()[id])
	return out


## The hull with this id, or null.
static func of(id: StringName) -> HullData:
	return all().get(id)


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
