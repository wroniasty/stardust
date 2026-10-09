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
var _jump: JumpController = null
var _veil: TransitVeil = null
var _rush: SpeedVeil = null
var _editor: ShipEditor = null
var _map: SystemMap = null
var _chart: GalaxyChart = null
var _garrisons: GarrisonSpawner = null
var _mining: MiningRig = null
var _help: HelpScreen = null
var _flight: FlightHud = null
var _energy: EnergyHud = null
var _creative: CreativeTool = null
var _aim: AimHud = null


## Radius of the crater the debug key blows in the crust.
const DEBUG_CRATER_RADIUS: float = 28.0


## The save this run is picking up, or empty for a fresh start. Read
## before anything is built, because which system to open is the first
## question the world asks and the save is what answers it.
var _resuming: Dictionary = {}


func _ready() -> void:
	_apply_menu_choices()
	if OS.get_cmdline_user_args().has("resume"):
		var saved: Dictionary = SaveGame.read()
		if SaveGame.is_valid(saved):
			_resuming = saved
	_open_system()
	_place_ship()
	var ship: Ship = (player as Player).ship
	if ship != null:
		ship.destroyed.connect(_on_ship_destroyed)
	_build_configurator()
	_build_loadout()
	_build_editor()
	_build_map()
	_build_chart()
	_build_garrisons()
	_build_mining()
	_build_help()
	_build_flight_hud()
	_build_creative()
	_build_aim_hud()
	_build_energy_hud()
	_build_scanner()
	_build_jump_hud()
	_finish_resume()


## What the main menu decided: the galaxy seed, and the ship to start in.
##
## Only when the menu has run. A world opened any other way -- from the editor,
## by a test, resumed from a save -- keeps the seed and the ship it was made
## with.
func _apply_menu_choices() -> void:
	if not GameSettings.chosen:
		return
	world_seed = GameSettings.galaxy_seed
	var ship: Ship = (player as Player).ship
	var preset: Dictionary = ShipFitout.preset(GameSettings.fitout_name)
	if ship != null and not preset.is_empty():
		ShipFitout.apply(ship, preset)


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
	# After the rig, which is built first, so the ORE row has something
	# to ask from the first frame rather than from the first jump.
	_flight.watch_ground(_mining)


func _build_map() -> void:
	_map = SystemMap.new()
	add_child(_map)
	_map.bind(
		Galaxy.system(Galaxy.here), (player as Player).ship, StreamingManager
	)
	_map.teleport_requested.connect(_on_map_teleport)


## The defenders, which need no streaming of their own: a garrison
## belongs to a body and the manager already says which bodies exist.
##
## Their own container rather than `systems`, because that one is
## cleared and rebuilt under them -- a foe parented to a body would be
## freed by machinery that knows nothing about it, and one parented to
## the system node would vanish on a jump without anybody deciding so.
func _build_garrisons() -> void:
	var field: Node2D = Node2D.new()
	field.name = "Garrisons"
	add_child(field)
	_garrisons = GarrisonSpawner.new()
	add_child(_garrisons)
	_garrisons.dropped.connect(_on_garrison_dropped)
	_garrisons.watch((player as Player).ship)
	_garrisons.bind(_tier_here(), Galaxy, StreamingManager, field)


## Which band of the galaxy the ship is in. From the position rather
## than from a system index, for the reason the loot generator wants
## the same answer: a misjump has no index and the dark between two
## core systems is still the core.
## Digging, which needs nothing built: the deposits are a model and the
## only node involved is the ship, which already knows what it is
## standing on.
func _build_mining() -> void:
	_mining = MiningRig.new()
	add_child(_mining)
	_mining.struck.connect(_on_ore_struck)
	_mining.bind(_tier_here(), Galaxy, StreamingManager, (player as Player).ship)
	_mining.watch_star(Star.of(get_tree()))


## One line per whole unit would be one line every half second, so this
## says the kind and leaves the running total to the hold panel.
func _on_ore_struck(kind: int, units: int, _at: Vector2) -> void:
	if units <= 0:
		print("hold full: the %s stays in the ground" % Stores.kind_name(kind))


