class_name Ship
extends RigidBody2D
## A ship: a rigid body plus a set of engine mounts.
##
## Steering is not scripted and engines have no assigned roles. The pilot names
## one of six commands, ShipControl works out from the geometry which engines
## serve it and how strongly, and the solver does the rest. Move an engine and
## its job moves with it; break one and the ship flies crooked, with no code
## anywhere that knows what "crooked" means (see IDEAS.md section 3).
##
## Gravity is applied by the ship itself from nearby bodies (M1.2), never by
## the physics server: gravity_scale stays 0.

## Nose direction in the ship's local frame.
const FORWARD: Vector2 = Vector2.UP

## Points of the hull tested against the terrain bitmap. The engine's own
## collision shape never meets the terrain, because the terrain is not a
## physics body (see IDEAS.md section 6): it is pixels, and these are the
## pixels we ask about. Nose and the two rear corners carry the hull outline,
## the rest stop a long edge from sinking in between corners.
## The shape the simulation uses, in the ship's own frame. Everything
## physical is derived from it and from nothing else: the contact points that
## sample the terrain, the convex shape projectiles hit, the mass, the centre
## of mass and the inertia.
##
## It is an approximation of the drawn hull, not a copy of it. The drawing and
## the shape are two different things; the outline only has to match closely
## enough not to look odd, and otherwise be cheap and predictable for the
## solver. That is why there are guidelines for drawing one -- see the
## configuration report -- rather than a solver clever enough for any shape
## (IDEAS.md section 6).
@export var hull_outline: PackedVector2Array = PackedVector2Array([
	Vector2(0, -12),
	Vector2(-8, 10),
	Vector2(8, 10),
])

## Spacing of the contact points along the outline, in pixels.
##
## Comes from the terrain, not from taste: the crust is 1.5 px per texel, so
## at four texels no terrain feature worth noticing fits between two points.
## A spike narrower than the gap slips between them and the hull either rests
## on nothing or sinks through it.
const CONTACT_STEP: float = 6.0

## Solver passes per tick, at the point count the stock hull has, and the
## ceiling. Sequential impulses converge more slowly the more contacts there
## are, so the passes grow with the outline instead of staying at a number
## chosen for a triangle.
const CONTACT_ITERATIONS: int = 4
const CONTACT_ITERATIONS_MAX: int = 10
const ITERATION_REFERENCE_POINTS: int = 6

## Projectiles are parented to the node in this group, so they stay put in the
## world instead of riding along with the ship that fired them.
const PROJECTILE_GROUP: StringName = &"projectile_container"

## Below this closing speed a contact does not bounce at all, in px/s. Without
## it a resting hull keeps trading tiny impulses with the ground.
const RESTITUTION_CUTOFF: float = 30.0

## Overlap left uncorrected, in pixels, and the fraction of the rest that is
## corrected per tick. Both exist to keep positional correction from pumping
## energy into a resting ship.
const PENETRATION_SLOP: float = 0.5
const PENETRATION_CORRECTION: float = 0.6

## Mass of the bare hull, before any modules. Modules add their mount size on
## top, which is what lets fitting and losing them move the centre of mass.
const HULL_MASS: float = 6.0

## Floor for the angular speed at which kill rotation gives up pulsing and just
## zeroes the spin. The real threshold is computed per tick from the ship's own
## authority, because a single pulse of an impulse engine changes the spin by a
## fixed amount: if the epsilon is smaller than one pulse, every correction
## overshoots and flips the sign, and the assist chatters around zero forever
## instead of finishing. Measured on the stock ship, one pulse is worth about
## 0.04 rad/s, which is twice this floor.
const KILL_ROTATION_EPS: float = 0.02

## Safety factor on that per-pulse estimate.
const KILL_ROTATION_PULSE_MARGIN: float = 1.5

## Angular speed at or above which kill rotation asks for full counter-thrust.
##
## Well under one rad/s on purpose. Because the assist tapers proportionally,
## the spin below this point decays exponentially rather than linearly, and a
## high value spends more time crawling through the last fraction than it did
## killing the first whole radian per second. At 1.0 the stock ship needs about
## two seconds to stop 2 rad/s; at 0.2 it needs under one, which is the bar.
const KILL_ROTATION_GAIN: float = 0.2

## Legs that must be on the ground before a landing is even considered.
const MIN_LEGS_DOWN: int = 2

## How far below a leg the ground may be and still count as touched, in pixels.
##
## Standing for the suspension travel real gear would have, and not optional:
## requiring the legs to be actually buried meant waiting until one of them had
## already been in the rock long enough for the contact solver to tip the ship
## onto it. The landing was then judged on an attitude the landing itself had
## caused, and a level touchdown on flat ground came out 32 degrees off.
const LEG_CONTACT_REACH: float = 5.0

## Damage per px/s of touchdown speed above what the gear can absorb.
const GEAR_OVERLOAD_DAMAGE: float = 0.01

## Below this speed the brake stops the ship outright rather than chasing it.
const BRAKE_EPS: float = 2.0

## The pool a ship has with no generator fitted: capacity, units per second,
## seconds of silence. Deliberately miserable. A ship whose generator was
## swapped out for something that does not fit still shoots, just very badly
## -- the same reason the hold refuses loot rather than losing it. A bad
## module choice should be a poor one, not a state with no way out of it.
const HULL_RAIL_CAPACITY: float = 40.0
const HULL_RAIL_RECHARGE: float = 15.0
const HULL_RAIL_DELAY: float = 1.5

## Below this speed there is no direction of travel to point at, so the
## heading assist does nothing rather than chasing numerical noise.
const HEADING_MIN_SPEED: float = 8.0

## How close counts as pointed, in radians, and the fastest the assist will
## swing the ship. The cap keeps a light ship with strong jets from spinning
## up to something that looks like a fault.
const HEADING_EPS: float = 0.02
const HEADING_MAX_SPIN: float = 2.0

## Heating. The hull warms with the power the air is dissipating, which for
## the linear damping the shells apply goes as density times speed squared.
## Tying it to the same quantity that does the braking is what stops the heat
## bar and the deceleration from telling different stories.
##
## HEAT_REFERENCE_SPEED is the speed at which a full-density atmosphere heats
## at HEAT_RATE per second; HEAT_COOLING is the constant bleed, which also sets
## the floor below which a descent never cooks the hull at all.
const HEAT_REFERENCE_SPEED: float = 300.0
const HEAT_RATE: float = 0.8
const HEAT_COOLING: float = 0.05

## Fired on every terrain impact hard enough to hurt. M1.7 turns this into hull
## HP and death; for now it only accumulates.
signal hull_impact(impact_speed: float, damage: float)

## Flight modes. Being landed is the only state that stops the solver; whether
## the ship is in orbit is read off its trajectory rather than switched on,
## because there is nothing for a mode to do about it (see IDEAS.md section 8).
enum FlightMode { PHYSICAL, LANDED }

## Emitted when the ship touches down or leaves the ground.
signal flight_mode_changed(mode: FlightMode)

## Emitted on a touchdown the gear could not absorb. `reason` is one of
## "speed", "tilt" or "slope", which is what the HUD wants to show.
signal landing_rejected(reason: String)

## Emitted the moment the ship settles on a planet.
signal landed(planet: Planet)

## Emitted when the hull runs out, with the last position and velocity so the
## wreck can be thrown in the right direction.
signal destroyed(at: Vector2, velocity: Vector2)

## Emitted whenever the hull changes, for the HUD.
signal hull_changed(integrity: float)

## Emitted when the hold changes, so the loadout screen can redraw without
## polling.
signal hold_changed(item: Resource)

## The cargo bay changed. Separate from hold_changed because the two answer
## different questions and the editor redraws different panels for each.
signal cargo_changed()

