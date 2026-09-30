class_name World
extends Node2D
## World: scene root. Everything that physically exists lives under this node.
##
## The player never becomes a child of a system: systems are instantiated and
## freed underneath a player that stays put (see IDEAS.md section 9).
##
## The system comes out of the model now: `world_seed` seeds the galaxy, the
## galaxy lays out system zero, and the world builds the first planet of it
## where the orbit says. Nothing is hand-placed and nothing is invented here
## -- change the seed and you get another system, with another world in it.
##
## Still only the one planet: switching bodies in and out as the player
## moves is the streaming manager, and this is the joint it plugs into.

const PLANET_SCENE: String = "res://scenes/planet.tscn"
const EXPLOSION_SCENE: String = "res://scenes/explosion.tscn"
const CRATE_SCENE: String = "res://scenes/loot_crate.tscn"

## Crates are put on the landing shelves rather than scattered at random. The
## shelves are the places the generator already built to be landed on, so loot
## and landing pull in the same direction instead of asking the pilot to set
## down on a cliff (IDEAS.md section 4).
const CRATES_PER_PLANET: int = 4

## Crates are placed standing on the shelf, not hovering over it. Anything
## more and they spend their first second falling the difference, which is
## work done to arrive where they were already put.
const CRATE_CLEARANCE: float = LootCrate.RADIUS

## How long a jettisoned crate ignores the ship that dropped it. Long enough
## to fly clear at a crawl, short enough that coming straight back for it is
## a decision rather than a wait.
const JETTISON_GRACE: float = 2.0

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

## The dev tool on F6, and which shelf it last put the ship on.
var _configurator: PlanetConfigurator = null
var _landing_site: int = 0
var _loadout: LoadoutScreen = null
var _scanner: ScannerHud = null
var _editor: ShipEditor = null
var _energy: EnergyHud = null
var _creative: CreativeTool = null
var _aim: AimHud = null


## Radius of the crater the debug key blows in the crust.
const DEBUG_CRATER_RADIUS: float = 28.0


func _ready() -> void:
	_spawn_planet()
	_place_ship()
	var ship: Ship = (player as Player).ship
	if ship != null:
		ship.destroyed.connect(_on_ship_destroyed)
	_build_configurator()
	_build_loadout()
	_build_editor()
	_build_creative()
	_build_aim_hud()
	_build_energy_hud()
	_build_scanner()
	_spawn_crates()


## The planet configurator edits the planet; putting the ship somewhere that
## still exists afterwards is the world's business, the same way respawning
## after a death is.
func _build_configurator() -> void:
	_configurator = PlanetConfigurator.new()
	add_child(_configurator)
	_configurator.bind(planet)
	_configurator.rebuilt.connect(_on_planet_rebuilt)
	_configurator.teleport_requested.connect(_on_next_landing_site)


func _build_editor() -> void:
	_editor = ShipEditor.new()
	add_child(_editor)
	_editor.bind((player as Player).ship)


func _build_creative() -> void:
	_creative = CreativeTool.new()
	add_child(_creative)
	_creative.bind((player as Player).ship)


func _build_aim_hud() -> void:
	_aim = AimHud.new()
	add_child(_aim)
	_aim.bind((player as Player).ship)


func _build_energy_hud() -> void:
	_energy = EnergyHud.new()
	add_child(_energy)
	_energy.bind((player as Player).ship)


func _build_scanner() -> void:
	_scanner = ScannerHud.new()
	add_child(_scanner)
	_scanner.bind((player as Player).ship)


func _build_loadout() -> void:
	_loadout = LoadoutScreen.new()
	add_child(_loadout)
	var ship: Ship = (player as Player).ship
	_loadout.bind(ship)
	if ship != null:
		ship.jettisoned.connect(_on_jettisoned)


## A module thrown overboard becomes a crate where the ship was, so it can be
## flown back to. Parented to the planet when there is one, so it rides the
## turning ground like every other crate rather than hanging in the sky the
## ground moves out from under.
func _on_jettisoned(item: Resource, rarity: int) -> void:
	var ship: Ship = (player as Player).ship
	if ship == null:
		return
	var crate: LootCrate = (load(CRATE_SCENE) as PackedScene).instantiate() as LootCrate
	crate.hold(item, rarity)
	crate.grace = JETTISON_GRACE
	crate.touched.connect(_on_crate_touched)
	var host: Node = planet if planet != null else self
	host.add_child(crate)
	# Out of the bay and aft, carrying the ship's own velocity. Parented
	# first, because eject() speaks world coordinates and a node outside the
	# tree has none.
	crate.eject(ship.eject_point(), ship.eject_velocity())
	print("jettisoned: %s" % crate.label())


