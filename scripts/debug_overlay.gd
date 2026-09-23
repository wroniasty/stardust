class_name DebugOverlay
extends CanvasLayer
## Flight telemetry while tuning the physics. Placeholder UI, dropped or
## replaced by the real HUD later.

## Every world-space debug visual joins this, so one key hides the lot. Held
## here because this is the node that owns the toggle.
const DEBUG_GROUP: StringName = &"debug_visuals"

@export var ship_path: NodePath

@onready var _label: Label = $Label

var _ship: Ship = null


func _ready() -> void:
	if not ship_path.is_empty():
		_ship = get_node_or_null(ship_path) as Ship


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		set_debug_visible(not visible)


## Shows or hides this readout and every world-space debug visual with it.
##
## Found through a group rather than exported paths: the engine overlay lives
## inside the ship scene, so the world has no stable path to it, and anything
## debug added later joins by calling add_to_group.
func set_debug_visible(shown: bool) -> void:
	visible = shown
	for node: Node in get_tree().get_nodes_in_group(DEBUG_GROUP):
		var visual: CanvasItem = node as CanvasItem
		if visual != null:
			visual.visible = shown


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

	lines.append("contacts %d   hull %.2f   damage %.3f" % [
		_ship.get_terrain_contacts(), _ship.hull_integrity, _ship.accumulated_damage,
	])

	var mode: String = "ORBIT" if _ship.flight_mode == Ship.FlightMode.ORBIT_LOCK else "free"
	lines.append("mode     %-6s  heat %.2f" % [mode, _ship.hull_heat])

	lines.append("commands %s" % _command_summary())
	lines.append("engines")
	for engine: EngineInstance in _ship.engines:
		lines.append("  %-20s %-8s thr %.2f  hp %.2f" % [
			engine.mount.name, engine.type_name(), engine.throttle, engine.health,
		])

	_label.text = "\n".join(lines)


## Only the commands actually asked for this tick, so the line stays short.
func _command_summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for command: ShipControl.Command in _ship.active_commands:
		parts.append("%s %.2f" % [_ship.control.command_name(command), _ship.active_commands[command]])
	if _ship.kill_rotation_command:
		parts.append("KILLROT")
	if _ship.brake_command:
		parts.append("BRAKE")
	return " ".join(parts) if not parts.is_empty() else "-"
