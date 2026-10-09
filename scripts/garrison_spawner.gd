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

## How close to a held body counts as landing on it, as a multiple of
## its own radius. Generous: a pilot setting down anywhere on a world
## is landing on that world, and arguing about which hemisphere would
## be arguing with somebody who is already on the ground.
const LANDED_WITHIN: float = 1.6

var _tier: int = 1
var _galaxy: Node = null
var _manager: Node = null

## Who the defenders are watching for, and who they shoot at. The
## player's ship in the game; whatever a test hands over otherwise.
var _target: Node2D = null

## How long a **passive** garrison needs the pilot out of its territory
## before it stands down, in seconds.
##
## The first version of this class said no garrison ever calms down,
## and gave a reason: a forgetting timer would let a pilot provoke a
## world, back off for twenty seconds and walk in on a garrison that
## had decided to believe them. The reason was wrong about this timer,
## because this one only runs **outside the territory** -- and outside
## the territory nothing can shoot the pilot anyway, since every
## defender's reach is well inside its own line. So calming changes
## nothing about a fight in progress. What it changes is the second
## approach, and that is exactly what has to change: without it,
## "passive" means "aggressive from the first mistake onwards", and the
## whole point of a world that has to be provoked is that it can be
## left alone again.
##
## Aggressive garrisons do not calm down, because there is nothing for
## them to calm down from: they open up on anything inside the line,
## roused or not.
const CALM_AFTER: float = 25.0

## Bodies whose garrison is in the fight.
var _roused: Dictionary = {}

## And how long the pilot has been outside the territory of each, which
## is the only thing that runs the clock down. Reset by any hit: a
## garrison that is being shot at is not being left alone.
var _calm_for: Dictionary = {}

## Where the foes go. Not under the body: bodies are taken down and
## rebuilt by the manager, and a defender parented to one would be
## freed by machinery that knows nothing about it.
var _field: Node2D = null

## body -> the foes standing for it, so sleep knows what to take away.
var _standing: Dictionary = {}

## Emitted when something dies and leaves something behind. The world
## owns crates, so the world decides what a drop looks like.
signal dropped(item: Resource, rarity: int, at: Vector2)

## A carrier has put one out. For the HUD that will want to say so, and
## for a test that should not have to count children to find out.
signal launched(carrier: Foe, foe: Foe)


## Who to read, where to put things, and which band of the galaxy this
## is. The manager may be null, which is what a test hands it: then
## nothing wakes by itself and `stand_up()` is called directly.
func bind(tier: int, galaxy: Node, manager: Node, field: Node2D) -> void:
	_tier = tier
	_galaxy = galaxy
	_field = field
	# A new system is a new set of grudges. This is the only place the
	# roused list is cleared, which is also the whole of the rule about
	# it: leaving is what calms a garrison, and nothing else does.
	_roused.clear()
	_calm_for.clear()
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


## Who the defenders are watching for. Handed in rather than looked up
## by group or by path, like everything else here.
func watch(target: Node2D) -> void:
	_target = target


## Whether this body's garrison is in the fight.
func is_roused(body: SystemBody) -> bool:
	return bool(_roused.get(body, false))


## Everything standing right now, for a test and for the HUD that will
## eventually want to mark them.
func standing() -> Array[Foe]:
	var out: Array[Foe] = []
	for body: Variant in _standing:
		for foe: Variant in _standing[body]:
			if is_instance_valid(foe):
				out.append(foe)
	return out


## In the physics step, not the idle one, because this is where the
## defenders move. `move_and_slide` scales by the physics delta
## whatever delta it is handed, so running the fight anywhere else
## would make a foe's speed depend on the frame rate.
func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	for body: Variant in _standing:
		_watch_over(body as SystemBody, delta)


## One body's garrison, one tick: where the body is now, whether
## anything has woken it, whether it has been left alone long enough to
## stand down again, and then everybody's own tick.
func _watch_over(body: SystemBody, delta: float) -> void:
	var raised: Array = _standing[body]
	if raised.is_empty():
		return
	var held: Dictionary = (raised[0] as Foe).held
	var at: Vector2 = _body_at(body)
	var away: float = _target.global_position.distance_to(at)
	if not is_roused(body):
		var reason: int = _provocation(body, held, away)
		if reason != 0 and Garrison.provoked_by(held, reason as Garrison.Provocation):
			rouse(body)
	elif int(held.get("posture", Garrison.Posture.AGGRESSIVE)) == Garrison.Posture.PASSIVE:
		if away > float(held.get("territory", 0.0)):
			_calm_for[body] = float(_calm_for.get(body, 0.0)) + delta
			if float(_calm_for[body]) >= CALM_AFTER:
				calm(body)
		else:
			_calm_for[body] = 0.0
	# Gathered rather than launched on the spot, because `raised` *is*
	# this body's standing list: launching inside the walk appends to the
	# array being walked, and whether that is a crash, a double tick or
	# nothing at all is not a thing to find out in a release.
	var wanted: Array[Array] = []
	for foe: Variant in raised:
		if not is_instance_valid(foe):
			continue
		# The body moves -- a planet turns, a station orbits -- so the
		# line moves with it rather than staying where it was when the
		# garrison stood up.
		(foe as Foe).anchor = at
		(foe as Foe).tick(delta, _target, _field)
		var entry: Dictionary = (foe as Foe).wants_to_launch(delta)
		if not entry.is_empty():
			wanted.append([foe, entry])
	for pair: Array in wanted:
		_launch(pair[0] as Foe, pair[1] as Dictionary, body)


