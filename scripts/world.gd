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
var _jump_hud: JumpHud = null
var _editor: ShipEditor = null
var _map: SystemMap = null
var _help: HelpScreen = null
var _flight: FlightHud = null
var _energy: EnergyHud = null
var _creative: CreativeTool = null
var _aim: AimHud = null


## Radius of the crater the debug key blows in the crust.
const DEBUG_CRATER_RADIUS: float = 28.0


func _ready() -> void:
	_open_system()
	_place_ship()
	var ship: Ship = (player as Player).ship
	if ship != null:
		ship.destroyed.connect(_on_ship_destroyed)
	_build_configurator()
	_build_loadout()
	_build_editor()
	_build_map()
	_build_help()
	_build_flight_hud()
	_build_creative()
	_build_aim_hud()
	_build_energy_hud()
	_build_scanner()
	_build_jump_hud()


## The planet configurator edits the planet; putting the ship somewhere that
## still exists afterwards is the world's business, the same way respawning
## after a death is.
func _build_configurator() -> void:
	_configurator = PlanetConfigurator.new()
	add_child(_configurator)
	_configurator.bind(planet)
	_configurator.rebuilt.connect(_on_planet_rebuilt)
	_configurator.teleport_requested.connect(_on_next_landing_site)


func _build_flight_hud() -> void:
	_flight = FlightHud.new()
	add_child(_flight)
	_flight.bind((player as Player).ship)


func _build_map() -> void:
	_map = SystemMap.new()
	add_child(_map)
	_map.bind(
		Galaxy.system(Galaxy.here), (player as Player).ship, StreamingManager
	)
	_map.teleport_requested.connect(_on_map_teleport)


func _build_help() -> void:
	_help = HelpScreen.new()
	add_child(_help)


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


## The outward-looking half of the scanner: where else there is to be.
##
## Built after the system is open, because it has to be handed the system
## it is in -- the mass lock is the system's own number, and a HUD that
## fetched it from an autoload would be a HUD with no tests.
func _build_jump_hud() -> void:
	_jump_hud = JumpHud.new()
	add_child(_jump_hud)
	_jump_hud.bind(
		(player as Player).ship, Galaxy.system(Galaxy.here), Galaxy.map, Galaxy.here, Galaxy
	)


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
	# Told, not inferred: the shelf this came off stays empty when the
	# planet is streamed out and back.
	StreamingManager.forget_crate(crate)
	crate.queue_free()


func _on_planet_rebuilt() -> void:
	# The ground the ship was standing on may not exist any more, and at worst
	# the ship is now inside a mountain, so a rebuild always ends with a
	# landing rather than leaving the pilot wherever they happened to be.
	_landing_site = 0
	_land_on_site(_landing_site)
	# The old crates stood on ground that no longer exists, and a rebuilt
	# world is a new world: whatever was taken off the old shelves has no
	# claim on the new ones.
	if planet.body != null:
		StreamingManager.restock(planet.body)


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


func _process(_delta: float) -> void:
	_follow_planet()


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


## Where a teleport puts the ship, as a multiple of the planet's radius
## above its terrain ceiling, and as a multiple of a bodiless thing's own
## radius. High enough to be in a stable orbit rather than in the air.
const ARRIVAL_CLEARANCE: float = 0.8
const ARRIVAL_RATIO: float = 3.0


## Opens a system: the manager takes it from here.
##
## The one body built by hand is the one the ship starts at, and it is
## built immediately rather than queued -- the ship has to be put
## somewhere, and it cannot be put next to a planet that is three frames
## away from existing. Everything else comes and goes as the pilot flies.
func _open_system() -> void:
	# Reset rather than assignment: the seed is what the galaxy is made of,
	# so setting it without rebuilding would leave the layout belonging to
	# the previous one.
	Galaxy.reset(world_seed)
	var here: StarSystem = Galaxy.system(Galaxy.here)
	StreamingManager.loot = LootGenerator
	# The one delta store, where the design puts it and where a save file
	# will look for it.
	StreamingManager.deltas = Galaxy.deltas
	StreamingManager.bind(here, systems, Galaxy.time)
	StreamingManager.track((player as Player).ship)
	StreamingManager.crate_placed.connect(_on_crate_placed)
	planet = StreamingManager.force_awake(here.planets()[0]) as Planet
	print("system %s (#%d of %d): arriving at %s, %.0f px out" % [
		here.display_name, Galaxy.here, Galaxy.map.count(),
		planet.body.display_name, planet.body.orbit_radius,
	])


func _on_crate_placed(crate: LootCrate) -> void:
	crate.touched.connect(_on_crate_touched)


## Puts the ship in orbit around whatever was picked on the map.
##
## A dev convenience, the same kind as the configurator's teleport between
## landing shelves: until M4 there is no crossing a system except by
## flying it, and testing the streaming manager that way is testing it
## once an hour.
##
## Built before placed, and not queued: the ship cannot be put in orbit
## around a planet that is three frames away from existing, which is
## exactly what `force_awake` is for.
func _on_map_teleport(body: SystemBody) -> void:
	var ship: Ship = (player as Player).ship
	if ship == null:
		return
	var node: Node2D = StreamingManager.force_awake(body)
	var centre: Vector2 = StreamingManager.position_of(body)
	# Arrive on the side the ship was already on, so a teleport does not
	# also silently turn the pilot around.
	var up: Vector2 = (ship.global_position - centre).normalized()
	if up.is_zero_approx():
		up = Vector2.UP

	var arrival: Planet = node as Planet
	if arrival == null:
		# A star or a station: nothing to orbit yet, so simply stand off it.
		ship.respawn(centre + up * body.radius * ARRIVAL_RATIO, Vector2.ZERO)
		return
	var radius: float = arrival.terrain_ceiling() + arrival.surface_radius * ARRIVAL_CLEARANCE
	ship.respawn(
		arrival.global_position + up * radius,
		up.orthogonal() * arrival.circular_orbit_speed(radius),
	)
	_follow_planet()
	print("teleported to %s" % body.display_name)


## Keeps the world's idea of "the planet" on the one the ship is at.
##
## It used to be whichever planet the world built at startup, which was
## fine while there was only ever one. With bodies streaming in and out,
## a stale reference means the configurator edits a planet the pilot left
## and a crater goes into the wrong world.
func _follow_planet() -> void:
	var ship: Ship = (player as Player).ship
	if ship == null:
		return
	var here: Planet = Planet.nearest(get_tree(), ship.global_position)
	if here == null or here == planet:
		return
	planet = here
	if _configurator != null:
		_configurator.bind(planet)


func _place_ship() -> void:
	var ship: Ship = (player as Player).ship
	if ship == null or planet == null:
		return
	# Measured from the terrain ceiling, not the nominal surface: mountains
	# rise above the surface radius and spawning inside one is no fun.
	var altitude: float = planet.surface_radius * spawn_altitude_ratio
	ship.global_position = planet.global_position + Vector2.UP * (planet.terrain_ceiling() + altitude)
	ship.linear_velocity = Vector2.ZERO
