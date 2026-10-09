class_name SaveGame
extends RefCounted
## A save: the seed, the deltas, and what the ship has on it.
##
## IDEAS.md section 10: *a save is the galaxy seed plus a dictionary of
## deltas*. The
## universe is a pure function of one number, so none of it is written
## down -- a hundred and eleven systems, their stars, planets, moons,
## terrain and names all come back from the seed. What a file has to
## hold is only the two things a seed cannot produce: what the player
## has changed about the world, and what the player has.
##
## That is why this file is short, and why it staying short is the
## measure of whether the model is still honest. The day a save has to
## store where a planet is, the generator has stopped being the truth.
##
## Written as `var_to_str`, not JSON. A save is full of `Vector2`s and
## typed arrays, and JSON turns every one of them into something else;
## the engine's own text format round-trips them and stays readable.

const PATH: String = "user://stardust.save"

## Bumped when the shape changes. A save from an older shape is
## declined rather than half-read -- a half-read save is a corrupt
## universe that looks fine until the pilot lands somewhere that is not
## there any more.
const VERSION: int = 1


## Everything that cannot be worked out from the seed.
static func capture(galaxy: Node, ship: Ship) -> Dictionary:
	return {
		"version": VERSION,
		"galaxy": {
			"seed": galaxy.galaxy_seed,
			"here": galaxy.here,
			"at": galaxy.at,
			"time": galaxy.time,
			# Read back with a default rather than behind a version bump:
			# a field nobody had is a field that defaults, and bumping the
			# version to add one would throw away every existing save for
			# the sake of a pin.
			"marked": NavMarker.marked,
			"deltas": galaxy.deltas.duplicate(true),
		},
		"ship": _capture_ship(ship),
	}


static func _capture_ship(ship: Ship) -> Dictionary:
	if ship == null or not is_instance_valid(ship):
		return {}
	var fitted: Dictionary = {}
	var mods: Dictionary = {}
	for child: Node in ship.get_children():
		var mount: EngineMount = child as EngineMount
		if mount != null and mount.installed != null:
			fitted[String(child.name)] = pack(mount.installed)
		var gun: Hardpoint = child as Hardpoint
		if gun != null:
			if gun.weapon != null:
				fitted[String(child.name)] = pack(gun.weapon)
			var fitted_mods: Array = []
			for mod: ShotModData in gun.mods:
				fitted_mods.append(pack(mod))
			if not fitted_mods.is_empty():
				mods[String(child.name)] = fitted_mods
		var bay: ModuleBay = child as ModuleBay
		if bay != null and bay.installed != null:
			fitted[String(child.name)] = pack(bay.installed)
		var legs: LandingGear = child as LandingGear
		if legs != null and legs.installed != null:
			fitted[String(child.name)] = pack(legs.installed)

	var stowed: Array = []
	for entry: Dictionary in ship.cargo:
		stowed.append({
			"item": pack(entry["item"] as ModuleData),
			"rarity": int(entry.get("rarity", 0)),
		})

	return {
		"at": ship.global_position,
		"facing": ship.global_rotation,
		# Whole numbers in a plain dictionary, read back with a default:
		# a save written before the hold could hold stuff by the unit is
		# a save with an empty bin, not a save this build refuses.
		"stores": ship.stores.to_record(),
		"velocity": ship.linear_velocity,
		"spin": ship.angular_velocity,
		"hull": ship.hull_integrity,
		"heat": ship.hull_heat,
		"energy": ship.energy,
		"fuel": ship.fuel,
		"fitted": fitted,
		"mods": mods,
		"cargo": stowed,
	}


## One module, as the properties its script says to store.
##
## Walked from the property list rather than named one field at a time.
## A hand-written list is a list that forgets the field somebody added
## last week, and the thing it forgets is always a rolled number -- so
## the save would quietly hand back a legendary drive with common
## figures.
static func pack(module: ModuleData) -> Dictionary:
	if module == null:
		return {}
	var out: Dictionary = {"script": module.get_script().resource_path}
	for entry: Dictionary in module.get_property_list():
		var usage: int = int(entry["usage"])
		var field: String = String(entry["name"])
		if usage & PROPERTY_USAGE_STORAGE == 0 or field == "script":
			continue
		out[field] = module.get(field)
	return out


static func unpack(data: Dictionary) -> ModuleData:
	if data.is_empty() or not data.has("script"):
		return null
	var kind: GDScript = load(String(data["script"])) as GDScript
	if kind == null:
		return null
	var module: ModuleData = kind.new() as ModuleData
	if module == null:
		return null
	for field: Variant in data:
		if String(field) == "script":
			continue
		module.set(String(field), data[field])
	return module