## What the pilot has just done, as the garrison would read it.
##
## One provocation at a time and the nearest reason wins, because the
## answer is only ever used to ask `provoked_by()`: a world that minds
## being landed on and not being approached has to be able to say so,
## and a pilot who lands on it has certainly also approached it.
func _provocation(body: SystemBody, held: Dictionary, away: float) -> int:
	var ship: Ship = _target as Ship
	if (
		ship != null
		and ship.flight_mode == Ship.FlightMode.LANDED
		and away < body.radius * LANDED_WITHIN
	):
		# Digging is the more specific reading of the same position, and
		# it is a separate roll: a world can mind being dug and not mind
		# being parked on, which is what makes it a world sitting on
		# something rather than a world with an opinion about visitors.
		if "mining" in ship and ship.mining:
			return Garrison.Provocation.MINED
		return Garrison.Provocation.LANDED
	if away <= float(held.get("territory", 0.0)):
		return Garrison.Provocation.APPROACHED
	return 0


## Stands a garrison down again: nobody awake, and the clock cleared.
##
## Public for the same reason `rouse` is -- something other than the
## tick may decide it, and a test should be able to say so directly.
func calm(body: SystemBody) -> void:
	if not is_roused(body):
		return
	_roused.erase(body)
	_calm_for.erase(body)
	for foe: Variant in _standing.get(body, []):
		if is_instance_valid(foe):
			(foe as Foe).awake = false
			(foe as Foe).queue_redraw()


## Wakes a garrison, and says so on every defender in it.
##
## Public because being shot at is a provocation nobody rolls for and
## it arrives through a signal rather than through the tick.
func rouse(body: SystemBody) -> void:
	if not _standing.has(body) or is_roused(body):
		return
	_roused[body] = true
	_calm_for[body] = 0.0
	for foe: Variant in _standing[body]:
		if is_instance_valid(foe):
			(foe as Foe).awake = true
			(foe as Foe).queue_redraw()


## Where a body is, which is where its garrison is standing round.
##
## Off the live node when there is one, because a planet turns and a
## station orbits; off the first defender's own station otherwise,
## which is what a test without a built world sees.
func _body_at(body: SystemBody) -> Vector2:
	if _manager != null and is_instance_valid(_manager):
		var node: Node2D = _manager.node_for(body)
		if node != null:
			return node.global_position
	return _centre_of(body)


func _centre_of(body: SystemBody) -> Vector2:
	if not _standing.has(body) or (_standing[body] as Array).is_empty():
		return Vector2.ZERO
	var first: Foe = _standing[body][0]
	var post: Vector2 = GarrisonSpawner.station_for(
		first.held, first.member, Vector2.ZERO, body.radius
	)
	return first.global_position - post


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
		# Its post and its line, both relative to the body so that the
		# body can move without the garrison sliding off it.
		foe.anchor = at
		foe.station = foe.global_position - at
		# Pointed out from what it is holding, which is where anything
		# worth shooting at is going to come from.
		foe.rotation = (foe.global_position - at).angle() + PI * 0.5
		foe.died.connect(_on_foe_died.bind(body))
		# Being shot wakes a garrison whatever it rolled, which is the
		# one provocation that is not a roll: a defender that let itself
		# be taken apart out of politeness is not a defender.
		foe.hurt.connect(_on_foe_hurt.bind(body))
		foe.awake = is_roused(body)
		raised.append(foe)
	_standing[body] = raised
	return raised.size()


## Puts one of a carrier's brood into the world.
##
## Out of the carrier's own mouth, offset by its size, so the thing the
## pilot is being told -- that this came from that -- is a thing they
## can see. It joins its body's standing list like anything else, so
## sleep takes it away and the garrison's own count includes it.
func _launch(carrier: Foe, entry: Dictionary, body: SystemBody) -> Foe:
	if _field == null or not is_instance_valid(_field):
		return null
	var foe: Foe = Foe.new()
	_field.add_child(foe)
	foe.arm(entry, carrier.held)
	foe.anchor = carrier.anchor
	# Its post is the carrier's, not a post of its own: what it is
	# defending is the thing that made it.
	foe.station = carrier.station
	foe.global_position = carrier.global_position + Vector2.RIGHT.rotated(
		float(entry.get("bearing", 0.0))
	) * (Foe.SIZE_CARRIER * 1.6)
	foe.rotation = carrier.rotation
	# Launched into a fight, so it arrives in it. A brood that had to be
	# provoked separately would be a brood the pilot can fly past.
	foe.awake = true
	foe.died.connect(_on_foe_died.bind(body))
	foe.hurt.connect(_on_foe_hurt.bind(body))
	carrier.brood.append(foe)
	if _standing.has(body):
		(_standing[body] as Array).append(foe)
	launched.emit(carrier, foe)
	return foe


## Takes a body's garrison away. The minors are not remembered, which
## is the rule rather than an omission: the seed puts them back.
func stand_down(body: SystemBody) -> void:
	if not _standing.has(body):
		return
	# The grudge goes with them. A garrison rebuilt from the seed is a
	# garrison that has not met anybody yet, which is the same rule the
	# minors come back under.
	_roused.erase(body)
	_calm_for.erase(body)
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
func _on_foe_hurt(_foe: Foe, body: SystemBody) -> void:
	rouse(body)
	# Being shot is the opposite of being left alone, so whatever the
	# clock had counted up does not count.
	_calm_for[body] = 0.0


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
	# What came out of a carrier is worth what the carrier is worth. See
	# `Foe.brood_entry`.
	if foe.was_launched():
		return
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
