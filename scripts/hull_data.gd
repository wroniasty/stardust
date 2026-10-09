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

## And the three kinds of small engine, which the hull used not to know
## about at all.
##
## They lived as literal positions in `ShipFitout`'s preset table --
## `{"name": "NoseLeftTorque", "at": Vector2(-8, -10)}` -- which meant a
## hull could not be reshaped without editing GDScript, and that the one
## thing a pilot can see about a ship was the one thing not in the ship's
## own resource. Drives and guns had been data-driven since M3; these had
## simply never caught up.
##
## Four torque jets in a cross, two strafe thrusters, one reverse nozzle
## in the nose. A hull that leaves one empty gets the frame
## `default_positions()` derives, which is a starting point rather than a
## design: these are booms and nozzles bolted outside the outline, and
## nothing about a triangle says where they should hang.
@export var torque_slots: Array[Vector2] = []
@export var strafe_slots: Array[Vector2] = []
@export var retro_slots: Array[Vector2] = []

## How many places every hull offers, by kind. The same on every hull, which
## is the point: what differs is where they land on the outline, not how many
## there are, so loot and presets can count on them.
const DRIVE_SLOTS: int = 3
const FRONT_HARDPOINTS: int = 2
const SIDE_HARDPOINTS: int = 3
const REAR_HARDPOINTS: int = 1
const TORQUE_SLOTS: int = 4
const STRAFE_SLOTS: int = 2
const RETRO_SLOTS: int = 1

## Kinds in `slots()`.
const SLOT_DRIVE: StringName = &"drive"
const SLOT_FRONT: StringName = &"front"
const SLOT_SIDE: StringName = &"side"
const SLOT_REAR: StringName = &"rear"
const SLOT_TORQUE: StringName = &"torque"
const SLOT_STRAFE: StringName = &"strafe"
const SLOT_RETRO: StringName = &"retro"

## Right angles, matching ShipFitout: a mount's `turn` is its node rotation.
const _LEFT: float = -PI * 0.5
const _RIGHT: float = PI * 0.5
const _AFT: float = PI

## Where the main drives sit: this far up from the stern, and this share of the
## local half-width off the centre line.
const DRIVE_INSET: float = 0.0
const DRIVE_SPREAD: float = 0.35

## A pointed stern has no width to take a share of, and a drive pair needs
## some: this is the least either side of the centre line.
const DRIVE_MIN_X: float = 2.5

## Front guns this far back from the nose, as a share of the hull's length.
const FRONT_SETBACK: float = 0.18
const FRONT_SPREAD: float = 0.6
const FRONT_MIN_X: float = 2.5

## How far past the stern the rear gun hangs, clear of the main drive.
const REAR_OFFSET: float = 2.0

## Where the side guns sit along the hull, 0 at the nose and 1 at the stern.
const SIDE_MID: float = 0.5
const SIDE_AFT: float = 0.75

## Where the derived frame puts the small engines, as shares of the
## hull's length, and how far out the strafe pair sits as a share of the
## bounding box's half-width.
const TORQUE_NOSE: float = 0.09
const TORQUE_TAIL: float = 1.16
const STRAFE_ALONG: float = 0.62
const STRAFE_OUT: float = 1.12

## And how far ahead of the nose the reverse nozzle hangs.
const RETRO_AHEAD: float = 0.0

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
static func matching(shape: PackedVector2Array) -> HullData:
	if shape.is_empty():
		return null
	for named: Variant in all():
		var hull: HullData = all()[named]
		if hull.outline == shape:
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
	for named: Variant in ids:
		out.append(all()[named])
	return out


