class_name TrajectoryPredictor
extends Node2D
## Draws where the ship is going if it does nothing.
##
## No longer only a debug visual. It is a flight computer function now
## (`FlightComputerData.has_trajectory_view`), switched from the panel
## in the corner, and F7 still brings it up with the rest of the
## instruments whether or not a box is fitted -- so it asks both rather
## than belonging to the debug group, which would have let the overlay
## write over the pilot's switch.
##
## Forward-integrates the same gravity function the ship uses, with the same
## semi-implicit Euler, so the line is not an approximation of the physics: it
## is the physics, run ahead. Drag and thrust are left out on purpose, because
## the question the player is asking is "if I let go now, what happens".
##
## The markers are what make it a planning tool rather than decoration:
## periapsis and apoapsis say what shape the orbit is, and the impact marker
## turns a deorbit burn into aiming (see IDEAS.md section 8).

## Steps simulated ahead, and how many physics ticks each step covers. More
## time per step buys reach at the cost of accuracy; the product is the horizon.
@export var steps: int = 320
@export var step_scale: float = 6.0

## Physics ticks between recomputes. The path only changes when the ship is
## pushed, so there is no point redoing it every tick.
@export var recompute_interval: int = 2

@export var ship_path: NodePath

@export var apoapsis_color: Color = Color(0.55, 0.75, 1.0)
@export var periapsis_color: Color = Color(1.0, 0.9, 0.45)
@export var impact_color: Color = Color(1.0, 0.35, 0.3)

const MARKER_RADIUS: float = 3.0

## How the path is drawn: a broad, faint, dashed ribbon rather than the
## one-pixel line it was on the debug layer.
##
## Wide because it is read at a glance against terrain and starfield,
## and faint for the same reason the panels are -- a line through the
## middle of the screen that hides what is behind it is a line that has
## to be switched off to fly. Dashed because a solid band of colour over
## the world reads as a wall; gaps say "this is a path, not a thing".
const PATH_WIDTH: float = 5.0
const PATH_ALPHA: float = 0.20
const DASH: float = 10.0
const DASH_GAP: float = 7.0

## Where the predicted path is, in this node's own frame, kept for the
## draw. It used to live in a `Line2D` child; a dashed ribbon whose
## colour says what the orbit is doing is not something `Line2D` draws,
## and two copies of the path would be one too many.
var _path: PackedVector2Array = PackedVector2Array()

var _ship: Ship = null
var _ticks: int = 0
var _apoapsis: Vector2 = Vector2.INF
var _periapsis: Vector2 = Vector2.INF
var _impact: Vector2 = Vector2.INF


func _ready() -> void:
	# **Not** in the debug group, though F7 still shows it. A group
	# member has its `visible` written by the overlay, which would mean
	# the debug key quietly switching off a function the pilot had
	# turned on. Asking both questions here instead leaves one owner of
	# the answer.
	if not ship_path.is_empty():
		_ship = get_node_or_null(ship_path) as Ship


## Whether anybody is asking for the path: the pilot through the
## computer, or the debug layer.
func wanted() -> bool:
	if _ship == null or not is_instance_valid(_ship):
		return false
	if _ship.is_latched(FlightAssists.Kind.TRAJECTORY):
		return true
	return DebugOverlay.showing


## Keeps the picture on the ship the renderer is drawing, not the one
## the solver last integrated.
##
## The same fault the beams, the sparks and the crosshair all had, and
## it shows here as the path twitching. With physics interpolation on
## -- project-wide -- the hull is drawn between its last two physics
## transforms while `global_position` hands back the newer of the two,
## so a path built from that number starts up to a full tick of travel
## ahead of the ship it belongs to. At sixty ticks and a render rate
## above it, that error is a different size every frame, which is seen
## as a line shivering against a hull that is moving smoothly.
##
## Moving the **node** rather than the points puts the markers and the
## dashes under the same correction, and keeps the prediction itself in
## world coordinates where it belongs. The offset is at most one tick
## of travel, so the far end of the path is out by an amount nothing
## can see, and the near end -- the end joined to the ship -- is exact.
##
## In `_process` because it has to be redone every **frame**: that is
## what `get_physics_interpolation_fraction` changes between.
func _process(_delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship) or _path.is_empty():
		position = Vector2.ZERO
		return
	position = _ship.drawn_transform().origin - _path[0]


func _physics_process(_delta: float) -> void:
	if _ship == null:
		return
	visible = wanted()
	if not visible:
		if not _path.is_empty():
			_path = PackedVector2Array()
			position = Vector2.ZERO
		return
	_ticks += 1
	if _ticks < recompute_interval:
		return
	_ticks = 0
	_predict()


## True if the predicted path ends in the ground rather than running out.
func has_impact() -> bool:
	return _impact.is_finite()


func get_impact_point() -> Vector2:
	return _impact


