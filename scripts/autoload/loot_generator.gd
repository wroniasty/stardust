extends Node
## LootGenerator: procedural weapons, engines and modules.
##
## Base template plus 0..N affixes, rarity drives affix count and magnitude
## (see IDEAS.md section 4). Every roll is derived from an explicit seed so
## the same container always yields the same loot.
##
## Rarity deliberately does not mean "strictly better". The strong affixes
## carry a drawback, so a rare item is more *extreme* than a common one rather
## than uniformly above it: a heavy autocannon hits harder and fires slower,
## and whether that is an upgrade depends on the pilot. Loot that is one
## scalar is a number going up, not a decision.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## Passed as the rarity when the seed should choose one.
const ROLLED: int = -1

## Relative chance of each rarity, indexed by the enum.
const RARITY_WEIGHTS: Array[float] = [55.0, 27.0, 13.0, 4.0, 1.0]

## How many affixes each rarity rolls.
const RARITY_AFFIXES: Array[int] = [0, 1, 2, 3, 4]

## Exponent applied to every affix factor. Exponent rather than a linear
## scale, because a factor below 1 scaled linearly crosses zero and produces
## items with negative rate of fire; raising it to a power stays on the right
## side of zero however strong the rarity gets.
const RARITY_STRENGTH: Array[float] = [1.0, 1.0, 1.25, 1.5, 1.8]

const RARITY_NAMES: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]

const WEAPON_BASES: Array[String] = [
	"res://resources/weapons/autocannon.tres",
	"res://resources/weapons/siege_slug.tres",
]

const ENGINE_BASES: Array[String] = [
	"res://resources/engines/main_drive.tres",
	"res://resources/engines/torque_jet.tres",
	"res://resources/engines/maneuver_thruster.tres",
	"res://resources/engines/retro_thruster.tres",
]

## An affix is a named multiplier on one field, optionally paid for with a
## multiplier on another. `factor` is the range rolled before rarity scaling;
## below 1 means the field goes down, which is an improvement for spread,
## spool time and fuel.
const WEAPON_AFFIXES: Array[Dictionary] = [
	{
		"name": &"heavy", "field": "damage", "factor": Vector2(1.20, 1.50),
		"cost_field": "rounds_per_second", "cost": Vector2(0.70, 0.85),
	},
	{
		"name": &"rapid", "field": "rounds_per_second", "factor": Vector2(1.20, 1.55),
		"cost_field": "spread_degrees", "cost": Vector2(1.30, 1.70),
	},
	{"name": &"precise", "field": "spread_degrees", "factor": Vector2(0.40, 0.70)},
	{"name": &"long", "field": "range_px", "factor": Vector2(1.25, 1.60)},
	{"name": &"breaching", "field": "crater_radius", "factor": Vector2(1.30, 1.90)},
	{
		"name": &"hot-loaded", "field": "muzzle_speed", "factor": Vector2(1.15, 1.40),
		"cost_field": "crater_radius", "cost": Vector2(0.75, 0.90),
	},
]

const ENGINE_AFFIXES: Array[Dictionary] = [
	{
		"name": &"overbored", "field": "max_thrust", "factor": Vector2(1.15, 1.45),
		"cost_field": "reliability", "cost": Vector2(0.80, 0.92),
	},
	{"name": &"responsive", "field": "spool_time", "factor": Vector2(0.45, 0.75)},
	{"name": &"hardened", "field": "reliability", "factor": Vector2(1.05, 1.20)},
	{"name": &"frugal", "field": "fuel_cost", "factor": Vector2(0.50, 0.80)},
	{
		"name": &"compact", "field": "bulk", "factor": Vector2(0.65, 0.85),
		"cost_field": "max_thrust", "cost": Vector2(0.78, 0.92),
	},
	{
		"name": &"oversized", "field": "max_thrust", "factor": Vector2(1.25, 1.60),
		"cost_field": "bulk", "cost": Vector2(1.20, 1.55),
	},
	{
		"name": &"tuned", "field": "max_thrust", "factor": Vector2(1.08, 1.20),
		"cost_field": "fuel_cost", "cost": Vector2(1.20, 1.60),
	},
]

## Which way is up for each field, so an affix cost can be checked for
## actually costing something and a configuration report can say whether a
## swap is an upgrade (M2).
const HIGHER_IS_BETTER: Dictionary = {
	"damage": true,
	"rounds_per_second": true,
	"muzzle_speed": true,
	"range_px": true,
	"crater_radius": true,
	"max_thrust": true,
	"reliability": true,
	"bulk": false,
	"spread_degrees": false,
	"spool_time": false,
	"fuel_cost": false,
}

## Floors and ceilings applied after the affixes, so no roll can produce an
## item the rest of the game cannot use.
const LIMITS: Dictionary = {
	"damage": Vector2(0.01, 1.0),
	"rounds_per_second": Vector2(0.1, 30.0),
	"spread_degrees": Vector2(0.0, 45.0),
	"muzzle_speed": Vector2(50.0, 3000.0),
	"range_px": Vector2(100.0, 20000.0),
	"crater_radius": Vector2(2.0, 80.0),
	"max_thrust": Vector2(1.0, 5000.0),
	# Generous on purpose. An engine too big for the hull you are flying is a
	# legitimate find rather than a bad roll -- it is loot for a bigger ship --
	# so the ceiling belongs to the machine, not to the stock hull's largest
	# slot. The loadout screen is what has to explain why it will not go in.
	"bulk": Vector2(0.1, 8.0),
	"spool_time": Vector2(0.05, 5.0),
	"reliability": Vector2(0.1, 1.0),
	"fuel_cost": Vector2(0.0, 100.0),
}


