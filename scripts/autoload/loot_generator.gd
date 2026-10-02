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

## Exponent applied to an affix's named benefit. Exponent rather than a
## linear scale, because a factor below 1 scaled linearly crosses zero and
## produces items with negative rate of fire; raising it to a power stays on
## the right side of zero however strong the rarity gets.
##
## Applied to the benefit only -- see _apply_affixes. Raised at the top end,
## because four affixes on a legendary are drawn from a table of seven and
## most of them do not touch the headline number, so a legendary that reads
## as legendary needs the ones that do to land hard.
const RARITY_STRENGTH: Array[float] = [1.0, 1.15, 1.45, 1.8, 2.3]

## The one list, on ModuleData, where the colours are too. Two lists of
## rarity names would drift the first time one of them gained an entry.
const RARITY_NAMES: Array[String] = ModuleData.RARITY_NAMES

const WEAPON_BASES: Array[String] = [
	"res://resources/weapons/autocannon.tres",
	"res://resources/weapons/siege_slug.tres",
	"res://resources/weapons/pulse_repeater.tres",
	"res://resources/weapons/beam_lance.tres",
	"res://resources/weapons/dumb_rocket.tres",
	"res://resources/weapons/seeker.tres",
	"res://resources/weapons/burst_shell.tres",
]

const GENERATOR_BASES: Array[String] = [
	"res://resources/generators/standard_cell.tres",
]

const ENGINE_BASES: Array[String] = [
	"res://resources/engines/main_drive.tres",
	"res://resources/engines/torque_jet.tres",
	"res://resources/engines/maneuver_thruster.tres",
	"res://resources/engines/retro_thruster.tres",
	"res://resources/engines/maneuver_pod.tres",
	"res://resources/engines/braking_bell.tres",
	"res://resources/engines/gimballed_drive.tres",
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
	{
		"name": &"turreted", "field": "traverse_range", "factor": Vector2(1.35, 1.90),
		"cost_field": "rounds_per_second", "cost": Vector2(0.80, 0.92),
	},
	{
		"name": &"quick-slewing", "field": "traverse_rate", "factor": Vector2(1.30, 1.80),
		"cost_field": "damage", "cost": Vector2(0.86, 0.95),
	},
	{
		"name": &"wide", "field": "blast_radius", "factor": Vector2(1.25, 1.65),
		"cost_field": "damage", "cost": Vector2(0.82, 0.94),
	},
	{
		"name": &"eager", "field": "missile_thrust", "factor": Vector2(1.25, 1.70),
		"cost_field": "range_px", "cost": Vector2(0.75, 0.90),
	},
	{"name": &"breaching", "field": "crater_radius", "factor": Vector2(1.30, 1.90)},
	{
		"name": &"lightweight", "field": "bulk", "factor": Vector2(0.60, 0.85),
		"cost_field": "damage", "cost": Vector2(0.80, 0.92),
	},
	{
		"name": &"efficient", "field": "energy_cost", "factor": Vector2(0.65, 0.85),
		"cost_field": "damage", "cost": Vector2(0.85, 0.95),
	},
	{
		"name": &"capacitor-fed", "field": "rounds_per_second", "factor": Vector2(1.25, 1.55),
		"cost_field": "energy_cost", "cost": Vector2(1.30, 1.70),
	},
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
	{
		"name": &"steerable", "field": "gimbal_range", "factor": Vector2(1.30, 1.80),
		"cost_field": "max_thrust", "cost": Vector2(0.85, 0.95),
	},
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
	# The cross-stat pair. An engine has no business holding charge, which is
	# exactly why finding one that does is a decision: a pilot who would
	# rather shoot flies a slower ship (IDEAS.md section 14).
	{
		"name": &"dynamo", "stat_add": &"energy_recharge", "amount": Vector2(4.0, 10.0),
		"cost_field": "max_thrust", "cost": Vector2(0.80, 0.92),
	},
	{
		"name": &"buffered", "stat_add": &"energy_capacity", "amount": Vector2(12.0, 30.0),
		"cost_field": "bulk", "cost": Vector2(1.15, 1.40),
	},
]

