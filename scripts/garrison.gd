class_name Garrison
extends RefCounted
## What defends a place, and what wakes it.
##
## Pure data, like `StarSystem` and `GalaxyMap`: a garrison exists before
## anything is instantiated, and the same seed gives the same defenders
## in the same places. Nothing here flies, shoots or thinks -- that is
## the spawner's and the AI's job, and both of them read this.
##
## **This is the first thing in the game that reads `tier_of()`.** Until
## it existed the tier was a number describing itself: the galaxy had a
## shape, a ladder and a chart, and tier 9 held exactly what tier 1 held.
##
## ## A garrison belongs to a body, not to a system
##
## The first version scattered a system's enemies across it as one flat
## list, with each one holding an abstract post -- surface, orbit, or
## loose in space. That is a crowd, not a defence: it answers "how many"
## and never "of what".
##
## Enemies stand at **planets and stations**, because those are the
## places worth standing at, and only very rarely in the dark between
## them. So the roll comes in two steps and the order is the design:
##
## 1. **Is this body defended at all?** Most are not, and a system of
##    quiet worlds with one held moon reads as a place with a reason in
##    it. A world that is always guarded is scenery.
## 2. **Only then, who holds it and how far out.** Nothing about the
##    defenders is rolled for an undefended world, which also means a
##    world can be checked for danger without unrolling an answer.
##
## ## They hold ground rather than hunt
##
## A garrison has a **territory**: a shell round its body that it is
## there to keep. Chasing a ship across a system is a fight nobody can
## leave, and a game where every contact is a commitment is a game of
## avoiding contacts. Holding ground makes the same enemy a decision --
## go round, or go in.
##
## ## Aggressive and passive, and what wakes the second kind
##
## An aggressive garrison opens up on anything inside its territory. A
## passive one has to be **provoked**, and which provocations count is
## rolled with the body: some worlds do not mind being looked at and do
## mind being landed on, and the pilot finds out which by reading the
## scanner or by being wrong.
##
## Shooting always counts. Anything else would be a defender that lets
## itself be shot to pieces out of politeness.
##
## ## The two rules of coming back, and the amendment a carrier forces
##
## - **A minor comes back when you come back, never while you are
##   there.** A roster derived from a seed *is* that rule: nothing is
##   stored, nothing is timed, and a place you cleared and left is the
##   same place when you return.
## - **A major beaten is beaten for good.** The only thing here a seed
##   cannot reproduce, so the only thing written down -- in
##   `Galaxy.deltas`, under the member's own seed, the scheme every
##   other entry in that dictionary uses. A major left alive is **not**
##   written down and comes back whole, or flying in and running away
##   would always be cheaper than fighting.
##
## A carrier launching fighters while the pilot is in the room is what
## the first rule forbids, and the rule is right: a place that drips
## reinforcements for ever is one to run from rather than one to clear.
## So the rule gains a clause rather than an exception: **nothing
## arrives from nowhere.** Every enemy that appears during a stay comes
## out of something standing there that can be shot, and shooting it
## stops the drip.

## Rank, and there are two on purpose. A third would be a third decision
## at every place that reads one. It is orthogonal to what a thing *is*:
## a turret and a carrier both come in both ranks, and the rule about
## coming back follows the rank, not the shape.
enum Rank { MINOR, MAJOR }

## Where a defender waits, relative to the body it is holding.
enum Post { SURFACE, ORBIT, SHELL }

## What it does. One enum rather than a kind and a behaviour, because
## for everything this model is asked the two are the same question: a
## turret is the thing that does not move.
enum Archetype { PATROL, AGGRESSOR, RUNNER, TURRET, CARRIER }

## Whether it shoots first.
enum Posture { AGGRESSIVE, PASSIVE }

## What wakes a passive garrison. Flags, because a body rolls a set of
## them rather than one.
##
## `SHOT_AT` is in every set and is not rolled: a defender that let
## itself be taken apart out of politeness is not a defender. The other
## three are the interesting ones, because each says something different
## about what the place is for -- a world that minds being approached is
## hiding something, one that only minds being dug is sitting on it.
##
## `MINED` is carried now and acted on when mining lands (PLAN.md M5.2).
## It costs a bit to roll it early and it would cost a save-format
## thought to add it late.
enum Provocation { SHOT_AT = 1, APPROACHED = 2, LANDED = 4, MINED = 8 }

