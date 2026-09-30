class_name StarSystem
extends RefCounted
## One star system, laid out from one number.
##
## Pure data, like everything in the model half of IDEAS.md section 9. The
## system exists whether or not a single node has been instantiated for it;
## the scene is only the part of it the player happens to be near.
##
## Nothing here is hand-placed and nothing is random at read time: the same
## seed gives the same star, the same planets in the same orbits, with the
## same names. A save is the galaxy seed plus a dictionary of deltas, so a
## system that generated differently on the second visit would take the save
## file down with it.

## How many planets a system can have.
const PLANET_COUNT: Vector2i = Vector2i(3, 5)

## The star, as a radius in pixels and a surface gravity in px/s^2.
##
## Together they set mu, and mu sets how long a year is. Chosen from travel
## time rather than from astronomy: at these numbers an inner planet goes
## round in some four minutes and a ship needs around 650 px/s to circle it,
## so a hop between neighbours is tens of seconds under thrust rather than
## an errand.
const STAR_RADIUS: Vector2 = Vector2(6000.0, 11000.0)
const STAR_GRAVITY: Vector2 = Vector2(260.0, 460.0)

## Where the innermost planet sits, as a multiple of the star's radius, and
## how much further out each next one is.
##
## Multiplicative rather than additive, which is roughly what real systems
## do and is also the cheapest guarantee that no two orbits cross: every gap
## is wider than the one inside it, so the ordering cannot invert however
## the rolls land.
const FIRST_ORBIT: Vector2 = Vector2(2.6, 3.4)
const ORBIT_STEP: Vector2 = Vector2(1.45, 1.85)

## The gap every planet keeps from whatever is inside it, on top of both
## bodies' own reach: the outer planet's gravity well at its narrowest
## possible roll.
##
## A multiplier alone does not guarantee this. Two neighbours that both
## rolled large and both kept a moon can want more room than the smallest
## step leaves, and a generator that only avoids collisions on most seeds
## is a generator with a bug waiting for a seed. So the step is what a
## planet asks for and this is what it gets at minimum.
##
## Wells are allowed to overlap further out, and should: a slingshot
## between two bodies is a thing the design wants (IDEAS.md section 9).
## What is not allowed is one planet sitting inside another's well.

## A moon's orbit, as a multiple of its parent's radius.
##
## The ceiling is the part that matters. A planet's well is only
## `Planet.INFLUENCE_RATIO.x` radii wide at its narrowest roll, and a moon
## orbiting outside its parent's gravity is a moon the player watches fall
## away. Kept under that floor with room to spare, because the planet rolls
## its own well and the layout never sees the roll.
const MOON_ORBIT: Vector2 = Vector2(2.0, 3.0)
const MOON_RADIUS: Vector2 = Vector2(350.0, 620.0)
const MOON_CHANCE: float = 0.45

## Only a world with room around it gets one.
const MOON_PARENT_RADIUS: float = 1300.0

## Docks. One always, and sometimes a second out in the dark between orbits.
const STATION_RADIUS: Vector2 = Vector2(55.0, 110.0)
const STATION_ORBIT_RATIO: float = 2.4
const DEEP_STATION_CHANCE: float = 0.4

## Syllables a system's name is built from. Short on purpose: the name has to
## fit an edge-of-screen marker at 640x360.
const NAME_HEAD: Array[String] = [
	"Vel", "Kor", "Ash", "Tor", "Mira", "Cal", "Yren", "Sol", "Dra", "Pha",
]
const NAME_TAIL: Array[String] = [
	"is", "ath", "un", "ex", "or", "ai", "eth", "ur", "ane", "ix",
]

var seed: int = 0
var display_name: String = "system"
var star: SystemBody = null

## Every body including the star, in the order they were made, so a caller
## that wants all of them does not have to walk the tree.
var bodies: Array[SystemBody] = []


