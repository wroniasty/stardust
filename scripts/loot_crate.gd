class_name LootCrate
extends Area2D
## A module lying on a planet, waiting to be flown into.
##
## The crate holds what the generator rolled for it, not a promise to roll
## something later: a container is its seed, and the seed is spent when the
## world builds it, so the same planet always offers the same finds (see
## IDEAS.md section 4).
##
## Parented to the planet rather than to the world, so it turns with the
## ground it sits on and a pilot who leaves and comes back finds it where
## they left it.

## Emitted when a ship touches the crate. The crate does not decide whether
## the ship can take it -- the hold might be full -- so it waits to be told.
signal touched(crate: LootCrate, body: Node)

## Every crate joins this, so anything that wants to find loot -- the scanner
## now, salvage and cargo later -- asks the group rather than walking the
## planet's children. The same shape as GravityWell.GROUP, and for the same
## reason: the day crates stop hanging off planets, one line changes.
const LOOT_GROUP: StringName = &"loot"

## What is inside. Rarity comes off the module itself now, so a crate
## cannot be painted a different colour from the thing in it.
var item: Resource = null

## The one list, on ModuleData. Kept here as a name because the scanner and
## the editor already say LootCrate.RARITY_COLORS and there is no reason for
## them to care where it moved to.
const RARITY_COLORS: Array[Color] = ModuleData.RARITY_COLORS

## Half the crate's body. The body polygon is twelve pixels across, so
## anything that touches rock six pixels from the centre has touched it.
const RADIUS: float = 6.0

## How much of the closing speed the ground gives back, and how much of the
## sideways slide it takes away. A crate is a box, not a ball: it should hop
## once and stop, not roll down the mountain.
const BOUNCE: float = 0.25
const FRICTION: float = 0.55

## Relative speed below which a crate in contact stops being simulated and
## becomes part of the ground it is lying on.
const SETTLE_SPEED: float = 9.0

## Clearance at which a woken crate decides the ground really has gone.
## Terrain gets carved by explosions, and a crate left hanging over a fresh
## crater is a box standing in mid-air.
const DISLODGE: float = 2.0

## How hard the air holds a crate back, as a fraction of its speed through
## the air per second at full density.
##
## Not the ship's drag shells: those are engine damping on a RigidBody2D and
## a crate integrates itself. The point is only that a crate dropped from
## height flutters down instead of arriving like a shell -- at a surface
## gravity around 30 px/s^2 this settles it at some sixty px/s.
const AIR_DRAG: float = 0.5

## How the crate is moving, in world space. Meaningful only while loose.
var velocity: Vector2 = Vector2.ZERO

## Whether the crate is being integrated.
##
## A crate the world builder put on a shelf is already where it belongs, and
## running a solver on a box that is not going anywhere is a solver spent on
## nothing. Ejecting one makes it loose; touching down settles it again.
var loose: bool = false

## Which body's shelf this crate was put on, and which shelf.
##
## Carried by the crate rather than tracked beside it: the streaming
## manager has to know which shelf went empty, and the thing that knows
## that best is the crate that was standing on it. -1 for a crate nobody
## placed, such as one thrown overboard.
var origin_seed: int = 0
var shelf: int = -1

## Seconds before the crate will answer a ship at all. A jettisoned module
## is dropped by a ship that is still sitting on top of it, and without this
## the pilot picks it straight back up in the same frame -- which turns
## throwing something overboard into a no-op.
var grace: float = 0.0:
	set(value):
		grace = value
		# Nothing to count down means nothing to run. _process fires on every
		# rendered frame, which is more often than physics.
		set_process(grace > 0.0)

@onready var _body: Polygon2D = $Body
@onready var _glow: Polygon2D = $Glow


func _ready() -> void:
	add_to_group(LOOT_GROUP)
	body_entered.connect(_on_body_entered)
	# Both driven by state rather than left on: a settled crate with nothing
	# to count down costs exactly nothing, which is what "settled" claims.
	set_physics_process(loose)
	set_process(grace > 0.0)
	# The ground it is lying on says when it stops being there.
	var ground: Planet = get_parent() as Planet
	if ground != null:
		ground.carved.connect(_on_ground_carved)
	_paint()


## Fills the crate. Called by whoever placed it, before it enters the tree or
## right after.
func hold(new_item: Resource, new_rarity: int = -1) -> void:
	item = new_item
	# Told, or asked. A caller that knows better may still say so; one that
	# just found the thing does not have to remember to.
	if new_rarity >= 0 and new_item is ModuleData:
		(new_item as ModuleData).rarity = new_rarity
	if is_node_ready():
		_paint()


## How good what is inside is, or the dullest grade when there is nothing.
## The colour this crate is painted, which is the one thing readable from
## orbit. Exposed so a test can check the crate and the grade agree rather
## than re-deriving the lookup and agreeing with itself.
func rarity_color_of() -> Color:
	return RARITY_COLORS[clampi(rarity(), 0, RARITY_COLORS.size() - 1)]


func rarity() -> int:
	var module: ModuleData = item as ModuleData
	return module.rarity if module != null else 0