## Puts a captured game back. Returns whether it took.
static func restore(data: Dictionary, galaxy: Node, ship: Ship) -> bool:
	if not is_valid(data):
		return false
	var sky: Dictionary = data["galaxy"]
	# Reset first and overwrite after: reset is what rebuilds the map
	# from the seed, and it also clears the address and the deltas,
	# which is why they go back on top rather than before.
	galaxy.reset(int(sky["seed"]))
	galaxy.here = int(sky["here"])
	galaxy.at = sky["at"] as Vector2
	galaxy.time = float(sky["time"])
	# After `reset`, which clears it: the saved pin goes back on top the
	# same way the saved address does.
	NavMarker.marked = sky.get("marked", Vector2.INF)
	galaxy.deltas.clear()
	for key: Variant in sky["deltas"]:
		galaxy.deltas[key] = (sky["deltas"][key] as Dictionary).duplicate(true)
	restore_ship(data, ship)
	return true


## The ship half on its own.
##
## Public because the world restores the two halves at different
## moments: which system to open is the first question it asks, and
## there is no hull to put a loadout into until after it has been
## answered. Restoring both at the end opened the starting system,
## generated its terrain and threw it away.
static func restore_ship(data: Dictionary, ship: Ship) -> void:
	_restore_ship(data.get("ship", {}) as Dictionary, ship)


static func _restore_ship(hull: Dictionary, ship: Ship) -> void:
	if hull.is_empty() or ship == null or not is_instance_valid(ship):
		return
	var fitted: Dictionary = hull.get("fitted", {})
	var mods: Dictionary = hull.get("mods", {})
	for child: Node in ship.get_children():
		var where: String = String(child.name)
		var module: ModuleData = unpack(fitted.get(where, {}) as Dictionary)
		var mount: EngineMount = child as EngineMount
		if mount != null:
			mount.installed = module as EngineData
		var gun: Hardpoint = child as Hardpoint
		if gun != null:
			gun.weapon = module as WeaponData
			gun.mods.clear()
			for packed: Variant in mods.get(where, []):
				var mod: ShotModData = unpack(packed as Dictionary) as ShotModData
				if mod != null:
					gun.mods.append(mod)
		var bay: ModuleBay = child as ModuleBay
		if bay != null:
			bay.installed = module
		var legs: LandingGear = child as LandingGear
		if legs != null:
			legs.installed = module as GearData

	ship.stores = Stores.from_record(hull.get("stores", {}) as Dictionary)
	ship.cargo.clear()
	for entry: Variant in hull.get("cargo", []):
		var stowed: Dictionary = entry as Dictionary
		var item: ModuleData = unpack(stowed.get("item", {}) as Dictionary)
		if item != null:
			ship.cargo.append({"item": item, "rarity": int(stowed.get("rarity", 0))})

	# After the parts are in, because the rebuild is what works out the
	# mass, the groups and the capacities the pools are then clamped to.
	ship.collect_parts()
	ship.rebuild_control_groups(false)

	ship.global_position = hull["at"] as Vector2
	ship.global_rotation = float(hull["facing"])
	ship.linear_velocity = hull["velocity"] as Vector2
	ship.angular_velocity = float(hull["spin"])
	ship.hull_integrity = float(hull["hull"])
	ship.hull_heat = float(hull["heat"])
	# Clamped, not trusted: a save written before a tank was swapped out
	# must not hand back more than the tank now fitted can hold.
	ship.energy = clampf(float(hull["energy"]), 0.0, ship.energy_capacity())
	ship.fuel = clampf(float(hull["fuel"]), 0.0, ship.fuel_capacity())
	# A `charges` key written by an older build is read and dropped: the
	# magazine is gone and one tank pays for everything now, so there is
	# nothing for the number to mean.


## Whether this is a save this build can read.
static func is_valid(data: Dictionary) -> bool:
	return (
		not data.is_empty()
		and int(data.get("version", -1)) == VERSION
		and data.has("galaxy")
		and (data["galaxy"] as Dictionary).has("seed")
	)


static func write(data: Dictionary, path: String = PATH) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("could not write %s (%d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(var_to_str(data))
	file.close()
	return true


static func read(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = str_to_var(text)
	return parsed as Dictionary if parsed is Dictionary else {}


static func forget(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
