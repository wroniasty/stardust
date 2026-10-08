extends Node
## StreamingManager: decides what exists as nodes around the player.
##
## The model half of IDEAS.md section 9 is `StarSystem`, which knows every
## body whether or not anything has been built for it. This is the other
## half: it walks that list, measures how far the player is from each body,
## and instantiates or frees accordingly. The player is never a child of a
## system -- systems appear and disappear underneath a player who stays put.
##
## **Three states, not the four the design sketched.** Level 1 there was
## "star and planets as sprites", and at 640x360 there is no regime where
## that is a thing: a planet is two thousand pixels across, so it is either
## wider than the screen or off it entirely. A body is either in the world
## or it is not, and what a pilot sees of a distant one is a scanner marker
## drawn from wherever the scanner reads. Inventing a middle level to match
## a table would be a level that does nothing.
##
## Bodies are placed once and do not move (IDEAS.md, "Planety nie okrazaja
## gwiazdy"), which is what keeps landed ships, crates and the contact
## solver working untouched. They spin; their centres stay put.

enum Level {
	GONE, ## Nothing in the scene. The body still exists in the model.
	AWAKE, ## The body itself: terrain, collision, gravity, atmosphere.
	SURFACE, ## Plus what is lying on it.
}

## How often the distance pass runs, in seconds. Bodies do not move and the
## player cannot cross a threshold's worth of hysteresis in half a second,
## so measuring every frame would be measuring the same answer sixty times.
const UPDATE_INTERVAL: float = 0.5

## How far out a body has to be built, as a multiple of its own radius.
##
## Eight, against the six a planet can roll for its gravity well: the node
## has to exist before its pull could reach the ship, or gravity would
## switch on under a pilot who was already inside it.
const WELL_MARGIN: float = 8.0

## And in absolute pixels, because the binding constraint is not gravity
## but eyesight. The scanner reports contacts out to twenty thousand
## pixels, and a contact that has not been built is a contact the scanner
## cannot report -- so nothing may be asleep inside the range of the
## longest-sighted thing in the game. The test pins that against the
## scanner's own number rather than trusting this comment.
const SIGHT_RANGE: float = 26000.0

## How much further out a body has to get before it is taken down again.
## Without the gap a pilot hovering on the threshold rebuilds a planet's
## terrain twice a second.
const HYSTERESIS: float = 1.3

## Surface content, as a multiple of the body's radius. Close enough that
## the pilot is committed to this world rather than passing it.
const SURFACE_IN: float = 2.2

## How many bodies may be started in one frame. The expensive part now runs
## on a worker, but each start still allocates a node and each finish still
## uploads a texture, so they are spread rather than taken together.
const BUILDS_PER_FRAME: int = 1

const PLANET_SCENE: String = "res://scenes/planet.tscn"
const STAR_SCENE: String = "res://scenes/star.tscn"
const STATION_SCENE: String = "res://scenes/station.tscn"
const CRATE_SCENE: String = "res://scenes/loot_crate.tscn"

## Crates are put on the landing shelves rather than scattered: the shelves
## are the places the generator already built to be landed on, so loot and
## landing pull in the same direction (IDEAS.md section 4).
const CRATES_PER_BODY: int = 4

## Crates stand on the shelf rather than hovering over it.
const CRATE_CLEARANCE: float = LootCrate.RADIUS

signal body_awake(body: SystemBody, node: Node2D)
signal body_asleep(body: SystemBody)

## Emitted for each crate put out, so whoever owns the pickup rules can
## wire them up. The manager decides where loot is; it does not decide what
## happens when a ship flies into it.
signal crate_placed(crate: LootCrate)

var system: StarSystem = null

## The moment on the galaxy clock this visit is a snapshot of.
##
## One clock for the whole system, frozen when it is entered, and not one
## per body. Freezing per body would put two planets woken ten minutes
## apart at mutually inconsistent angles, and a body taken down and put
## back would jump to wherever its orbit had carried it -- at several
## hundred px/s that is a planet teleporting a third of a million pixels.
## Between visits the clock runs on, which is exactly right: come back
## later and the system has moved, and nobody saw it happen.
var visit_time: float = 0.0

## What rolls the loot. Handed in rather than reached for by path: the
## generator is an autoload in the game and does not exist at all under
## `--script`, and a manager that can only run inside the game is a
## manager whose delta bookkeeping nothing can check.
var loot: Node = null

## Everything about this system that cannot be regenerated from a seed,
## keyed by body seed: which shelves were emptied, and what the crust looks
## like after being shot at. Handed in rather than owned, because the
## design puts it on `Galaxy` where a save file can reach it -- this is the
## dictionary from there, not a second copy of it.
var deltas: Dictionary = {}