## What a generator can roll. Capacity, rate and silence are the three knobs
## and each affix moves one of them at the cost of another, so a found cell is
## a different machine rather than a bigger number.
const GENERATOR_AFFIXES: Array[Dictionary] = [
	{
		"name": &"deep", "field": "capacity", "factor": Vector2(1.20, 1.55),
		"cost_field": "recharge_rate", "cost": Vector2(0.78, 0.92),
	},
	{
		"name": &"brisk", "field": "recharge_rate", "factor": Vector2(1.15, 1.45),
		"cost_field": "capacity", "cost": Vector2(0.75, 0.90),
	},
	{"name": &"responsive", "field": "recharge_delay", "factor": Vector2(0.55, 0.80)},
	{
		"name": &"compact", "field": "bulk", "factor": Vector2(0.60, 0.85),
		"cost_field": "capacity", "cost": Vector2(0.80, 0.92),
	},
]

## Shot mods, as a fixed catalogue rather than a rolled template: a mod is a
## decision the pilot makes, so the interesting variety is in which ones they
## own, not in each one being slightly different.
##
## Every entry raises the cost of a shot. That is an invariant of the table,
## checked by a test the same way affix costs are: the slot says how many fit,
## energy says how much you get to fire with them.
const SHOT_MODS: Array[Dictionary] = [
	{"name": "heavy slug", "energy": 1.35, "damage": 1.40, "rate": 0.85},
	{"name": "choke", "energy": 1.15, "spread": 0.45},
	{"name": "breaching charge", "energy": 1.45, "crater": 1.90, "speed": 0.85},
	{"name": "long barrel", "energy": 1.20, "range": 1.50, "speed": 1.25},
	{"name": "penetrator", "energy": 1.55, "damage": 0.85, "effect": 1, "pierce": 2},
	{"name": "shrapnel shell", "energy": 1.50, "damage": 0.80, "effect": 2},
]

