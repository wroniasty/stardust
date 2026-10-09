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

## How big the star is, and how heavy. Both rolled, which they were not:
## the mass used to be derived from the planets and came out so small that
## the star pulled four hundredths of a pixel per second squared where
## anyone flies -- a tenth of a per cent of what a ship feels. See
## `_well_limit` for why that derivation had to go.
##
## The radius came down with it, from six to eleven thousand. A star that
## wide is never a disc on a 640x360 screen, only a wall you eventually
## run into, and it was wide in the first place to carry mass that is now
## carried by the gravity instead. At three thousand you can see it curve.
const STAR_RADIUS: Vector2 = Vector2(2600.0, 4800.0)
const STAR_GRAVITY: Vector2 = Vector2(45.0, 110.0)

## Where the innermost planet sits, in pixels, and how much further out
## each next one is.
##
## Absolute rather than a multiple of the star's radius, now that the
## radius no longer stands in for the mass. Tying the whole system's scale
## to how fat the star looked was a leftover: it meant a heavy star and a
## wide one were the same thing, and shrinking one shrank the system.
##
## The step is multiplicative, which is roughly what real systems do and
## is also the cheapest guarantee that no two orbits cross: every gap is
## wider than the one inside it, so the ordering cannot invert however the
## rolls land.
const FIRST_ORBIT: Vector2 = Vector2(14000.0, 22000.0)
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
## The ceiling is the part that matters. A planet is only guaranteed
## `WELL_FLOOR` radii of well -- that is the whole point of the floor --
## and a moon orbiting outside its parent's gravity is a moon the player
## watches fall away. Kept under the floor with room for the moon's own
## radius on top, because the moon is placed before the layout knows how
## much well its parent ended up with.
const MOON_ORBIT: Vector2 = Vector2(1.8, 2.4)
const MOON_RADIUS: Vector2 = Vector2(350.0, 620.0)
const MOON_CHANCE: float = 0.45

## Only a world with room around it gets one.
const MOON_PARENT_RADIUS: float = 1300.0

## How far past everything in the system the star holds a ship down, as a
## multiple of the outermost thing orbiting it.
##
## How far from a body a ship has to be before the drive will light, as a
## multiple of that body's own radius and measured from its centre.
##
## **This replaces the mass lock**, which was 1.5 times the whole
## system's outer radius and measured out at 72000 to 504000 px across
## 300 seeds. Against a view 582 px wide at the widest zoom, that is a
## hundred and twenty to nearly nine hundred screens of holding one key:
## the old note called a sprawling system "a nuisance to leave", and the
## honest word is a waiting simulator. Nothing about a jump was being
## decided during that climb.
##
## So the rule is local. A body holds you down while you are near it,
## and 2.5 of its own radius is what "near it" means -- a thousand-pixel
## planet lets go fifteen hundred pixels above its surface, which is
## about three screens and five seconds of burn. A dock at 55 to 110 px
## lets go almost at once, which is right: pushing off is leaving.
##
## Scaled by the body rather than flat, so a gas giant is a longer push
## than a moon. That is the same shape as every other reach in this
## project and it keeps one number where a table would otherwise grow.
const JUMP_CLEARANCE: float = 2.5

## And how wide of a body the lane to the destination has to pass, as a
## multiple of that body's radius.
##
## The other half of the rule, and the half that makes where you stand
## matter rather than only how far out you are: a drive pointed through a
## planet has nowhere to put the ship. A quarter of the body's own size
## as margin, because the lane is a corridor a hull flies down and not a
## mathematical line.
const LANE_CLEARANCE: float = 1.25

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


## How far an interstellar sector reaches, in pixels.
##
## It has no star and nothing orbiting, so there is nothing to measure
## against and the number is simply chosen: about a quarter of a small
## system, which is far enough that arriving at one edge and leaving
## from the other is a flight rather than a formality.
const VOID_REACH: float = 24000.0