## Rolls one item of either kind from `item_seed`.
func generate(item_seed: int, rarity: int = ROLLED) -> Resource:
	var rng: RandomNumberGenerator = _rng_for(item_seed)
	# Drawn before anything else so that the kind of item a container holds is
	# fixed by its seed, whatever the tables gain later.
	if rng.randf() < 0.5:
		return _build_weapon(rng, rarity)
	return _build_engine(rng, rarity)


## Rolls a weapon. `rarity` of ROLLED lets the seed decide.
func weapon(item_seed: int, rarity: int = ROLLED) -> WeaponData:
	return _build_weapon(_rng_for(item_seed), rarity)


## Rolls an engine. `rarity` of ROLLED lets the seed decide.
func engine(item_seed: int, rarity: int = ROLLED) -> EngineData:
	return _build_engine(_rng_for(item_seed), rarity)


## Picks a rarity from the weights.
func roll_rarity(rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for weight: float in RARITY_WEIGHTS:
		total += weight
	var pick: float = rng.randf() * total
	for i: int in range(RARITY_WEIGHTS.size()):
		pick -= RARITY_WEIGHTS[i]
		if pick <= 0.0:
			return i
	return Rarity.COMMON


func _rng_for(item_seed: int) -> RandomNumberGenerator:
	# A fresh generator per item rather than one shared member: two containers
	# opened in a different order must still hold the same things.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = item_seed
	return rng


func _build_weapon(rng: RandomNumberGenerator, rarity: int) -> WeaponData:
	var base: WeaponData = load(WEAPON_BASES[rng.randi() % WEAPON_BASES.size()]) as WeaponData
	if base == null:
		return null
	var item: WeaponData = base.duplicate() as WeaponData
	var rolled: int = rarity if rarity != ROLLED else roll_rarity(rng)
	item.affixes = _apply_affixes(rng, item, WEAPON_AFFIXES, rolled)
	_clamp_all(item)
	item.display_name = _name_for(item.display_name, item.affixes)
	return item


func _build_engine(rng: RandomNumberGenerator, rarity: int) -> EngineData:
	var base: EngineData = load(ENGINE_BASES[rng.randi() % ENGINE_BASES.size()]) as EngineData
	if base == null:
		return null
	var item: EngineData = base.duplicate() as EngineData
	var rolled: int = rarity if rarity != ROLLED else roll_rarity(rng)
	# EngineData has no name of its own: what an engine is called comes from
	# its type, because its purpose comes from where it is mounted.
	_apply_affixes(rng, item, ENGINE_AFFIXES, rolled)
	_clamp_all(item)
	return item


## Applies `count` distinct affixes from `table` to `item`, and returns their
## names in the order they were rolled.
func _apply_affixes(
	rng: RandomNumberGenerator, item: Resource, table: Array[Dictionary], rarity: int
) -> Array[StringName]:
	var names: Array[StringName] = []
	var count: int = mini(RARITY_AFFIXES[rarity], table.size())
	var strength: float = RARITY_STRENGTH[rarity]

	var pool: Array[int] = []
	for i: int in range(table.size()):
		pool.append(i)

	for _step: int in range(count):
		var choice: int = rng.randi() % pool.size()
		var affix: Dictionary = table[pool[choice]]
		pool.remove_at(choice)

		_scale(item, String(affix["field"]), affix["factor"] as Vector2, strength, rng)
		if affix.has("cost_field"):
			_scale(item, String(affix["cost_field"]), affix["cost"] as Vector2, strength, rng)
		names.append(affix["name"] as StringName)

	return names


## Brings every limited field of a finished item inside its bounds.
##
## Run over the whole item rather than only the fields an affix touched, so
## that "a rolled item is always usable" holds without exceptions. Some bases
## sit outside a bound already -- a thruster stores spool_time 0 because its
## type ignores the field -- and an invariant with a footnote is one nobody
## can test.
func _clamp_all(item: Resource) -> void:
	for field: String in LIMITS:
		if not (field in item):
			continue
		var bounds: Vector2 = LIMITS[field]
		item.set(field, clampf(float(item.get(field)), bounds.x, bounds.y))


## Multiplies one field by a rolled factor raised to the rarity's strength,
## then clamps it to what the rest of the game can use.
func _scale(
	item: Resource,
	field: String,
	factor: Vector2,
	strength: float,
	rng: RandomNumberGenerator,
) -> void:
	var rolled: float = rng.randf_range(factor.x, factor.y)
	var value: float = float(item.get(field)) * pow(rolled, strength)
	if LIMITS.has(field):
		var bounds: Vector2 = LIMITS[field]
		value = clampf(value, bounds.x, bounds.y)
	item.set(field, value)


func _name_for(base_name: String, affixes: Array[StringName]) -> String:
	if affixes.is_empty():
		return base_name
	var parts: PackedStringArray = PackedStringArray()
	for affix: StringName in affixes:
		parts.append(String(affix))
	parts.append(base_name)
	return " ".join(parts)


## What a rarity is called, for the HUD and the pickup prompt.
func rarity_name(rarity: int) -> String:
	return RARITY_NAMES[clampi(rarity, 0, RARITY_NAMES.size() - 1)]
