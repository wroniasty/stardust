class_name DebugOverlay
extends CanvasLayer
## Flight telemetry while tuning the physics. Placeholder UI, dropped or
## replaced by the real HUD later.

@export var ship_path: NodePath

## World-space arrows toggled together with this readout, so one key hides the
## whole debug layer instead of leaving half of it on screen.
@export var vectors_path: NodePath

@onready var _label: Label = $Label

var _ship: Ship = null
var _vectors: DebugVectors = null


func _ready() -> void:
	if not ship_path.is_empty():
		_ship = get_node_or_null(ship_path) as Ship
	if not vectors_path.is_empty():
		_vectors = get_node_or_null(vectors_path) as DebugVectors


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		set_debug_visible(not visible)


func set_debug_visible(shown: bool) -> void:
	visible = shown
	if _vectors != null:
		_vectors.visible = shown


func _process(_delta: float) -> void:
	if not visible:
		return
	if _ship == null:
		_label.text = "no ship"
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append("pos      %6.0f %6.0f" % [_ship.global_position.x, _ship.global_position.y])
	lines.append("vel      %6.1f %6.1f  |v| %6.1f" % [
		_ship.linear_velocity.x, _ship.linear_velocity.y, _ship.linear_velocity.length(),
	])
	lines.append("fwd vel  %6.1f" % _ship.get_forward_speed())
	lines.append("ang vel  %6.2f rad/s   rot %6.1f deg" % [
		_ship.angular_velocity, rad_to_deg(_ship.global_rotation),
	])
	lines.append("force    %6.1f %6.1f   torque %8.1f" % [
		_ship.get_applied_force().x, _ship.get_applied_force().y, _ship.get_applied_torque(),
	])
	var gravity: Vector2 = _ship.get_applied_gravity()
	lines.append("gravity  %6.1f px/s2" % gravity.length())

	var planet: Planet = _ship.nearest_planet()
	if planet != null:
		lines.append("altitude %6.0f   (surface r %.0f)" % [
			planet.altitude_at(_ship.global_position), planet.surface_radius,
		])
		var up: Vector2 = (_ship.global_position - planet.global_position).normalized()
		lines.append("vertical %6.1f   lateral %6.1f" % [
			_ship.linear_velocity.dot(up), _ship.linear_velocity.dot(up.orthogonal()),
		])

	lines.append("contacts %d   damage %.3f" % [_ship.get_terrain_contacts(), _ship.accumulated_damage])

	var mode: String = "ORBIT" if _ship.flight_mode == Ship.FlightMode.ORBIT_LOCK else "free"
	lines.append("mode     %-6s  heat %.2f" % [mode, _ship.hull_heat])

	lines.append("engines")
	for engine: ShipEngine in _ship.engines:
		lines.append("  %-16s thr %.2f  eff %.2f  rel %.2f" % [
			engine.name, engine.throttle, engine.efficiency, engine.reliability,
		])

	_label.text = "\n".join(lines)
