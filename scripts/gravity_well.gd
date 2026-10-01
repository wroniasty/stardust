class_name GravityWell
extends Node2D
## Anything in the world that pulls: a planet, a moon, a star.
##
## Gravity is not a gravity_point Area2D. Its falloff is fixed and cannot be
## faded out at the edge of the well, so sources publish themselves in GROUP
## and whatever is being pulled sums `gravity_at()` itself (IDEAS.md
## section 5).
##
## This class exists because the star arrived. Until then the group held
## planets and every reader cast to `Planet`, which made "is a gravity
## source" and "has a crust you can land on" the same statement. They are
## not: the star pulls and burns and has no terrain, and a reader that wants
## ground -- the trajectory predictor's impact test, the configurator --
## still asks for a Planet and gets only planets.

## What a coasting trajectory is doing with respect to this body.
##
## Derived from the trajectory, never switched on. An earlier version made
## "in orbit" a mode the ship entered, which meant a second implementation of
## motion that had to agree with the first and twice did not; and because it
## only accepted near-circular orbits, a perfectly good ellipse was never
## called an orbit at all (see IDEAS.md section 8).
enum OrbitState {
	ESCAPE,  ## Leaves the well, or is already outside it.
	ORBIT,  ## Closed, and clears the air the whole way round.
	DECAYING,  ## Closed, but dips into the atmosphere and will not last.
	SUBORBITAL,  ## Comes down: the low point is inside the rock.
}

## Sources register here so that nothing has to know a scene path.
const GROUP: StringName = &"gravity_sources"

## Radius of the nominal surface, in pixels.
var surface_radius: float = 600.0

## Gravitational acceleration at that surface, in pixels per second squared.
var surface_gravity: float = 40.0

## Beyond this radius the body pulls nothing.
var influence_radius: float = 3000.0

## The descriptor this body was built from, when it came out of a system
## rather than out of a bare seed. Kept so that whatever has a node can
## ask which body it is without a second table to keep in step.
var body: SystemBody = null


## What to call this in a readout. The catalogue name when there is one,
## and the node's own name when the body was built from a bare seed.
func catalogue_name() -> String:
	return name if body == null else body.display_name


func _enter_tree() -> void:
	# Here rather than in `_ready` so that subclasses are free to write their
	# own `_ready` without having to remember to call super. Forgetting it
	# would mean a body in the world that nothing falls towards, which is
	# the kind of bug that looks like physics.
	add_to_group(GROUP)


## The standard gravitational parameter, in px^3/s^2. `g * r^2`: the only
## quantity orbits actually care about, which is why size and surface
## gravity are the two numbers everything else is derived from.
func mu() -> float:
	return surface_gravity * surface_radius * surface_radius


## Gravitational acceleration a body feels at `point`, in pixels per second
## squared. Inverse square above the surface, faded smoothly to nothing at
## the edge of the well so a ship does not get a kick when it crosses the
## boundary.
func gravity_at(point: Vector2) -> Vector2:
	var to_centre: Vector2 = global_position - point
	var distance: float = to_centre.length()
	if distance < 0.001 or distance >= influence_radius:
		return Vector2.ZERO

	# Underground the inverse square would blow up, so hold it at surface value.
	var effective: float = maxf(distance, surface_radius)
	var strength: float = surface_gravity * pow(surface_radius / effective, 2.0)
	strength *= _edge_falloff(distance)
	return (to_centre / distance) * strength


## Every source in the world, as the readers that only want the pull see it.
static func all(tree: SceneTree) -> Array[GravityWell]:
	var wells: Array[GravityWell] = []
	for source: Node in tree.get_nodes_in_group(GROUP):
		var well: GravityWell = source as GravityWell
		if well != null:
			wells.append(well)
	return wells


## The pull at `point`: the body whose well it is in, and the ones further
## out only to the extent that body has let go of it.
##
## **Not a sum, and the reason is that our planets do not move.** In a real
## system a ship in orbit round a planet barely feels the star, because the
## planet is falling towards the star at the same rate and only the
## difference across the orbit -- the tide -- is left. Ours are nailed down
## (IDEAS.md "Planety nie okrazaja gwiazdy"), so a plain sum gives the ship
## the star's full pull while the planet takes none of it, and that is not
## a perturbation, it is a steady shove in one direction.
##
## Measured, before this: a circular orbit at 1.6 planet radii came down
## into the ground inside three minutes, and orbits at 2.6 and 4.0 radii
## left the well entirely. The same orbits with the star taken out held to
## a tenth of a per cent. A ship could not orbit a planet at all.
##
## So the wells are patched rather than added. Inside a body's well that
## body pulls and the ones outside it do not, which is what "the planet is
## carrying you" looks like when the planet cannot actually carry you. The
## seam is the fade each well already has at its own edge: a body hands the
## ship over exactly as fast as it lets go, so the field stays continuous
## and nothing kicks on the way across.
static func pull_at(tree: SceneTree, point: Vector2) -> Vector2:
	return pull_from(all(tree), point)


