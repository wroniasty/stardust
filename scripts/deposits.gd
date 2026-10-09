class_name Deposits
extends RefCounted
## What is in the ground of a world, and where.
##
## Pure data, like `Garrison` and `StarSystem`: a deposit exists before
## anything is instantiated, the same seed puts the same ore under the
## same bearing, and nothing here digs, draws or decides when the pilot
## may have it.
##
## ## Two ores, and the ladder decides which
##
## Iron ore is everywhere and becomes spare parts, which is repair. Dust
## ore is scarce at the rim and common in the core and becomes stardust,
## which is range. So the ground says the same thing the rest of the
## galaxy says -- going deeper is worth it -- without a second scale to
## keep in step with the tier. See `Stores.Kind` for why there are two
## and not five.
##
## ## On the surface and under it
##
## A patch is either exposed or buried, and a buried one has to be dug
## down to. That is not a new mechanic: the crust is already a bitmap a
## weapon can blow holes in, and holes already persist through
## `Galaxy.deltas`. Burying half the ore is what turns carving from
## vandalism into prospecting.
##
## Depth is a share of the crust band rather than a number of pixels,
## because the band is a share of the planet (`PlanetTerrain.
## DEPTH_FRACTION`) and a moon is not a gas giant. A patch measured in
## pixels would be exposed on one world and unreachable on the next.
##
## ## What is taken stays taken
##
## Mined units are written to `Galaxy.deltas` under the **patch's own
## seed**, which is the key schema every other entry in that dictionary
## uses: a body's crust, a system's `seen`, a garrison member's
## `beaten`, and now a patch's `mined`. A world that refilled itself
## between visits would make the whole ladder pointless -- there would
## be no reason to go anywhere new.

## Where a body's deposits draw their seed from.
##
## Far from anything else that hangs off a body: `Garrison.SEED_INDEX`
## is 1000 and a carrier's brood numbers from 7000. A shared index is a
## shared `deltas` key, and the first thing to break would be a mined-out
## patch reviving an elite.
const SEED_INDEX: int = 2000

## How many patches a world has, at each end of the ladder.
##
## Few on purpose. A world covered in ore is a world with no reason to
## read the survey scanner, and the scanner is how a pilot is supposed
## to find these -- flying round a planet turning over every bearing is
## not prospecting, it is mowing.
const PATCHES_AT_RIM: Vector2i = Vector2i(1, 3)
const PATCHES_AT_CORE: Vector2i = Vector2i(3, 6)

## The chance one patch is dust ore rather than iron, at each end.
const DUST_SHARE_AT_RIM: float = 0.15
const DUST_SHARE_AT_CORE: float = 0.55

## How much is in a patch, by kind.
##
## Measured against the hold rather than chosen: the stock hold takes
## thirty iron ore or twenty-four dust ore (`Stores.BULK`), so a middling
## iron patch is about one hold and a rich one about one and a third. A
## patch worth several holds would make the second trip the game.
const IRON_UNITS: Vector2i = Vector2i(18, 40)
const DUST_UNITS: Vector2i = Vector2i(8, 20)

## And how much more of it a moon has. A moon is a rock, and a rock is
## mostly rock -- it is also the body a pilot can land on without a
## gravity well worth arguing with, so it being worth the trip is the
## reward for noticing that.
const MOON_RICHNESS: float = 1.25

## The chance a patch is buried, and the deepest one can be as a share
## of the crust band.
##
## Not all of the band: ore at the very bottom would need the hole dug
## to the last pixel, and a patch that is technically reachable and
## practically not is worse than no patch.
const BURIED_CHANCE: float = 0.55
const DEEPEST: float = 0.6

## How wide a patch is, in radians of arc.
##
## Narrow. A pilot has to be over it, which is what makes the bearing
## worth writing down -- a patch spanning a tenth of a world would be a
## patch you land on by accident.
const SPAN: Vector2 = Vector2(0.03, 0.10)


## The seed of one patch, two steps from the body's own the same way a
## garrison member's is.
static func seed_of(body_seed: int, index: int) -> int:
	return StarSystem.derive(StarSystem.derive(body_seed, SEED_INDEX), index)


## Whether this body has ground to dig at all.
##
## Its own question, asked far more often than "what is in it": a
## scanner sweeping a system wants to mark the worlds worth landing on,
## and a station has no ground however rich its system is.
static func diggable(body: SystemBody) -> bool:
	if body == null:
		return false
	return body.kind == SystemBody.Kind.PLANET or body.kind == SystemBody.Kind.MOON


