extends SceneTree
## Long-duration orbit check for M1.5. Run with:
##   godot --headless --fixed-fps 60 --path . --script res://tools/orbit_endurance.gd
##
## --fixed-fps is not optional. Without it the headless loop runs in real time
## and the cases take fifteen wall-clock minutes; with it the loop runs as fast
## as the CPU allows while still reporting a 1/60 s step, so the integrator sees
## exactly the timestep the game uses.
##
## The smoke test only watches an orbit for half a minute, which is enough to
## catch a broken gravity function but not enough to see semi-implicit Euler
## precess. This runs circular and elliptical orbits for minutes and reports the
## drift, so the answer goes into IDEAS.md as a number rather than an opinion.
##
## Orbit lock is switched off here: the point is to measure the raw integrator,
## and a locked ship holds its radius by definition.

const PLANET_SCENE: String = "res://scenes/planet.tscn"
const SHIP_SCENE: String = "res://scenes/ship.tscn"
const TEST_SEED: int = 20260922

const MINUTES: float = 5.0

## Starting radius as a multiple of the planet radius, and the fraction of
## circular speed that sets the shape. 1.0 is circular; below it the start point
## becomes apoapsis and the orbit is an ellipse.
##
## The speeds are not arbitrary. Released at k times circular speed, an orbit
## comes back down to r0 * k^2 / (2 - k^2), and if that dips into the air or the
## crust the run measures drag and crashes instead of the integrator. Every case
## here keeps its periapsis above the atmosphere, and _begin_case checks it.
const CASES: Array[Vector2] = [
	Vector2(2.0, 1.00),
	Vector2(2.0, 0.93),
	Vector2(3.0, 0.85),
]

var _planet: Planet = null
var _ship: Ship = null
var _case: int = -1
var _ticks: int = 0
var _total_ticks: int = 0

var _start_radius: float = 0.0
var _min_radius: float = INF
var _max_radius: float = 0.0
var _first_apoapsis: float = 0.0
var _last_apoapsis: float = 0.0
var _first_periapsis: float = 0.0
var _last_periapsis: float = 0.0
var _previous_radius: float = 0.0
var _rising: bool = false
var _samples: int = 0


func _initialize() -> void:
	_total_ticks = int(MINUTES * 60.0 * float(Engine.physics_ticks_per_second))
	print("orbit endurance: %.0f minutes per case" % MINUTES)
	# Deliberately not starting a case here. Nodes added from _initialize() are
	# not in the tree yet, so the planet would still be carrying its default
	# radius and gravity, and every number below would describe a world that
	# does not exist.


func _physics_process(_delta: float) -> bool:
	if _case < 0:
		_case = 0
		_begin_case()
		return false

	_ticks += 1

	var radius: float = _ship.global_position.distance_to(_planet.global_position)
	_min_radius = minf(_min_radius, radius)
	_max_radius = maxf(_max_radius, radius)

	# Turning points, not just the range: a shrinking orbit shows up as each
	# high point coming in lower than the last, which min/max alone would hide.
	#
	# The detector needs two real samples before it means anything. Seeding it
	# from the intended start instead reported the launch radius as the first
	# periapsis and turned a stable ellipse into a fake 24% collapse.
	_samples += 1
	if _samples == 1:
		_previous_radius = radius
	elif _samples == 2:
		_rising = radius > _previous_radius
		_previous_radius = radius
	else:
		var rising_now: bool = radius > _previous_radius
		if _rising and not rising_now:
			if _first_apoapsis == 0.0:
				_first_apoapsis = _previous_radius
			_last_apoapsis = _previous_radius
		elif not _rising and rising_now:
			if _first_periapsis == 0.0:
				_first_periapsis = _previous_radius
			_last_periapsis = _previous_radius
		_rising = rising_now
		_previous_radius = radius

	if _ticks < _total_ticks:
		return false

	_report()
	_clear_case()
	_case += 1
	if _case >= CASES.size():
		quit(0)
		return true
	_begin_case()
	return false


func _begin_case() -> void:
	_ticks = 0
	_min_radius = INF
	_max_radius = 0.0
	_first_apoapsis = 0.0
	_last_apoapsis = 0.0
	_first_periapsis = 0.0
	_last_periapsis = 0.0
	_rising = false
	_samples = 0

	var planet_scene: PackedScene = load(PLANET_SCENE) as PackedScene
	_planet = planet_scene.instantiate() as Planet
	_planet.planet_seed = TEST_SEED
	root.add_child(_planet)

	var ship_scene: PackedScene = load(SHIP_SCENE) as PackedScene
	_ship = ship_scene.instantiate() as Ship
	_ship.use_player_input = false
	root.add_child(_ship)

	var case_data: Vector2 = CASES[_case]
	_start_radius = _planet.surface_radius * case_data.x
	_ship.global_position = _planet.global_position + Vector2.UP * _start_radius
	_ship.linear_velocity = Vector2.RIGHT * _planet.circular_orbit_speed(_start_radius) * case_data.y

	var expected_low: float = _expected_periapsis(_start_radius, case_data.y)
	var air_top: float = _planet.atmosphere_radius()
	print("")
	print("%s: start %.0f px (%.1f R) at %.0f%% of circular speed" % [
		_shape_name(case_data.y), _start_radius, case_data.x, case_data.y * 100.0,
	])
	print("  predicted periapsis %.0f px, atmosphere tops out at %.0f px" % [expected_low, air_top])
	if expected_low <= air_top:
		print("  WARNING: this orbit dips into the air, the result measures drag, not the integrator")


## Where an orbit released at `fraction` of circular speed comes back down to.
func _expected_periapsis(radius: float, fraction: float) -> float:
	if is_equal_approx(fraction, 1.0):
		return radius
	var squared: float = fraction * fraction
	return radius * squared / (2.0 - squared)


func _shape_name(fraction: float) -> String:
	return "circular" if is_equal_approx(fraction, 1.0) else "elliptical"


func _report() -> void:
	var case_data: Vector2 = CASES[_case]
	print("  radius over %.0f min: %.0f .. %.0f px" % [MINUTES, _min_radius, _max_radius])

	if is_equal_approx(case_data.y, 1.0):
		var drift: float = maxf(_max_radius - _start_radius, _start_radius - _min_radius) / _start_radius
		print("  drift from the starting radius: %.4f%%" % (drift * 100.0))
		return

	if _first_apoapsis > 0.0 and _last_apoapsis > 0.0:
		var decay: float = (_first_apoapsis - _last_apoapsis) / _first_apoapsis
		print("  apoapsis %.0f -> %.0f px over the run, change %.4f%%" % [
			_first_apoapsis, _last_apoapsis, decay * 100.0,
		])
	if _first_periapsis > 0.0 and _last_periapsis > 0.0:
		var shift: float = (_last_periapsis - _first_periapsis) / _first_periapsis
		print("  periapsis %.0f -> %.0f px over the run, change %.4f%%" % [
			_first_periapsis, _last_periapsis, shift * 100.0,
		])
	if _first_apoapsis == 0.0:
		print("  no full orbit completed inside the run")


func _clear_case() -> void:
	if _ship != null:
		_ship.free()
		_ship = null
	if _planet != null:
		_planet.free()
		_planet = null