var _container: Node2D = null
var _tracked: Node2D = null
var _levels: Dictionary = {}
var _nodes: Dictionary = {}
var _queue: Array[SystemBody] = []

## Bodies whose crust is being computed on a worker: body -> {planet, task}.
## The node is out of the tree for as long as it is here, which is the
## point -- a half-built planet nothing can ask about is a planet that
## does not have to be defended against.
var _building: Dictionary = {}

var _since_update: float = 0.0


## Hands the manager a system to keep. `at_time` is the moment the whole
## visit is a snapshot of.
func bind(new_system: StarSystem, into: Node2D, at_time: float) -> void:
	clear()
	system = new_system
	_container = into
	visit_time = at_time
	# The star goes up with the system and never comes down. It is the one
	# body whose pull reaches the whole system, so a star that streamed out
	# at distance would be a system that loses its gravity the moment you
	# are far enough away to be coasting on it. It costs one node with no
	# terrain, which is why it can simply always be there.
	if system != null and system.star != null:
		_raise_to(system.star, Level.AWAKE)


## Whose distance decides everything. The player, in practice.
func track(node: Node2D) -> void:
	_tracked = node


func clear() -> void:
	# Waited for rather than abandoned. A worker writing into a freed
	# object's arrays is a crash with no stack worth reading, and there is
	# no cancelling a task that has already started.
	for body: SystemBody in _building.keys():
		var pending: Dictionary = _building[body]
		WorkerThreadPool.wait_for_task_completion(int(pending["task"]))
		(pending["planet"] as Node).free()
	_building.clear()
	for body: SystemBody in _nodes.keys():
		var node: Node2D = _nodes[body]
		if not is_instance_valid(node):
			continue
		# Out of the tree now, deleted whenever. `queue_free` alone leaves
		# the node in its groups until the end of the frame, so a caller
		# that unbinds one system and asks a question before the next
		# frame -- a test, or a jump between systems -- gets answers from
		# a world that has already been thrown away.
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()
	_nodes.clear()
	_levels.clear()
	_queue.clear()
	system = null
	_container = null


func level_of(body: SystemBody) -> Level:
	return _levels.get(body, Level.GONE) as Level


## Every body that exists as a node right now.
##
## Public because something arriving after the fact has to be able to
## catch up: a listener that only hears `body_awake` learns about the
## worlds that wake **after** it, and the first planet of a system is
## always built before anything else has had a chance to listen.
func awake_bodies() -> Array[SystemBody]:
	var out: Array[SystemBody] = []
	for body: Variant in _nodes:
		if is_instance_valid(_nodes[body]):
			out.append(body as SystemBody)
	return out


func node_for(body: SystemBody) -> Node2D:
	var node: Node2D = _nodes.get(body)
	return node if is_instance_valid(node) else null


## Builds a body now, on this thread, skipping both the queue and the
## worker. What arriving in a system needs: the ship has to be put
## somewhere, and it cannot be put next to a planet that is still three
## frames away from existing. Arrival pays the hitch once; flying about
## afterwards pays nothing, which is the right way round.
func force_awake(body: SystemBody) -> Node2D:
	_raise_to(body, Level.SURFACE)
	return node_for(body)


## Where a body stands this visit. Public because the scanner and the map
## want it for bodies that have no node at all.
func position_of(body: SystemBody) -> Vector2:
	return body.position_at(visit_time)


## Throws away the record of what was taken from a body, and puts the loot
## back. For the planet configurator, which rebuilds terrain under the
## shelves the crates were standing on.
func restock(body: SystemBody) -> void:
	_delta(body).erase("taken")
	var node: Node2D = node_for(body)
	if node == null:
		return
	for child: Node in node.get_children():
		if child is LootCrate:
			child.queue_free()
	_place_crates(body, node as Planet)


## Records that a crate is gone for good, so the shelf stays empty.
func forget_crate(crate: LootCrate) -> void:
	if crate.shelf < 0:
		return
	var record: Dictionary = _delta_of(crate.origin_seed)
	var taken: PackedInt32Array = record.get("taken", PackedInt32Array())
	if not taken.has(crate.shelf):
		taken.append(crate.shelf)
	record["taken"] = taken


## This body's record of what cannot be regenerated, made on first ask.
func _delta(body: SystemBody) -> Dictionary:
	return _delta_of(body.seed)


func _delta_of(seed: int) -> Dictionary:
	if not deltas.has(seed):
		deltas[seed] = {}
	return deltas[seed]


func _process(delta: float) -> void:
	_collect_finished()
	_drain_queue()
	_since_update += delta
	if _since_update < UPDATE_INTERVAL:
		return
	_since_update = 0.0
	_sweep()


