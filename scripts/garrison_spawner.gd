class_name GarrisonSpawner
extends Node2D
## Puts the garrison in the world, and takes it away again.
##
## The model half is `Garrison`: who holds which body, how far out, and
## what wakes them. This is the half that makes any of it exist.
##
## **It needs no streaming of its own**, which fell out of moving
## garrisons onto bodies and is the best argument that the move was
## right. A garrison belongs to a body, the manager already decides
## which bodies exist as nodes, and it says so out loud -- so a
## defender's life is exactly its body's: `body_awake` builds it,
## `body_asleep` takes it down. Two signals, no distance pass, and
## nothing that can disagree with where the planets are.
##
## Taking them down on sleep is not a leak being avoided, it is the
## rule about coming back. A minor is regenerated from the seed every
## time its body wakes, which is "a minor comes back when you come back
## and never while you are there" with no timer and nothing stored.
## What *is* stored is the beaten major, written to `deltas` the moment
## it dies, so leaving and returning finds it still gone.
##
## Everything is handed in. The galaxy and the manager are autoloads
## and do not exist in a `--script` run, and a spawner that reached for
## them by name would be a spawner with no tests.

## How far above the rock a grounded defender sits, as a share of its
## own size. Just clear: a turret half inside the hill reads as a bug
## rather than as a turret.
const FOOT: float = 1.2

## Where in the territory the two standing-off posts sit, as a fraction
## of the way from the body's own edge to the edge of the shell.
##
## Orbit is close and the shell is the rest of it, spread rather than
## stacked on one circle -- a dozen defenders all at exactly the same
## radius is a ring, and a ring is a thing you fly through once.
const ORBIT_BAND: float = 0.25
const SHELL_FROM: float = 0.45
const SHELL_TO: float = 0.95

var _tier: int = 1
var _galaxy: Node = null
var _manager: Node = null

## Where the foes go. Not under the body: bodies are taken down and
## rebuilt by the manager, and a defender parented to one would be
## freed by machinery that knows nothing about it.
var _field: Node2D = null

## body -> the foes standing for it, so sleep knows what to take away.
var _standing: Dictionary = {}

## Emitted when something dies and leaves something behind. The world
## owns crates, so the world decides what a drop looks like.
signal dropped(item: Resource, rarity: int, at: Vector2)


## Who to read, where to put things, and which band of the galaxy this
## is. The manager may be null, which is what a test hands it: then
## nothing wakes by itself and `stand_up()` is called directly.
func bind(tier: int, galaxy: Node, manager: Node, field: Node2D) -> void:
	_tier = tier
	_galaxy = galaxy
	_field = field
	if _manager == manager:
		return
	if _manager != null and is_instance_valid(_manager):
		_manager.body_awake.disconnect(_on_body_awake)
		_manager.body_asleep.disconnect(_on_body_asleep)
	_manager = manager
	if _manager == null:
		return
	_manager.body_awake.connect(_on_body_awake)
	_manager.body_asleep.connect(_on_body_asleep)
	catch_up()


## Stands up the garrisons of everything that is **already** awake.
##
## The signal only tells a listener about worlds that wake after it,
## and the first planet of a system is always built before anything
## else exists to hear about it -- the world opens the system and then
## builds the screens. Without this, the one world a pilot starts next
## to is the one world with no defenders on it, at the start of a new
## game and again after every jump.
##
## Found by asking the running game rather than by reading the code:
## the model said fifteen defenders across three held bodies and the
## field held none.
func catch_up() -> void:
	if _manager == null or not is_instance_valid(_manager):
		return
	if not _manager.has_method("awake_bodies"):
		return
	for body: SystemBody in _manager.awake_bodies():
		stand_up(body, _manager.node_for(body))


## Everything standing right now, for a test and for the HUD that will
## eventually want to mark them.
func standing() -> Array[Foe]:
	var out: Array[Foe] = []
	for body: Variant in _standing:
		for foe: Variant in _standing[body]:
			if is_instance_valid(foe):
				out.append(foe)
	return out


func _on_body_awake(body: SystemBody, node: Node2D) -> void:
	stand_up(body, node)


func _on_body_asleep(body: SystemBody) -> void:
	stand_down(body)