## Builds a system from its seed. The only way to make one.
static func generate(system_seed: int) -> StarSystem:
	var system: StarSystem = StarSystem.new()
	system.seed = system_seed
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = system_seed
	system.display_name = "%s%s" % [
		NAME_HEAD[rng.randi() % NAME_HEAD.size()],
		NAME_TAIL[rng.randi() % NAME_TAIL.size()],
	]

	system.star = SystemBody.new()
	system.star.kind = SystemBody.Kind.STAR
	system.star.seed = derive(system_seed, 0)
	system.star.display_name = system.display_name
	system.star.radius = rng.randf_range(STAR_RADIUS.x, STAR_RADIUS.y)
	system.star.surface_gravity = rng.randf_range(STAR_GRAVITY.x, STAR_GRAVITY.y)
	system.bodies.append(system.star)

	var orbit: float = system.star.radius * rng.randf_range(FIRST_ORBIT.x, FIRST_ORBIT.y)
	var inner: SystemBody = null
	for index: int in range(rng.randi_range(PLANET_COUNT.x, PLANET_COUNT.y)):
		inner = system._add_planet(rng, index, orbit, inner)
		orbit = inner.orbit_radius * rng.randf_range(ORBIT_STEP.x, ORBIT_STEP.y)

	system._add_stations(rng)
	return system


## Derives a child seed from a parent's seed and an index.
##
## Written out rather than left to hash(), because "reproducible from the
## seed" is a promise made to every save file and hash() on a built-in is a
## promise the engine only makes to itself. This is splitmix64, masked back
## to positive after each step: GDScript shifts arithmetically, so a value
## that has wrapped negative would drag sign bits down through the mix.
##
## The three constants are splitmix64's, written as the signed decimals
## Godot can parse -- 0x9E37..., 0xBF58... and 0x94D0... are all above
## 2^63 and rejected as hex literals.
const MIX_GOLDEN: int = -7046029254386353131
const MIX_A: int = -4658895280553007687
const MIX_B: int = -7723592293110705685
const MIX_MASK: int = 0x7FFFFFFFFFFFFFFF


static func derive(parent_seed: int, index: int) -> int:
	var value: int = (parent_seed + (index + 1) * MIX_GOLDEN) & MIX_MASK
	value = ((value ^ (value >> 30)) * MIX_A) & MIX_MASK
	value = ((value ^ (value >> 27)) * MIX_B) & MIX_MASK
	return (value ^ (value >> 31)) & MIX_MASK


## The body with this name, or null. For tools and tests; the game walks
## `bodies`.
func find(wanted: String) -> SystemBody:
	for body: SystemBody in bodies:
		if body.display_name == wanted:
			return body
	return null


## How far the outermost thing in the system reaches from the star.
##
## The number the floating-origin decision is waiting on. Godot's float32
## positions start shaking somewhere past a hundred thousand units, and
## whether a system needs a moving origin is a question about this number
## and nothing else.
func outer_radius() -> float:
	var out: float = star.radius
	for body: SystemBody in star.children:
		out = maxf(out, body.extent())
	return out


func planets() -> Array[SystemBody]:
	return of_kind(SystemBody.Kind.PLANET)


func of_kind(kind: SystemBody.Kind) -> Array[SystemBody]:
	var out: Array[SystemBody] = []
	for body: SystemBody in bodies:
		if body.kind == kind:
			out.append(body)
	return out