## Every patch still worth digging on this body. Empty when there is
## nothing, or nothing left.
##
## `deltas` is handed in rather than fetched, for the reason every model
## here states: `Galaxy` is an autoload and does not exist in a
## `--script` run, so a model that reached for it could not be tested.
static func on(body: SystemBody, tier: int, deltas: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not diggable(body):
		return out
	var rung: float = GalaxyMap.rung_of(tier)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = StarSystem.derive(body.seed, SEED_INDEX)
	var count: int = rng.randi_range(
		roundi(lerpf(float(PATCHES_AT_RIM.x), float(PATCHES_AT_CORE.x), rung)),
		roundi(lerpf(float(PATCHES_AT_RIM.y), float(PATCHES_AT_CORE.y), rung)),
	)
	var dust_share: float = lerpf(DUST_SHARE_AT_RIM, DUST_SHARE_AT_CORE, rung)
	var richness: float = MOON_RICHNESS if body.kind == SystemBody.Kind.MOON else 1.0
	for index: int in range(count):
		var kind: int = (
			Stores.Kind.DUST_ORE if rng.randf() < dust_share else Stores.Kind.IRON_ORE
		)
		var span: Vector2i = DUST_UNITS if kind == Stores.Kind.DUST_ORE else IRON_UNITS
		var units: int = maxi(int(round(
			float(rng.randi_range(span.x, span.y)) * richness
		)), 1)
		var patch_seed: int = seed_of(body.seed, index)
		var gone: int = taken(deltas, patch_seed)
		if gone >= units:
			continue
		out.append({
			"seed": patch_seed,
			"body": body,
			"kind": kind,
			"bearing": rng.randf_range(0.0, TAU),
			"span": rng.randf_range(SPAN.x, SPAN.y),
			# Nought is exposed; anything above it is a share of the crust
			# band to be dug through first.
			"depth": (
				rng.randf_range(0.1, DEEPEST) if rng.randf() < BURIED_CHANCE else 0.0
			),
			"units": units,
			"left": units - gone,
			"tier": tier,
		})
	return out


## How much has already been dug out of this patch.
static func taken(deltas: Dictionary, patch_seed: int) -> int:
	return int((deltas.get(patch_seed, {}) as Dictionary).get("mined", 0))


## Writes down that this much came out, and returns how much actually
## did -- less than asked for when the patch runs dry, the same shape as
## drawing on a tank that is nearly empty.
static func take(deltas: Dictionary, patch: Dictionary, units: int) -> int:
	if units <= 0 or patch.is_empty():
		return 0
	var key: int = int(patch["seed"])
	var total: int = int(patch["units"])
	var gone: int = taken(deltas, key)
	var given: int = mini(units, maxi(total - gone, 0))
	if given <= 0:
		return 0
	var record: Dictionary = deltas.get(key, {})
	record["mined"] = gone + given
	deltas[key] = record
	patch["left"] = maxi(total - gone - given, 0)
	return given


## Whether the rock over this patch is out of the way.
##
## Takes the ground's current radius as a number rather than a `Planet`,
## so the rule can be checked without building a world -- and so that
## the one place the rule lives is here rather than half here and half
## in whatever is doing the digging.
static func reachable(patch: Dictionary, surface_now: float, body_radius: float) -> bool:
	if patch.is_empty():
		return false
	var depth: float = float(patch.get("depth", 0.0))
	if depth <= 0.0:
		return true
	return surface_now <= radius_of(patch, body_radius)


## How far from the centre this patch sits, in the planet's polar frame.
static func radius_of(patch: Dictionary, body_radius: float) -> float:
	var depth: float = float(patch.get("depth", 0.0))
	return body_radius * (1.0 - depth * PlanetTerrain.DEPTH_FRACTION)


## Whether a bearing is over this patch. Wrapped, because a patch
## straddling nought is a patch like any other.
static func covers(patch: Dictionary, bearing: float) -> bool:
	if patch.is_empty():
		return false
	var off: float = wrapf(bearing - float(patch["bearing"]), -PI, PI)
	return absf(off) <= float(patch.get("span", SPAN.x)) * 0.5


## The patch under this bearing, or an empty dictionary.
##
## The nearest one when two overlap, which they can: the bearings are
## independent rolls and nothing stops two patches sharing ground. The
## alternative -- rejecting overlaps at generation -- would make a
## patch's seed depend on the patches before it.
static func under(patches: Array[Dictionary], bearing: float) -> Dictionary:
	var best: Dictionary = {}
	var closest: float = INF
	for patch: Dictionary in patches:
		if not covers(patch, bearing):
			continue
		var off: float = absf(wrapf(bearing - float(patch["bearing"]), -PI, PI))
		if off < closest:
			closest = off
			best = patch
	return best


static func kind_name(patch: Dictionary) -> String:
	return Stores.kind_name(int(patch.get("kind", Stores.Kind.IRON_ORE)))
