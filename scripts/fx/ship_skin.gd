class_name ShipSkin
extends Node2D
## The picture of the ship: hull, nozzles, plumes, guns, legs.
##
## Reads the ship, never writes to it. Every number it uses -- throttle,
## gimbal, gun facing, gear extension, daylight -- the simulation was already
## computing for its own reasons, so this node is a readout rather than a
## second model (VISUALS.md section 1, point 2).
##
## A child of the ship, so the ship's own transform carries it and there is
## nothing to follow. That also keeps it clear of physics interpolation,
## which is why everything below ticks in `_physics_process`: the values it
## reads change at the physics rate, and a transform written from a render
## frame fights the interpolator instead of riding it.
##
## One tick for the whole skin, not one per sprite. That is the other half of
## the StripSprite decision: the rate an animation runs at is a reading off
## the ship, and there is exactly one place the reading is taken.

## Where each family sits front to back. Explicit, because the default is the
## order the nodes happened to be added in -- an accident that looks fine
## until a gun lands behind the hull it is bolted to.
const Z_PLUME: int = -20
const Z_NOZZLE: int = -10
const Z_HULL: int = 0
const Z_GEAR: int = 5
const Z_GUN: int = 10

## How short a plume is at a whisker of throttle, as a share of full length.
## Not zero: an engine ticking over still has a flame, and one that grew from
## nothing would read as the engine starting rather than as it idling.
const PLUME_SHORTEST: float = 0.45

## Throttle below which a plume is not drawn at all.
const PLUME_CUTOFF: float = 0.02

## How much wider a plume gets per unit of emergency power, against how much
## longer. A boosted drive is mostly a longer flame, not a fatter one: the
## square root keeps three times the thrust at under twice the width, which
## is what stops it reading as a cloud round the stern.
const PLUME_BOOST_WIDTH: float = 0.5

## How dim a half-open leg is. Gear part-way down must not read as gear you
## could land on, which is exactly what `contact_points()` refuses to hand
## out until the timer finishes.
const GEAR_DIMMEST: float = 0.4

## What a hull at full heat is tinted. Over one on purpose: `hull_heat`
## reaching 1.0 is the ship about to die of it, and a glow that stopped at
## white would make the last half of that range look like the first.
const HEAT_GLOW: Color = Color(1.45, 1.15, 0.95)

## And what nothing left of it looks like. Scorched rather than merely
## dark, so a wrecked hull reads as damaged instead of as unlit -- the
## night side already owns dark.
const SCORCHED: Color = Color(0.46, 0.33, 0.29)

## How dark a nozzle gets at zero condition. A dead engine is visibly a
## dead engine before the pilot looks at the configuration report.
const RUINED_NOZZLE: float = 0.45

## Seconds for a plume to fall away once the throttle shuts.
##
## The reason this exists is the torque jets. They are impulse engines: the
## delta-sigma modulator in `EngineInstance.advance()` gives them a
## throttle that is 0 or 1 on any given tick and the right average over
## many, so a plume following it exactly strobes at sixty hertz. Decaying
## instead turns a 30% duty cycle into a jet that stutters, which is what
## it is -- and the average brightness still tracks the duty cycle, so
## nothing is being hidden.
##
## Rising is instant. A burn starts when it starts; only the dying away
## has any physical reason to lag.
const PLUME_AFTERGLOW: float = 0.07

var ship: Ship = null

var _hull: StripSprite = null
var _nozzles: Dictionary = {} ## mount name -> StripSprite
var _plumes: Dictionary = {} ## mount name -> StripSprite
var _exits: Dictionary = {} ## mount name -> float, design px from mount to lip
var _guns: Dictionary = {} ## hardpoint name -> StripSprite

## Per engine, the flame as it is drawn rather than as it is commanded:
## instant up, PLUME_AFTERGLOW down. Keyed by mount name like the rest.
var _afterglow: Dictionary = {}
var _legs: Array[Dictionary] = [] ## {strut, pad, at}

## What the skin replaces, kept so `F8` can hand the view back to it.
var _polygon: Polygon2D = null

var _nozzle_looks: LookTable = null
var _plume_looks: LookTable = null
var _gun_looks: LookTable = null
var _gear_looks: LookTable = null
var _hull_looks: LookTable = null