## The same, from a list gathered once. The trajectory predictor steps
## hundreds of times and cannot afford a group lookup each step -- and has
## to arrive at the same answer the ship does, so it calls the same code.
static func pull_from(wells: Array[GravityWell], point: Vector2) -> Vector2:
	var reaching: Array[GravityWell] = []
	for well: GravityWell in wells:
		if well.global_position.distance_to(point) < well.influence_radius:
			reaching.append(well)
	# Innermost first, by how far each reaches: a moon's well is inside its
	# planet's, which is inside the star's. Sorting by reach rather than by
	# distance is what makes that hold wherever in the well the ship is.
	reaching.sort_custom(func(a: GravityWell, b: GravityWell) -> bool:
		return a.influence_radius < b.influence_radius
	)

	var total: Vector2 = Vector2.ZERO
	var share: float = 1.0
	for well: GravityWell in reaching:
		total += well.gravity_at(point) * share
		share *= 1.0 - well.hold_at(point)
		if share <= 0.0:
			break
	return total


## How firmly this well holds `point`: one well inside it, nought at its
## edge and beyond. What is left over is what the next body out gets.
func hold_at(point: Vector2) -> float:
	var distance: float = global_position.distance_to(point)
	if distance >= influence_radius:
		return 0.0
	return _edge_falloff(distance)


## The innermost well `point` is inside, or null out in the dark.
##
## "Innermost" by reach, not by distance, for the same reason as above: a
## ship low over a moon is nearer the moon than the planet, but it is the
## narrower well that owns it either way.
static func local_at(tree: SceneTree, point: Vector2) -> GravityWell:
	var best: GravityWell = null
	for well: GravityWell in all(tree):
		if well.global_position.distance_to(point) >= well.influence_radius:
			continue
		if best == null or well.influence_radius < best.influence_radius:
			best = well
	return best


## Whether this body has a surface worth talking about: ground to land
## on, air to brake in, a slope under the ship. A planet does, a star does
## not, and a readout asks rather than checking the class.
func has_ground() -> bool:
	return false


## Height of `point` above this body, in pixels. Above the nominal surface,
## which for a body with terrain is not the same as above the ground --
## Planet overrides it with the one the landing check uses.
func height_above_terrain(point: Vector2) -> float:
	return global_position.distance_to(point) - surface_radius


## How fast the surface is moving under `point`. Zero unless the body spins
## and has a surface to speak of.
func surface_velocity_at(_point: Vector2) -> Vector2:
	return Vector2.ZERO


## Radius above which nothing solid can exist. The surface, unless the body
## has terrain standing above it -- which only a planet does.
func terrain_ceiling() -> float:
	return surface_radius


## Radius at the top of the air. The surface, unless the body has air --
## which, again, only a planet does.
##
## Both of these are here so the orbit maths above can be written once.
## "Where does the ground stop" and "where does the air stop" are the only
## two questions in it that a star answers differently from a planet, and
## for a star they are the same place: its own surface.
func atmosphere_radius() -> float:
	return surface_radius


## What colour this body reads as from a distance: on a scanner marker, on
## the map, anywhere it is too far away to be itself. Answered by the body
## because the body is what knows -- a planet has a surface, a star has a
## temperature, and a HUD that worked it out from the kind would be a
## second table to keep in step with the first.
func marker_color() -> Color:
	return Color(0.7, 0.7, 0.72)


## Speed of a circular orbit at `radius`, in pixels per second.
##
## For an inverse square field measured at the surface this is
## sqrt(g * R^2 / r). Orbit lock, the tests and any autopilot must agree on it,
## so it lives here rather than being rederived at each call site.
func circular_orbit_speed(radius: float) -> float:
	if radius <= 0.001:
		return 0.0
	return sqrt(surface_gravity * surface_radius * surface_radius / radius)