## Nothing, somewhere between two somewheres.
##
## IDEAS.md section 10's misjump: an interstellar sector, a "system"
## with no star. Everything that asks a system a question has to cope
## with one of these, which is less work than it sounds -- the streaming
## manager already null-checked `star`, because a system with none was
## always going to turn up eventually.
##
## No star means no mass lock, which is the one mercy here: a pilot who
## has fallen out of the lane is stranded by their tank, not by a
## gravity well. Whether there is enough left to leave is a different
## question, and the one the sector is actually about.
static func deep_space(sector_seed: int) -> StarSystem:
	var system: StarSystem = StarSystem.new()
	system.seed = sector_seed
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = sector_seed
	system.display_name = "pustka %s%s" % [
		NAME_HEAD[rng.randi() % NAME_HEAD.size()],
		NAME_TAIL[rng.randi() % NAME_TAIL.size()],
	]
	return system


## Whether this is a real system or the gap between two of them.
func is_deep_space() -> bool:
	return star == null


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

	var orbit: float = rng.randf_range(FIRST_ORBIT.x, FIRST_ORBIT.y)
	var inner: SystemBody = null
	for index: int in range(rng.randi_range(PLANET_COUNT.x, PLANET_COUNT.y)):
		inner = system._add_planet(rng, index, orbit, inner)
		orbit = inner.orbit_radius * rng.randf_range(ORBIT_STEP.x, ORBIT_STEP.y)

	system._add_stations(rng)
	system._set_periods()
	# A fifth past the outermost orbit. Last, because it is the only well
	# in the system that is a question about everything else: the star has
	# to still be pulling wherever the player can get to, or deep space
	# would be the one place with no gravity at all and a trajectory
	# crossing the line would kink.
	system.star.well_radius = maxf(system.outer_radius() * 1.2, system.star.radius * 4.0)
	return system


## How much harder a planet must pull than the star at the edge of its own
## well, for the well to be worth the name.
##
## Two to one. One to one is the formal boundary and a terrible place to
## stand: the two pulls cancel, so a ship there is in free fall towards
## nothing in particular and the conic the HUD draws is meaningless.
const WELL_DOMINANCE: float = 2.0

## The narrowest well a planet is allowed to keep, in its own radii.
##
## Below this a world is not somewhere you can orbit: three radii leaves
## room to come round twice at a sensible altitude, and it is what the
## moons are sized against. A planet that cannot hold this much where the
## layout wanted to put it gets moved outwards until it can -- moving a
## planet is free, and making the star lighter is not.
const WELL_FLOOR: float = 3.0


## Where this planet stops out-pulling the star by WELL_DOMINANCE, in
## pixels from its own centre. How far its gravity is allowed to reach.
##
## This replaced deriving the **star's mass** from the planets, which is
## the same constraint read from the wrong end and which cost the star
## everything. The old rule took every planet's widest possible well as
## given and asked how light the star had to be to leave all of them
## intact; the tightest planet in the system then set the mass for the
## whole thing. Measured: the star ended up pulling 0.07 px/s^2 where the
## ship actually flies, four tenths of one per cent of what it feels, and
## 0.045 px/s^2 out between the orbits where it was the only thing pulling
## at all -- two hundred pixels of drift over a hundred seconds, which is
## nothing.
##
## Read the other way round it costs nothing at all. The star is rolled
## like any other body and each planet keeps the well it can actually
## hold: tight for an inner world, the full rolled width further out. The
## same sampled systems now give 0.9 to 2.2 px/s^2 at the innermost orbit
## and 0.6 to 1.4 between orbits, twenty times what they did, at the price
## of inner orbits moving out by at most half as much again.
##
##     mu_p / w^2  =  WELL_DOMINANCE * mu_star / (a - w)^2
##
## solved for w, with the star measured from the near side of the orbit,
## which is where it is worst.
func _well_limit(planet: SystemBody) -> float:
	var ratio: float = sqrt(WELL_DOMINANCE * star.mu() / planet.mu())
	return planet.orbit_radius / (1.0 + ratio)


## The orbit at which `planet` would just keep WELL_FLOOR radii of well.
## The same equation as `_well_limit`, solved for the orbit instead.
func _orbit_holding_floor(planet: SystemBody) -> float:
	var well: float = planet.radius * WELL_FLOOR
	return well * (1.0 + sqrt(WELL_DOMINANCE * star.mu() / planet.mu()))


## Every orbit's period, from the body it goes round. Done in one pass at
## the end so that nothing carries a period worked out from a mass that was
## later revised.
func _set_periods() -> void:
	for body: SystemBody in bodies:
		var above: SystemBody = body.parent_body()
		if above != null:
			body.orbit_period = above.period_for(body.orbit_radius)


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
	if star == null:
		return VOID_REACH
	var out: float = star.radius
	for body: SystemBody in star.children:
		out = maxf(out, body.extent())
	return out


