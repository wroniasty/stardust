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

## Sources register here so that nothing has to know a scene path.
const GROUP: StringName = &"gravity_sources"

## Radius of the nominal surface, in pixels.
var surface_radius: float = 600.0

## Gravitational acceleration at that surface, in pixels per second squared.
var surface_gravity: float = 40.0

## Beyond this radius the body pulls nothing.
var influence_radius: float = 3000.0


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


## Sums the pull of every source that reaches `point`.
static func pull_at(tree: SceneTree, point: Vector2) -> Vector2:
	var total: Vector2 = Vector2.ZERO
	for source: Node in tree.get_nodes_in_group(GROUP):
		var well: GravityWell = source as GravityWell
		if well != null:
			total += well.gravity_at(point)
	return total


## What colour this body reads as from a distance: on a scanner marker, on
## the map, anywhere it is too far away to be itself. Answered by the body
## because the body is what knows -- a planet has a surface, a star has a
## temperature, and a HUD that worked it out from the kind would be a
## second table to keep in step with the first.
func marker_color() -> Color:
	return Color(0.7, 0.7, 0.72)


## Smoothly takes gravity to zero over the outer tenth of the well.
func _edge_falloff(distance: float) -> float:
	var fade_start: float = influence_radius * 0.9
	if distance <= fade_start:
		return 1.0
	return 1.0 - smoothstep(fade_start, influence_radius, distance)