func _tier_here() -> int:
	return 1 if Galaxy.map == null else Galaxy.map.tier_at(Galaxy.at)


## What a dead defender leaves. The spawner rolls it -- the floor is a
## fact about the roster -- and the world turns it into a thing you can
## fly into, because crates are the world's business.
func _on_garrison_dropped(item: Resource, rarity: int, at: Vector2) -> void:
	_leave_crate(item, rarity, at, Vector2.ZERO, 0.0)


## The galaxy chart, one layer out from the system map. Handed the
## galaxy rather than left to fetch it, like everything else here: the
## autoload does not exist under `--script` and the chart has tests.
func _build_chart() -> void:
	_chart = GalaxyChart.new()
	add_child(_chart)
	_chart.bind(
		Galaxy.map, (player as Player).ship, Galaxy, Galaxy.here, Galaxy.at
	)


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
	var ship: Ship = (player as Player).ship
	_jump = JumpController.new()
	add_child(_jump)
	_jump.bind(ship, Galaxy.current(), Galaxy.map, Galaxy.here, Galaxy, Galaxy.at)
	_jump.crossed.connect(_on_crossed)
	_jump.refused.connect(_on_jump_refused)
	_jump.arrived.connect(_on_jump_arrived)
	_jump.misjumped.connect(_on_misjumped)
	# A misjump is an arrival too, and the one most worth having
	# written down: the pilot may be about to find out they cannot
	# leave.
	_jump.misjumped.connect(func(_toward: int, _adrift_at: Vector2) -> void: _autosave())

	_veil = TransitVeil.new()
	add_child(_veil)
	_veil.bind(_jump)

	_rush = SpeedVeil.new()
	_rush.ship_path = ship.get_path()
	add_child(_rush)

	_jump_hud = JumpHud.new()
	add_child(_jump_hud)
	_jump_hud.bind(
		ship, Galaxy.current(), Galaxy.map, Galaxy.here, Galaxy, _jump, Galaxy.at
	)


## The crossing. The controller decides when; this is the only place
## that knows what a system is made of, so this is where one is taken
## down and the next put up.
##
## Under the effect, halfway through the transit, which is why the order
## here does not have to be careful about what the pilot sees: nothing
## is visible. It does have to be careful about the ship, which is not a
## child of either system and survives both.
func _on_crossed(_from_index: int, to_index: int, at: Vector2, heading: float) -> void:
	var ship: Ship = (player as Player).ship
	if to_index >= 0:
		# Through `enter` rather than by setting the two fields, because
		# that is also where the visit is written down -- and the chart's
		# fog is only ever as good as the one place that records one.
		Galaxy.enter(to_index)
	# The pin was a point in the system being left, and system pixels mean
	# nothing in the next one. Dropped rather than carried: a marker that
	# quietly reappeared over a different world would be worse than one
	# that is gone. Misjumps come through here too -- they emit `crossed`
	# with -1 -- so this is the one place it has to happen.
	NavMarker.unmark()
	var landing: StarSystem = Galaxy.current()
	StreamingManager.bind(landing, systems, Galaxy.time)
	StreamingManager.track(ship)
	# An interstellar sector has nothing in it, which is the point of
	# one. Nothing to force awake, and nothing for the landing camera to
	# be near -- the handle has to be cleared or the next thing to read
	# it reads a planet from a system that no longer exists.
	planet = (
		StreamingManager.force_awake(landing.planets()[0]) as Planet
		if not landing.planets().is_empty() else null
	)

	ship.global_position = at
	ship.global_rotation = heading
	# Most of the way scrubbed off rather than all of it: a crossing that
	# parked the ship would make the heading it just preserved mean
	# nothing.
	ship.linear_velocity *= JumpController.SPEED_KEPT
	ship.angular_velocity = 0.0
	# A crossing is not a movement. Without these the interpolator
	# draws one tick of the ship sliding in from the system it left,
	# and everything the presentation layer puts at the hull is placed
	# somewhere along that streak.
	ship.reset_physics_interpolation()
	ship.snap_drawn()
	# The camera too: it follows with weight, and weight across half a
	# galaxy is a sweep through every system in between. Invisible under
	# the transit veil, which is exactly why it would have stayed.
	var eye: ShipCamera = get_viewport().get_camera_2d() as ShipCamera
	if eye != null:
		eye.snap()

	_jump.bind(ship, landing, Galaxy.map, to_index, Galaxy, Galaxy.at)
	_jump_hud.bind(ship, landing, Galaxy.map, to_index, Galaxy, _jump, Galaxy.at)
	_map.bind(landing, ship, StreamingManager)
	_chart.bind(Galaxy.map, ship, Galaxy, to_index, Galaxy.at)
	_tier_the_loot()
	_garrisons.bind(_tier_here(), Galaxy, StreamingManager, _garrisons_field())
	_mining.bind(_tier_here(), Galaxy, StreamingManager, ship)
	_mining.watch_star(Star.of(get_tree()))
	_dress_sky(landing)
	print("jumped to %s (%s), out at %.0f px" % [
		landing.display_name,
		"adrift" if to_index < 0 else "#%d" % to_index,
		at.length(),
	])