## Where a ship goes if it does nothing, as world points, with the place it
## ends in the ground if it does.
##
## Static and free of this node, because there are two things that want
## this answer now -- the line on F7 and the dashed curve on the system
## map -- and two forward integrations of the same ship would be two
## futures to keep in step. Forward-integrated with the same gravity
## function and the same semi-implicit Euler as the solver, so this is not
## an approximation of the physics: it is the physics, run ahead.
##
## Drag and thrust are left out on purpose. The question being asked is
## "if I let go now, what happens".
static func coast(ship: Ship, count: int, stride: float) -> Dictionary:
	var result: Dictionary = {"path": PackedVector2Array(), "impact": Vector2.INF}
	if ship == null or not is_instance_valid(ship) or not ship.is_inside_tree():
		return result

	# Gathered once, not per step: the group lookup would otherwise dominate.
	# Two lists, because the two questions are different ones: everything
	# pulls, only a planet has ground to end the flight against.
	var wells: Array[GravityWell] = GravityWell.all(ship.get_tree())
	var planets: Array[Planet] = []
	for well: GravityWell in wells:
		var planet: Planet = well as Planet
		if planet != null:
			planets.append(planet)

	var step: float = (1.0 / float(Engine.physics_ticks_per_second)) * stride
	var at: Vector2 = ship.global_position
	var velocity: Vector2 = ship.linear_velocity
	var path: PackedVector2Array = PackedVector2Array()
	path.append(at)

	for i: int in range(count):
		# The ship's own sum, not a second one: the line on the screen and
		# the path the solver takes have to come from one rule, and the
		# patching in it is not something to reimplement by eye.
		var acceleration: Vector2 = GravityWell.pull_from(wells, at)
		# Semi-implicit Euler, matching the solver: velocity first, then use it.
		velocity += acceleration * step
		at += velocity * step
		path.append(at)
		if hits_ground(planets, at):
			result["impact"] = at
			break

	result["path"] = path
	return result


func _predict() -> void:
	_apoapsis = Vector2.INF
	_periapsis = Vector2.INF

	var flight: Dictionary = coast(_ship, steps, step_scale)
	var path: PackedVector2Array = flight["path"]
	_impact = flight["impact"]

	var reference: Planet = Planet.nearest(get_tree(), _ship.global_position)
	var radii: PackedFloat32Array = PackedFloat32Array()
	if reference != null:
		for point: Vector2 in path:
			radii.append(point.distance_to(reference.global_position))

	_path = path
	_find_extremes(path, radii)
	queue_redraw()


## Terrain is only worth sampling once the path is low enough to reach it.
static func hits_ground(planets: Array[Planet], point: Vector2) -> bool:
	for planet: Planet in planets:
		if point.distance_to(planet.global_position) > planet.terrain_ceiling():
			continue
		if planet.is_solid_at(point):
			return true
	return false


## First turning point of each kind along the path.
func _find_extremes(path: PackedVector2Array, radii: PackedFloat32Array) -> void:
	for i: int in range(1, radii.size() - 1):
		var previous: float = radii[i - 1]
		var current: float = radii[i]
		var next: float = radii[i + 1]
		if current > previous and current >= next and not _apoapsis.is_finite():
			_apoapsis = path[i]
		elif current < previous and current <= next and not _periapsis.is_finite():
			_periapsis = path[i]
		if _apoapsis.is_finite() and _periapsis.is_finite():
			return


## What the path is doing, as the colour it is drawn in.
##
## Four answers, and they are the four a pilot acts on differently: a
## closed orbit that clears the air is fine, one that dips into it is a
## clock running, an open path is simply going somewhere, and a path
## that ends in rock is the only one that needs doing something about
## now. The last beats the rest, because `orbit_state` can call a path
## SUBORBITAL while the impact is still off the end of the prediction.
func path_ink() -> Color:
	var ink: Palette = Palette.current()
	if _impact.is_finite():
		return ink.alarm
	var planet: Planet = null
	if _ship != null and is_instance_valid(_ship):
		planet = Planet.nearest(get_tree(), _ship.global_position)
	if planet == null:
		return ink.nav
	match planet.orbit_state(_ship.global_position, _ship.linear_velocity):
		GravityWell.OrbitState.ORBIT:
			return ink.ok
		GravityWell.OrbitState.DECAYING:
			return ink.caution
		GravityWell.OrbitState.SUBORBITAL:
			return ink.caution
		_:
			return ink.nav


func _draw() -> void:
	_draw_path()
	if _apoapsis.is_finite():
		_draw_marker(_apoapsis, apoapsis_color)
	if _periapsis.is_finite():
		_draw_marker(_periapsis, periapsis_color)
	if _impact.is_finite():
		# Filled, so an impending crash reads differently from an orbit marker
		# at a glance.
		draw_circle(_impact, MARKER_RADIUS, impact_color)


func _draw_marker(point: Vector2, color: Color) -> void:
	draw_arc(point, MARKER_RADIUS, 0.0, TAU, 12, color, 1.0)


## The path as dashes of a fixed length on the ground, not per step.
##
## Per step would stripe it by how fast the ship is going -- the
## predictor's points are a fixed time apart, so they crowd at apoapsis
## and spread at periapsis -- and a pattern that changes with speed
## reads as the line meaning something it does not. Walking the arc
## length keeps every dash the same size on screen.
func _draw_path() -> void:
	var ink: Color = path_ink()
	ink.a *= PATH_ALPHA
	var marks: PackedVector2Array = dashes(_path)
	for i: int in range(0, marks.size(), 2):
		draw_line(marks[i], marks[i + 1], ink, PATH_WIDTH)


## The path cut into dashes, as pairs of points.
##
## Separated from the drawing so the pattern can be measured: a dash
## walker is a loop with a modulo in it and two ways to be subtly wrong
## -- dashes that drift out of step across segments, or a gap that eats
## a whole segment -- and neither shows in a screenshot.
static func dashes(path: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if path.size() < 2:
		return out
	var period: float = DASH + DASH_GAP
	var walked: float = 0.0
	for i: int in range(1, path.size()):
		var from: Vector2 = path[i - 1]
		var to: Vector2 = path[i]
		var span: float = from.distance_to(to)
		if span <= 0.0:
			continue
		var at: float = 0.0
		while at < span:
			var into: float = fmod(walked + at, period)
			if into >= DASH:
				# In a gap: step to where the next dash starts.
				at += period - into
				continue
			var run: float = minf(DASH - into, span - at)
			out.append(from.lerp(to, at / span))
			out.append(from.lerp(to, (at + run) / span))
			at += run
		walked += span
	return out