## One distance pass over every body in the system.
func _sweep() -> void:
	if system == null or _tracked == null or not is_instance_valid(_tracked):
		return
	var from: Vector2 = _tracked.global_position
	for body: SystemBody in system.bodies:
		if not builds_as_node(body):
			continue
		var gap: float = from.distance_to(position_of(body)) - body.radius
		var wanted: Level = _wanted_level(body, gap)
		if wanted > level_of(body):
			_enqueue(body, wanted)
		elif wanted < level_of(body):
			_lower_to(body, wanted)


## What level a body at `gap` pixels of clearance should be, given what it
## is already. The hysteresis is here rather than in the thresholds so that
## coming up and going down read as one rule with a gap in the middle.
func _wanted_level(body: SystemBody, gap: float) -> Level:
	var now: Level = level_of(body)
	var out: float = HYSTERESIS if now >= Level.AWAKE else 1.0
	if gap < body.radius * SURFACE_IN * (HYSTERESIS if now == Level.SURFACE else 1.0):
		return Level.SURFACE
	if gap < awake_distance(body) * out:
		return Level.AWAKE
	return Level.GONE


## How close a body has to be to be built at all.
func awake_distance(body: SystemBody) -> float:
	return maxf(body.radius * WELL_MARGIN, SIGHT_RANGE)


func _enqueue(body: SystemBody, wanted: Level) -> void:
	# Going straight to SURFACE from nothing still queues, because the cost
	# is the terrain and that is paid on the way to AWAKE either way.
	if level_of(body) == Level.GONE:
		if not _queue.has(body) and not _building.has(body):
			_queue.append(body)
		return
	_raise_to(body, wanted)


func _drain_queue() -> void:
	var started: int = 0
	while started < BUILDS_PER_FRAME and not _queue.is_empty():
		var body: SystemBody = _queue.pop_front()
		if system == null or not system.bodies.has(body) or _building.has(body):
			continue
		if node_for(body) != null:
			continue
		_start_build(body)
		started += 1


## Puts a planet's crust on a worker thread. The node is made here and kept
## out of the tree until the crust is ready.
func _start_build(body: SystemBody) -> void:
	if not builds_as_node(body):
		return
	if body.kind == SystemBody.Kind.STATION:
		# Nothing to compute on a worker: a station is a few lines and a
		# lamp, so it goes up whole on the spot rather than taking a
		# frame's build slot to discover it has no crust.
		_raise_to(body, Level.AWAKE)
		return
	var planet: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	planet.name = body.display_name.replace(" ", "_")
	planet.prepare(body, visit_time)
	_building[body] = {
		"planet": planet,
		"task": WorkerThreadPool.add_task(
			planet.crust_task(_remembered_crust(body)), false, planet.name
		),
	}


## Brings in whatever the workers have finished. One per frame, because
## what is left on the main thread -- the texture upload and the visuals --
## is still worth spreading.
func _collect_finished() -> void:
	for body: SystemBody in _building.keys():
		var pending: Dictionary = _building[body]
		if not WorkerThreadPool.is_task_completed(int(pending["task"])):
			continue
		WorkerThreadPool.wait_for_task_completion(int(pending["task"]))
		_building.erase(body)
		var planet: Planet = pending["planet"]
		# The pilot may have left while it was being built. Finished and
		# thrown away rather than kept: keeping it would mean a planet in
		# the world at a distance the manager has already decided is too
		# far, which is the rule the whole class exists to enforce.
		if system == null or not system.bodies.has(body) or _wanted_now(body) == Level.GONE:
			planet.free()
			return
		_container.add_child(planet)
		_nodes[body] = planet
		_levels[body] = Level.AWAKE
		body_awake.emit(body, planet)
		return


## What level a body should be at right now, for deciding whether a build
## that has just finished is still wanted.
func _wanted_now(body: SystemBody) -> Level:
	if _tracked == null or not is_instance_valid(_tracked):
		return Level.GONE
	return _wanted_level(
		body, _tracked.global_position.distance_to(position_of(body)) - body.radius
	)


func _raise_to(body: SystemBody, wanted: Level) -> void:
	if wanted >= Level.AWAKE and node_for(body) == null:
		var node: Node2D = _build(body)
		if node == null:
			# Stations have no scene yet, so they stay in the model until
			# their own step builds them. Saying so here beats a level
			# table that claims they are in the world.
			return
		_nodes[body] = node
		_levels[body] = Level.AWAKE
		body_awake.emit(body, node)
	if wanted == Level.SURFACE and level_of(body) < Level.SURFACE:
		_levels[body] = Level.SURFACE
		var planet: Planet = node_for(body) as Planet
		if planet != null:
			_place_crates(body, planet)