## A jump that fell short. The sector is made before the crossing is
## handled, because the crossing is going to ask for the system the ship
## is now in and there has to be one.
func _on_misjumped(toward: int, adrift_at: Vector2) -> void:
	Galaxy.enter(-1, adrift_at)
	print("misjump: fell short of %s, adrift at %.1f, %.1f ly" % [
		Galaxy.system(toward).display_name, adrift_at.x, adrift_at.y,
	])


## Tells the loot generator where it is, which is what makes a flight
## inwards worth taking.
##
## From the **position** rather than from the system index, because a
## misjump has no index and the dark between two core systems is still
## the core. One line, in the two places the ship can arrive.
func _garrisons_field() -> Node2D:
	return get_node_or_null("Garrisons") as Node2D


func _tier_the_loot() -> void:
	if Galaxy.map != null:
		LootGenerator.tier = Galaxy.map.tier_at(Galaxy.at)


## Rolls this system's sky. From the system's own seed, so two systems
## are two skies and the same system is the same sky every visit.
func _dress_sky(system: StarSystem) -> void:
	var sky: Starfield = get_node_or_null("Starfield") as Starfield
	if sky != null and system != null:
		sky.dress(system.seed)



func _on_jump_refused(reason: String) -> void:
	print("jump: %s" % reason)


## Arriving is the autosave point.
##
## IDEAS.md section 10 puts it here and the reason is the shape of the
## game rather than convenience: a jump is the only thing that changes
## which universe you are in, so it is the only moment where losing
## progress costs more than a flight back. Everything else -- a crate
## picked up, a hole dug -- is a delta that the next jump writes down.
func _on_jump_arrived(index: int) -> void:
	print("arrived at %s" % Galaxy.current().display_name)
	_autosave()


func _autosave() -> void:
	var ship: Ship = (player as Player).ship
	if SaveGame.write(SaveGame.capture(Galaxy, ship)):
		print("saved to %s" % SaveGame.PATH)


## The rest of picking up where a save left off: the ship.
##
## The galaxy half already happened, in `_open_system`, because which
## system to build is the first question the world asks. This is what
## is left once there is a hull to put the loadout back into.
##
## Not automatic. There is no menu until M6, and a game that silently
## resumed would be a game a developer cannot start fresh without
## finding a file -- so it is asked for, with `-- resume` on the command
## line, and M6's menu will call the same function.
func _finish_resume() -> void:
	if _resuming.is_empty():
		return
	var ship: Ship = (player as Player).ship
	SaveGame.restore_ship(_resuming, ship)
	_jump.bind(ship, Galaxy.current(), Galaxy.map, Galaxy.here, Galaxy, Galaxy.at)
	_jump_hud.bind(
		ship, Galaxy.current(), Galaxy.map, Galaxy.here, Galaxy, _jump, Galaxy.at
	)
	print("resumed in %s, %.0f px out, fuel %.0f" % [
		Galaxy.current().display_name, ship.global_position.length(), ship.fuel,
	])


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
	_leave_crate(
		item, rarity, ship.eject_point(), ship.eject_velocity(), JETTISON_GRACE
	)