func _ready() -> void:
	ship = get_parent() as Ship
	if ship == null:
		push_error("ShipSkin needs a Ship for a parent")
		set_physics_process(false)
		return
	_polygon = ship.get_node_or_null("Hull") as Polygon2D
	_nozzle_looks = load("res://resources/fx/looks/engine_nozzle.tres") as LookTable
	_plume_looks = load("res://resources/fx/looks/engine_plume.tres") as LookTable
	_gun_looks = load("res://resources/fx/looks/weapon_muzzle.tres") as LookTable
	_gear_looks = load("res://resources/fx/looks/gear_leg.tres") as LookTable
	_hull_looks = load("res://resources/fx/looks/hull.tres") as LookTable
	# Fitting anything changes what has to be drawn, and the ship already
	# announces that for its own reasons.
	ship.configuration_changed.connect(rebuild)
	rebuild()


## Builds every sprite from scratch.
##
## Thrown away and remade rather than reconciled. A refit can change the
## engine in a mount, the gun on a hardpoint and the shape of the hull at
## once, and a diff against all three would be more code than the rebuild it
## saves -- on an event that happens when a pilot presses a key, not per tick.
func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_nozzles.clear()
	_plumes.clear()
	_exits.clear()
	_afterglow.clear()
	_guns.clear()
	_legs.clear()
	_hull = null

	_build_hull()
	for engine: EngineInstance in ship.engines:
		_build_engine(engine)
	for hardpoint: Hardpoint in ship.hardpoints:
		_build_gun(hardpoint)
	_build_gear()


## The hull picture, if this shape is one of the named ones.
##
## Matched on the outline rather than read off a field, which is the cheap
## half of M3.5's "hulls as resources". The expensive half is collapsing
## `CreativeTool.SHAPES` and the `ShipFitout` presets onto the resources, and
## until that happens a field on the ship would be a fourth copy of the
## catalogue for three callers to forget to set.
##
## A hull the creative tool reshaped matches nothing, so it gets no sprite
## and the `Polygon2D` underneath stays visible. That is the right answer
## rather than a gap: a sandbox has to show the shape it actually got.
func _build_hull() -> void:
	var named: HullData = HullData.matching(ship.hull_outline)
	if named == null:
		return
	# The preset's key when it has one, the hull's name otherwise. A
	# preset is a whole ship and that includes what it looks like, so two
	# fitouts on one hull can wear different pictures.
	#
	# Still gated on the outline matching, which is the part worth
	# keeping: a shape the creative tool scaled matches nothing, gets no
	# sprite, and the polygon underneath stays visible. A sandbox has to
	# show the shape it actually got, and a key cannot make that untrue.
	var key: StringName = ship.look_key if ship.look_key != &"" else named.id
	var strip: SpriteStrip = _hull_looks.pick(named, key)
	if strip == null:
		return
	_hull = _place(strip, Vector2.ZERO, 0.0, Z_HULL)


func _build_engine(engine: EngineInstance) -> void:
	var exhaust: Vector2 = -engine.mount.force_direction()
	var nozzle: SpriteStrip = _nozzle_looks.pick(engine.data)
	var lip: float = 0.0
	if nozzle != null:
		_nozzles[engine.mount.name] = _place(
			nozzle, engine.mount.position, _facing(exhaust), Z_NOZZLE
		)
		lip = nozzle.exit
	_exits[engine.mount.name] = lip

	var plume: SpriteStrip = _plume_looks.pick(engine.data)
	if plume != null:
		# At the nozzle's exit plane, which the nozzle states rather than the
		# skin guessing from where its pixels happen to stop.
		_plumes[engine.mount.name] = _place(
			plume, engine.mount.position + exhaust * lip, _facing(exhaust), Z_PLUME
		)


func _build_gun(hardpoint: Hardpoint) -> void:
	if hardpoint.weapon == null:
		return
	var strip: SpriteStrip = _gun_looks.pick(hardpoint.weapon)
	if strip == null:
		return
	_guns[hardpoint.name] = _place(strip, hardpoint.position, hardpoint.rotation, Z_GUN)


func _build_gear() -> void:
	if ship.gear == null:
		return
	var strut: SpriteStrip = _gear_looks.pick(null, &"strut")
	var pad: SpriteStrip = _gear_looks.pick(null, &"pad")
	if strut == null or pad == null:
		return
	for leg: Vector2 in ship.gear.legs:
		_legs.append({
			"strut": _place(strut, Vector2.ZERO, 0.0, Z_GEAR),
			"pad": _place(pad, Vector2.ZERO, 0.0, Z_GEAR),
			"at": leg,
		})


