class_name Garrison
extends RefCounted
## What stands in a system, and what is left of it after a fight.
##
## Pure data, like `StarSystem` and `GalaxyMap`: the roster exists whether
## or not a single node has been instantiated, and the same seed gives the
## same enemies in the same places. Nothing here flies, shoots or thinks --
## that is the spawner's and the AI's job, and both of them read this.
##
## **This is the first thing in the game that reads `tier_of()`.** Until
## it existed the tier was a number describing itself: the galaxy had a
## shape, a ladder and a chart, and tier 9 held exactly what tier 1 held.
##
## ## Strength in numbers
##
## A system is crowded rather than guarded. The first pass put two to six
## enemies in a system and made each one four times tougher at the core;
## that is a boss rush with a long commute between bosses. What a 640x360
## arcade fight wants is the opposite -- a lot of small things, each
## killable in a pass, that are dangerous because of how many angles they
## come from. So the count climbs hard going inwards and the individual
## climbs gently, and both climb: a core minor is still four times a rim
## minor, it is just that neither of them is a wall.
##
## ## Three things that are not a fighter
##
## - **A turret** trades going anywhere for being hard to shift. It
##   stands on a surface, on an orbit, or free in space, and it is what
##   makes a place defended rather than merely occupied.
## - **A carrier** is a big ship that keeps putting out small ones.
## - **An elite** is the one fighter a system is remembered for.
##
## ## The two rules of coming back, and the amendment a carrier forces
##
## - **A minor comes back when you come back, never while you are
##   there.** A roster derived from a seed *is* that rule: nothing is
##   stored, nothing is timed, and a system you cleared and left is the
##   same system when you return.
## - **A major beaten is beaten for good.** The only thing here a seed
##   cannot reproduce, so the only thing written down -- in
##   `Galaxy.deltas`, under the member's own seed, the scheme every other
##   entry in that dictionary uses. A major left alive is **not** written
##   down and comes back whole, or flying in and running away would
##   always be cheaper than fighting.
##
## A carrier launching fighters while the pilot is in the room is exactly
## what the first rule forbids, and the rule is right: a system that
## drips reinforcements for ever is a system to run from rather than one
## to clear. So the rule gains a clause rather than an exception:
## **nothing arrives from nowhere.** Every enemy that appears during a
## stay comes out of something standing in that system that can be shot,
## and shooting it stops the drip. That turns "run away" into "kill the
## carrier first", which is a decision rather than a timer.

## Rank, and there are two on purpose. A third would be a third decision
## at every place that reads one. It is orthogonal to what a thing *is*:
## a turret and a carrier both come in both ranks, and the rule about
## coming back follows the rank, not the shape.
enum Rank { MINOR, MAJOR }

## Where it waits. The roster names the kind of place rather than the
## body, because it knows a seed and a tier and nothing about what the
## system contains; binding `SURFACE` to a particular planet is the
## spawner's job. A system with nothing to stand on puts them in space.
enum Post { SPACE, SURFACE, ORBIT }

## What it does. One enum rather than a kind and a behaviour, because
## for everything this model is asked the two are the same question: a
## turret is the thing that does not move.
enum Archetype { PATROL, AGGRESSOR, RUNNER, TURRET, CARRIER }

const RANK_NAMES: Array[String] = ["minor", "major"]
const POST_NAMES: Array[String] = ["space", "surface", "orbit"]
const ARCHETYPE_NAMES: Array[String] = [
	"patrol", "aggressor", "runner", "turret", "carrier",
]

## Where the garrison's own seed is drawn from the system's.
##
## An index like any other, and deliberately one no body will ever use:
## `StarSystem` numbers its star 0, its planets 1 to 5 and its docks after
## them, so the twenties are already generous. A garrison sharing a seed
## with a moon would share a `deltas` key with it, and the first thing to
## break would be a dug crater bringing an elite back to life.
const SEED_INDEX: int = 1000

## How many fighters a system holds, at the bottom of the ladder and at
## the top. A range rather than a number at each end, so two systems on
## the same rung are not the same fight.
const FIGHTERS_AT_RIM: Vector2i = Vector2i(4, 7)
const FIGHTERS_AT_CORE: Vector2i = Vector2i(20, 32)

## And how many guns are bolted down.
##
## Not zero at the rim: one gun on a ridge is how a pilot learns that
## ground can shoot back, and learning that over a core world is
## learning it too late.
const TURRETS_AT_RIM: Vector2i = Vector2i(1, 2)
const TURRETS_AT_CORE: Vector2i = Vector2i(4, 9)