## Which body is too close for the drive to light, or null when none is.
##
## The body rather than a bool, because "you cannot jump" is not
## something an instrument may say on its own: a pilot who is told
## *what* is holding them knows which way to fly, and a pilot told only
## "no" has to guess. The nearest offender when several overlap, for the
## same reason.
##
## Bodies orbit, so this takes the clock their positions are read
## against -- the same frozen `StreamingManager.visit_time` every planet
## in the scene was placed with, so the model and the nodes cannot
## disagree about where anything is.
func holding(point: Vector2, time: float = 0.0) -> SystemBody:
	var worst: SystemBody = null
	var closest: float = INF
	for body: SystemBody in bodies:
		var reach: float = body.radius * JUMP_CLEARANCE
		var away: float = point.distance_to(body.position_at(time))
		if away < reach and away < closest:
			closest = away
			worst = body
	return worst


## How much further the ship has to get, in pixels, before the drive will
## light. Zero once it is clear, which is what a readout counts down.
func clearance_to(point: Vector2, time: float = 0.0) -> float:
	var body: SystemBody = holding(point, time)
	if body == null:
		return 0.0
	return body.radius * JUMP_CLEARANCE - point.distance_to(body.position_at(time))


## Which body the lane to a destination runs into, or null when it is
## clear.
##
## The lane is a ray from the ship along the heading to the destination,
## and anything whose centre sits within `LANE_CLEARANCE` of its own
## radius of that ray is in the way. Only what is **ahead**: a planet
## the ship has already passed is behind the drive, not in front of it.
##
## The nearest obstruction rather than any, because that is the one the
## pilot would hit first and the one worth naming.
func lane_blocked(from: Vector2, toward: Vector2, time: float = 0.0) -> SystemBody:
	var along: Vector2 = toward.normalized()
	if along.is_zero_approx():
		return null
	var worst: SystemBody = null
	var nearest: float = INF
	for body: SystemBody in bodies:
		var at: Vector2 = body.position_at(time)
		var ahead: float = (at - from).dot(along)
		if ahead <= 0.0:
			continue
		var sideways: float = absf((at - from).cross(along))
		if sideways < body.radius * LANE_CLEARANCE and ahead < nearest:
			nearest = ahead
			worst = body
	return worst


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
	planet.atmosphere_height = Planet.roll_air(rng, planet.radius)
	planet.set_parent_body(star)
	star.children.append(planet)
	bodies.append(planet)

	if planet.radius >= MOON_PARENT_RADIUS and rng.randf() < MOON_CHANCE:
		_add_moon(rng, planet)

	# The widest well this planet would like, rolled here rather than by
	# the planet: the layout has to know it to place the next one out, and
	# two places rolling the same quantity is two places that drift apart.
	var ceiling: float = planet.radius * rng.randf_range(
		Planet.INFLUENCE_RATIO.x, Planet.INFLUENCE_RATIO.y
	)

	var floor_orbit: float = _orbit_holding_floor(planet)
	if inner != null:
		floor_orbit = maxf(
			floor_orbit,
			inner.orbit_radius + _reach_of(inner) + _reach_of(planet)
				+ Planet.INFLUENCE_RATIO.x * planet.radius,
		)
	planet.orbit_radius = maxf(wanted, floor_orbit)
	planet.orbit_phase = rng.randf() * TAU
	# Only now: how far it reaches depends on where it ended up.
	planet.well_radius = minf(ceiling, _well_limit(planet))
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
	moon.atmosphere_height = Planet.roll_air(rng, moon.radius)
	moon.set_parent_body(planet)
	moon.orbit_radius = planet.radius * rng.randf_range(MOON_ORBIT.x, MOON_ORBIT.y)
	moon.orbit_phase = rng.randf() * TAU
	# A moon is deep inside its parent, so what limits its own well is the
	# parent and not the star. Half the way back to the parent: far enough
	# to orbit, near enough that the two wells do not fight over the gap.
	moon.well_radius = minf(
		moon.radius * Planet.INFLUENCE_RATIO.y, moon.orbit_radius * 0.5
	)
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
	host.children.append(station)
	bodies.append(station)
