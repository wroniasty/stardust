class_name DebugOverlay
extends CanvasLayer
## Flight telemetry while tuning the physics. Placeholder UI, dropped or
## replaced by the real HUD later.

@export var ship_path: NodePath

@onready var _label: Label = $Label

var _ship: Ship = null


func _ready() -> void:
	if not ship_path.is_empty():
		_ship = get_node_or_null(ship_path) as Ship


func _process(_delta: float) -> void:
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
	lines.append("engines")
	for engine: ShipEngine in _ship.engines:
		lines.append("  %-16s thr %.2f  eff %.2f  rel %.2f" % [
			engine.name, engine.throttle, engine.efficiency, engine.reliability,
		])

	_label.text = "\n".join(lines)
