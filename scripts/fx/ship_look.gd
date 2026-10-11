class_name ShipLook
extends RefCounted
## Ktora grafika nalezy sie ktorej czesci statku i jak jest obrocona.
##
## The look rules with no ship attached. `ShipSkin` is a node on a live
## ship that ticks every physics frame; this is the half of it a dock can
## ask: which strip a part gets, which way round it hangs, and where the
## whole picture sits when nothing is moving.
##
## Split out because the preset dock has to show the skinning, and the
## one wrong way to do that is to let the dock choose the pictures for
## itself. A second copy of "a strafe thruster faces this way" is a copy
## that will disagree with the game, and the disagreement stays invisible
## until a flame comes out of the wrong side of the hull in flight.
##
## What is **not** here is motion: throttle, gimbal, afterglow, heat,
## daylight, gear travel. Those are readings off a running ship and they
## stay in `ShipSkin`, which is why `still_of` is called a still. The
## dock shows the picture at rest; the Sandbox is where it moves.

## Where each family sits front to back. Explicit, because the default is
## the order the nodes happened to be added in -- an accident that looks
## fine until a gun lands behind the hull it is bolted to.
##
## Here rather than on `ShipSkin`, which is where they were, because the
## dock paints the same stack without instantiating a single node. Two
## orderings of one stack is how a dock ends up showing a plume over the
## hull the game draws it under.
const Z_PLUME: int = -20
const Z_NOZZLE: int = -10
const Z_HULL: int = 0
const Z_GEAR: int = 5
const Z_GUN: int = 10

## What the hull's own `z_index` has to be for the whole of that stack
## to clear the world it is flying over.
##
## The five above are **relative to the hull**, which is the right way
## to write them -- a plume belongs behind its own ship whatever else
## is on screen. What that leaves is a hull at zero putting its flames
## at -20, and a planet draws its atmosphere, its terrain and its
## clouds at zero. Reported as the engines rendering underneath the
## atmosphere, which is exactly what it was: the hull was visible over
## the planet only because the ship comes later in the tree, and tree
## order settles nothing between different z levels.
##
## Derived from the deepest part rather than written down, so adding
## something deeper than a plume cannot quietly put it under a planet
## again. Five of margin, so the stack sits clear rather than tying
## with the world and falling back on tree order.
const Z_SHIP: int = -Z_PLUME + 5

const HULL_TABLE: String = "res://resources/fx/looks/hull.tres"
const NOZZLE_TABLE: String = "res://resources/fx/looks/engine_nozzle.tres"
const PLUME_TABLE: String = "res://resources/fx/looks/engine_plume.tres"
const GUN_TABLE: String = "res://resources/fx/looks/weapon_muzzle.tres"
const GEAR_TABLE: String = "res://resources/fx/looks/gear_leg.tres"


## Every table this run has already opened, in a game. Empty in the
## editor; see below.
static var _open: Dictionary = {}


## The table at `path`.
##
## Held in a game, looked up again in the editor, and the split is
## measured rather than tidy. `load()` on a resource already in the
## cache is not free: counted at 14335 calls in one suite run -- a ship
## asks for five tables every time it rebuilds its skin, and a refit
## rebuilds it -- which was 17 of the suite's 64 seconds. `ShipSkin`
## used to load the five once into fields of its own, and dropping that
## for a call per picture is what paid for it.
##
## The editor is the exception because there the file genuinely changes
## under the dock: a look table edited in the inspector has to show
## through on the next redraw, and a dock painting the pictures a table
## had before the edit is a dock lying about the file it sits next to.
## Nothing in a running game can edit one.
static func table(path: String) -> LookTable:
	if Engine.is_editor_hint():
		return load(path) as LookTable
	if not _open.has(path):
		_open[path] = load(path) as LookTable
	return _open[path] as LookTable


## The hull's own picture. `key` is what the preset asked to wear, which
## is the hull's id unless it said otherwise.
static func hull_strip(hull: HullData, key: StringName) -> SpriteStrip:
	return table(HULL_TABLE).pick(hull, key)


static func nozzle_strip(engine: EngineData) -> SpriteStrip:
	return table(NOZZLE_TABLE).pick(engine)


static func plume_strip(engine: EngineData) -> SpriteStrip:
	return table(PLUME_TABLE).pick(engine)


static func gun_strip(weapon: WeaponData) -> SpriteStrip:
	return table(GUN_TABLE).pick(weapon)


## A leg's two parts, by the names the table keys them under.
static func gear_strip(which: StringName) -> SpriteStrip:
	return table(GEAR_TABLE).pick(null, which)


## The angle at which a sprite's own down points along `direction`.
##
## Everything bolted to the hull hangs downward from its pivot -- a
## nozzle opens down, a plume flows down, a leg extends down -- so one
## conversion covers all of them and no sprite has to be drawn
## pre-rotated for the mount it happens to sit on.
static func facing(direction: Vector2) -> float:
	if direction.is_zero_approx():
		return 0.0
	return direction.angle() - Vector2.DOWN.angle()