## The angle at which a sprite's own down points along `direction`.
##
## Everything bolted to the hull hangs downward from its pivot -- a nozzle
## opens down, a plume flows down, a leg extends down -- so one conversion
## covers all of them and no sprite has to be drawn pre-rotated for the mount
## it happens to sit on.
func _facing(direction: Vector2) -> float:
	if direction.is_zero_approx():
		return 0.0
	return direction.angle() - Vector2.DOWN.angle()


func _place(strip: SpriteStrip, at: Vector2, turn: float, depth: int) -> StripSprite:
	var sprite: StripSprite = StripSprite.new()
	add_child(sprite)
	sprite.show_strip(strip)
	sprite.position = at
	sprite.rotation = turn
	sprite.z_index = depth
	return sprite


func _physics_process(delta: float) -> void:
	refresh(delta)


## One tick of the whole skin, gated on the switch.
##
## The light is read either way, because where the ship is standing is a
## fact about the world rather than about which layer is painting it, and
## with the layer off the `Polygon2D` underneath is what needs shading.
func refresh(delta: float) -> void:
	Presentation.read_toggle()
	var on: bool = Presentation.is_on()
	visible = on

	# One reading of the light for the whole ship. Here rather than on the
	# ship, which used to reach into its own Polygon2D and set it -- that
	# was the simulation painting.
	var lit: float = GravityWell.daylight_at(get_tree(), global_position)
	var shade: Color = Color(lit, lit, lit)
	_hand_back(on, shade)
	if not on:
		return
	paint(delta, shade)


## The per-frame work itself, with no gate on it.
##
## Split out from `refresh()` so a headless test can take one step of it.
## The layer is never shown without a window, so `refresh()` returns before
## reaching any of this -- which meant the first version of the boost test
## measured a plume that had never been ticked and reported the scale
## `show_strip()` had left on it. A skin whose ticking cannot be tested is
## a skin whose ticking is not tested.
func paint(delta: float, shade: Color) -> void:
	var worn: Color = hull_shade(shade)
	if _hull != null:
		_hull.self_modulate = worn
	_tick_engines(delta, shade)
	_tick_guns(worn)
	_tick_gear(worn)


## What the hull is painted: the light on it, what is left of it, and how
## hot it is, in that order.
##
## The order is the argument. Scorching first and glow second means a wreck
## on re-entry is a glowing wreck rather than a clean ship -- heat is
## something happening to the hull now, damage is what has already happened
## to it, and the second does not undo the first.
##
## Both numbers were already there. `hull_integrity` and `hull_heat` have
## been computed every tick since M1 and nothing had ever shown either of
## them anywhere but as a line of text.
func hull_shade(lit: Color) -> Color:
	var hurt: float = 1.0 - clampf(ship.hull_integrity, 0.0, 1.0)
	var worn: Color = lit.lerp(
		Color(lit.r * SCORCHED.r, lit.g * SCORCHED.g, lit.b * SCORCHED.b), hurt
	)
	return worn.lerp(HEAT_GLOW, clampf(ship.hull_heat, 0.0, 1.0))


## Shows or hides what the skin replaces, and shades it either way.
##
## The ship's own drawing is still in the scene and is what `F8` reveals. It
## gets the same light, because where the ship is standing is a fact about
## the world rather than about which layer is painting it.
func _hand_back(on: bool, shade: Color) -> void:
	if _polygon != null:
		_polygon.visible = not (on and _hull != null)
		_polygon.self_modulate = shade
	if ship.gear != null:
		ship.gear.visible = not (on and not _legs.is_empty())
		ship.gear.self_modulate = shade