## Periapsis and apoapsis radii of the coasting orbit through `point` at
## `velocity`, as (periapsis, apoapsis). Apoapsis is INF when the ship leaves.
##
## Exact only where the field is: below the surface gravity is capped, and over
## the outer tenth of the well it is faded out so a ship does not get a kick
## crossing the boundary (see gravity_at). An apoapsis past the influence
## radius therefore never happens -- the ship coasts out of the well instead --
## so it is reported as an escape rather than as a number that would be wrong.
func orbit_extremes(point: Vector2, velocity: Vector2) -> Vector2:
	var arm: Vector2 = point - global_position
	var radius: float = arm.length()
	var mu: float = mu()
	if radius < 0.001 or mu <= 0.0:
		return Vector2(0.0, INF)

	var energy: float = velocity.length_squared() * 0.5 - mu / radius
	# Angular momentum: in 2D the cross product is the scalar h.
	var momentum: float = arm.cross(velocity)
	var eccentricity: float = sqrt(maxf(
		0.0, 1.0 + 2.0 * energy * momentum * momentum / (mu * mu)
	))

	if energy >= 0.0:
		# Unbound: there is still a periapsis, from the conic's semi-latus
		# rectum, but no far side to come back to.
		var latus: float = momentum * momentum / mu
		return Vector2(latus / maxf(1.0 + eccentricity, 0.001), INF)

	var semi_major: float = -mu / (2.0 * energy)
	var apoapsis: float = semi_major * (1.0 + eccentricity)
	if apoapsis >= influence_radius:
		return Vector2(semi_major * (1.0 - eccentricity), INF)
	return Vector2(semi_major * (1.0 - eccentricity), apoapsis)


## The coasting conic through `point`, as something that can be drawn.
##
## `orbit_extremes()` answers the two numbers a readout needs. A picture
## needs the shape as well, and that is the **eccentricity vector**: it
## points at periapsis and its length is the eccentricity. Returned as one
## vector rather than as an angle and a magnitude, because those would be
## two values that can disagree.
func orbit_shape(point: Vector2, velocity: Vector2) -> Dictionary:
	var extremes: Vector2 = orbit_extremes(point, velocity)
	var shape: Dictionary = {
		"periapsis": extremes.x, "apoapsis": extremes.y, "eccentricity": Vector2.ZERO,
	}
	var arm: Vector2 = point - global_position
	var radius: float = arm.length()
	var mu: float = mu()
	if radius < 0.001 or mu <= 0.0:
		return shape
	shape["eccentricity"] = (
		arm * (velocity.length_squared() - mu / radius) - velocity * arm.dot(velocity)
	) / mu
	return shape


## Radius of a conic with this periapsis and eccentricity, `theta` radians
## round from periapsis.
##
## One formula for both kinds: an ellipse closes because the divisor never
## reaches zero, and a hyperbola runs off to infinity because it does.
static func conic_radius(periapsis: float, eccentricity: float, theta: float) -> float:
	var divisor: float = 1.0 + eccentricity * cos(theta)
	return INF if divisor <= 0.0001 else periapsis * (1.0 + eccentricity) / divisor


## Classifies the coasting trajectory through `point` at `velocity`.
##
## This is what "are we in orbit" means: both ends of the conic inside the
## well, and the near end clear of the air. Every other answer is a different
## thing the pilot needs to know about rather than a failure to be in orbit.
func orbit_state(point: Vector2, velocity: Vector2) -> OrbitState:
	var arm: Vector2 = point - global_position
	# Beyond the well the planet has no say: gravity there is zero, so the
	# conic would be a fiction drawn around a body that is not pulling.
	if arm.length() >= influence_radius:
		return OrbitState.ESCAPE

	var extremes: Vector2 = orbit_extremes(point, velocity)
	var inbound: bool = velocity.dot(arm) < 0.0
	if extremes.x <= terrain_ceiling() and (inbound or not is_inf(extremes.y)):
		# An open trajectory heading outwards has a periapsis below the rock in
		# its past, not its future, so only an inbound one is coming down.
		return OrbitState.SUBORBITAL
	if is_inf(extremes.y):
		return OrbitState.ESCAPE
	if extremes.x <= atmosphere_radius():
		return OrbitState.DECAYING
	return OrbitState.ORBIT


## Smoothly takes gravity to zero over the outer tenth of the well.
func _edge_falloff(distance: float) -> float:
	var fade_start: float = influence_radius * 0.9
	if distance <= fade_start:
		return 1.0
	return 1.0 - smoothstep(fade_start, influence_radius, distance)