## A shot the pool could not pay for. The HUD flashes; the sound comes with
## VISUALS.
signal shot_refused()

## The pilot threw a module overboard. The world turns it into a crate.
signal jettisoned(item: Resource, rarity: int)

## If true the ship steers itself from the player's input actions. AI ships and
## tests turn this off and write the command fields directly.
@export var use_player_input: bool = true

## Restitution: how much of the closing speed a hard hit gives back. Only
## applied above RESTITUTION_CUTOFF, so a ship sitting on the ground stays.
@export_range(0.0, 1.0) var terrain_bounce: float = 0.15

## Coulomb friction coefficient between hull and rock. Caps the tangential
## impulse at each contact, which is what stops a landed ship sliding downhill.
@export_range(0.0, 2.0) var terrain_friction: float = 0.7

## Impacts slower than this are free. Above it, damage grows with the excess.
@export var damage_speed_threshold: float = 60.0
@export var damage_per_speed: float = 0.004

var engines: Array[EngineInstance] = []
var hardpoints: Array[Hardpoint] = []

## Geometry-derived control groups. Rebuilt on every configuration change.
var control: ShipControl = ShipControl.new()

## What the pilot is asking for, ShipControl.Command -> 0..1. Persistent: input
## refreshes it every tick, an AI or a test writes it once and it holds.
var commands: Dictionary = {}

## What is actually flown this tick: the pilot's commands plus whatever the
## assists add on top, rebuilt from scratch every tick.
##
## Kept separate from `commands` on purpose. When the assists wrote straight
## into the pilot's set, nothing ever cleared their entries for a ship not
## driven by input, so the brake kept pushing after the ship had stopped and
## drove it backwards instead of settling.
var active_commands: Dictionary = {}

## Assist holds, set from input or by an AI.
var kill_rotation_command: bool = false
var brake_command: bool = false

## Which way the heading assist is pointing the nose, if at all. Set from the
## Q+E+W and Q+E+S chords, and left here for an AI to drive the same way.
var heading_command: ControlChords.Chord = ControlChords.Chord.NONE

## Reads the chorded commands off the held keys.
var chords: ControlChords = ControlChords.new()

## Held-down trigger. Read by the weapons every physics tick.
var fire_command: bool = false

## Hull condition, 1.0 intact and 0.0 destroyed.
##
## On the same 0..1 scale as hull_heat and engine health, which is what makes
## the existing damage numbers work unchanged: a 100 px/s scrape costs 0.16, a
## 200 px/s crash costs 0.56, and anything past about 310 px/s is fatal outright.
var hull_integrity: float = 1.0

## Total damage taken since the last respawn, for the readout.
var accumulated_damage: float = 0.0

## Hull heat, 0..1. Climbs while braking against thick air at speed and bleeds
## off in vacuum. M2 turns a full bar into engine damage.
var hull_heat: float = 0.0

## Air density at the hull, 0..1, refreshed every physics tick. Cached here
## because the heat model, the contrails and the HUD all want it and none of
## them should be repeating the planet lookup.
var air_density: float = 0.0

var flight_mode: FlightMode = FlightMode.PHYSICAL

## The landing gear, if this hull has any.
var gear: LandingGear = null

## Why the last touchdown was refused, for the HUD. Empty once landed.
var last_landing_rejection: String = ""

## The one module the ship is carrying loose, and how good it was. One slot,
## not an inventory: a full hold has to be dealt with before the next find,
## which keeps the loadout screen to a single decision (IDEAS.md section 4).
var carried: Resource = null
var carried_rarity: int = 0

## The cargo bay: things stowed for later, measured in the same bulk unit as
## everything else. Not slots -- a capacity -- so "can I take this" is a
## question about the machine rather than about a grid, and a full bay of
## heavy modules is felt in how the ship flies.
##
## Entries are { "item": Resource, "rarity": int }, in the order they were
## stowed. Rarity rides alongside because no module Resource carries it.
var cargo: Array[Dictionary] = []

## Total bulk the cargo bay can hold, before anything a module adds. A
## property of the hull, set in the scene, because how much a ship can carry
## is the first thing that distinguishes a hauler from a fighter.
@export var hull_cargo_capacity: float = 12.0


## What the bay actually holds, hull plus whatever the fitted modules
## contribute. One place to ask, so the editor, the mass sum and the pickup
## check can never disagree about how full the ship is.
##
## Nothing adds to it yet. The line exists because a cargo module is an
## obvious find and the alternative is that `cargo_capacity` stays a constant
## every caller has to remember is not the whole story.
func cargo_capacity() -> float:
	var total: float = stat(&"cargo_capacity", hull_cargo_capacity)
	if generator_bay != null and generator_bay.installed != null:
		# A generator takes room in the hull, not only mass. Nothing else
		# does yet.
		total -= generator_bay.installed.bulk * CARGO_CROWDING
	return maxf(total, 0.0)


## How much of a fitted module's bulk comes out of the cargo bay rather than
## simply being carried. Less than one: machinery is packed into space that
## was never going to hold crates anyway.
const CARGO_CROWDING: float = 0.5

## Ship-wide numbers a module is allowed to change. A key outside this list
## is a typo in an affix table, and a typo that silently does nothing passes
## every test anyone will write -- so it is an error, loudly.
const STATS: Array[StringName] = [
	&"energy_capacity",
	&"energy_recharge",
	&"energy_delay",
	&"cargo_capacity",
]

## key -> { "add": float, "mul": float }, and key -> the modules behind it.
## Both recomputed at every refit and never per frame: a number worked out
## each tick is a number the configuration report cannot show.
var stats: Dictionary = {}
var stat_sources: Dictionary = {}

## Energy in the pool, and how long since the last spend. Combat's clock:
## it refills itself, is never bought, and cannot be saved up
## (IDEAS.md section 14).
var energy: float = 0.0
var _since_spend: float = 0.0

## The bay, if the hull has one. Found at ready like the other mounts.
var generator_bay: GeneratorBay = null

## Contact points along the outline, without the gear's. Built once.
var _outline_contacts: Array[Vector2] = []

## Where the cargo sits, in the ship's frame. Placed on the stock centre of
## mass on purpose: a bay anywhere else would make loading up a balance fault
## as well as a mass gain, and nagging the pilot for picking things up would
## teach them to ignore the configuration report. Loading is felt as
## sluggishness, not as a warning.
const CARGO_BAY: Vector2 = Vector2(0.0, 1.75)


var _landed_planet: Planet = null
var _landed_angle: float = 0.0
var _landed_radius: float = 0.0
var _landed_heading: float = 0.0

var _applied_force: Vector2 = Vector2.ZERO
var _applied_torque: float = 0.0
var _gravity: Vector2 = Vector2.ZERO
var _terrain_contacts: int = 0


func _ready() -> void:
	for child: Node in get_children():
		if child is Hardpoint:
			hardpoints.append(child as Hardpoint)
		elif child is GeneratorBay:
			generator_bay = child as GeneratorBay
		elif child is LandingGear:
			gear = child as LandingGear
	# Set once here rather than at every landing: it never changes, and writing
	# it from _integrate_forces would be another state change the server
	# refuses mid-flush.
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	# Both derived from the outline, before anything asks for either.
	_build_contact_points()
	_build_collision_shape()
	rebuild_control_groups()
	# A ship starts charged. The rebuild above only clamps downwards, so
	# without this a fresh hull would come out of the yard unable to fire.
	energy = energy_capacity()
	_since_spend = energy_recharge_delay()


## Every engine mount on the hull, fitted or empty.
func engine_mounts() -> Array[EngineMount]:
	var mounts: Array[EngineMount] = []
	for child: Node in get_children():
		var mount: EngineMount = child as EngineMount
		if mount != null:
			mounts.append(mount)
	return mounts