## Rolls one module per shelf from the world seed, so the same world always
## offers the same finds in the same places.
func _spawn_crates() -> void:
	if planet == null:
		return
	var sites: PackedFloat32Array = planet.landing_sites()
	if sites.is_empty():
		return

	var scene: PackedScene = load(CRATE_SCENE) as PackedScene
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + 7919

	for i: int in range(mini(CRATES_PER_PLANET, sites.size())):
		var angle: float = sites[i]
		var crate: LootCrate = scene.instantiate() as LootCrate
		var item_seed: int = rng.randi()
		var rarity: int = LootGenerator.roll_rarity(rng)
		crate.hold(LootGenerator.generate(item_seed, rarity), rarity)
		# A child of the planet, in the planet's own frame, so it turns with
		# the ground and needs no per-frame bookkeeping.
		var ground: float = planet.terrain.surface_radius_at(angle)
		crate.position = Vector2.from_angle(angle) * (ground + CRATE_CLEARANCE)
		crate.rotation = angle + PI * 0.5
		crate.touched.connect(_on_crate_touched)
		planet.add_child(crate)


func _on_crate_touched(crate: LootCrate, body: Node) -> void:
	var ship: Ship = body as Ship
	if ship == null or crate.item == null:
		return
	if not ship.take(crate.item):
		# A full hold is the pilot's problem to solve, not a reason to destroy
		# what they flew into.
		return
	print("picked up: %s" % crate.label())
	_loadout.announce_pickup()
	crate.queue_free()


func _on_planet_rebuilt() -> void:
	# The ground the ship was standing on may not exist any more, and at worst
	# the ship is now inside a mountain, so a rebuild always ends with a
	# landing rather than leaving the pilot wherever they happened to be.
	_landing_site = 0
	_land_on_site(_landing_site)
	# The old crates stood on ground that no longer exists.
	for child: Node in planet.get_children():
		if child is LootCrate:
			child.queue_free()
	_spawn_crates()


func _on_next_landing_site() -> void:
	_landing_site += 1
	_land_on_site(_landing_site)


## Sets the ship down just above the shelf at `index`, at rest with respect to
## the ground and with the legs out.
func _land_on_site(index: int) -> void:
	var ship: Ship = (player as Player).ship
	if ship == null or planet == null:
		return

	var sites: PackedFloat32Array = planet.landing_sites()
	if sites.is_empty():
		_place_ship()
		return

	var angle: float = sites[posmod(index, sites.size())]
	var ground: float = planet.terrain.surface_radius_at(angle)
	var point: Vector2 = planet.polar_to_world(angle, ground + LANDING_CLEARANCE)

	# Standing up: the ship's nose has to point away from the centre. Local -y
	# is the nose, and a Node2D at rotation r sends local -y to (sin r, -cos r),
	# so the outward angle plus a quarter turn is what stands it on its legs.
	var up: Vector2 = (point - planet.global_position).normalized()
	ship.respawn(point, planet.surface_velocity_at(point))
	ship.global_rotation = up.angle() + PI * 0.5
	if ship.gear != null:
		ship.gear.set_deployed(true)
		ship.gear.extension = 1.0


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

## How far above the shelf the configurator drops the ship. Enough for the
## legs to be clear, little enough that it settles at once instead of falling.
const LANDING_CLEARANCE: float = 22.0


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

	if event.is_action_pressed("debug_repair") and ship != null:
		ship.repair_engines()
		print("debug: engines repaired")


func _damage_engine(ship: Ship, mount_name: String) -> void:
	for engine: EngineInstance in ship.engines:
		if engine.mount.name == mount_name:
			engine.health = DEBUG_ENGINE_HEALTH
			print("debug: %s health set to %.2f" % [mount_name, engine.health])
			return
	print("debug: no mount called %s" % mount_name)


## Which system this world is a visit to. One, for now: laying systems out
## across a galaxy is M4, and until then index zero is the only address.
const SYSTEM_INDEX: int = 0


func _spawn_planet() -> void:
	var scene: PackedScene = load(PLANET_SCENE) as PackedScene
	planet = scene.instantiate() as Planet
	# Seeded through the galaxy rather than straight from the export, so the
	# planet the pilot lands on is a body the model knows about -- with an
	# orbit, a name and a place in a system -- and not a one-off rolled here.
	Galaxy.galaxy_seed = world_seed
	planet.body = Galaxy.system(SYSTEM_INDEX).planets()[0]
	planet.placed_at = Galaxy.time
	systems.add_child(planet)
	print("system %s: %s at %.0f px" % [
		Galaxy.system(SYSTEM_INDEX).display_name, planet.body.display_name,
		planet.body.orbit_radius,
	])


func _place_ship() -> void:
	var ship: Ship = (player as Player).ship
	if ship == null or planet == null:
		return
	# Measured from the terrain ceiling, not the nominal surface: mountains
	# rise above the surface radius and spawning inside one is no fun.
	var altitude: float = planet.surface_radius * spawn_altitude_ratio
	ship.global_position = planet.global_position + Vector2.UP * (planet.terrain_ceiling() + altitude)
	ship.linear_velocity = Vector2.ZERO