## What the pilot is told they have found.
func label() -> String:
	if item == null:
		return "empty crate"
	if item is WeaponData:
		return (item as WeaponData).display_name
	if item is EngineData:
		return "%s engine" % EngineData.Type.keys()[(item as EngineData).type].to_lower()
	return "module"


func _paint() -> void:
	if _body == null:
		return
	var colour: Color = RARITY_COLORS[clampi(rarity(), 0, RARITY_COLORS.size() - 1)]
	_body.color = colour
	_glow.color = Color(colour.r, colour.g, colour.b, 0.25)


func _process(delta: float) -> void:
	if grace <= 0.0:
		return
	grace = maxf(grace - delta, 0.0)
	if grace <= 0.0:
		# Whoever was standing in it while it was inert has to be noticed now,
		# or a crate dropped and left alone would stay invisible to a ship
		# that never re-entered the area.
		for body: Node2D in get_overlapping_bodies():
			touched.emit(self, body)
		set_process(false)


func _on_body_entered(body: Node2D) -> void:
	if grace > 0.0:
		return
	touched.emit(self, body)


## Throws the crate, in world space. Whoever ejected it decides where it
## goes; the crate only knows how to fall once it is on its way.
func eject(from: Vector2, with_velocity: Vector2) -> void:
	global_position = from
	velocity = with_velocity
	loose = true
	set_physics_process(true)


## One step, no substepping.
##
## A crate cannot fall through the ground because contact is measured
## radially -- how far the crate is above the ground beneath it -- rather
## than by asking whether this particular point is inside rock. To miss the
## crust that way it would have to cross all two hundred-odd pixels of it
## between two frames, which is thirteen thousand px/s. Substeps were
## written first and measured second: at 1200 px/s they bought two tenths of
## a pixel of penetration, and code that buys that is code to delete.
##
## The bound worth knowing: a crate flying sideways faster than the terrain
## sampling is fine, could still pass over a spire narrower than one step.
## Nothing in the game throws a crate anywhere near hard enough.
func _physics_process(delta: float) -> void:
	if not loose:
		return
	var planet: Planet = Planet.nearest(get_tree(), global_position)
	# The same sum a ship makes, through the same function, so a crate and
	# the ship that dropped it never fall differently. One thrown in deep
	# space keeps going; one thrown near the star drifts towards it.
	velocity += GravityWell.pull_at(get_tree(), global_position) * delta
	if planet != null:
		var air: float = planet.air_density_at(global_position)
		if air > 0.0:
			# Towards the air's own speed, not towards a standstill: the
			# atmosphere turns with the planet it belongs to.
			var through: Vector2 = velocity - planet.surface_velocity_at(global_position)
			velocity -= through * minf(AIR_DRAG * air * delta, 1.0)
	global_position += velocity * delta
	if planet != null:
		_resolve_ground(planet)



func _resolve_ground(planet: Planet) -> void:
	var clearance: float = planet.height_above_terrain(global_position) - RADIUS
	if clearance >= 0.0:
		return
	var normal: Vector2 = planet.surface_normal_at(global_position)
	if normal.is_zero_approx():
		normal = (global_position - planet.global_position).normalized()
	# Out of the rock first, speeds second. The other order leaves the crate
	# a frame inside the ground, and a frame inside the ground reads as a
	# crate that sank.
	global_position -= normal * clearance

	# Measured against the ground, not against the world. The rock is moving
	# on a planet that turns, and a crate brought to a standstill in world
	# space is a crate the ground slides out from under -- the same mistake
	# the ship's contact solver was fixed for (IDEAS.md section 7).
	var ground: Vector2 = planet.surface_velocity_at(global_position)
	var relative: Vector2 = velocity - ground
	var into: float = relative.dot(normal)
	if into < 0.0:
		relative -= normal * into * (1.0 + BOUNCE)
	relative -= (relative - normal * relative.dot(normal)) * FRICTION
	velocity = ground + relative
	if relative.length() < SETTLE_SPEED:
		_settle(planet)


## Lays the crate on the ground and stops solving it. Standing up as well as
## standing still: a crate on a slope should look like it is on the slope.
func _settle(planet: Planet) -> void:
	loose = false
	velocity = Vector2.ZERO
	set_physics_process(false)
	var up: Vector2 = (global_position - planet.global_position).normalized()
	if up.is_zero_approx():
		return
	global_position = planet.global_position + up * (
		planet.surface_radius_at(global_position) + RADIUS
	)
	global_rotation = up.angle() + PI * 0.5


## A settled crate is part of the ground until the ground stops being there,
## and the ground is what tells it. Polling for this cost 1.3 us per crate
## per tick -- eighty per cent of what a settled crate cost at all -- to
## watch for something that happens when a shell lands.
func _on_ground_carved(point: Vector2, radius: float) -> void:
	if loose:
		return
	# Only a hole near enough to be under this crate is worth looking at.
	if global_position.distance_to(point) > radius + RADIUS * 2.0:
		return
	var ground: Planet = get_parent() as Planet
	if ground == null:
		return
	if ground.height_above_terrain(global_position) - RADIUS > DISLODGE:
		loose = true
		set_physics_process(true)