const RANK_NAMES: Array[String] = ["minor", "major"]
const POST_NAMES: Array[String] = ["surface", "orbit", "shell"]
const POSTURE_NAMES: Array[String] = ["aggressive", "passive"]
const ARCHETYPE_NAMES: Array[String] = [
	"patrol", "aggressor", "runner", "turret", "carrier",
]

## Where a garrison's own seed is drawn from the body's.
##
## An index like any other, and deliberately one no child will ever use:
## a planet numbers its moon 1 and a system numbers its docks after its
## planets, so the twenties are already generous. A garrison sharing a
## seed with a moon would share a `deltas` key with it, and the first
## thing to break would be a dug crater bringing an elite back to life.
const SEED_INDEX: int = 1000

## How likely a planet is to be defended, at each end of the ladder.
##
## Most worlds are nobody's, which is what makes the held one worth
## noticing. A system where everything is guarded has nothing to say
## about any of it.
const DEFENDED_AT_RIM: float = 0.18
const DEFENDED_AT_CORE: float = 0.60

## And how much more or less likely that is for something other than a
## planet. A dock is somebody's by definition; a moon is a rock.
const DEFENDED_STATION: float = 1.5
const DEFENDED_MOON: float = 0.55

## How likely a system is to hold a group in the dark between its
## bodies, and how big that group is.
##
## Rare on purpose. Empty space should read as empty, so that the one
## time it does not is a thing that happened rather than a thing that
## always happens.
const LOOSE_CHANCE: float = 0.07
const LOOSE_COUNT: Vector2i = Vector2i(1, 3)

## Fighters a defended body keeps, at each end of the ladder.
##
## Per body rather than per system, which is why these are a third of
## what the flat version used: a core system has several defended
## bodies, and the crowd is the sum rather than the entry.
const FIGHTERS_AT_RIM: Vector2i = Vector2i(2, 4)
const FIGHTERS_AT_CORE: Vector2i = Vector2i(7, 12)

## And guns bolted to it. Not zero at the rim: one gun on a ridge is how
## a pilot learns that ground can shoot back, and learning that over a
## core world is learning it too late.
const TURRETS_AT_RIM: Vector2i = Vector2i(1, 2)
const TURRETS_AT_CORE: Vector2i = Vector2i(4, 7)

## The chance of a carrier, and of an elite, at a defended body.
const CARRIER_AT_RIM: float = 0.04
const CARRIER_AT_CORE: float = 0.45
const ELITE_AT_RIM: float = 0.08
const ELITE_AT_CORE: float = 0.55

## How far out the garrison keeps, as a multiple of the body's own
## reach, and how much that varies.
##
## Against the well rather than the surface, because the well is what
## the place already means on every other instrument: the map draws it,
## the trajectory bends in it, and a territory that matched nothing the
## pilot can see would be a wall they discover by hitting it.
const TERRITORY: Vector2 = Vector2(1.15, 2.1)

## And never tighter than this, in pixels.
##
## A dock has no gravity and a radius of a hundred-odd, so its reach
## works out at a few hundred pixels -- and a dozen defenders inside
## four hundred pixels is a pile, not a picket. Measured before the
## floor went in: fifteen ships holding a shell 443 px across. The
## floor is what makes a station's garrison a perimeter you cross
## rather than a wall you collide with.
const MIN_TERRITORY: float = 2500.0

## How likely a defended body is to shoot first, at each end.
const AGGRESSIVE_AT_RIM: float = 0.25
const AGGRESSIVE_AT_CORE: float = 0.75

## What one fighter is worth, as a multiple of the weakest there is, at
## each end of the ladder.
##
## **The crowd has to grow faster than the thing in it.** Six enemies a
## system at four times the strength is a boss rush with a commute;
## nineteen at four times is still a ladder where the answer is a better
## gun rather than a better plan. The test states the claim as the ratio
## it is -- crowd growth against individual growth -- and these two
## numbers are what it costs.
const STRENGTH_AT_RIM: float = 0.55
const STRENGTH_AT_CORE: float = 1.65

## How much of that a single roll may vary by, either way.
const STRENGTH_SPREAD: float = 0.18

## What the three heavier things are worth against a fighter of their
## own tier. A turret cannot go anywhere, so it is allowed to be harder
## to shift than the thing that can. An elite is "bring friends or bring
## a plan". A carrier is worth more than either and most of its weight
## is the stream it puts out.
const TURRET_STRENGTH: float = 1.6
const ELITE_STRENGTH: float = 2.5
const CARRIER_STRENGTH: float = 3.0