## Which way the exhaust leaves a place turned `turn`.
##
## `ShipFitout.apply` builds every mount with `thrust_direction` UP and
## the place's own `turn` as its rotation, so thrust leaves along UP
## turned that far and the exhaust goes the other way. Stated here once
## because the still has no mount to ask -- and `facing` of this is the
## turn itself, which is a fact worth having a test for rather than a
## simplification worth hiding.
static func exhaust_from(turn: float) -> Vector2:
	return Vector2.DOWN.rotated(turn)


## The whole ship as pictures, at rest, in painting order.
##
## Each entry is `{strip, at, turn, stretch, z, part, name}`: `at` in
## hull coordinates, `turn` in radians, `stretch` the scale **beyond**
## `Art.WORLD_SCALE` that this part is drawn at. Nothing here is a node
## and nothing here is animated.
##
## At rest means the states where a misalignment shows: plumes at full
## flow, because that is the length that can reach a leg or a gun, and
## gear fully out, because that is where the strut has to end at the
## foot the solver will stand on. A plume at idle and a leg half-stowed
## are the running ship's business.
static func still_of(hull: HullData, wanted: ShipPreset) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if hull == null:
		return out

	# `ShipPreset.skin_key` answers for the preset's **own** hull, and the
	# hull dock pairs a preset with a different one on purpose: it asks
	# what the dart's fitout looks like on the brick being edited. So the
	# fallback is the hull that was passed, not the one the preset names.
	var key: StringName = hull.id
	if wanted != null and wanted.look_key != &"":
		key = wanted.look_key
	var body: SpriteStrip = hull_strip(hull, key)
	if body != null:
		out.append(_part(body, Vector2.ZERO, 0.0, Z_HULL, &"hull", String(key)))

	for spot: Dictionary in ShipFitout.placements(hull, wanted):
		# The engine the mount will really be given, share and overrides
		# and scale included, because the nozzle is picked off its
		# thrust: a drive split across two places gets half the thrust
		# and may well get a smaller bell for it.
		var engine: EngineData = ShipFitout.engine_in(spot)
		if engine == null:
			continue
		var at: Vector2 = spot["at"]
		var turn: float = float(spot["turn"])
		var named: String = String(spot["name"])
		var lip: float = 0.0
		var nozzle: SpriteStrip = nozzle_strip(engine)
		if nozzle != null:
			out.append(_part(nozzle, at, turn, Z_NOZZLE, &"nozzle", named))
			lip = nozzle.exit
		var plume: SpriteStrip = plume_strip(engine)
		if plume != null:
			# At the nozzle's exit plane, which the nozzle states rather
			# than the skin guessing it from where its pixels stop.
			out.append(_part(
				plume, at + exhaust_from(turn) * lip, turn, Z_PLUME, &"plume", named,
			))

	for spot: Dictionary in ShipFitout.armament(hull, wanted):
		var weapon: WeaponData = ShipFitout.dressed(
			spot["weapon"], spot["overrides"]
		) as WeaponData
		if weapon == null:
			continue
		var slot: Dictionary = spot["slot"]
		var gun: SpriteStrip = gun_strip(weapon)
		if gun != null:
			out.append(_part(
				gun, slot["at"], float(slot["turn"]), Z_GUN,
				&"gun", String(slot["name"]),
			))

	out.append_array(_gear_parts(hull))

	# Painted back to front, which is what a `_draw` has instead of a
	# `z_index`. Stable, so two parts at one depth keep the order they
	# were built in rather than swapping between redraws.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["z"]) < int(b["z"])
	)
	return out


## Both halves of every leg, fully extended.
##
## The strut is stretched to reach the foot exactly rather than swapped
## for a longer picture, the same as in flight: what is being shown is
## where the ship will actually touch down.
static func _gear_parts(hull: HullData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var strut: SpriteStrip = gear_strip(&"strut")
	var pad: SpriteStrip = gear_strip(&"pad")
	if strut == null or pad == null:
		return out
	for foot: Vector2 in hull.legs:
		var hip: Vector2 = LandingGear.root_on(hull.outline, foot)
		var down: Vector2 = foot - hip
		var own: float = maxf(strut.design_size().y, 1.0)
		out.append(_part(
			strut, hip, facing(down), Z_GEAR, &"strut", "noga",
			Vector2(1.0, down.length() / own),
		))
		out.append(_part(pad, foot, facing(down), Z_GEAR, &"pad", "stopa"))
	return out


static func _part(
	strip: SpriteStrip, at: Vector2, turn: float, depth: int,
	part: StringName, named: String, stretch: Vector2 = Vector2.ONE
) -> Dictionary:
	return {
		"strip": strip,
		"at": at,
		"turn": turn,
		"stretch": stretch,
		"z": depth,
		"part": part,
		"name": named,
	}