func _tick_engines(delta: float, shade: Color) -> void:
	for engine: EngineInstance in ship.engines:
		var exhaust: Vector2 = -engine.thrust_direction()
		var aim: float = _facing(exhaust)
		var nozzle: StripSprite = _nozzles.get(engine.mount.name) as StripSprite
		if nozzle != null:
			# Turned every tick rather than only on a gimballed engine: a
			# fixed nozzle recomputes the angle it already had, and a branch
			# to avoid that is a branch to get wrong.
			nozzle.rotation = aim
			# Darkened by its own condition, not the hull's: a ship can be
			# sound with one jet beaten in, and that is exactly the case
			# the damage model exists to make visible.
			var sound: float = lerpf(RUINED_NOZZLE, 1.0, clampf(engine.health, 0.0, 1.0))
			nozzle.self_modulate = Color(
				shade.r * sound, shade.g * sound, shade.b * sound
			)

		var plume: StripSprite = _plumes.get(engine.mount.name) as StripSprite
		if plume == null:
			continue
		# What is leaving the bell, which on emergency power is more than the
		# engine's rating -- see EngineInstance.exhaust_flow(). Reading the
		# throttle here instead is exactly how boost managed to look the same
		# as not boosting for a whole milestone.
		# As drawn, not as commanded. See PLUME_AFTERGLOW: a torque jet's
		# throttle is 0 or 1 on any given tick, and a flame following that
		# exactly is a strobe rather than a jet pulsing.
		var flow: float = _afterglow_of(engine, delta)
		plume.visible = flow > PLUME_CUTOFF
		if not plume.visible:
			continue
		plume.rotation = aim
		plume.position = (
			engine.mount.position + exhaust * float(_exits.get(engine.mount.name, 0.0))
		)
		# Four readings of one number, which is the point of driving a look
		# off the machine: the flame is as long, as wide, as bright and as
		# fast as the engine is working. Length is scaled along the sprite's
		# own down, so a quarter throttle is a short flame rather than a
		# faint full-length one -- and a faint full-length one is the halo
		# this project has already been told once it does not want.
		var throttle: float = minf(flow, 1.0)
		var over: float = maxf(flow, 1.0)
		plume.scale = Vector2(
			Art.WORLD_SCALE * pow(over, PLUME_BOOST_WIDTH),
			Art.WORLD_SCALE * lerpf(PLUME_SHORTEST, 1.0, throttle) * over
		)
		plume.self_modulate = Color(1.0, 1.0, 1.0, throttle)
		plume.drive(flow)
		plume.advance(delta)


## The flame this engine is drawing with: straight up to whatever it is
## throwing, and falling away over PLUME_AFTERGLOW when it stops.
func _afterglow_of(engine: EngineInstance, delta: float) -> float:
	var now: float = engine.exhaust_flow()
	var was: float = float(_afterglow.get(engine.mount.name, 0.0))
	var drawn: float = now if now >= was else lerpf(
		was, now, clampf(delta / maxf(PLUME_AFTERGLOW, 0.001), 0.0, 1.0)
	)
	_afterglow[engine.mount.name] = drawn
	return drawn


func _tick_guns(shade: Color) -> void:
	for hardpoint: Hardpoint in ship.hardpoints:
		var gun: StripSprite = _guns.get(hardpoint.name) as StripSprite
		if gun == null:
			continue
		gun.rotation = hardpoint.rotation + hardpoint.facing
		gun.self_modulate = shade


## Legs grow out of the hull as the gear travels.
##
## The strut is stretched along its own length rather than swapped for a
## longer picture, because what is being shown is a leg part-way out and
## there is no sensible number of pictures for "part-way". It is stretched to
## reach the foot exactly, so what the pilot lines up with is where the
## solver will really touch.
func _tick_gear(shade: Color) -> void:
	if ship.gear == null:
		return
	var out: float = ship.gear.extension
	var dim: Color = shade * lerpf(GEAR_DIMMEST, 1.0, out)
	dim.a = 1.0
	for leg: Dictionary in _legs:
		var strut: StripSprite = leg["strut"]
		var pad: StripSprite = leg["pad"]
		strut.visible = out > 0.0
		pad.visible = out > 0.0
		if out <= 0.0:
			continue
		var foot: Vector2 = leg["at"]
		var hip: Vector2 = ship.gear.leg_root(foot)
		var down: Vector2 = foot - hip
		var own: float = maxf(strut.strip.design_size().y, 1.0)
		strut.position = hip
		strut.rotation = _facing(down)
		strut.scale = Vector2(
			Art.WORLD_SCALE, Art.WORLD_SCALE * down.length() * out / own
		)
		strut.self_modulate = dim
		pad.position = hip + down * out
		pad.self_modulate = dim
