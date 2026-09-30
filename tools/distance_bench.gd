extends SceneTree
## How far from the origin the game can be played before float32 shows. Run:
##   godot --headless --path . --script res://tools/distance_bench.gd
##
## Written to answer one open question in PLAN M3 -- floating origin, yes or
## no -- with numbers instead of the received wisdom that Godot "starts
## shaking past a hundred thousand units". Systems come out between 41k and
## 302k pixels across, so the question is whether that range costs anything,
## and the only way to know is to move the whole scene out and look.
##
## Three measurements, all in the planet's own frame, because in the world's
## frame a ship parked on a turning planet is moving and always was:
##
## - **store**: the error in holding a coordinate at all. The floor under
##   everything else, and pure float32 with no physics in it.
## - **local**: a world point taken into the planet's frame and back.
## - **rest**: how far a ship lying on the ground slides in ten seconds,
##   held there by the contact solver rather than frozen. This is the one
##   that mixes precision with real physics: the value at the origin is the
##   solver's own creep, and the growth above it is what distance costs.
## - **orbit**: how much the radius of a coasting circular orbit changes in
##   ten seconds. Analytically zero, so whatever comes out is the
##   integrator and the float together.
##
## Not measured here, and worth saying so: rendering. Headless draws
## nothing, so visible shimmer at distance is a separate question.

const PLANET_SCENE: String = "res://scenes/planet.tscn"
const SHIP_SCENE: String = "res://scenes/ship.tscn"
const PLANET_SEED: int = 20260922

const OFFSETS: Array[float] = [0.0, 40000.0, 100000.0, 300000.0, 1000000.0]

## Long enough for the contact solver to stop arguing with the landing, and
## then ten seconds of measurement at sixty ticks.
const SETTLE_TICKS: int = 240
const MEASURE_TICKS: int = 600


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var planet: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	planet.planet_seed = PLANET_SEED
	root.add_child(planet)
	var ship: Ship = (load(SHIP_SCENE) as PackedScene).instantiate() as Ship
	ship.use_player_input = false
	root.add_child(ship)
	ship.rebuild_control_groups(false)
	await process_frame

	print("offset       | store px | local px | rest px/10s | orbit px/10s")
	for offset: float in OFFSETS:
		await _at(ship, planet, offset)
	quit()


func _at(ship: Ship, planet: Planet, offset: float) -> void:
	planet.global_position = Vector2(offset, 0.0)

	var wanted: Vector2 = Vector2(offset + 1234.5678, 987.6543)
	var marker: Node2D = Node2D.new()
	planet.add_child(marker)
	marker.global_position = wanted
	var store_error: float = marker.global_position.distance_to(wanted)
	var probe: Vector2 = Vector2(700.3, -415.9)
	var local_error: float = planet.to_local(planet.to_global(probe)).distance_to(probe)
	marker.queue_free()

	var angle: float = 0.0
	var ground: float = planet.terrain.surface_radius_at(angle)
	var up: Vector2 = Vector2.from_angle(angle + planet.global_rotation)
	ship.respawn(planet.global_position + up * (ground + ship.hull_extent() + 1.0), Vector2.ZERO)
	ship.global_rotation = up.angle() + PI * 0.5
	ship.linear_velocity = planet.surface_velocity_at(ship.global_position)
	for tick: int in range(SETTLE_TICKS):
		await physics_frame
	var was: Vector2 = planet.to_local(ship.global_position)
	for tick: int in range(MEASURE_TICKS):
		await physics_frame
	var rest_drift: float = planet.to_local(ship.global_position).distance_to(was)

	var radius: float = planet.surface_radius * 2.2
	var mu: float = planet.surface_gravity * planet.surface_radius * planet.surface_radius
	ship.respawn(
		planet.global_position + Vector2(radius, 0.0), Vector2(0.0, sqrt(mu / radius))
	)
	var first: float = ship.global_position.distance_to(planet.global_position)
	for tick: int in range(MEASURE_TICKS):
		await physics_frame
	var orbit_drift: float = absf(
		ship.global_position.distance_to(planet.global_position) - first
	)

	print("%8.0f px | %8.4f | %8.4f | %11.4f | %12.3f" % [
		offset, store_error, local_error, rest_drift, orbit_drift,
	])