## True if `mount` will take this engine: the right kind, and small enough to
## go in the slot. The slot is the mount's business, so ask the mount.
func mount_accepts(mount: EngineMount, data: EngineData) -> bool:
	if mount == null:
		return false
	return mount.fits(data)


## Bolts `data` into `mount` and hands back whatever came out, or hands `data`
## straight back if the mount will not take it.
##
## Rebuilds the control groups, because fitting an engine changes the mass,
## the centre of mass and what every command can do -- which is the whole
## point of engines being loot.
func fit_engine(mount: EngineMount, data: EngineData) -> EngineData:
	if not mount_accepts(mount, data):
		return data
	var previous: EngineData = mount.installed
	mount.installed = data
	rebuild_control_groups(false)
	return previous


## Takes a loose module into the hold. Returns false when the hold is full,
## which is the caller's cue to tell the pilot rather than to lose the item.
func take(item: Resource, rarity: int) -> bool:
	if carried != null or item == null:
		return false
	carried = item
	carried_rarity = rarity
	hold_changed.emit(carried)
	return true


## How big any module is, whichever kind it is. The one place that knows
## that both module Resources answer to the same field.
static func module_bulk(item: Resource) -> float:
	var module: ModuleData = item as ModuleData
	return module.bulk if module != null else 0.0


func cargo_used() -> float:
	var total: float = 0.0
	for entry: Dictionary in cargo:
		total += module_bulk(entry["item"] as Resource)
	return total


func cargo_free() -> float:
	return maxf(cargo_capacity() - cargo_used(), 0.0)


## Moves what is in the hold into the bay. Fails, rather than overfilling,
## when there is no room: the bay is the constraint, not a suggestion.
##
## Rebuilds the control groups, because cargo is mass and mass is handling.
func stow() -> bool:
	if carried == null or module_bulk(carried) > cargo_free():
		return false
	cargo.append({"item": carried, "rarity": carried_rarity})
	carried = null
	carried_rarity = 0
	rebuild_control_groups(false)
	hold_changed.emit(null)
	cargo_changed.emit()
	return true


## Moves one thing out of the bay and into the hold, which must be empty.
func retrieve(index: int) -> bool:
	if carried != null or index < 0 or index >= cargo.size():
		return false
	var entry: Dictionary = cargo[index]
	cargo.remove_at(index)
	carried = entry["item"]
	carried_rarity = int(entry["rarity"])
	rebuild_control_groups(false)
	hold_changed.emit(carried)
	cargo_changed.emit()
	return true


## Throws what is in the hold overboard. Announced rather than destroyed: who
## turns it back into a crate in the world is the world's business, and a
## jettison that annihilates the cargo is not a tactical decision, it is
## tidying up.
func jettison() -> Resource:
	if carried == null:
		return null
	var item: Resource = carried
	var rarity: int = carried_rarity
	release()
	jettisoned.emit(item, rarity)
	return item


## Empties the hold and returns what was in it.
func release() -> Resource:
	var item: Resource = carried
	carried = null
	carried_rarity = 0
	hold_changed.emit(null)
	return item


## What this configuration can do, and what is wrong with it. Built fresh
## rather than cached: it is asked for on a rebuild and on a swap, both of
## which have just invalidated any stored answer.
func configuration() -> ConfigurationReport:
	return ConfigurationReport.of(self)


## Re-reads the fitted engines, recomputes mass, centre of mass and inertia,
## and rebuilds the control groups from the new geometry.
##
## Must be called after anything that changes the configuration: fitting or
## removing a module, or a change in mass. Not after damage: health is
## deliberately left out of the group maths so a broken engine shows up as a
## crooked ship rather than being quietly compensated for.
func rebuild_control_groups(verbose: bool = true) -> void:
	# Condition survives the rebuild. An EngineInstance is a pairing the ship
	# throws away and remakes on every refit, so without this, bolting on any
	# module anywhere would quietly repair every engine on the hull -- a free
	# repair bench in the swap screen.
	#
	# Carried by mount, and only while the same engine is still in it. An
	# engine moved to another socket comes up fresh, which is the one case
	# this gets wrong; call it bench time.
	var carried: Dictionary = {}
	for engine: EngineInstance in engines:
		carried[engine.mount.name] = {"data": engine.data, "health": engine.health}

	engines.clear()
	for child: Node in get_children():
		var mount: EngineMount = child as EngineMount
		if mount != null and mount.installed != null:
			var instance: EngineInstance = EngineInstance.new(mount.installed, mount)
			var previous: Dictionary = carried.get(mount.name, {})
			if previous.get("data") == mount.installed:
				instance.health = float(previous["health"])
			engines.append(instance)

	_aggregate_stats()
	_recompute_mass_properties()
	control.rebuild(engines, center_of_mass, mass, inertia)
	# Fitting a smaller generator must not leave the pool holding more than
	# the new one can. Topping it up on a swap is the other way round and
	# would make refitting a free reload.
	energy = minf(energy, energy_capacity())

	if verbose:
		var report: PackedStringArray = configuration().lines()
		print("%s: %s" % [name, report[0]])
		for line: String in report.slice(1):
			print("  " + line)


## Mass, centre of mass and inertia from the hull plus the fitted modules.
##
## The hull is treated as a uniform lamina over its collision polygon, so the
## numbers follow the shape instead of being guessed; modules are point masses
## at their mounts. The body is switched to a custom centre of mass because the
## default one ignores the modules entirely, and every torque in the control
## maths is measured from it.
func _recompute_mass_properties() -> void:
	var polygon: PackedVector2Array = _hull_polygon()
	var hull_centroid: Vector2 = _polygon_centroid(polygon)
	var hull_inertia: float = _polygon_inertia(polygon, HULL_MASS, hull_centroid)

	var total_mass: float = HULL_MASS
	var weighted: Vector2 = hull_centroid * HULL_MASS
	for engine: EngineInstance in engines:
		var module: float = engine.mount.module_mass()
		total_mass += module
		weighted += engine.mount.position * module

	# Cargo is mass like anything else. A hold full of engines is a slower
	# ship, which is the price of hoarding and the reason to choose.
	var load: float = cargo_used()
	total_mass += load
	weighted += CARGO_BAY * load

	if generator_bay != null:
		var bay_mass: float = generator_bay.module_mass()
		total_mass += bay_mass
		weighted += generator_bay.position * bay_mass

	var centre: Vector2 = weighted / maxf(total_mass, 0.0001)

	# Parallel axis theorem: the hull's own inertia about its centroid, shifted
	# to the combined centre, plus each module as a point mass.
	var total_inertia: float = hull_inertia + HULL_MASS * hull_centroid.distance_squared_to(centre)
	for engine: EngineInstance in engines:
		total_inertia += engine.mount.module_mass() * engine.mount.position.distance_squared_to(centre)
	total_inertia += load * CARGO_BAY.distance_squared_to(centre)
	if generator_bay != null:
		total_inertia += generator_bay.module_mass() * generator_bay.position.distance_squared_to(
			centre
		)

	mass = total_mass
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centre
	inertia = maxf(total_inertia, 0.0001)


func _hull_polygon() -> PackedVector2Array:
	var shape_node: CollisionShape2D = get_node_or_null("HullShape") as CollisionShape2D
	if shape_node != null:
		var convex: ConvexPolygonShape2D = shape_node.shape as ConvexPolygonShape2D
		if convex != null and convex.points.size() >= 3:
			return convex.points
	# The outline is the source; the shape above is derived from it and this
	# is only the path taken before _ready has run.
	return hull_outline