## One crate, wherever something came loose: thrown overboard, or left
## by something that died. One function because the two differ in a
## point and a velocity and in nothing else, and two copies of this is
## one of them forgetting to connect `touched`.
func _leave_crate(
	item: Resource, rarity: int, at: Vector2, thrown: Vector2, grace: float
) -> void:
	if item == null:
		return
	var crate: LootCrate = (load(CRATE_SCENE) as PackedScene).instantiate() as LootCrate
	crate.hold(item, rarity)
	crate.grace = grace
	crate.touched.connect(_on_crate_touched)
	# Parented to the planet when there is one, so it rides the turning
	# ground rather than hanging in a sky that moves out from under it.
	# First, because eject() speaks world coordinates and a node outside
	# the tree has none.
	var host: Node = planet if planet != null else self
	host.add_child(crate)
	crate.eject(at, thrown)
	print("dropped: %s" % crate.label())


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


## How far from the wreck the hold ends up, how hard it is thrown, and
## how long before it can be picked up again.
##
## The grace matters more than it looks: without it the new ship spawns
## into its own spilled cargo and collects the lot, which would make
## dying free.
const WRECK_SCATTER: float = 26.0
const WRECK_THROW: float = 55.0
const WRECK_GRACE: float = 2.5


## Death is the world's business, not the ship's: the ship reports that it has
## run out of hull, and the world decides where the next one starts. Respawn is
## immediate and in place, with no menu and no reload (IDEAS.md, explore fast,
## die often).
func _on_ship_destroyed(at: Vector2, velocity: Vector2) -> void:
	_spawn_explosion(at, velocity)

	var ship: Ship = (player as Player).ship
	if ship == null or planet == null:
		return

	# The hold goes overboard where the wreck was, which is the whole of
	# what a death costs -- `Ship.spill` says why that and nothing else.
	# Scattered rather than deleted, so the loss is a flight back through
	# whatever killed you rather than a number going down.
	#
	# What is **not** undone: `Galaxy.deltas`. A major beaten before the
	# death stays beaten, the craters stay dug, and the systems stay
	# seen. That is the only irreversible progress a pilot has that is
	# not bolted to the hull, and a death that took it back would make
	# every fight provisional.
	for entry: Dictionary in ship.spill():
		_leave_crate(
			entry["item"],
			int(entry.get("rarity", 0)),
			at + Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * WRECK_SCATTER,
			velocity + Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * WRECK_THROW,
			WRECK_GRACE,
		)

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
	# And the saved address on top of it, before anything is built. The
	# first version restored after the world was up, which opened the
	# starting system, generated its terrain and threw it away -- a
	# visible flash of the wrong place, in a feature whose whole job is
	# putting the pilot back where they were.
	if not _resuming.is_empty():
		var sky: Dictionary = _resuming["galaxy"]
		Galaxy.reset(int(sky["seed"]))
		Galaxy.here = int(sky["here"])
		Galaxy.at = sky["at"] as Vector2
		Galaxy.time = float(sky["time"])
		NavMarker.marked = sky.get("marked", Vector2.INF)
		for key: Variant in sky["deltas"]:
			Galaxy.deltas[key] = (sky["deltas"][key] as Dictionary).duplicate(true)
	var here: StarSystem = Galaxy.current()
	StreamingManager.loot = LootGenerator
	_tier_the_loot()
	# The one delta store, where the design puts it and where a save file
	# will look for it.
	StreamingManager.deltas = Galaxy.deltas
	StreamingManager.bind(here, systems, Galaxy.time)
	StreamingManager.track((player as Player).ship)
	StreamingManager.crate_placed.connect(_on_crate_placed)
	planet = (
		StreamingManager.force_awake(here.planets()[0]) as Planet
		if not here.planets().is_empty() else null
	)
	_dress_sky(here)
	print("system %s (%s of %d): %s" % [
		here.display_name,
		"adrift" if Galaxy.here < 0 else "#%d" % Galaxy.here,
		Galaxy.map.count(),
		(
			"arriving at %s, %.0f px out" % [
				planet.body.display_name, planet.body.orbit_radius,
			] if planet != null else "nothing here"
		),
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