## Builds the garrison of one body. Public so a test can wake a world
## without a streaming manager and without a frame.
func stand_up(body: SystemBody, node: Node2D) -> int:
	stand_down(body)
	if body == null or _field == null:
		return 0
	var held: Dictionary = Garrison.at(body, _tier, _deltas())
	if held.is_empty():
		return 0

	var at: Vector2 = node.global_position if node != null else Vector2.ZERO
	var planet: Planet = node as Planet
	var raised: Array[Foe] = []
	for entry: Variant in held["members"]:
		var member: Dictionary = entry
		var foe: Foe = Foe.new()
		_field.add_child(foe)
		foe.arm(member, held)
		foe.global_position = station_for(held, member, at, _surface_under(planet, body, member))
		# Pointed out from what it is holding, which is where anything
		# worth shooting at is going to come from.
		foe.rotation = (foe.global_position - at).angle() + PI * 0.5
		foe.died.connect(_on_foe_died.bind(body))
		raised.append(foe)
	_standing[body] = raised
	return raised.size()


## Takes a body's garrison away. The minors are not remembered, which
## is the rule rather than an omission: the seed puts them back.
func stand_down(body: SystemBody) -> void:
	if not _standing.has(body):
		return
	for foe: Variant in _standing[body]:
		if not is_instance_valid(foe):
			continue
		# Out of the tree **now**, freed later. `queue_free` happens at
		# the end of the frame, and until then the node is still a child
		# and still a body in the physics world -- so a garrison that
		# had been taken down could be shot at, and hit, after it had
		# stopped existing as far as this class was concerned.
		var leaving: Foe = foe
		if leaving.get_parent() != null:
			leaving.get_parent().remove_child(leaving)
		leaving.queue_free()
	_standing.erase(body)


## Where one defender stands, in world coordinates.
##
## A pure function of the roster entry and the body, so the same
## defender is in the same place on the second visit -- the bearing is
## rolled with the garrison and the radius comes off the member's own
## seed. Public because that determinism is the claim worth checking,
## and checking it should not need a planet to be built.
static func station_for(
	held: Dictionary, member: Dictionary, body_at: Vector2, surface: float
) -> Vector2:
	var territory: float = maxf(float(held.get("territory", 0.0)), surface * 1.2)
	var out: Vector2 = Vector2.RIGHT.rotated(float(member.get("bearing", 0.0)))
	var post: int = int(member.get("post", Garrison.Post.SHELL))
	if post == Garrison.Post.SURFACE:
		return body_at + out * surface
	var edge: float = surface * 1.15
	if post == Garrison.Post.ORBIT:
		return body_at + out * lerpf(edge, territory, ORBIT_BAND)
	# Spread through the shell by the member's own seed, so a dozen of
	# them are a cloud rather than a ring.
	var spread: float = float(absi(int(member.get("seed", 0))) % 1000) / 1000.0
	return body_at + out * lerpf(edge, territory, lerpf(SHELL_FROM, SHELL_TO, spread))


## How far out the ground is under a defender's bearing.
##
## Off the built planet when there is one, because terrain is why a
## nominal radius is not where the rock is; off the model otherwise,
## which is what a test sees.
func _surface_under(planet: Planet, body: SystemBody, member: Dictionary) -> float:
	var bearing: float = float(member.get("bearing", 0.0))
	if planet == null or not is_instance_valid(planet):
		return body.radius * FOOT
	var probe: Vector2 = (
		planet.global_position + Vector2.RIGHT.rotated(bearing) * body.radius * 2.0
	)
	return planet.surface_radius_at(probe) + Foe.SIZE_TURRET * FOOT


## A defender is gone. A major is gone for good and that is the one
## thing here worth writing down.
func _on_foe_died(foe: Foe, body: SystemBody) -> void:
	if not is_instance_valid(foe):
		return
	if foe.is_major():
		Garrison.beat(_deltas(), foe.member)
	if _standing.has(body):
		(_standing[body] as Array).erase(foe)
	_drop_for(foe)
	foe.queue_free()


## What it leaves behind.
##
## The floor comes off the roster rather than from here: a major drops
## well because it is a major, and that is a fact about the roster
## rather than a decision the spawner is entitled to make. Everything
## else rolls at the tier like any other find, which is what makes
## killing things in the core worth more than killing things at the
## rim without a second table saying so.
func _drop_for(foe: Foe) -> void:
	var loot: Node = _loot()
	if loot == null:
		return
	var floor_grade: int = int(foe.member.get("rarity_floor", 0))
	var rolled: int = loot.roll_rarity(_rng_for(foe))
	var item: Resource = loot.generate(
		int(foe.member.get("seed", 0)), maxi(rolled, floor_grade)
	)
	if item != null:
		dropped.emit(item, maxi(rolled, floor_grade), foe.global_position)


func _rng_for(foe: Foe) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(foe.member.get("seed", 0))
	return rng


func _deltas() -> Dictionary:
	if _galaxy != null and is_instance_valid(_galaxy) and "deltas" in _galaxy:
		return _galaxy.deltas
	return {}


func _loot() -> Node:
	if _manager != null and is_instance_valid(_manager) and "loot" in _manager:
		return _manager.loot as Node
	return null