## What a carrier launches, how many it keeps up, and how long it waits
## between launches at each end of the ladder.
const BROOD_STRENGTH: float = 0.75
const BROOD_AT_RIM: int = 2
const BROOD_AT_CORE: int = 5
const CADENCE_AT_RIM: float = 14.0
const CADENCE_AT_CORE: float = 7.0

## The rarity a major's drop is guaranteed to reach, as `LootGenerator`
## counts rarity. The reason to fight one rather than fly round it.
const MAJOR_RARITY_FLOOR: int = 2

## Where a defender stands within its territory: the share on the ground
## and the share in orbit, with the rest loose in the shell. Turrets
## want something to be bolted to, so they lean the other way.
const FIGHTER_SURFACE: float = 0.22
const FIGHTER_ORBIT: float = 0.18
const TURRET_SURFACE: float = 0.5
const TURRET_ORBIT: float = 0.35


## The seed of one member of a body's garrison.
##
## Two steps, the same way a planet's seed comes from its system's: the
## garrison gets a seed of its own from the body, and its members are
## numbered from that. One step with a large index would have worked and
## would have left the garrison without an identity of its own, which
## the next thing to hang off a body would have had to invent again.
static func seed_of(body_seed: int, index: int) -> int:
	return StarSystem.derive(StarSystem.derive(body_seed, SEED_INDEX), index)


## Whether this body is held at all, and nothing else.
##
## Its own function because it is its own question, asked far more often
## than "by whom": a scanner sweeping a system wants to know which
## worlds to mark, and most of them are nobody's. Rolling the defenders
## to answer that would be unrolling a fight nobody is having.
static func is_defended(body: SystemBody, tier: int) -> bool:
	if body == null or body.kind == SystemBody.Kind.STAR:
		return false
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = StarSystem.derive(body.seed, SEED_INDEX)
	var odds: float = lerpf(DEFENDED_AT_RIM, DEFENDED_AT_CORE, _rung(tier))
	match body.kind:
		SystemBody.Kind.STATION:
			odds *= DEFENDED_STATION
		SystemBody.Kind.MOON:
			odds *= DEFENDED_MOON
		_:
			pass
	return rng.randf() < clampf(odds, 0.0, 1.0)


## Who holds this body, how far out, and what wakes them. Empty when
## nobody does.
##
## `deltas` is handed in rather than fetched, for the reason every model
## in this project states: `Galaxy` is an autoload and does not exist in
## a `--script` run, so a roster that reached for it could not be tested.
static func at(body: SystemBody, tier: int, deltas: Dictionary = {}) -> Dictionary:
	if not is_defended(body, tier):
		return {}
	var rung: float = _rung(tier)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# One step past the seed the defended roll used, so that whether a
	# body is held and who holds it are two draws rather than one number
	# read twice.
	rng.seed = StarSystem.derive(body.seed, SEED_INDEX + 1)

	var posture: Posture = (
		Posture.AGGRESSIVE
		if rng.randf() < lerpf(AGGRESSIVE_AT_RIM, AGGRESSIVE_AT_CORE, rung)
		else Posture.PASSIVE
	)
	var provokes: int = Provocation.SHOT_AT
	if posture == Posture.PASSIVE:
		# A passive garrison that could only be woken by being shot would
		# be scenery with hit points. At least one of the other three,
		# so every quiet world is quiet about something in particular.
		var rolled: Array[int] = [Provocation.APPROACHED, Provocation.LANDED, Provocation.MINED]
		provokes |= rolled[rng.randi_range(0, rolled.size() - 1)]
		for extra: int in rolled:
			if rng.randf() < 0.35:
				provokes |= extra

	var reach: float = maxf(body.well_radius, body.radius * 2.0)
	var territory: float = maxf(
		reach * rng.randf_range(TERRITORY.x, TERRITORY.y), MIN_TERRITORY
	)

	var members: Array[Dictionary] = []
	var strength: float = lerpf(STRENGTH_AT_RIM, STRENGTH_AT_CORE, rung)
	var has_elite: bool = rng.randf() < lerpf(ELITE_AT_RIM, ELITE_AT_CORE, rung)
	var has_carrier: bool = rng.randf() < lerpf(CARRIER_AT_RIM, CARRIER_AT_CORE, rung)
	var fighters: int = _count(rng, FIGHTERS_AT_RIM, FIGHTERS_AT_CORE, rung)
	var turrets: int = _count(rng, TURRETS_AT_RIM, TURRETS_AT_CORE, rung)
	# A rock with nothing to stand on keeps no guns on the ground; the
	# spawner would have nowhere to put them, and a roster that promised
	# one would be a roster the world has to argue with.
	if body.kind == SystemBody.Kind.STATION:
		turrets = maxi(turrets - 1, 0)

	var slot: int = 0
	for index: int in range(fighters):
		members.append(_member(
			body, slot, Rank.MINOR,
			rng.randi_range(0, Archetype.RUNNER) as Archetype,
			_post_for(rng, FIGHTER_SURFACE, FIGHTER_ORBIT, body),
			rng, strength, rung, tier,
		))
		slot += 1
	for index: int in range(turrets):
		members.append(_member(
			body, slot, Rank.MINOR, Archetype.TURRET,
			_post_for(rng, TURRET_SURFACE, TURRET_ORBIT, body),
			rng, strength, rung, tier,
		))
		slot += 1
	# Last and in a fixed order, so that whether a body has a carrier
	# cannot move an elite's seed. A member's seed is its identity in
	# `deltas`, and an identity that shifts when something else is
	# rolled is a dead elite coming back to life next patch.
	if has_elite:
		members.append(_member(
			body, slot, Rank.MAJOR, Archetype.AGGRESSOR, Post.SHELL,
			rng, strength, rung, tier,
		))
		slot += 1
	if has_carrier:
		members.append(_member(
			body, slot, Rank.MAJOR, Archetype.CARRIER, Post.SHELL,
			rng, strength, rung, tier,
		))

	var standing: Array[Dictionary] = []
	for entry: Dictionary in members:
		if not beaten(deltas, int(entry["seed"])):
			standing.append(entry)
	return {
		"body": body,
		"seed": StarSystem.derive(body.seed, SEED_INDEX),
		"territory": territory,
		"posture": posture,
		"provokes": provokes,
		"tier": tier,
		"members": standing,
	}