func _lower_to(body: SystemBody, wanted: Level) -> void:
	if wanted == Level.GONE:
		var node: Node2D = node_for(body)
		if node != null:
			_remember_crust(body, node as Planet)
			node.queue_free()
		_nodes.erase(body)
		_levels.erase(body)
		body_asleep.emit(body)
		return
	# Down from SURFACE to AWAKE: the crates go, the world stays. They come
	# back from the same seed minus whatever was taken, so the shelves look
	# the same as they were left.
	_levels[body] = wanted
	var planet: Planet = node_for(body) as Planet
	if planet != null:
		for child: Node in planet.get_children():
			if child is LootCrate:
				child.queue_free()


## Whether the distance sweep has anything to do about this kind of body.
##
## Everything but the star, which is excluded for the opposite reason to
## anything that has no scene: it is never taken down, so measuring how
## far away it is would only ever answer a question nobody asked. It is
## skipped rather than queued and refused, because a body that is queued
## and then refused spends the frame's one build slot on discovering it
## has nothing to do -- which is how, when stations were the refused
## kind, the first planet never got built at all.
static func builds_as_node(body: SystemBody) -> bool:
	return body.kind != SystemBody.Kind.STAR


## The star of the bound system, if it is in the world. Always, in the
## game; null under a test that bound nothing.
func star_node() -> Star:
	if system == null or system.star == null:
		return null
	return node_for(system.star) as Star


## Keeps the crust of a world that was shot at, so the crater is still
## there next time. Compressed, because the grid is up to 1.7 MB of mostly
## runs and an unvisited galaxy should not be paid for in megabytes; the
## raw size goes with it, since decompressing needs to know it.
func _remember_crust(body: SystemBody, planet: Planet) -> void:
	if planet == null:
		return
	var crust: PackedByteArray = planet.crust_delta()
	if crust.is_empty():
		return
	var record: Dictionary = _delta(body)
	record["crust"] = crust.compress(FileAccess.COMPRESSION_ZSTD)
	record["crust_size"] = crust.size()


## The crust this world was left with, unpacked, or nothing.
##
## The mode has to be named on the way out too: decompress() defaults to
## FASTLZ, and a ZSTD buffer read as FASTLZ comes back empty rather than
## wrong -- so the crust was simply refused and the crater quietly vanished.
func _remembered_crust(body: SystemBody) -> PackedByteArray:
	var record: Dictionary = _delta(body)
	if not record.has("crust"):
		return PackedByteArray()
	var packed: PackedByteArray = record["crust"]
	return packed.decompress(int(record["crust_size"]), FileAccess.COMPRESSION_ZSTD)


## Puts it back on a planet that was built on this thread. Only the
## immediate path needs this; a threaded build does it on the worker.
func _replace_crust(body: SystemBody, planet: Planet) -> void:
	var remembered: PackedByteArray = _remembered_crust(body)
	if not remembered.is_empty():
		planet.apply_crust(remembered)


func _build(body: SystemBody) -> Node2D:
	if body.kind == SystemBody.Kind.STAR:
		var star: Star = (load(STAR_SCENE) as PackedScene).instantiate() as Star
		star.name = body.display_name.replace(" ", "_") + "_Star"
		star.adopt(body)
		_container.add_child(star)
		return star
	if body.kind == SystemBody.Kind.STATION:
		var dock: Station = (
			load(STATION_SCENE) as PackedScene
		).instantiate() as Station
		dock.name = body.display_name.replace(" ", "_")
		_container.add_child(dock)
		dock.adopt(body, visit_time)
		return dock
	if not builds_as_node(body):
		return null
	var planet: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	planet.body = body
	planet.placed_at = visit_time
	planet.name = body.display_name.replace(" ", "_")
	_container.add_child(planet)
	_replace_crust(body, planet)
	return planet


## One module per shelf, rolled from the body's own seed, so the same world
## always offers the same finds in the same places -- and offers them once.
func _place_crates(body: SystemBody, planet: Planet) -> void:
	var sites: PackedFloat32Array = planet.landing_sites()
	if sites.is_empty():
		return
	if loot == null:
		return
	var taken: PackedInt32Array = _delta(body).get("taken", PackedInt32Array())
	var scene: PackedScene = load(CRATE_SCENE) as PackedScene
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = body.seed

	for i: int in range(mini(CRATES_PER_BODY, sites.size())):
		# Rolled whether or not it is placed, so taking one crate does not
		# change what the others are.
		var item_seed: int = rng.randi()
		var rarity: int = loot.roll_rarity(rng)
		if taken.has(i):
			continue
		var crate: LootCrate = scene.instantiate() as LootCrate
		crate.hold(loot.generate(item_seed, rarity), rarity)
		crate.origin_seed = body.seed
		crate.shelf = i
		var angle: float = sites[i]
		var ground: float = planet.terrain.surface_radius_at(angle)
		crate.position = Vector2.from_angle(angle) * (ground + CRATE_CLEARANCE)
		crate.rotation = angle + PI * 0.5
		planet.add_child(crate)
		crate_placed.emit(crate)
