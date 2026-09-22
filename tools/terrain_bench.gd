extends SceneTree
## Measures the two terrain costs M1.3 asks about. Run with:
##   godot --headless --path . --script res://tools/terrain_bench.gd
##
## Both numbers decide whether bitmap sampling is enough or whether the crust
## has to move to chunked collision polygons (IDEAS.md section 6), so they are
## reported per planet size rather than as one figure.

const PLANET_SCENE: String = "res://scenes/planet.tscn"

## Seeds chosen to span the generated radius range.
const SEEDS: Array[int] = [20260922, 4, 11]

const CARVE_RADIUS: float = 28.0
const CARVE_SAMPLES: int = 40
const SAMPLE_BATCHES: int = 200


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	print("terrain bench")
	for planet_seed: int in SEEDS:
		var scene: PackedScene = load(PLANET_SCENE) as PackedScene
		var planet: Planet = scene.instantiate() as Planet
		planet.planet_seed = planet_seed
		root.add_child(planet)
		await process_frame

		_report(planet)
		planet.free()

	quit(0)


func _report(planet: Planet) -> void:
	var terrain: PlanetTerrain = planet.terrain
	var texels: int = terrain.angular_samples * terrain.radial_samples

	print("")
	print("seed %d: R %.0f px, grid %d x %d = %d texels (%.0f KB)" % [
		planet.planet_seed, planet.surface_radius,
		terrain.angular_samples, terrain.radial_samples, texels, float(texels) / 1024.0,
	])
	print("  texel size at the surface: %.2f px" % (TAU * planet.surface_radius / float(terrain.angular_samples)))
	print("  generation: %.1f ms" % _time_generation(planet))
	print("  carve r=%.0f + texture upload: %.2f ms avg over %d craters" % [
		CARVE_RADIUS, _time_carve(planet), CARVE_SAMPLES,
	])
	print("  hull sampling: %.3f ms per physics tick (%d points, worst case all in rock)" % [
		_time_sampling(planet), Ship.HULL_POINTS.size(),
	])


func _time_generation(planet: Planet) -> float:
	var started: int = Time.get_ticks_usec()
	planet.terrain.generate(planet.planet_seed, planet.surface_radius)
	return float(Time.get_ticks_usec() - started) / 1000.0


## Craters are walked around the planet so no two hit the same rock twice.
func _time_carve(planet: Planet) -> float:
	var total: int = 0
	var hits: int = 0
	for i: int in range(CARVE_SAMPLES):
		var angle: float = TAU * float(i) / float(CARVE_SAMPLES)
		var point: Vector2 = planet.global_position + Vector2.from_angle(angle) * planet.surface_radius
		var started: int = Time.get_ticks_usec()
		var changed: bool = planet.carve(point, CARVE_RADIUS)
		total += Time.get_ticks_usec() - started
		if changed:
			hits += 1
	if hits == 0:
		return 0.0
	return float(total) / float(CARVE_SAMPLES) / 1000.0


## Worst case: every hull point buried, so every point pays for a normal and a
## penetration march on top of the occupancy lookup.
func _time_sampling(planet: Planet) -> float:
	var centre: Vector2 = planet.global_position
	var inside: Vector2 = centre + Vector2.UP * (planet.surface_radius * 0.95)

	var started: int = Time.get_ticks_usec()
	for batch: int in range(SAMPLE_BATCHES):
		for hull_point: Vector2 in Ship.HULL_POINTS:
			var point: Vector2 = inside + hull_point
			if planet.is_solid_at(point):
				var normal: Vector2 = planet.surface_normal_at(point)
				planet.penetration_at(point, normal)
	var elapsed: int = Time.get_ticks_usec() - started
	return float(elapsed) / float(SAMPLE_BATCHES) / 1000.0