## Which way is up for each field, so an affix cost can be checked for
## actually costing something and a configuration report can say whether a
## swap is an upgrade (M2).
const HIGHER_IS_BETTER: Dictionary = {
	"damage": true,
	"rounds_per_second": true,
	"muzzle_speed": true,
	"range_px": true,
	"traverse_range": true,
	"traverse_rate": true,
	"crater_radius": true,
	"max_thrust": true,
	"reliability": true,
	"bulk": false,
	"spread_degrees": false,
	"energy_cost": false,
	"capacity": true,
	"recharge_rate": true,
	"recharge_delay": false,
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
	"traverse_range": Vector2(0.0, 3.14),
	"traverse_rate": Vector2(0.2, 12.0),
	"blast_radius": Vector2(0.0, 160.0),
	"missile_thrust": Vector2(0.0, 2000.0),
	"missile_turn_rate": Vector2(0.0, 8.0),
	"energy_cost": Vector2(0.5, 200.0),
	"capacity": Vector2(10.0, 600.0),
	"recharge_rate": Vector2(2.0, 200.0),
	"recharge_delay": Vector2(0.1, 5.0),
	"max_thrust": Vector2(1.0, 5000.0),
	"gimbal_range": Vector2(0.0, 0.6),
	"gimbal_rate": Vector2(0.2, 12.0),
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
	# A ship carries many guns and engines and exactly one generator, so cells
	# turn up least often. Drawn before anything else, as before, so the kind
	# a container holds is fixed by its seed whatever the tables gain later.
	var kind: float = rng.randf()
	if kind < 0.38:
		return _build_weapon(rng, rarity)
	if kind < 0.70:
		return _build_engine(rng, rarity)
	if kind < 0.82:
		return _build_generator(rng, rarity)
	if kind < 0.90:
		return computer(rng.randi(), rarity)
	return shot_mod(rng.randi() % SHOT_MODS.size())


## Rolls a weapon. `rarity` of ROLLED lets the seed decide.
func weapon(item_seed: int, rarity: int = ROLLED) -> WeaponData:
	return _build_weapon(_rng_for(item_seed), rarity)


## Rolls an engine. `rarity` of ROLLED lets the seed decide.
func engine(item_seed: int, rarity: int = ROLLED) -> EngineData:
	return _build_engine(_rng_for(item_seed), rarity)


## Rolls a generator. `rarity` of ROLLED lets the seed decide.
func generator(item_seed: int, rarity: int = ROLLED) -> GeneratorData:
	return _build_generator(_rng_for(item_seed), rarity)


## Rolls a flight computer. Not from a base resource: what makes one
## interesting is which functions it has, and that is a set of switches
## rather than a set of numbers to scale.
func computer(item_seed: int, rarity: int = ROLLED) -> FlightComputerData:
	var rng: RandomNumberGenerator = _rng_for(item_seed)
	var rolled: int = rarity if rarity != ROLLED else roll_rarity(rng)
	var box: FlightComputerData = FlightComputerData.new()
	box.rarity = rolled
	box.allocation = (
		FlightComputerData.Allocation.NNLS if rolled >= Rarity.UNCOMMON
		else FlightComputerData.Allocation.HEURISTIC
	)
	# The good functions are what rarity buys here, not bigger numbers.
	box.has_auto_level = rolled >= Rarity.UNCOMMON and rng.randf() < 0.7
	box.has_auto_orbit = rolled >= Rarity.RARE and rng.randf() < 0.6
	box.bulk = rng.randf_range(0.4, 1.2)
	box.idle_draw = rng.randf_range(0.5, 3.0)

	var parts: PackedStringArray = PackedStringArray()
	if box.allocation == FlightComputerData.Allocation.NNLS:
		parts.append("solving")
	if box.has_auto_level:
		parts.append("levelling")
	if box.has_auto_orbit:
		parts.append("orbital")
	box.display_name = "%s computer" % " ".join(parts) if not parts.is_empty() else "basic computer"
	return box


## Builds one shot mod from the catalogue.
func shot_mod(index: int) -> ShotModData:
	var entry: Dictionary = SHOT_MODS[clampi(index, 0, SHOT_MODS.size() - 1)]
	var mod: ShotModData = ShotModData.new()
	mod.display_name = String(entry["name"])
	mod.energy_multiplier = float(entry["energy"])
	mod.damage_multiplier = float(entry.get("damage", 1.0))
	mod.rate_multiplier = float(entry.get("rate", 1.0))
	mod.spread_multiplier = float(entry.get("spread", 1.0))
	mod.crater_multiplier = float(entry.get("crater", 1.0))
	mod.range_multiplier = float(entry.get("range", 1.0))
	mod.speed_multiplier = float(entry.get("speed", 1.0))
	mod.effect = int(entry.get("effect", 0)) as ShotModData.Effect
	mod.pierce_count = int(entry.get("pierce", 1))
	mod.bulk = 0.2
	return mod


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
	item.rarity = rolled
	item.affixes = _apply_affixes(rng, item, WEAPON_AFFIXES, rolled)
	# Rarity buys room for decisions, not just bigger numbers.
	item.mod_slots = mini(rolled, 3)
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
	item.rarity = rolled
	_apply_affixes(rng, item, ENGINE_AFFIXES, rolled)
	_clamp_all(item)
	return item


func _build_generator(rng: RandomNumberGenerator, rarity: int) -> GeneratorData:
	var base: GeneratorData = load(
		GENERATOR_BASES[rng.randi() % GENERATOR_BASES.size()]
	) as GeneratorData
	if base == null:
		return null
	var item: GeneratorData = base.duplicate() as GeneratorData
	var rolled: int = rarity if rarity != ROLLED else roll_rarity(rng)
	item.rarity = rolled
	item.display_name = _name_for(item.display_name, _apply_affixes(
		rng, item, GENERATOR_AFFIXES, rolled
	))
	_clamp_all(item)
	return item


## Applies `count` distinct affixes from `table` to `item`, and returns their
## names in the order they were rolled.
func _apply_affixes(
	rng: RandomNumberGenerator, item: Resource, table: Array[Dictionary], rarity: int
) -> Array[StringName]:
	var names: Array[StringName] = []
	var strength: float = RARITY_STRENGTH[rarity]

	# The pool is what this base can actually use, not the whole category.
	# A rarity that cannot fill its slots gets fewer affixes rather than
	# dead ones: there is genuinely less to vary on a fixed gun, and
	# saying so is better than four names of which two do nothing.
	var pool: Array[int] = []
	for i: int in range(table.size()):
		if affix_bites(item, table[i]):
			pool.append(i)
	var count: int = mini(RARITY_AFFIXES[rarity], pool.size())

	for _step: int in range(count):
		var choice: int = rng.randi() % pool.size()
		var affix: Dictionary = table[pool[choice]]
		pool.remove_at(choice)

		if affix.has("stat_add"):
			# Flat, not a multiplier: what it adds to is the ship's own base,
			# and a multiplier here would be scaling a number this module has
			# never seen.
			var key: StringName = affix["stat_add"]
			var span: Vector2 = affix["amount"] as Vector2
			var module: ModuleData = item as ModuleData
			module.stat_add = module.stat_add.duplicate()
			module.stat_add[key] = (
				float(module.stat_add.get(key, 0.0)) + rng.randf_range(span.x, span.y) * strength
			)
		else:
			_scale(item, String(affix["field"]), affix["factor"] as Vector2, strength, rng)
		if affix.has("cost_field"):
			# The cost is rolled at face value, never raised to the rarity
			# exponent. Amplifying both sides made rarity mean "more extreme
			# in both directions", and measured over 600 rolls that came out
			# as a legendary engine averaging 0.82 of its base thrust and
			# bottoming out at 0.08 -- loot that is on average a downgrade
			# and occasionally a brick.
			#
			# Extreme is still the aim, but around a higher mean: the named
			# benefit scales with rarity, the price stays what it says.
			_scale(item, String(affix["cost_field"]), affix["cost"] as Vector2, 1.0, rng)
		names.append(affix["name"] as StringName)

	return names


## Whether this affix can do anything to this base.
##
## An affix multiplies a field, and a multiplier on zero is zero: it lands,
## takes one of the item's few slots, and changes nothing. Measured over
## 8400 rolls before this existed, **14% of affixes were landing dead**, and
## 19% on the torque and manoeuvring jets -- because the whole engine pool
## could roll "steerable" onto a base with no gimbal.
##
## The other half is the mirror of it. An affix whose **cost** lands on a
## field the base leaves at zero is not a trade, it is a gift: "tuned" buys
## thrust with fuel, and on a jet that burns none it buys thrust with
## nothing. The table is built on every affix costing something, so an affix
## that cannot charge this base does not belong in its pool either.
##
## Derived rather than listed, which is the decision M3.5 recorded: a list
## per base would mean writing every new affix into seven files, and
## forgetting the eighth. A base inherits the category's pool and excludes
## what it has no room for, and the arithmetic works out which that is.
func affix_bites(item: Resource, affix: Dictionary) -> bool:
	# A cross-stat affix adds to the ship rather than scaling the module,
	# so there is no field of the base for it to land flat on.
	if affix.has("field") and not _has_room(item, String(affix["field"])):
		return false
	if affix.has("cost_field") and not _has_room(item, String(affix["cost_field"])):
		return false
	return true


## Whether `field` on this item is something a multiplier could move.
func _has_room(item: Resource, field: String) -> bool:
	if not (field in item):
		return false
	return absf(float(item.get(field))) > 0.0001


## Which affixes of `table` this base can take, by name. For the tests and
## for anything that wants to show a pilot what a base is capable of.
func affixes_for(item: Resource, table: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for affix: Dictionary in table:
		if affix_bites(item, affix):
			out.append(affix["name"] as StringName)
	return out


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