func _polygon_centroid(polygon: PackedVector2Array) -> Vector2:
	var area: float = 0.0
	var centroid: Vector2 = Vector2.ZERO
	for i: int in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var cross: float = a.cross(b)
		area += cross
		centroid += (a + b) * cross
	if absf(area) < 0.0001:
		return Vector2.ZERO
	return centroid / (3.0 * area)


## Mass moment of inertia of a uniform polygon about its own centroid.
func _polygon_inertia(polygon: PackedVector2Array, polygon_mass: float, centroid: Vector2) -> float:
	var area: float = 0.0
	var moment: float = 0.0
	for i: int in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var cross: float = a.cross(b)
		area += cross
		moment += cross * (a.dot(a) + a.dot(b) + b.dot(b))
	area *= 0.5
	if absf(area) < 0.0001:
		return polygon_mass
	# moment/12 is the polar second moment of AREA about the origin; multiplying
	# by the areal density turns it into a mass moment, then the parallel axis
	# theorem shifts it to the centroid.
	var about_origin: float = (moment / 12.0) * (polygon_mass / area)
	return maxf(about_origin - polygon_mass * centroid.length_squared(), 0.0001)


## Weapons fire here and not in _integrate_forces: that callback runs while the
## physics server is flushing queries, and adding nodes to the tree from inside
## it is not allowed.
## Input is polled here rather than in _integrate_forces, and so is the decision
## to leave the ground. A frozen body gets no _integrate_forces at all, so a
## landed ship that only listened there could never be told to take off again.
func _physics_process(delta: float) -> void:
	if use_player_input:
		read_player_input(delta)
		fire_command = Input.is_action_pressed("ship_fire")
		if Input.is_action_just_pressed("toggle_gear") and gear != null:
			gear.set_deployed(not gear.is_deployed() and not gear.is_moving())

	if gear != null:
		gear.advance(delta)
		# Deployed legs only bite in air. Scaling by density rather than
		# switching on a boolean keeps the speed brake worthless in vacuum,
		# where a drag penalty would be nonsense.
		linear_damp = gear.deployed_drag * gear.extension * air_density

	if flight_mode == FlightMode.LANDED:
		if _wants_translation(commands) or brake_command:
			take_off()
		else:
			_hold_landed_pose()

	_recharge(delta)

	var container: Node = projectile_container()
	for hardpoint: Hardpoint in hardpoints:
		hardpoint.tick(delta)
		if not fire_command or not hardpoint.can_fire():
			continue
		# Charged before fired: a shot either comes out whole or does not come
		# out. Half a shot is unreadable and breaks every affix reckoned on
		# damage (IDEAS.md section 14).
		# The mounted cost, not the bare weapon's: mods are paid for at the
		# trigger, which is the whole reason they cost energy at all.
		if not spend_energy(hardpoint.energy_cost()):
			# Announced, not silent. A trigger that does nothing and says
			# nothing reads as a stuck key (IDEAS.md section 14).
			shot_refused.emit()
			continue
		hardpoint.fire(linear_velocity, container, self)


## Every module bolted to the hull, with the name to blame in a report.
func fitted_modules() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child: Node in get_children():
		var mount: EngineMount = child as EngineMount
		if mount != null and mount.installed != null:
			out.append({"name": child.name, "module": mount.installed})
		var hardpoint: Hardpoint = child as Hardpoint
		if hardpoint != null and hardpoint.weapon != null:
			out.append({"name": child.name, "module": hardpoint.weapon})
		var bay: GeneratorBay = child as GeneratorBay
		if bay != null and bay.installed != null:
			out.append({"name": child.name, "module": bay.installed})
	return out


## A ship-wide number with every module's say in it: base, plus every
## addition, then times every multiplier. Sums first, so a multiplier acts on
## the whole ship rather than on whatever was fitted before it.
func stat(key: StringName, base: float) -> float:
	var entry: Dictionary = stats.get(key, {})
	return (base + float(entry.get("add", 0.0))) * float(entry.get("mul", 1.0))


func _aggregate_stats() -> void:
	stats = {}
	stat_sources = {}
	for key: StringName in STATS:
		stats[key] = {"add": 0.0, "mul": 1.0}
		stat_sources[key] = []

	for entry: Dictionary in fitted_modules():
		var module: ModuleData = entry["module"]
		for key: StringName in module.stat_add:
			if _record_stat(key, entry["name"], "add", float(module.stat_add[key])):
				stats[key]["add"] = float(stats[key]["add"]) + float(module.stat_add[key])
		for key: StringName in module.stat_mul:
			if _record_stat(key, entry["name"], "mul", float(module.stat_mul[key])):
				stats[key]["mul"] = float(stats[key]["mul"]) * float(module.stat_mul[key])


## Whether `key` is a stat modules may touch. Split out so the gate can be
## checked without firing the error: a test that makes push_error go off is a
## test that fails the build, since check.ps1 scans the run for errors.
static func knows_stat(key: StringName) -> bool:
	return STATS.has(key)


func _record_stat(key: StringName, source: String, kind: String, value: float) -> bool:
	if not knows_stat(key):
		push_error("%s: module %s changes unknown stat '%s'" % [name, source, key])
		return false
	(stat_sources[key] as Array).append({"module": source, "kind": kind, "value": value})
	return true


## The generator fitted, or null when running on the hull's own rail.
func generator() -> GeneratorData:
	return generator_bay.installed if generator_bay != null else null


func energy_capacity() -> float:
	var fitted: GeneratorData = generator()
	return stat(&"energy_capacity", fitted.capacity if fitted != null else HULL_RAIL_CAPACITY)


func energy_recharge_rate() -> float:
	var fitted: GeneratorData = generator()
	return stat(
		&"energy_recharge", fitted.recharge_rate if fitted != null else HULL_RAIL_RECHARGE
	)


func energy_recharge_delay() -> float:
	var fitted: GeneratorData = generator()
	return maxf(stat(
		&"energy_delay", fitted.recharge_delay if fitted != null else HULL_RAIL_DELAY
	), 0.0)


## True while the pool is waiting out the silence rather than filling. The
## HUD needs the two apart: a bar that is stopped and a bar that is climbing
## mean different things to a pilot deciding whether to hold the trigger.
func energy_waiting() -> bool:
	return _since_spend < energy_recharge_delay() and energy < energy_capacity()