## Every garrison in a system: one per held body, plus the rare group
## out in the dark between them.
static func in_system(
	system: StarSystem, tier: int, deltas: Dictionary = {}
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if system == null:
		return out
	for body: SystemBody in system.bodies:
		var held: Dictionary = at(body, tier, deltas)
		if not held.is_empty():
			out.append(held)
	var loose: Dictionary = adrift(system, tier, deltas)
	if not loose.is_empty():
		out.append(loose)
	return out


## The group in the empty part of a system, when there is one.
##
## Rare, and holding nothing: it has no body, so its territory is where
## it happens to be. Aggressive always -- something sitting in the dark
## between two worlds is not there to be left alone.
static func adrift(
	system: StarSystem, tier: int, deltas: Dictionary = {}
) -> Dictionary:
	if system == null:
		return {}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = StarSystem.derive(system.seed, SEED_INDEX + 2)
	if rng.randf() >= LOOSE_CHANCE:
		return {}
	var rung: float = _rung(tier)
	var strength: float = lerpf(STRENGTH_AT_RIM, STRENGTH_AT_CORE, rung)
	var members: Array[Dictionary] = []
	for index: int in range(rng.randi_range(LOOSE_COUNT.x, LOOSE_COUNT.y)):
		var entry: Dictionary = _member(
			null, index, Rank.MINOR, Archetype.PATROL, Post.SHELL,
			rng, strength, rung, tier,
		)
		entry["seed"] = seed_of(StarSystem.derive(system.seed, SEED_INDEX + 2), index)
		if not beaten(deltas, int(entry["seed"])):
			members.append(entry)
	if members.is_empty():
		return {}
	return {
		"body": null,
		"seed": StarSystem.derive(system.seed, SEED_INDEX + 2),
		"territory": 0.0,
		"posture": Posture.AGGRESSIVE,
		"provokes": Provocation.SHOT_AT,
		"tier": tier,
		"members": members,
	}


## Whether this would wake that garrison.
##
## The whole of what "passive" means, in one predicate, so the spawner
## and the AI cannot come to different conclusions about the same world.
## An aggressive garrison needs no provoking and says so by answering
## yes to everything.
static func provoked_by(held: Dictionary, what: Provocation) -> bool:
	if held.is_empty():
		return false
	if int(held.get("posture", Posture.AGGRESSIVE)) == Posture.AGGRESSIVE:
		return true
	return int(held.get("provokes", Provocation.SHOT_AT)) & int(what) != 0


static func _count(
	rng: RandomNumberGenerator, rim: Vector2i, core: Vector2i, rung: float
) -> int:
	var low: int = roundi(lerpf(float(rim.x), float(core.x), rung))
	var high: int = roundi(lerpf(float(rim.y), float(core.y), rung))
	return rng.randi_range(low, maxi(low, high))


## Where one defender waits. A body with no ground keeps nobody on it.
static func _post_for(
	rng: RandomNumberGenerator, on_ground: float, in_orbit: float, body: SystemBody
) -> Post:
	var roll: float = rng.randf()
	var grounded: bool = body != null and body.kind != SystemBody.Kind.STATION
	if grounded and roll < on_ground:
		return Post.SURFACE
	if roll < on_ground + in_orbit:
		return Post.ORBIT
	return Post.SHELL


static func _member(
	body: SystemBody,
	index: int,
	rank: Rank,
	archetype: Archetype,
	post: Post,
	rng: RandomNumberGenerator,
	strength: float,
	rung: float,
	tier: int,
) -> Dictionary:
	var rolled: float = strength * rng.randf_range(
		1.0 - STRENGTH_SPREAD, 1.0 + STRENGTH_SPREAD
	)
	var weight: float = 1.0
	match archetype:
		Archetype.TURRET:
			weight = TURRET_STRENGTH
		Archetype.CARRIER:
			weight = CARRIER_STRENGTH
		_:
			weight = ELITE_STRENGTH if rank == Rank.MAJOR else 1.0
	var entry: Dictionary = {
		"seed": 0 if body == null else seed_of(body.seed, index),
		"rank": rank,
		"archetype": archetype,
		"strength": rolled * weight,
		"post": post,
		# Where round the body it stands, as an angle. The spawner turns
		# this into a place; keeping it here is what makes the same
		# defender stand in the same spot on the second visit.
		"bearing": rng.randf_range(0.0, TAU),
		"tier": tier,
		"rarity_floor": MAJOR_RARITY_FLOOR if rank == Rank.MAJOR else 0,
	}
	if archetype == Archetype.CARRIER:
		entry["brood"] = roundi(lerpf(float(BROOD_AT_RIM), float(BROOD_AT_CORE), rung))
		entry["cadence"] = lerpf(CADENCE_AT_RIM, CADENCE_AT_CORE, rung)
		entry["brood_strength"] = rolled * BROOD_STRENGTH
	return entry


## Whether this one is gone for good.
static func beaten(deltas: Dictionary, enemy_seed: int) -> bool:
	return bool((deltas.get(enemy_seed, {}) as Dictionary).get("beaten", false))


## Writes down that a major will not be coming back. Returns whether
## anything was written.
##
## Minors are not recorded, and that is the rule rather than an
## omission: the model already says a minor comes back next visit, so a
## note saying it is dead would be a note the next roster ignores -- or
## worse, obeys, which would quietly turn every world into one that
## stays cleared.
static func beat(deltas: Dictionary, entry: Dictionary) -> bool:
	if int(entry.get("rank", Rank.MINOR)) != Rank.MAJOR:
		return false
	var key: int = int(entry["seed"])
	var record: Dictionary = deltas.get(key, {})
	record["beaten"] = true
	deltas[key] = record
	return true


## Everything a garrison can have in the air at once: what stands there,
## plus what its carriers are keeping up.
static func press(held: Dictionary) -> int:
	var members: Array = held.get("members", [])
	var most: int = members.size()
	for entry: Variant in members:
		most += int((entry as Dictionary).get("brood", 0))
	return most


## And the same for a whole system, which is the number the spawner
## budgets against.
static func system_press(garrisons: Array[Dictionary]) -> int:
	var most: int = 0
	for held: Dictionary in garrisons:
		most += press(held)
	return most


## How far up the ladder a tier is, 0 at the bottom rung and 1 at the top.
static func _rung(tier: int) -> float:
	return clampf(
		float(clampi(tier, 1, GalaxyMap.TIERS) - 1) / float(GalaxyMap.TIERS - 1),
		0.0,
		1.0,
	)


static func rank_name(rank: int) -> String:
	return RANK_NAMES[clampi(rank, 0, RANK_NAMES.size() - 1)]


static func post_name(post: int) -> String:
	return POST_NAMES[clampi(post, 0, POST_NAMES.size() - 1)]


static func posture_name(posture: int) -> String:
	return POSTURE_NAMES[clampi(posture, 0, POSTURE_NAMES.size() - 1)]


static func archetype_name(archetype: int) -> String:
	return ARCHETYPE_NAMES[clampi(archetype, 0, ARCHETYPE_NAMES.size() - 1)]
