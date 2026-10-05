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
## now the tier was a number describing itself: the galaxy had a shape, a
## ladder and a chart, and tier 9 held exactly what tier 1 held. A flight
## inwards was a commute. Everything below is the arithmetic that turns
## the ladder into a reason.
##
## ## The two rules of coming back
##
## IDEAS.md and PLAN.md M5.1 ask for two different ones, and the first
## costs nothing at all:
##
## - **A minor comes back when you come back, never while you are there.**
##   A roster derived from a seed *is* that rule. Nothing is stored,
##   nothing is timed, and a system you cleared and left is the same
##   system when you return. A spawner that dripped enemies in while the
##   pilot was in the room would be a system to run from rather than one
##   to clear, which is the whole reason the rule is written that way.
## - **A major beaten is beaten for good.** That one cannot come from a
##   seed, so it is the only thing here that is written down, and it goes
##   in `Galaxy.deltas` under the major's own seed -- the same scheme
##   every other entry in that dictionary uses.
##
## A major left alive is **not** written down, which is the other half of
## the rule: it comes back whole, at full health, because otherwise
## flying in and running away is always cheaper than fighting.

## Rank, and there are two on purpose. A third would be a third decision
## at every place that reads one.
enum Rank { MINOR, MAJOR }

## Where it waits. The roster names the kind of place rather than the
## body, because it knows a seed and a tier and nothing about what the
## system contains. A system with nothing to stand on puts its surface
## enemies in space, and that is the spawner's call.
enum Post { SPACE, SURFACE }

## What it does when it sees you. Named here because a roster that could
## only say "an enemy" could not say that the mix changes going inwards,
## which is half of what a tier is for. The behaviours arrive with the AI.
enum Archetype { PATROL, AGGRESSOR, RUNNER }

const RANK_NAMES: Array[String] = ["minor", "major"]
const ARCHETYPE_NAMES: Array[String] = ["patrol", "aggressor", "runner"]

## Where the garrison's own seed is drawn from the system's.
##
## An index like any other, and deliberately one no body will ever use:
## `StarSystem` numbers its star 0, its planets 1 to 5 and its docks after
## them, so the twenties are already generous. A garrison sharing a seed
## with a moon would share a `deltas` key with it, and the first thing to
## break would be a dug crater bringing an elite back to life.
const SEED_INDEX: int = 1000

## How many minors a system holds, at the bottom of the ladder and at the
## top. A range rather than a number at each end, so two systems on the
## same rung are not the same fight.
const MINORS_AT_RIM: Vector2i = Vector2i(1, 3)
const MINORS_AT_CORE: Vector2i = Vector2i(5, 8)

## The chance of a major, at each end of the ladder.
##
## Not zero at the rim and not one at the core. A rim with no elites at
## all would teach the pilot that elites are a core thing and leave the
## first one they meet unexplained; a core where every system has one
## would make the finale a formality by the time they got there.
const MAJOR_AT_RIM: float = 0.08
const MAJOR_AT_CORE: float = 0.80

## What a minor is worth, as a multiple of the weakest one there is, at
## each end. The one scale everything that fights will read.
const STRENGTH_AT_RIM: float = 1.0
const STRENGTH_AT_CORE: float = 4.0

## How much of that a single roll may vary by, either way.
const STRENGTH_SPREAD: float = 0.18

## What a major is worth against a minor of its own tier.
##
## Two and a half, which is meant to be "bring friends or bring a plan"
## rather than "come back later": an elite that is simply a wall teaches
## nothing, and the loot it drops is the reason to try.
const MAJOR_STRENGTH: float = 2.5

## The rarity a major's drop is guaranteed to reach, as `LootGenerator`
## counts rarity. The reason to fight one rather than fly round it.
const MAJOR_RARITY_FLOOR: int = 2

## How much of a garrison waits on a surface rather than in space, at each
## end of the ladder. Rising inwards, because a system that can only be
## cleared by landing is a longer, more committing fight, and that belongs
## where the stakes are.
const SURFACE_AT_RIM: float = 0.2
const SURFACE_AT_CORE: float = 0.45


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
static func of(system_seed: int, tier: int, deltas: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rung: float = _rung(tier)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = StarSystem.derive(system_seed, SEED_INDEX)

	var span: Vector2i = Vector2i(
		roundi(lerpf(float(MINORS_AT_RIM.x), float(MINORS_AT_CORE.x), rung)),
		roundi(lerpf(float(MINORS_AT_RIM.y), float(MINORS_AT_CORE.y), rung)),
	)
	var count: int = rng.randi_range(span.x, maxi(span.x, span.y))
	# The major is rolled **before** the minors and placed last, so that
	# whether a system has one does not shift every minor's rolls. Two
	# systems a rung apart should differ because the rung differs, not
	# because a coin came down differently three calls earlier.
	var has_major: bool = rng.randf() < lerpf(MAJOR_AT_RIM, MAJOR_AT_CORE, rung)
	var surface_share: float = lerpf(SURFACE_AT_RIM, SURFACE_AT_CORE, rung)
	var strength: float = lerpf(STRENGTH_AT_RIM, STRENGTH_AT_CORE, rung)

	for index: int in range(count):
		out.append(_member(
			system_seed, index, Rank.MINOR, rng, strength, surface_share, tier
		))
	if has_major:
		out.append(_member(
			system_seed, count, Rank.MAJOR, rng, strength, surface_share, tier
		))

	var standing: Array[Dictionary] = []
	for entry: Dictionary in out:
		if not beaten(deltas, int(entry["seed"])):
			standing.append(entry)
	return standing


static func _member(
	system_seed: int,
	index: int,
	rank: Rank,
	rng: RandomNumberGenerator,
	strength: float,
	surface_share: float,
	tier: int,
) -> Dictionary:
	var major: bool = rank == Rank.MAJOR
	var rolled: float = strength * rng.randf_range(
		1.0 - STRENGTH_SPREAD, 1.0 + STRENGTH_SPREAD
	)
	return {
		"seed": seed_of(system_seed, index),
		"rank": rank,
		# An elite is an aggressor. Not a roll: a major that patrols past
		# the pilot and goes back to its rounds is a major they never
		# meet, and the one enemy a system is remembered for should be
		# the one that comes for you.
		"archetype": (
			Archetype.AGGRESSOR if major
			else rng.randi_range(0, ARCHETYPE_NAMES.size() - 1) as Archetype
		),
		"strength": rolled * (MAJOR_STRENGTH if major else 1.0),
		"post": Post.SURFACE if rng.randf() < surface_share else Post.SPACE,
		"tier": tier,
		"rarity_floor": MAJOR_RARITY_FLOOR if major else 0,
	}


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


## How far up the ladder a tier is, 0 at the bottom rung and 1 at the top.
static func _rung(tier: int) -> float:
	return clampf(
		float(clampi(tier, 1, GalaxyMap.TIERS) - 1) / float(GalaxyMap.TIERS - 1),
		0.0,
		1.0,
	)


static func rank_name(rank: int) -> String:
	return RANK_NAMES[clampi(rank, 0, RANK_NAMES.size() - 1)]


static func archetype_name(archetype: int) -> String:
	return ARCHETYPE_NAMES[clampi(archetype, 0, ARCHETYPE_NAMES.size() - 1)]
