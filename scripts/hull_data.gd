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

## Where the places on this hull are, in the ship's own frame. Four lists
## because the kinds are different jobs: engines aft, guns forward, guns along
## the sides, a gun astern. Counts are DRIVE_SLOTS and friends.
##
## Left empty, a list falls back to `default_positions()`, which works them
## out from the outline -- so a hull someone just drew has places before
## anyone has placed them. `tools/bake_hull_slots.gd` writes those defaults
## into every .tres, after which they are plain data to move by hand.
@export var drive_slots: Array[Vector2] = []
@export var front_slots: Array[Vector2] = []
@export var side_slots: Array[Vector2] = []
@export var rear_slots: Array[Vector2] = []

## How many places every hull offers, by kind. The same on every hull, which
## is the point: what differs is where they land on the outline, not how many
## there are, so loot and presets can count on them.
const DRIVE_SLOTS: int = 2
const FRONT_HARDPOINTS: int = 2
const SIDE_HARDPOINTS: int = 3
const REAR_HARDPOINTS: int = 1

## Kinds in `slots()`.
const SLOT_DRIVE: StringName = &"drive"
const SLOT_FRONT: StringName = &"front"
const SLOT_SIDE: StringName = &"side"
const SLOT_REAR: StringName = &"rear"

## Right angles, matching ShipFitout: a mount's `turn` is its node rotation.
const _LEFT: float = -PI * 0.5
const _RIGHT: float = PI * 0.5
const _AFT: float = PI

## Where the main drives sit: this far up from the stern, and this share of the
## local half-width off the centre line.
const DRIVE_INSET: float = 2.0
const DRIVE_SPREAD: float = 0.35

## Front guns this far back from the nose, as a share of the hull's length.
const FRONT_SETBACK: float = 0.18
const FRONT_SPREAD: float = 0.6
const FRONT_MIN_X: float = 2.5

## How far past the stern the rear gun hangs, clear of the main drive.
const REAR_OFFSET: float = 2.0

## Where the side guns sit along the hull, 0 at the nose and 1 at the stern.
const SIDE_MID: float = 0.5
const SIDE_AFT: float = 0.75

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


## Half the width of the outline at height `y`, or 0 where it does not reach.
func half_width_at(y: float) -> float:
	var reach: float = 0.0
	var count: int = outline.size()
	for i: int in range(count):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % count]
		if (a.y - y) * (b.y - y) > 0.0 or is_equal_approx(a.y, b.y):
			continue
		var along: float = (y - a.y) / (b.y - a.y)
		reach = maxf(reach, absf(lerpf(a.x, b.x, along)))
	return reach


## Where each kind of place lands by default, worked out from the outline:
## two drives aft, two guns forward, three along the sides and one astern.
##
## Three side guns cannot be symmetric, so the third sits on the right, aft of
## the pair.
func default_positions() -> Dictionary:
	var out: Dictionary = {
		SLOT_DRIVE: [], SLOT_FRONT: [], SLOT_SIDE: [], SLOT_REAR: [],
	}
	if outline.is_empty():
		return out
	var box: Rect2 = bounds()
	var stern: float = box.end.y
	var nose: float = box.position.y
	var length: float = stern - nose

	var drive_y: float = stern - DRIVE_INSET
	var drive_x: float = half_width_at(drive_y) * DRIVE_SPREAD
	out[SLOT_DRIVE] = [Vector2(-drive_x, drive_y), Vector2(drive_x, drive_y)]

	var front_y: float = nose + length * FRONT_SETBACK
	var front_x: float = maxf(half_width_at(front_y) * FRONT_SPREAD, FRONT_MIN_X)
	out[SLOT_FRONT] = [Vector2(-front_x, front_y), Vector2(front_x, front_y)]

	var mid_y: float = nose + length * SIDE_MID
	var aft_y: float = nose + length * SIDE_AFT
	out[SLOT_SIDE] = [
		Vector2(-half_width_at(mid_y), mid_y),
		Vector2(half_width_at(mid_y), mid_y),
		Vector2(half_width_at(aft_y), aft_y),
	]
	# A pylon past the stern: the hull's own end is where the main drive sits.
	out[SLOT_REAR] = [Vector2(0.0, stern + REAR_OFFSET)]
	return out


## Every place this hull offers: what the resource says, or the default for a
## kind it says nothing about. Each entry is `{name, kind, at, turn}`, in the
## ship's own frame, with `turn` the node rotation the mount should have.
func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if outline.is_empty():
		return out
	var defaults: Dictionary = default_positions()
	var written: Dictionary = {
		SLOT_DRIVE: drive_slots, SLOT_FRONT: front_slots,
		SLOT_SIDE: side_slots, SLOT_REAR: rear_slots,
	}
	var names: Dictionary = {
		SLOT_DRIVE: "MainDrive", SLOT_FRONT: "FrontHardpoint",
		SLOT_SIDE: "SideHardpoint", SLOT_REAR: "RearHardpoint",
	}
	for kind: StringName in [SLOT_DRIVE, SLOT_FRONT, SLOT_SIDE, SLOT_REAR]:
		var places: Array = written[kind] if not (written[kind] as Array).is_empty() else defaults[kind]
		for i: int in range(places.size()):
			var at: Vector2 = places[i]
			var slot_name: String = String(names[kind])
			# The first drive is "MainDrive" and the second "MainDrive2";
			# the others count from one, and a lone rear gun has no number.
			if kind == SLOT_DRIVE:
				slot_name += "" if i == 0 else str(i + 1)
			elif kind != SLOT_REAR or places.size() > 1:
				slot_name += str(i + 1)
			out.append(_slot(StringName(slot_name), kind, at, _turn_for(kind, at)))
	return out


## Which way a place faces: forward and aft drives point the ship's way, side
## guns point out of the side they are on, the rear gun points astern.
static func _turn_for(kind: StringName, at: Vector2) -> float:
	if kind == SLOT_SIDE:
		return _LEFT if at.x < 0.0 else _RIGHT
	if kind == SLOT_REAR:
		return _AFT
	return 0.0


## The slots of one kind, in order.
func slots_of(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: Dictionary in slots():
		if slot["kind"] == kind:
			out.append(slot)
	return out


static func _slot(slot_name: StringName, kind: StringName, at: Vector2, turn: float) -> Dictionary:
	return {"name": slot_name, "kind": kind, "at": at, "turn": turn}


## The box the outline sits in, which is what a sprite canvas is cut from.
func bounds() -> Rect2:
	if outline.is_empty():
		return Rect2()
	var box: Rect2 = Rect2(outline[0], Vector2.ZERO)
	for point: Vector2 in outline:
		box = box.expand(point)
	return box
