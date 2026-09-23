class_name World
extends Node2D
## World: scene root. Everything that physically exists lives under this node.
##
## The player never becomes a child of a system: systems are instantiated and
## freed underneath a player that stays put (see IDEAS.md section 9).
##
## For M1 the "system" is one seeded planet at the origin and the ship parked
## above it. Nothing is hand-placed: change the seed and you get another world.

const PLANET_SCENE: String = "res://scenes/planet.tscn"
const EXPLOSION_SCENE: String = "res://scenes/explosion.tscn"

## Where a wrecked ship comes back, as a multiple of the planet radius. Outside
## the atmosphere, so the pilot gets a moment to gather themselves rather than
## respawning already on fire.
const RESPAWN_RADIUS_RATIO: float = 2.0

## Seed every world object is derived from.
@export var world_seed: int = 20260922

## Where the ship starts, as a fraction of the planet radius above the terrain
## ceiling. Tuned to drop the ship near the top of the atmosphere rather than
## far out in empty space.
@export var spawn_altitude_ratio: float = 0.3

## Container the StreamingManager instantiates the active system into.
@onready var systems: Node2D = $Systems

## The player, kept as a direct child of the world for the whole game.
@onready var player: Node2D = $Player

var planet: Planet = null


## Radius of the crater the debug key blows in the crust.
const DEBUG_CRATER_RADIUS: float = 28.0


func _ready() -> void:
	_spawn_planet()
	_place_ship()
	var ship: Ship = (player as Player).ship
	if ship != null:
		ship.destroyed.connect(_on_ship_destroyed)


## Death is the world's business, not the ship's: the ship reports that it has
## run out of hull, and the world decides where the next one starts. Respawn is
## immediate and in place, with no menu and no reload (IDEAS.md, explore fast,
## die often).
func _on_ship_destroyed(at: Vector2, velocity: Vector2) -> void:
	_spawn_explosion(at, velocity)

	var ship: Ship = (player as Player).ship
	if ship == null or planet == null:
		return

	# Straight back onto a circular orbit, which is both a safe place to be and
	# the state the rest of the game is built around.
	var radius: float = planet.surface_radius * RESPAWN_RADIUS_RATIO
	var up: Vector2 = Vector2.UP
	if not at.is_zero_approx() and at != planet.global_position:
		# Above wherever the wreck happened, so the pilot keeps their bearings.
		up = (at - planet.global_position).normalized()
	ship.respawn(
		planet.global_position + up * radius,
		up.orthogonal() * planet.circular_orbit_speed(radius),
	)


func _spawn_explosion(at: Vector2, velocity: Vector2) -> void:
	var scene: PackedScene = load(EXPLOSION_SCENE) as PackedScene
	var explosion: Explosion = scene.instantiate() as Explosion
	explosion.global_position = at
	add_child(explosion)
	explosion.set_drift(velocity)
	explosion.scar_terrain()


## Health the debug key drops an engine to, low enough for the asymmetry to be
## obvious in flight.
const DEBUG_ENGINE_HEALTH: float = 0.3


func _unhandled_input(event: InputEvent) -> void:
	var ship: Ship = (player as Player).ship

	# Sandbox shortcut so terrain destruction can be judged before there is a
	# weapon to do it properly (M1.4).
	if event.is_action_pressed("debug_carve") and ship != null and planet != null:
		planet.carve(ship.global_position, DEBUG_CRATER_RADIUS)

	# Cripples one side of the rotation pair, so the asymmetric handling the
	# control groups produce can be felt without waiting for combat damage.
	if event.is_action_pressed("debug_damage_engine") and ship != null:
		_damage_engine(ship, "NoseLeftTorque")


func _damage_engine(ship: Ship, mount_name: String) -> void:
	for engine: EngineInstance in ship.engines:
		if engine.mount.name == mount_name:
			engine.health = DEBUG_ENGINE_HEALTH
			print("debug: %s health set to %.2f" % [mount_name, engine.health])
			return
	print("debug: no mount called %s" % mount_name)


func _spawn_planet() -> void:
	var scene: PackedScene = load(PLANET_SCENE) as PackedScene
	planet = scene.instantiate() as Planet
	planet.planet_seed = world_seed
	systems.add_child(planet)


func _place_ship() -> void:
	var ship: Ship = (player as Player).ship
	if ship == null or planet == null:
		return
	# Measured from the terrain ceiling, not the nominal surface: mountains
	# rise above the surface radius and spawning inside one is no fun.
	var altitude: float = planet.surface_radius * spawn_altitude_ratio
	ship.global_position = planet.global_position + Vector2.UP * (planet.terrain_ceiling() + altitude)
	ship.linear_velocity = Vector2.ZERO
