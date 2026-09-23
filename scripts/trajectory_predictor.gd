class_name TrajectoryPredictor
extends Node2D
## Draws where the ship is going if it does nothing.
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

@onready var _line: Line2D = $Line

var _ship: Ship = null
var _ticks: int = 0
var _apoapsis: Vector2 = Vector2.INF
var _periapsis: Vector2 = Vector2.INF
var _impact: Vector2 = Vector2.INF


func _ready() -> void:
	# On the debug layer rather than always on. M1.5 built it as a HUD element,
	# but a permanent line through the middle of the screen is clutter when you
	# are not reading it; F7 brings it back with the rest of the instruments.
	add_to_group(DebugOverlay.DEBUG_GROUP)
	if not ship_path.is_empty():
		_ship = get_node_or_null(ship_path) as Ship


func _physics_process(_delta: float) -> void:
	if _ship == null:
		return
	if not visible:
		if _line.get_point_count() > 0:
			_line.clear_points()
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


func _predict() -> void:
	_apoapsis = Vector2.INF
	_periapsis = Vector2.INF
	_impact = Vector2.INF

	# Gathered once, not per step: the group lookup would otherwise dominate.
	var planets: Array[Planet] = []
	for source: Node in get_tree().get_nodes_in_group(Planet.GRAVITY_GROUP):
		var planet: Planet = source as Planet
		if planet != null:
			planets.append(planet)

	var reference: Planet = Planet.nearest(get_tree(), _ship.global_position)
	var step: float = (1.0 / float(Engine.physics_ticks_per_second)) * step_scale

	var position_now: Vector2 = _ship.global_position
	var velocity: Vector2 = _ship.linear_velocity

	var path: PackedVector2Array = PackedVector2Array()
	path.append(position_now)

	var radii: PackedFloat32Array = PackedFloat32Array()
	if reference != null:
		radii.append(position_now.distance_to(reference.global_position))

	for i: int in range(steps):
		var acceleration: Vector2 = Vector2.ZERO
		for planet: Planet in planets:
			acceleration += planet.gravity_at(position_now)
		# Semi-implicit Euler, matching the solver: velocity first, then use it.
		velocity += acceleration * step
		position_now += velocity * step
		path.append(position_now)

		if reference != null:
			radii.append(position_now.distance_to(reference.global_position))

		if _hits_ground(planets, position_now):
			_impact = position_now
			break

	_line.points = path
	_find_extremes(path, radii)
	queue_redraw()


## Terrain is only worth sampling once the path is low enough to reach it.
func _hits_ground(planets: Array[Planet], point: Vector2) -> bool:
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


func _draw() -> void:
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