## Takes `cost` from the pool if all of it is there, and returns whether it
## was. Every spend pushes the recharge back, which is what makes firing and
## charging mutually exclusive.
func spend_energy(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if energy < cost:
		return false
	energy -= cost
	_since_spend = 0.0
	return true


func _recharge(delta: float) -> void:
	var capacity: float = energy_capacity()
	_since_spend += delta
	if _since_spend < energy_recharge_delay():
		return
	energy = minf(energy + energy_recharge_rate() * delta, capacity)


## Where fired rounds are parented. Falls back to the ship's own parent so a
## ship dropped into a bare scene (a test, a preview) still shoots.
func projectile_container() -> Node:
	var container: Node = get_tree().get_first_node_in_group(PROJECTILE_GROUP)
	if container != null:
		return container
	return get_parent()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if flight_mode == FlightMode.LANDED:
		return

	_resolve_commands(state)
	control.apply_commands(engines, active_commands)
	for engine: EngineInstance in engines:
		engine.advance(state.step)
		engine.mount.set_exhaust(engine.effective_output())

	_applied_force = Vector2.ZERO
	_applied_torque = 0.0

	# Gravity is summed from the bodies in range rather than left to the
	# physics server, so the falloff can be ours (see IDEAS.md section 5).
	_gravity = gravity_acceleration_at(state.transform.origin)
	state.apply_central_force(_gravity * mass)

	var body_rotation: float = state.transform.get_rotation()
	for engine: EngineInstance in engines:
		var local_force: Vector2 = engine.current_force()
		if local_force.is_zero_approx():
			continue
		# Confirmed against the 4.7 docs: apply_force()'s position is "the
		# offset from the body origin in global coordinates". From the ORIGIN,
		# not the centre of mass, so the mount position is only rotated, never
		# shifted. The server takes the torque about the centre of mass itself,
		# which is why center_of_mass has to be right for any of this to work.
		var force: Vector2 = local_force.rotated(body_rotation)
		var offset: Vector2 = engine.mount.position.rotated(body_rotation)
		state.apply_force(force, offset)
		_applied_force += force
		_applied_torque += (engine.mount.position - center_of_mass).rotated(body_rotation).cross(force)

	_resolve_terrain(state)
	_update_heat(state.step)


## Hull heating from braking against the air.
func _update_heat(step: float) -> void:
	var planet: Planet = nearest_planet()
	air_density = planet.air_density_at(global_position) if planet != null else 0.0

	if air_density > 0.0:
		var speed_ratio: float = linear_velocity.length() / HEAT_REFERENCE_SPEED
		hull_heat += air_density * speed_ratio * speed_ratio * HEAT_RATE * step
	hull_heat = clampf(hull_heat - HEAT_COOLING * step, 0.0, 1.0)


## True if any command in `command_set` would translate the ship rather than
## turn it. Lift-off asks this: a landed ship may aim freely, but the moment it
## is told to move it has to be handed back to the solver.
func _wants_translation(command_set: Dictionary) -> bool:
	for command: ShipControl.Command in ShipControl.LINEAR_COMMANDS:
		if float(command_set.get(command, 0.0)) > 0.001:
			return true
	return false


## Resolves every hull point that is inside rock.
##
## Each contact gets its own impulse applied at its own offset from the centre
## of mass, which is what makes the ship pivot: touch down on one rear corner
## and the impulse there spins the ship about that corner, exactly as it should.
## An aggregated central response cannot do that no matter how it is tuned.
##
## Runs after the engine forces because it has the last word: it edits the
## velocity, the spin and the transform directly.
func _resolve_terrain(state: PhysicsDirectBodyState2D) -> void:
	_terrain_contacts = 0

	var planet: Planet = nearest_planet()
	if planet == null:
		return

	var body_transform: Transform2D = state.transform
	var points: Array[Vector2] = []
	var normals: Array[Vector2] = []
	var deepest: float = 0.0
	var deepest_normal: Vector2 = Vector2.ZERO
	## Where the worst of it landed, in the ship's own frame. Kept so the
	## damage can fall on the engines that were actually there.
	var deepest_local: Vector2 = Vector2.ZERO

	# Before the impulses, while the approach speed and attitude are still the
	# ones the pilot flew rather than ones the first bounce produced.
	if _try_land(state, planet):
		return

	var local_points: Array[Vector2] = contact_points()
	for i: int in range(local_points.size()):
		var world_point: Vector2 = body_transform * local_points[i]
		if not planet.is_solid_at(world_point):
			continue
		var point_normal: Vector2 = planet.surface_normal_at(world_point)
		if point_normal.is_zero_approx():
			continue
		points.append(world_point)
		normals.append(point_normal)
		var depth: float = planet.penetration_at(world_point, point_normal, penetration_limit())
		if depth > deepest:
			deepest = depth
			deepest_normal = point_normal
			deepest_local = local_points[i]

	_terrain_contacts = points.size()
	if _terrain_contacts == 0:
		return

	# Torque comes from the lever arm to the centre of mass, not to the origin.
	# On this hull they are ~3 px apart, which is enough to matter.
	var centre_of_mass: Vector2 = body_transform.origin + state.center_of_mass
	var impact_speed: float = _apply_contact_impulses(state, planet, centre_of_mass, points, normals)

	# Positional correction is deliberately partial and leaves a sliver of
	# overlap. Pushing the hull fully clear every tick adds height that gravity
	# then gives back, and the ship hops along the ground forever.
	if deepest > PENETRATION_SLOP:
		body_transform.origin += deepest_normal * ((deepest - PENETRATION_SLOP) * PENETRATION_CORRECTION)
		state.transform = body_transform

	if impact_speed > damage_speed_threshold:
		var damage: float = (impact_speed - damage_speed_threshold) * damage_per_speed
		hull_impact.emit(impact_speed, damage)
		take_damage(damage, "impact")
		# The engines nearest where it struck take it. Landing on a jet is
		# supposed to be a different mistake from landing on the nose.
		damage_engines_near(deepest_local, damage)


## Solves the contacts with sequential impulses and returns the hardest
## approach speed seen, for the damage model.
##
## Several passes because the contacts are coupled: an impulse at the nose
## changes the closing speed at the tail. Four is plenty for six points.
func _apply_contact_impulses(
	state: PhysicsDirectBodyState2D,
	planet: Planet,
	centre_of_mass: Vector2,
	points: Array[Vector2],
	normals: Array[Vector2],
) -> float:
	var inverse_mass: float = state.inverse_mass
	var inverse_inertia: float = state.inverse_inertia
	var hardest: float = 0.0

	for iteration: int in range(contact_iterations()):
		for i: int in range(points.size()):
			var arm: Vector2 = points[i] - centre_of_mass
			var normal: Vector2 = normals[i]
			# Everything here is measured against the GROUND, not the world.
			# The rock at this point is moving if the planet turns, and a
			# solver that does not know it drives the hull to a standstill in
			# world space instead -- which is the planet sliding out from
			# under a ship that looks parked (IDEAS.md section 7).
			var ground: Vector2 = planet.surface_velocity_at(points[i])
			var relative: Vector2 = _velocity_at(state, arm) - ground

			var closing: float = relative.dot(normal)
			if closing >= 0.0:
				continue
			if iteration == 0:
				hardest = maxf(hardest, -closing)

			var normal_arm: float = arm.cross(normal)
			var normal_mass: float = inverse_mass + normal_arm * normal_arm * inverse_inertia
			if normal_mass <= 0.0:
				continue

			# Bounce only above a cutoff. Keeping restitution at a resting
			# contact is the other half of why the ship never stopped hopping.
			var restitution: float = terrain_bounce if -closing > RESTITUTION_CUTOFF else 0.0
			var normal_impulse: float = -(1.0 + restitution) * closing / normal_mass
			_apply_impulse_at(state, normal * normal_impulse, arm, inverse_mass, inverse_inertia)

			# Coulomb friction along the surface, capped by the normal impulse.
			var tangent: Vector2 = Vector2(-normal.y, normal.x)
			# Re-read after the normal impulse, and again against the ground.
			var sliding: float = (_velocity_at(state, arm) - ground).dot(tangent)
			var tangent_arm: float = arm.cross(tangent)
			var tangent_mass: float = inverse_mass + tangent_arm * tangent_arm * inverse_inertia
			if tangent_mass <= 0.0:
				continue
			var limit: float = terrain_friction * normal_impulse
			var friction_impulse: float = clampf(-sliding / tangent_mass, -limit, limit)
			_apply_impulse_at(state, tangent * friction_impulse, arm, inverse_mass, inverse_inertia)

	return hardest


## Velocity of the hull at an offset from the centre of mass.
func _velocity_at(state: PhysicsDirectBodyState2D, arm: Vector2) -> Vector2:
	return state.linear_velocity + state.angular_velocity * Vector2(-arm.y, arm.x)


func _apply_impulse_at(
	state: PhysicsDirectBodyState2D,
	impulse: Vector2,
	arm: Vector2,
	inverse_mass: float,
	inverse_inertia: float,
) -> void:
	state.linear_velocity += impulse * inverse_mass
	state.angular_velocity += arm.cross(impulse) * inverse_inertia


## Points tested against the terrain: the hull always, the legs once they are
## fully out. The legs are appended last so the contact loop can tell which
## contacts were made on them.
func contact_points() -> Array[Vector2]:
	var points: Array[Vector2] = _outline_contacts.duplicate()
	if gear != null:
		points.append_array(gear.contact_points())
	return points


## Vertices of the outline plus a point every CONTACT_STEP along each edge,
## worked out once rather than per tick.
func _build_contact_points() -> void:
	_outline_contacts.clear()
	var outline: PackedVector2Array = hull_outline
	if outline.size() < 3:
		return
	for i: int in range(outline.size()):
		var from: Vector2 = outline[i]
		var to: Vector2 = outline[(i + 1) % outline.size()]
		_outline_contacts.append(from)
		# Ceil, not floor: the spacing has to come out at or under the step,
		# and rounding down would leave the longest edges under-sampled --
		# which is exactly where a spike would slip through.
		var segments: int = maxi(1, ceili(from.distance_to(to) / CONTACT_STEP))
		for step: int in range(1, segments):
			_outline_contacts.append(from.lerp(to, float(step) / float(segments)))


## The convex shape projectiles hit, built from the same outline the terrain
## sampling uses. One source, so what a bullet hits and what touches the
## ground can never drift apart.
func _build_collision_shape() -> void:
	var shape_node: CollisionShape2D = get_node_or_null("HullShape") as CollisionShape2D
	if shape_node == null or hull_outline.size() < 3:
		return
	var convex: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
	convex.points = Geometry2D.convex_hull(hull_outline)
	shape_node.shape = convex


## How many solver passes this hull needs. More contacts couple more tightly,
## so a bigger outline gets more work rather than a softer landing.
func contact_iterations() -> int:
	var points: int = maxi(_outline_contacts.size(), 1)
	return clampi(
		ceili(float(CONTACT_ITERATIONS) * float(points) / float(ITERATION_REFERENCE_POINTS)),
		CONTACT_ITERATIONS,
		CONTACT_ITERATIONS_MAX,
	)


## How deep the terrain probe should look for this hull. A larger, faster
## ship buries itself further in one tick, and a fixed ceiling would saturate
## and leave the correction quietly under-doing it.
func penetration_limit() -> float:
	return maxf(PlanetTerrain.MAX_PENETRATION, hull_extent() * 2.0)


## Half the longest span of the outline: the ship's own idea of how big it is.
func hull_extent() -> float:
	var extent: float = 0.0
	for point: Vector2 in hull_outline:
		extent = maxf(extent, point.length())
	return extent


## Decides whether a touchdown is a landing, and does it.
##
## Nothing here is scripted difficulty: every threshold is a gear stat, and the
## ship either meets them or does not. Returns true when the ship has landed,
## in which case the caller must not also apply contact impulses.
func _try_land(state: PhysicsDirectBodyState2D, planet: Planet) -> bool:
	if gear == null or not gear.is_deployed():
		return false
	# Not while burning. Without this a ship that has just lifted off is still
	# sitting on its legs at zero descent, meets every condition, and lands
	# again on the same tick, so it can never leave.
	if _wants_translation(active_commands) or brake_command:
		return false

	var legs_down: int = 0
	for clearance: float in ground_under_legs(planet, state.transform):
		if clearance <= LEG_CONTACT_REACH:
			legs_down += 1
	# Nothing is touching yet, so there is nothing to judge.
	if legs_down == 0:
		return false

	var up: Vector2 = (state.transform.origin - planet.global_position).normalized()
	var slope: float = slope_under_legs(planet, state.transform)
	# Derived from the height field rather than probed out of the bitmap. The
	# probe ring needs to straddle a surface, and a leg resting a few pixels
	# into the rock has most of its ring inside: it reported a level shelf as a
	# 55 degree wall and refused every landing. Taking the normal from the same
	# slope the check already measures cannot disagree with it either.
	var normal: Vector2 = up.rotated(-slope)
	# Measured against the ground, which is moving on a spinning planet: what
	# matters is the speed relative to the rock, not to the planet's centre.
	var relative: Vector2 = state.linear_velocity - planet.surface_velocity_at(state.transform.origin)
	var descent: float = -relative.dot(up)
	var lateral: float = absf(relative.dot(up.orthogonal()))

	var over_descent: float = descent - gear.max_vertical_speed
	var over_lateral: float = lateral - gear.max_lateral_speed
	if over_descent > 0.0 or over_lateral > 0.0:
		_reject_landing("speed")
		# Not binary: the legs take the overshoot as damage and the ship stays
		# in the air's hands, rather than the landing simply not happening.
		var excess: float = maxf(over_descent, 0.0) + maxf(over_lateral, 0.0)
		var damage: float = excess * GEAR_OVERLOAD_DAMAGE
		hull_impact.emit(descent, damage)
		take_damage(damage, "gear")
		# Straight down through the legs, so it is the tail end that suffers.
		damage_engines_near(_gear_point(), damage)
		return false

	# Attitude is judged on the first leg to touch, not once they all have.
	# They never all would: at an 18 px track and 3 px of travel, two legs can
	# only be down together if the ship is within about ten degrees of level,
	# so waiting for both made a fifteen degree tolerance unreachable and the
	# check dead code. Refusing early also gives the pilot a reason instead of
	# an unexplained tumble.
	var ship_up: Vector2 = FORWARD.rotated(state.transform.get_rotation())
	if absf(ship_up.angle_to(normal)) > gear.max_tilt:
		_reject_landing("tilt")
		return false

	# Standing on one leg is not standing.
	if legs_down < MIN_LEGS_DOWN:
		return false

	# Measured across the legs, which is the ground they actually have to stand
	# on. A shorter span is no good here: over 12 px on a 1.5 px texel grid a
	# single step between texels reads as a cliff.
	if absf(slope) > gear.max_slope:
		_reject_landing("slope")
		return false

	_settle_on(planet, state)
	return true


## Clearance between each leg and the ground directly beneath it, in pixels.
## Negative means the leg is already in the rock.
##
## Sampled per leg rather than through the ship's centre. A two point slope
## taken across the hull can read as perfectly level while the ship sits astride
## a ridge, because both samples land on the flanks and neither sees the crest
## between them. Asking each leg about its own patch cannot be fooled that way,
## and it is what IDEAS.md section 7 specifies anyway.
func ground_under_legs(planet: Planet, from: Transform2D) -> Array[float]:
	var clearances: Array[float] = []
	if gear == null:
		return clearances
	for leg: Vector2 in gear.legs:
		var leg_point: Vector2 = from * leg
		clearances.append(
			leg_point.distance_to(planet.global_position) - planet.surface_radius_at(leg_point)
		)
	return clearances


## Ground slope across the outermost legs, in radians, signed along the line
## from the first leg to the last.
func slope_under_legs(planet: Planet, from: Transform2D) -> float:
	if gear == null or gear.legs.size() < 2:
		return 0.0
	var first_leg: Vector2 = gear.legs[0]
	var last_leg: Vector2 = gear.legs[gear.legs.size() - 1]
	var first: Vector2 = from * first_leg
	var last: Vector2 = from * last_leg
	var run: float = first.distance_to(last)
	if run < 0.001:
		return 0.0
	var rise: float = planet.surface_radius_at(last) - planet.surface_radius_at(first)
	return atan2(rise, run) * signf(last_leg.x - first_leg.x)


func _reject_landing(reason: String) -> void:
	if last_landing_rejection == reason:
		return
	last_landing_rejection = reason
	landing_rejected.emit(reason)


## Pins the ship to the ground in the planet's polar frame.
##
## Stored as (angle, radius, heading relative to the planet) rather than as a
## world transform, so a turning planet carries the ship with it. The ship is
## deliberately NOT reparented to the planet: IDEAS.md section 9 requires the
## player to stay a direct child of the world, because systems are streamed in
## and out underneath it.
func _settle_on(planet: Planet, state: PhysicsDirectBodyState2D) -> void:
	var offset: Vector2 = state.transform.origin - planet.global_position
	_landed_planet = planet
	_landed_angle = offset.angle() - planet.global_rotation
	_landed_radius = offset.length()
	_landed_heading = state.transform.get_rotation() - planet.global_rotation

	state.linear_velocity = Vector2.ZERO
	state.angular_velocity = 0.0
	# Deferred, because this runs inside _integrate_forces and freezing is a
	# change to the body's state in the physics server, which refuses it while
	# it is flushing queries. The same trap as spawning a projectile from here.
	# One tick passes before it takes hold, which costs nothing: flight_mode is
	# already LANDED, so _integrate_forces bails out and applies no gravity, and
	# the velocity has just been zeroed.
	set_deferred("freeze", true)

	last_landing_rejection = ""
	flight_mode = FlightMode.LANDED
	flight_mode_changed.emit(flight_mode)
	landed.emit(planet)


## Keeps a landed ship glued to its patch of ground as the planet turns.
func _hold_landed_pose() -> void:
	if _landed_planet == null or not is_instance_valid(_landed_planet):
		flight_mode = FlightMode.PHYSICAL
		freeze = false
		return
	# The angle stays in the planet's own frame: polar_to_world runs it through
	# to_global(), which already applies the planet's rotation. Adding the
	# rotation here as well turned a parked ship into one sliding across the
	# ground at twice the surface speed.
	global_position = _landed_planet.polar_to_world(_landed_angle, _landed_radius)
	global_rotation = _landed_heading + _landed_planet.global_rotation


## Releases the ship from the ground, carrying the surface velocity with it so
## lift-off from a spinning planet does not start with a jolt.
func take_off(state: PhysicsDirectBodyState2D = null) -> void:
	if flight_mode != FlightMode.LANDED:
		return
	var surface_velocity: Vector2 = Vector2.ZERO
	if _landed_planet != null and is_instance_valid(_landed_planet):
		surface_velocity = _landed_planet.surface_velocity_at(global_position)

	freeze = false
	flight_mode = FlightMode.PHYSICAL
	_landed_planet = null
	if state != null:
		state.linear_velocity = surface_velocity
	else:
		linear_velocity = surface_velocity
	flight_mode_changed.emit(flight_mode)


## How far from an impact an engine still feels it, in the ship's own frame.
## About the width of the hull: a hit is local, but not to the pixel.
const ENGINE_DAMAGE_RADIUS: float = 16.0

## Engine health lost per point of hull damage, at the point of impact. Above
## one on purpose -- machinery is more fragile than structure, and a ship
## that always dies before its engines do has no damage model worth the name.
const ENGINE_DAMAGE_SHARE: float = 1.6


## Hurts the engines around `point` (in the ship's frame) in proportion to
## how close they are to it.
##
## Nothing here rebuilds the control groups. That is the whole design: the
## groups are built from nominal thrust, so a half-dead engine is not
## compensated for and the ship flies crooked until the pilot finds a flight
## computer that will do the compensating (IDEAS.md section 3).
func damage_engines_near(point: Vector2, severity: float) -> void:
	if severity <= 0.0:
		return
	for engine: EngineInstance in engines:
		var reach: float = engine.mount.position.distance_to(point) / ENGINE_DAMAGE_RADIUS
		if reach >= 1.0:
			continue
		engine.health = clampf(
			engine.health - severity * ENGINE_DAMAGE_SHARE * (1.0 - reach), 0.0, 1.0
		)


## Where the legs meet the ground, in the ship's frame -- the gear node if
## the hull has one, the bottom of the hull otherwise.
func _gear_point() -> Vector2:
	if gear != null:
		return gear.position
	return Vector2(0.0, 10.0)


## Puts every engine back into new condition. The repair key for now; a bench
## at a station later.
func repair_engines() -> void:
	for engine: EngineInstance in engines:
		engine.health = 1.0


## The worst-off engine, for the HUD and the configuration report.
func worst_engine_health() -> float:
	var worst: float = 1.0
	for engine: EngineInstance in engines:
		worst = minf(worst, engine.health)
	return worst


## Takes damage from any source. The single door in, so that every way of
## hurting the ship shares the death path rather than each inventing its own.
## `cause` is not used yet. It is here because M2 wants damage to fall on the
## part that took it, and the call sites that know the answer are these.
func take_damage(amount: float, cause: String = "") -> void:
	if amount <= 0.0 or hull_integrity <= 0.0:
		return
	var _taken_by: String = cause
	accumulated_damage += amount
	hull_integrity = maxf(hull_integrity - amount, 0.0)
	hull_changed.emit(hull_integrity)
	if hull_integrity <= 0.0:
		_destroy()


func is_destroyed() -> bool:
	return hull_integrity <= 0.0


func _destroy() -> void:
	# The ship is not freed. Everything points at it, the camera, the HUD, the
	# contrails, the debug layer, and re-instantiating would mean rewiring all
	# of it on every death in a game whose whole point is dying often. The world
	# puts it back together in place instead.
	if flight_mode == FlightMode.LANDED:
		set_deferred("freeze", false)
		flight_mode = FlightMode.PHYSICAL
		_landed_planet = null
	destroyed.emit(global_position, linear_velocity)


## Puts a wrecked ship back in the air, intact and empty-handed.
##
## Resets everything a death should clear rather than only the obvious parts:
## leaving the heat, the gear or a stale landing rejection behind would have the
## new ship inherit the old one's problems.
func respawn(at: Vector2, velocity: Vector2) -> void:
	hull_integrity = 1.0
	accumulated_damage = 0.0
	hull_heat = 0.0
	last_landing_rejection = ""
	commands.clear()
	active_commands.clear()
	kill_rotation_command = false
	heading_command = ControlChords.Chord.NONE
	brake_command = false
	fire_command = false
	energy = energy_capacity()
	_since_spend = energy_recharge_delay()
	repair_engines()
	for engine: EngineInstance in engines:
		engine.throttle = 0.0
		engine.target_throttle = 0.0
		engine.mount.set_exhaust(0.0)
	if gear != null:
		gear.set_deployed(false)
		gear.extension = 0.0

	flight_mode = FlightMode.PHYSICAL
	_landed_planet = null
	freeze = false
	global_position = at
	global_rotation = velocity.angle() - PI * 0.5 if not velocity.is_zero_approx() else 0.0
	linear_velocity = velocity
	angular_velocity = 0.0
	# Without this the interpolator draws a streak from where the wreck died to
	# where the new ship appeared.
	reset_physics_interpolation()

	hull_changed.emit(hull_integrity)
	flight_mode_changed.emit(flight_mode)


## How many hull points were inside rock last tick.
func get_terrain_contacts() -> int:
	return _terrain_contacts


## Closest planet, or null if there is none in the scene.
func nearest_planet() -> Planet:
	return Planet.nearest(get_tree(), global_position)


## Gravitational acceleration the ship felt last tick. Not get_gravity(),
## which is already taken by PhysicsBody2D.
func get_applied_gravity() -> Vector2:
	return _gravity


## Sums the pull of every gravity source that reaches `point`.
func gravity_acceleration_at(point: Vector2) -> Vector2:
	var total: Vector2 = Vector2.ZERO
	for source: Node in get_tree().get_nodes_in_group(Planet.GRAVITY_GROUP):
		var planet: Planet = source as Planet
		if planet != null:
			total += planet.gravity_at(point)
	return total


## Total force applied by the engines last tick, in global coordinates.
func get_applied_force() -> Vector2:
	return _applied_force


## Total torque applied by the engines last tick.
func get_applied_torque() -> float:
	return _applied_torque


## Ship speed along its own nose direction. Negative means flying backwards.
func get_forward_speed() -> float:
	return linear_velocity.dot(FORWARD.rotated(global_rotation))


## Fills the command set from the input actions. Only action names here, never
## keycodes. Called from _physics_process, see the note there.
func read_player_input(delta: float) -> void:
	commands.clear()

	# Chords first: a key taken over by one must not also be read as the
	# command it usually means.
	var chord: ControlChords.Chord = chords.update(ControlChords.poll(), delta)
	var taken: Array[StringName] = chords.consumed()

	_set_command(ShipControl.Command.FORWARD, _strength(&"thrust_forward", taken))
	_set_command(ShipControl.Command.BACK, _strength(&"thrust_reverse", taken))
	_set_command(ShipControl.Command.CCW, _strength(&"rotate_left", taken))
	_set_command(ShipControl.Command.CW, _strength(&"rotate_right", taken))
	_set_command(ShipControl.Command.STRAFE_LEFT, _strength(&"strafe_left", taken))
	_set_command(ShipControl.Command.STRAFE_RIGHT, _strength(&"strafe_right", taken))

	kill_rotation_command = chord == ControlChords.Chord.KILL_ROTATION
	heading_command = chord
	if chord == ControlChords.Chord.KILL_ROTATION:
		heading_command = ControlChords.Chord.NONE
	brake_command = Input.is_action_pressed("brake")


func _strength(action: StringName, taken: Array[StringName]) -> float:
	return 0.0 if taken.has(action) else Input.get_action_strength(action)


func _set_command(command: ShipControl.Command, amount: float) -> void:
	if amount > 0.0:
		commands[command] = amount


## Adds whatever the two assists are asking for on top of the pilot's commands.
func _resolve_commands(state: PhysicsDirectBodyState2D) -> void:
	active_commands = commands.duplicate()
	if kill_rotation_command:
		_apply_kill_rotation(state)
	if heading_command != ControlChords.Chord.NONE:
		_apply_heading_hold(state)
	if brake_command:
		_apply_brake(state)


## Cancels spin by asking for the opposite rotation, proportionally.
##
## Below the epsilon the spin is zeroed outright: impulse engines are all or
## nothing, so chasing the last hundredth of a radian with them oscillates
## forever instead of converging.
func _apply_kill_rotation(state: PhysicsDirectBodyState2D) -> void:
	var spin: float = state.angular_velocity
	var opposing: ShipControl.Command = (
		ShipControl.Command.CCW if spin > 0.0 else ShipControl.Command.CW
	)

	# Derived rather than fixed, so retuning the torque jets cannot silently
	# reintroduce the chatter this guards against.
	var per_pulse: float = control.authority_of(opposing) / maxf(inertia, 0.0001) * state.step
	var epsilon: float = maxf(KILL_ROTATION_EPS, per_pulse * KILL_ROTATION_PULSE_MARGIN)
	if absf(spin) <= epsilon:
		state.angular_velocity = 0.0
		return
	var amount: float = clampf(absf(spin) / KILL_ROTATION_GAIN, 0.0, 1.0)
	active_commands[opposing] = maxf(float(active_commands.get(opposing, 0.0)), amount)


## Swings the nose onto the direction of travel, or onto its opposite.
##
## Velocity is measured against the ground, the same frame the landing check
## and the contact solver use, so a ship parked on a turning planet reads as
## stopped rather than as drifting east at eight pixels a second. In orbit
## that differs from the true orbital prograde by the surface speed, a few
## degrees at most; when M2's auto-orbit needs better it will work from the
## orbital elements rather than from this.
##
## Bang-bang rather than a pair of tuned gains: aim for the fastest spin that
## can still be stopped by the time the nose arrives, which is the same
## time-to-kill shape the brake uses and needs no constants that would go
## stale the next time the torque jets change.
func _apply_heading_hold(state: PhysicsDirectBodyState2D) -> void:
	var travel: Vector2 = state.linear_velocity
	var planet: Planet = nearest_planet()
	if planet != null:
		travel -= planet.surface_velocity_at(global_position)
	if travel.length() < HEADING_MIN_SPEED:
		return
	if heading_command == ControlChords.Chord.RETROGRADE:
		travel = -travel

	# Where the ship must be rotated to for its nose to lie along `travel`.
	var wanted: float = angle_difference(
		state.transform.get_rotation(), travel.angle() - FORWARD.angle()
	)
	var spin: float = state.angular_velocity

	var toward: ShipControl.Command = (
		ShipControl.Command.CW if wanted > 0.0 else ShipControl.Command.CCW
	)
	var alpha: float = control.authority_of(toward) / maxf(inertia, 0.0001)
	if alpha <= 0.0:
		return

	# Arrive with no spin left: the fastest approach speed from which the
	# remaining angle is still enough room to stop in.
	var cruise: float = signf(wanted) * minf(sqrt(2.0 * alpha * absf(wanted)), HEADING_MAX_SPIN)
	var change: float = cruise - spin
	if absf(wanted) <= HEADING_EPS and absf(spin) <= HEADING_EPS:
		state.angular_velocity = 0.0
		return

	var command: ShipControl.Command = (
		ShipControl.Command.CW if change > 0.0 else ShipControl.Command.CCW
	)
	var reach: float = control.authority_of(command) / maxf(inertia, 0.0001) * state.step
	var amount: float = clampf(absf(change) / maxf(reach, 0.0001), 0.0, 1.0)
	active_commands[command] = maxf(float(active_commands.get(command, 0.0)), amount)


## Kills linear velocity by pushing against it, one axis at a time.
##
## Rotation is left alone entirely: brake is for stopping, aiming stays the
## pilot's job. A direction with no engines behind it simply is not braked, so
## a ship with no reverse thruster cannot stop itself going forward. That is
## the intended consequence of building the groups from geometry, not a gap.
func _apply_brake(state: PhysicsDirectBodyState2D) -> void:
	var local_velocity: Vector2 = state.linear_velocity.rotated(-state.transform.get_rotation())
	if local_velocity.length() < BRAKE_EPS:
		state.linear_velocity = Vector2.ZERO
		return

	# Each pair is (what fights a negative component, what fights a positive
	# one). Forward is -Y, so drifting forward is negative and wants BACK;
	# drifting right is +X and wants STRAFE_LEFT. Getting the second pair the
	# wrong way round made the brake push the ship harder in the direction it
	# was already sliding.
	_brake_axis(
		local_velocity.y,
		ShipControl.Command.BACK,
		ShipControl.Command.FORWARD,
	)
	_brake_axis(
		local_velocity.x,
		ShipControl.Command.STRAFE_RIGHT,
		ShipControl.Command.STRAFE_LEFT,
	)


## One velocity component against the group that opposes it.
##
## `opposes_negative` is the command that pushes against a negative component,
## `opposes_positive` against a positive one. Named for what they fight rather
## than for their own direction, because the two read the same at a glance and
## the pair for the sideways axis was written backwards. The throttle
## is the time the group would need to kill this component, clamped to one
## second, so it holds full thrust while there is real speed to shed and eases
## off over the last stretch instead of overshooting into a wobble.
func _brake_axis(
	component: float, opposes_negative: ShipControl.Command, opposes_positive: ShipControl.Command
) -> void:
	if is_zero_approx(component):
		return
	var command: ShipControl.Command = opposes_negative if component < 0.0 else opposes_positive
	var authority: float = control.authority_of(command)
	if authority <= 0.0:
		return
	var amount: float = clampf(absf(component) * mass / authority, 0.0, 1.0)
	active_commands[command] = maxf(float(active_commands.get(command, 0.0)), amount)