## The hull with this id, or null.
static func of(named: StringName) -> HullData:
	return all().get(named)


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
## three drives aft, two guns forward, three along the sides and one astern.
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
	var drive_x: float = maxf(half_width_at(drive_y) * DRIVE_SPREAD, DRIVE_MIN_X)
	# Centre first, then the pair either side of it.
	out[SLOT_DRIVE] = [
		Vector2(0.0, drive_y), Vector2(-drive_x, drive_y), Vector2(drive_x, drive_y),
	]

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

	# The small engines hang off the **bounding box** rather than off the
	# outline, because that is what they physically are: booms and
	# nozzles bolted outside the hull, not sockets cut into it. The dart's
	# torque jets sit at plus and minus eight where the hull at that
	# height is less than one wide.
	#
	# A frame rather than a design. Every hull in the game writes its own
	# (see the .tres files); this is what a shape invented in the creative
	# tool gets so that it flies at all.
	var boom: float = box.size.x * 0.5
	var nose_y: float = nose + length * TORQUE_NOSE
	var tail_y: float = nose + length * TORQUE_TAIL
	out[SLOT_TORQUE] = [
		Vector2(-boom, nose_y), Vector2(boom, nose_y),
		Vector2(-boom, tail_y), Vector2(boom, tail_y),
	]
	var strafe_y: float = nose + length * STRAFE_ALONG
	# The thruster that pushes left sits on the **right**, which is why
	# the names and the signs look crossed. See `_turn_for`.
	out[SLOT_STRAFE] = [
		Vector2(boom * STRAFE_OUT, strafe_y), Vector2(-boom * STRAFE_OUT, strafe_y),
	]
	out[SLOT_RETRO] = [Vector2(0.0, nose - RETRO_AHEAD)]
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
		SLOT_TORQUE: torque_slots, SLOT_STRAFE: strafe_slots,
		SLOT_RETRO: retro_slots,
	}
	var names: Dictionary = {
		SLOT_DRIVE: "MainDrive", SLOT_FRONT: "FrontHardpoint",
		SLOT_SIDE: "SideHardpoint", SLOT_REAR: "RearHardpoint",
		SLOT_TORQUE: "Torque", SLOT_STRAFE: "StrafeThruster",
		SLOT_RETRO: "NoseReverseThruster",
	}
	var middle: float = bounds().get_center().y
	for kind: StringName in [
		SLOT_DRIVE, SLOT_FRONT, SLOT_SIDE, SLOT_REAR,
		SLOT_TORQUE, SLOT_STRAFE, SLOT_RETRO,
	]:
		var places: Array = written[kind] if not (written[kind] as Array).is_empty() else defaults[kind]
		for i: int in range(places.size()):
			var at: Vector2 = places[i]
			var slot_name: String = String(names[kind])
			# Drives are named by where they sit, which is what a fitout and
			# a pilot both ask about; the guns count from one, and a lone
			# rear gun has no number.
			if kind == SLOT_DRIVE:
				slot_name += "Center" if is_zero_approx(at.x) else ("Left" if at.x < 0.0 else "Right")
			elif kind == SLOT_TORQUE:
				# Named by where it is rather than by its place in the
				# array, so the four may be written in any order and a
				# hull that lists them differently still builds the same
				# ship. Against the middle of the bounding box, not
				# against zero: a hull whose whole outline sits below the
				# origin still has a nose and a tail.
				slot_name = (
					("Nose" if at.y < middle else "Tail")
					+ ("Left" if at.x < 0.0 else "Right") + "Torque"
				)
			elif kind == SLOT_STRAFE:
				# The thruster that **pushes** left sits on the right, so
				# the name is about the push and the position is its
				# mirror. Crossed on purpose and crossed in the original
				# preset table; see `_turn_for`.
				slot_name = (
					"Strafe" + ("Left" if at.x > 0.0 else "Right") + "Thruster"
				)
			elif kind == SLOT_RETRO:
				pass
			elif kind != SLOT_REAR or places.size() > 1:
				slot_name += str(i + 1)
			out.append(_slot(StringName(slot_name), kind, at, _turn_for(kind, at)))
	return out


## Which way a place faces: forward and aft drives point the ship's way, side
## guns point out of the side they are on, the rear gun points astern.
static func _turn_for(kind: StringName, at: Vector2) -> float:
	if kind == SLOT_SIDE:
		return _LEFT if at.x < 0.0 else _RIGHT
	if kind == SLOT_REAR or kind == SLOT_RETRO:
		return _AFT
	if kind == SLOT_TORQUE:
		# A torque jet pushes **across** the hull, and the one on the left
		# pushes right: that is what makes a nose jet and the far tail jet
		# a couple. The opposite sign from a side gun, which points out of
		# the side it is on.
		return _RIGHT if at.x < 0.0 else _LEFT
	if kind == SLOT_STRAFE:
		# And a strafe thruster pushes away from the side it is on, which
		# is the same crossing its name carries.
		return _LEFT if at.x > 0.0 else _RIGHT
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