## Rolls a planet, gives it whatever moon it gets, and only then decides
## where it goes -- because where it can go depends on how far it reaches,
## and how far it reaches depends on the moon.
func _add_planet(
	rng: RandomNumberGenerator, index: int, wanted: float, inner: SystemBody
) -> SystemBody:
	var planet: SystemBody = SystemBody.new()
	planet.kind = SystemBody.Kind.PLANET
	planet.seed = derive(seed, index + 1)
	# Lettered from b, the way a catalogue does it: the star is a.
	planet.display_name = "%s %s" % [display_name, char(98 + index)]
	planet.radius = rng.randf_range(Planet.RADIUS_RANGE.x, Planet.RADIUS_RANGE.y)
	planet.surface_gravity = rng.randf_range(Planet.GRAVITY_RANGE.x, Planet.GRAVITY_RANGE.y)
	planet.set_parent_body(star)
	star.children.append(planet)
	bodies.append(planet)

	if planet.radius >= MOON_PARENT_RADIUS and rng.randf() < MOON_CHANCE:
		_add_moon(rng, planet)

	var floor_orbit: float = 0.0
	if inner != null:
		floor_orbit = inner.orbit_radius + _reach_of(inner) + _reach_of(planet) 			+ Planet.INFLUENCE_RATIO.x * planet.radius
	planet.orbit_radius = maxf(wanted, floor_orbit)
	planet.orbit_phase = rng.randf() * TAU
	planet.orbit_period = star.period_for(planet.orbit_radius)
	return planet


## How much room a body needs around its own centre.
##
## Its moon if it has one, and space for a dock whether it has one or not:
## stations are handed out after the orbits are laid, and a planet that grew
## a station afterwards would have been placed too close to its neighbour.
## Reserving for both sides is why this is a function and not a local -- the
## planet inside has to have been given the same allowance.
static func _reach_of(body: SystemBody) -> float:
	return maxf(
		body.extent() - body.orbit_radius,
		STATION_ORBIT_RATIO * body.radius + STATION_RADIUS.y,
	)


func _add_moon(rng: RandomNumberGenerator, planet: SystemBody) -> void:
	var moon: SystemBody = SystemBody.new()
	moon.kind = SystemBody.Kind.MOON
	moon.seed = derive(planet.seed, 1)
	moon.display_name = "%s I" % planet.display_name
	moon.radius = rng.randf_range(MOON_RADIUS.x, MOON_RADIUS.y)
	moon.surface_gravity = rng.randf_range(
		Planet.GRAVITY_RANGE.x, Planet.GRAVITY_RANGE.y * 0.6
	)
	moon.set_parent_body(planet)
	moon.orbit_radius = planet.radius * rng.randf_range(MOON_ORBIT.x, MOON_ORBIT.y)
	moon.orbit_phase = rng.randf() * TAU
	moon.orbit_period = planet.period_for(moon.orbit_radius)
	planet.children.append(moon)
	bodies.append(moon)


func _add_stations(rng: RandomNumberGenerator) -> void:
	var hosts: Array[SystemBody] = planets()
	if hosts.is_empty():
		return
	var host: SystemBody = hosts[rng.randi() % hosts.size()]
	_add_station(
		rng, host, host.radius * STATION_ORBIT_RATIO, "%s Dock" % host.display_name
	)
	if rng.randf() < DEEP_STATION_CHANCE:
		# Out in the dark between two orbits, which is where a station with
		# nothing to orbit but the star belongs.
		_add_station(
			rng, star, outer_radius() * rng.randf_range(0.5, 0.9),
			"%s Reach" % display_name,
		)


func _add_station(
	rng: RandomNumberGenerator, host: SystemBody, orbit: float, named: String
) -> void:
	var station: SystemBody = SystemBody.new()
	station.kind = SystemBody.Kind.STATION
	station.seed = derive(host.seed, bodies.size())
	station.display_name = named
	station.radius = rng.randf_range(STATION_RADIUS.x, STATION_RADIUS.y)
	# A station has no well worth the name: you dock with it, you do not
	# orbit it, and a gravity source this small would only add noise to the
	# ship's own solver.
	station.surface_gravity = 0.0
	station.set_parent_body(host)
	station.orbit_radius = orbit
	station.orbit_phase = rng.randf() * TAU
	station.orbit_period = host.period_for(orbit)
	host.children.append(station)
	bodies.append(station)
