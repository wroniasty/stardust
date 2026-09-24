class_name LandingHud
extends CanvasLayer
## What the pilot needs to fly by: how high, how fast down, how steep the
## ground is, whether the legs are out -- and, once there is a planet to go
## round, what shape the orbit is.
##
## Separate from the debug overlay on purpose. The overlay is instrumentation
## that goes away; this is the game telling the player what it is about to
## judge them on, and every value shown here is one the landing check actually
## uses (IDEAS.md section 7).

## Slope in radians at which the readout turns amber, then red. Read from the
## gear so the colours always mean "this ship can or cannot stand here",
## rather than some fixed number that stops being true when the gear changes.
const CAUTION_FRACTION: float = 0.6

const GOOD: Color = Color(0.45, 1.0, 0.5)
const CAUTION: Color = Color(1.0, 0.85, 0.3)
const BAD: Color = Color(1.0, 0.4, 0.35)
const IDLE: Color = Color(0.7, 0.75, 0.8)

@export var ship_path: NodePath

@onready var _periapsis: Label = $Panel/Rows/Periapsis
@onready var _apoapsis: Label = $Panel/Rows/Apoapsis
@onready var _altitude: Label = $Panel/Rows/Altitude
@onready var _descent: Label = $Panel/Rows/Descent
@onready var _slope: Label = $Panel/Rows/Slope
@onready var _gear: Label = $Panel/Rows/Gear
@onready var _hull: Label = $Panel/Rows/Hull
@onready var _status: Label = $Panel/Rows/Status

var _ship: Ship = null


func _ready() -> void:
	if not ship_path.is_empty():
		_ship = get_node_or_null(ship_path) as Ship


func _process(_delta: float) -> void:
	if _ship == null:
		return
	var planet: Planet = _ship.nearest_planet()
	if planet == null:
		_show_in_deep_space()
		return

	var up: Vector2 = (_ship.global_position - planet.global_position).normalized()
	var ground: float = planet.surface_radius_at(_ship.global_position)
	var altitude: float = _ship.global_position.distance_to(planet.global_position) - ground

	# Relative to the ground, which moves on a spinning planet: the same
	# quantity the landing check uses, so the HUD cannot disagree with it.
	var relative: Vector2 = _ship.linear_velocity - planet.surface_velocity_at(_ship.global_position)
	var descent: float = -relative.dot(up)
	var slope: float = planet.slope_at(_ship.global_position)

	_update_orbit(planet)
	_altitude.text = "ALT  %6.0f" % altitude
	_descent.text = "V/S  %+6.1f" % -descent
	_slope.text = "SLOPE %5.1f deg" % rad_to_deg(slope)
	_slope.add_theme_color_override("font_color", _slope_color(absf(slope)))
	_descent.add_theme_color_override("font_color", _descent_color(descent))
	_gear.text = "GEAR %s" % _gear_text()
	_gear.add_theme_color_override("font_color", _gear_color())
	_update_hull()
	_status.text = _status_text()


func _show_in_deep_space() -> void:
	_periapsis.text = "PERI      --"
	_apoapsis.text = "APO       --"
	_periapsis.add_theme_color_override("font_color", IDLE)
	_apoapsis.add_theme_color_override("font_color", IDLE)
	_altitude.text = "ALT       --"
	_descent.text = "V/S       --"
	_slope.text = "SLOPE     --"
	_gear.text = "GEAR %s" % _gear_text()
	_update_hull()
	_status.text = ""


## The shape of the coasting orbit, as altitudes above the nominal surface.
##
## Altitudes rather than radii, and above the NOMINAL surface rather than the
## ground below the ship: an apsis happens somewhere else on the planet, where
## the ground is a different height, so the only honest common reference is the
## radius the planet is named by.
##
## Colour is the whole point of showing periapsis at all. Green is an orbit
## that clears the terrain, amber one that dips into the air and will decay,
## red one that ends in the ground -- which is what a deorbit burn is aiming
## for, and what a botched one produces by accident.
func _update_orbit(planet: Planet) -> void:
	if _ship.flight_mode == Ship.FlightMode.LANDED:
		_periapsis.text = "PERI      --"
		_apoapsis.text = "APO       --"
		_periapsis.add_theme_color_override("font_color", IDLE)
		_apoapsis.add_theme_color_override("font_color", IDLE)
		return

	var extremes: Vector2 = planet.orbit_extremes(
		_ship.global_position, _ship.linear_velocity
	)
	var periapsis: float = extremes.x
	_periapsis.text = "PERI %6.0f" % (periapsis - planet.surface_radius)
	_periapsis.add_theme_color_override("font_color", _periapsis_color(planet, periapsis))

	if is_inf(extremes.y):
		# Not a failure: leaving is a legitimate thing to be doing, and the
		# pilot still needs to know the difference between that and an orbit.
		_apoapsis.text = "APO   ESCAPE"
		_apoapsis.add_theme_color_override("font_color", IDLE)
		return
	_apoapsis.text = "APO  %6.0f" % (extremes.y - planet.surface_radius)
	_apoapsis.add_theme_color_override("font_color", GOOD)


func _periapsis_color(planet: Planet, periapsis: float) -> Color:
	if periapsis <= planet.terrain_ceiling():
		return BAD
	if periapsis <= planet.atmosphere_radius():
		return CAUTION
	return GOOD


func _update_hull() -> void:
	_hull.text = "HULL %4.0f%%" % (_ship.hull_integrity * 100.0)
	var colour: Color = GOOD
	if _ship.hull_integrity < 0.25:
		colour = BAD
	elif _ship.hull_integrity < 0.6:
		colour = CAUTION
	_hull.add_theme_color_override("font_color", colour)


func _gear_text() -> String:
	if _ship.gear == null:
		return "NONE"
	if _ship.gear.is_deployed():
		return "DOWN"
	if _ship.gear.is_stowed():
		return "UP"
	return "%3.0f%%" % (_ship.gear.extension * 100.0)


func _gear_color() -> Color:
	if _ship.gear == null:
		return BAD
	if _ship.gear.is_deployed():
		return GOOD
	return IDLE if _ship.gear.is_stowed() else CAUTION


func _slope_color(slope: float) -> Color:
	if _ship.gear == null:
		return IDLE
	if slope > _ship.gear.max_slope:
		return BAD
	return CAUTION if slope > _ship.gear.max_slope * CAUTION_FRACTION else GOOD


func _descent_color(descent: float) -> Color:
	if _ship.gear == null or descent <= 0.0:
		return IDLE
	if descent > _ship.gear.max_vertical_speed:
		return BAD
	return CAUTION if descent > _ship.gear.max_vertical_speed * CAUTION_FRACTION else GOOD


func _status_text() -> String:
	if _ship.flight_mode == Ship.FlightMode.LANDED:
		return "LANDED"
	if _ship.flight_mode == Ship.FlightMode.ORBIT_LOCK:
		return "ORBIT"
	if not _ship.last_landing_rejection.is_empty():
		return "WAVE OFF: %s" % _ship.last_landing_rejection.to_upper()
	return ""