## The chance of a carrier, and of an elite, at each end of the ladder.
##
## Both, independently, so a core system can have neither, either or
## both. Not zero at the rim and not one at the core: a pilot who meets
## their first elite halfway in has nothing to read it against, and a
## core where every system has everything makes the finale a formality
## by the time they reach it.
const CARRIER_AT_RIM: float = 0.04
const CARRIER_AT_CORE: float = 0.70
const ELITE_AT_RIM: float = 0.08
const ELITE_AT_CORE: float = 0.80

## What one fighter is worth, as a multiple of the weakest there is, at
## each end of the ladder.
##
## **The crowd has to grow faster than the thing in it**, and the first
## attempt at this got it backwards twice over. Six enemies a system at
## four times the strength is a boss rush with a commute; then nineteen
## at four times is still a ladder where the answer is a better gun
## rather than a better plan. The test states the claim as the ratio it
## is -- crowd growth against individual growth -- and these two numbers
## are what it costs: three-fold on the individual against nearly
## five-fold on the count.
const STRENGTH_AT_RIM: float = 0.55
const STRENGTH_AT_CORE: float = 1.65

## How much of that a single roll may vary by, either way.
const STRENGTH_SPREAD: float = 0.18

## What the three heavier things are worth against a fighter of their own
## tier.
##
## A turret cannot go anywhere, so it is allowed to be harder to shift
## than the thing that can. An elite is "bring friends or bring a plan"
## rather than "come back later". A carrier is worth more than either and
## most of its weight is the stream it puts out, not its own guns.
const TURRET_STRENGTH: float = 1.6
const ELITE_STRENGTH: float = 2.5
const CARRIER_STRENGTH: float = 3.0

## What a carrier launches, how many it keeps in the air, and how long it
## waits between launches at each end of the ladder.
##
## Weaker than the system's own fighters, deliberately: the stream is
## pressure, not a second garrison, and the answer to it is the carrier
## rather than the stream. The live cap is what keeps "ignore it" from
## being an unbounded swarm -- a pilot who leaves it alone gets a
## standing escort, not an avalanche.
const BROOD_STRENGTH: float = 0.75
const BROOD_AT_RIM: int = 2
const BROOD_AT_CORE: int = 5
const CADENCE_AT_RIM: float = 14.0
const CADENCE_AT_CORE: float = 7.0

## The rarity a major's drop is guaranteed to reach, as `LootGenerator`
## counts rarity. The reason to fight one rather than fly round it.
const MAJOR_RARITY_FLOOR: int = 2

## Where a fighter waits: the share of them on a surface, at each end.
## Rising inwards, because a system that can only be cleared by landing
## is a longer, more committing fight.
const FIGHTER_SURFACE_AT_RIM: float = 0.2
const FIGHTER_SURFACE_AT_CORE: float = 0.45

## And where a gun is bolted. A turret wants something to be bolted to,
## so most of them are; the rest are platforms hanging in the dark.
const TURRET_SURFACE: float = 0.45
const TURRET_ORBIT: float = 0.40


## The seed of one member of a system's garrison.
##
## Two steps, the same way a planet's seed comes from its system's and a
## system's from the galaxy's: the garrison gets a seed of its own from
## the system, and its members are numbered from that. One step with a
## large index would have worked and would have left the garrison without
## an identity of its own, which the next thing to hang off a system
## would then have had to invent again.
static func seed_of(system_seed: int, index: int) -> int:
	return StarSystem.derive(StarSystem.derive(system_seed, SEED_INDEX), index)


