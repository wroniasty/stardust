class_name DebugOverlay
extends CanvasLayer
## Flight telemetry while tuning the physics. Placeholder UI, dropped or
## replaced by the real HUD later.

## Every world-space debug visual joins this, so one key hides the lot. Held
## here because this is the node that owns the toggle.
const DEBUG_GROUP: StringName = &"debug_visuals"

@export var ship_path: NodePath

@onready var _label: Label = $Label
@onready var _planet_label: Label = $Planet

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
		_planet_label.text = ""
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

	var mode: String = "landed" if _ship.flight_mode == Ship.FlightMode.LANDED else "free"
	lines.append("mode     %-6s  heat %.2f" % [mode, _ship.hull_heat])

	lines.append("commands %s" % _command_summary())
	lines.append("engines")
	for engine: EngineInstance in _ship.engines:
		lines.append("  %-20s %-8s thr %.2f  hp %.2f" % [
			engine.mount.name, engine.type_name(), engine.throttle, engine.health,
		])

	_label.text = "\n".join(lines)
	_planet_label.text = "\n".join(_planet_lines(planet))


## Every parameter the generator rolled, plus what it built out of them.
##
## The whole planet comes from one seed, so when a world flies strangely the
## question is always which of these numbers it got -- and reading them off a
## screen beats adding a print and restarting. Paired with the configurator on
## F6, which edits the same fields (IDEAS.md section 5).
func _planet_lines(planet: Planet) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if planet == null:
		return PackedStringArray(["PLANET   none in range"])

	lines.append("PLANET   seed %d" % planet.planet_seed)
	lines.append("radius   %7.0f   gravity %6.1f" % [planet.surface_radius, planet.surface_gravity])
	lines.append("influence%7.0f   mu   %7.1f M" % [
		planet.influence_radius, planet.mu() / 1000000.0,
	])
	lines.append("crust    %7.0f .. %.0f" % [planet.terrain.inner_radius, planet.terrain.outer_radius])
	lines.append("air h    %7.0f   density %6.2f" % [planet.atmosphere_height, planet.atmosphere_density])
	lines.append("air top  %7.0f   v_esc   %6.1f" % [
		planet.atmosphere_radius(),
		sqrt(2.0 * planet.mu() / maxf(planet.surface_radius, 1.0)),
	])
	lines.append("v_circ   %7.1f at surface" % planet.circular_orbit_speed(planet.surface_radius))
	var day: String = "never"
	if not is_zero_approx(planet.spin_rate):
		day = "%.0f s" % (TAU / absf(planet.spin_rate))
	lines.append("spin    %8.4f rad/s  day %s" % [planet.spin_rate, day])
	lines.append("shelves  %7d   grid %d x %d" % [
		planet.landing_sites().size(), planet.terrain.angular_samples, planet.terrain.radial_samples,
	])
	lines.append("ground   #%s   sky #%s" % [
		planet.surface_color.to_html(false), planet.atmosphere_color.to_html(false),
	])

	lines.append("")
	if not planet.has_clouds:
		lines.append("WEATHER  none")
		return lines

	lines.append("WEATHER  %s   %d clouds" % [
		Planet.CloudType.keys()[planet.cloud_type], planet.cloud_count(),
	])
	lines.append("deck     %7.0f .. %.0f" % [planet.cloud_base_radius(), planet.cloud_ceiling()])
	lines.append("base/dep %7.2f / %.2f of air h" % [planet.cloud_base, planet.cloud_depth])
	lines.append("coverage %7.2f   opacity %6.2f" % [planet.cloud_coverage, planet.cloud_opacity])
	lines.append("puff     %7.2f x %.2f of deck" % [planet.cloud_puff_size, planet.cloud_puff_height])
	lines.append("soft/warp%7.2f / %.2f" % [planet.cloud_softness, planet.cloud_warp])
	lines.append("relief   %7.2f   flat base %5.2f" % [
		planet.cloud_height_variation, planet.cloud_flat_base,
	])
	lines.append("shear    %7.2f   shading %6.2f" % [planet.cloud_shear, planet.cloud_shading])
	lines.append("lobes    %7d   spin %8.4f" % [planet.cloud_octaves + 1, planet.cloud_speed])
	lines.append("colour   #%s   under #%s" % [
		planet.cloud_color.to_html(false), planet.cloud_shade_color().to_html(false),
	])
	return lines


## Only the commands actually asked for this tick, so the line stays short.
func _command_summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for command: ShipControl.Command in _ship.active_commands:
		parts.append("%s %.2f" % [_ship.control.command_name(command), _ship.active_commands[command]])
	if _ship.kill_rotation_command:
		parts.append("KILLROT")
	if _ship.heading_command != ControlChords.Chord.NONE:
		parts.append(ControlChords.Chord.keys()[int(_ship.heading_command)])
	if _ship.brake_command:
		parts.append("BRAKE")
	return " ".join(parts) if not parts.is_empty() else "-"