## Everything that stands in a system, minus whatever has been beaten for
## good.
##
## `deltas` is handed in rather than fetched, for the reason every model
## in this project states: `Galaxy` is an autoload and does not exist in a
## `--script` run, so a roster that reached for it could not be tested at
## all.
##
## The order of the rolls is fixed and the heavy things are rolled
## **first**, before the counts that depend on no one. Two systems a rung
## apart should differ because the rung differs, not because a coin came
## down differently three calls earlier and shifted every roll after it.
static func of(system_seed: int, tier: int, deltas: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rung: float = _rung(tier)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = StarSystem.derive(system_seed, SEED_INDEX)

	var has_elite: bool = rng.randf() < lerpf(ELITE_AT_RIM, ELITE_AT_CORE, rung)
	var has_carrier: bool = rng.randf() < lerpf(CARRIER_AT_RIM, CARRIER_AT_CORE, rung)
	var fighters: int = _count(rng, FIGHTERS_AT_RIM, FIGHTERS_AT_CORE, rung)
	var turrets: int = _count(rng, TURRETS_AT_RIM, TURRETS_AT_CORE, rung)
	var strength: float = lerpf(STRENGTH_AT_RIM, STRENGTH_AT_CORE, rung)
	var surface: float = lerpf(
		FIGHTER_SURFACE_AT_RIM, FIGHTER_SURFACE_AT_CORE, rung
	)

	var slot: int = 0
	for index: int in range(fighters):
		var kind: Archetype = rng.randi_range(0, Archetype.RUNNER) as Archetype
		out.append(_member(
			system_seed, slot, Rank.MINOR, kind,
			Post.SURFACE if rng.randf() < surface else Post.SPACE,
			rng, strength, rung, tier,
		))
		slot += 1
	for index: int in range(turrets):
		out.append(_member(
			system_seed, slot, Rank.MINOR, Archetype.TURRET,
			_turret_post(rng), rng, strength, rung, tier,
		))
		slot += 1
	# Last, and in a fixed order, so that whether a system has a carrier
	# cannot move an elite's seed. A member's seed is its identity in
	# `deltas`, and an identity that shifts when something else is rolled
	# is a dead elite coming back to life next patch.
	if has_elite:
		out.append(_member(
			system_seed, slot, Rank.MAJOR, Archetype.AGGRESSOR,
			Post.SPACE, rng, strength, rung, tier,
		))
		slot += 1
	if has_carrier:
		out.append(_member(
			system_seed, slot, Rank.MAJOR, Archetype.CARRIER,
			Post.SPACE, rng, strength, rung, tier,
		))
		slot += 1

	var standing: Array[Dictionary] = []
	for entry: Dictionary in out:
		if not beaten(deltas, int(entry["seed"])):
			standing.append(entry)
	return standing


static func _count(
	rng: RandomNumberGenerator, rim: Vector2i, core: Vector2i, rung: float
) -> int:
	var low: int = roundi(lerpf(float(rim.x), float(core.x), rung))
	var high: int = roundi(lerpf(float(rim.y), float(core.y), rung))
	return rng.randi_range(low, maxi(low, high))


## A gun wants something to be bolted to, so most of them have one.
static func _turret_post(rng: RandomNumberGenerator) -> Post:
	var roll: float = rng.randf()
	if roll < TURRET_SURFACE:
		return Post.SURFACE
	return Post.ORBIT if roll < TURRET_SURFACE + TURRET_ORBIT else Post.SPACE


static func _member(
	system_seed: int,
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
		"seed": seed_of(system_seed, index),
		"rank": rank,
		"archetype": archetype,
		"strength": rolled * weight,
		"post": post,
		"tier": tier,
		"rarity_floor": MAJOR_RARITY_FLOOR if rank == Rank.MAJOR else 0,
	}
	if archetype == Archetype.CARRIER:
		# What the stream is, stated here rather than left to the
		# spawner: how hard a carrier presses is a property of where it
		# stands in the galaxy, and the spawner knows nothing about that.
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
## Minors are not recorded, and that is the rule rather than an omission:
## the model already says a minor comes back next visit, so a note saying
## it is dead would be a note the next roster ignores -- or worse, obeys,
## which would quietly turn every system into one that stays cleared.
static func beat(deltas: Dictionary, entry: Dictionary) -> bool:
	if int(entry.get("rank", Rank.MINOR)) != Rank.MAJOR:
		return false
	var key: int = int(entry["seed"])
	var record: Dictionary = deltas.get(key, {})
	record["beaten"] = true
	deltas[key] = record
	return true


## Everything a system can have in the air at once: what stands there,
## plus what the carriers are keeping up.
##
## The number the spawner budgets against, and the one worth watching
## when the counts are tuned -- a roster of forty is forty things to
## stream, and the live swarm is what the frame has to carry.
static func press(roster: Array[Dictionary]) -> int:
	var most: int = roster.size()
	for entry: Dictionary in roster:
		most += int(entry.get("brood", 0))
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


static func archetype_name(archetype: int) -> String:
	return ARCHETYPE_NAMES[clampi(archetype, 0, ARCHETYPE_NAMES.size() - 1)]
