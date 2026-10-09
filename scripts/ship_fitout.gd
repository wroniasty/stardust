class_name ShipFitout
extends RefCounted
## Whole ships, as data: which hull, where the mounts are, and what is
## bolted into them.
##
## The creative tool could already change a hull's shape, which is half of
## what a ship is. The other half is the fitout, and until now there was
## exactly one of those -- the layout in `ship.tscn` -- so every question
## about flying something different had to be answered by editing a scene.
##
## These are sandbox presets, not a catalogue the game draws from. What
## they are for is finding out what the control model does with a shape it
## was not tuned on: the gimbal-only ship below is the one that found the
## control groups could not count a gimbal at all.

## Engine resources the presets are built from, by short name so a table
## entry reads as a sentence rather than as a path.
const ENGINES: Dictionary = {
	"main": "res://resources/engines/main_drive.tres",
	"torque": "res://resources/engines/torque_jet.tres",
	"thruster": "res://resources/engines/maneuver_thruster.tres",
	"retro": "res://resources/engines/retro_thruster.tres",
	"gimbal": "res://resources/engines/gimballed_drive.tres",
}

const WEAPONS: Dictionary = {
	"autocannon": "res://resources/weapons/autocannon.tres",
	"pulse": "res://resources/weapons/pulse_repeater.tres",
	"beam": "res://resources/weapons/beam_lance.tres",
	"rocket": "res://resources/weapons/dumb_rocket.tres",
}

const MOUNT_SCENE: String = "res://scenes/engine_mount.tscn"

## How big a socket each small-engine role has.
##
## Facts about the role rather than about the ship, which is why they are
## here once instead of repeated in every preset: every preset in the
## game used 0.8 for a torque jet, 1.0 for a strafe thruster and 2.5 for
## the nose reverse, because that is what those jobs take.
const TORQUE_SOCKET: float = 0.8
const STRAFE_SOCKET: float = 1.0
const RETRO_SOCKET: float = 2.5

## And which socket size goes with which kind of place the hull offers.
const SOCKET_FOR: Dictionary = {
	HullData.SLOT_TORQUE: TORQUE_SOCKET,
	HullData.SLOT_STRAFE: STRAFE_SOCKET,
	HullData.SLOT_RETRO: RETRO_SOCKET,
	HullData.SLOT_DRIVE: MAIN_DRIVE_SOCKET,
}

## What the "stronger jets" preset multiplies its engines by. Named
## because the blurb is computed from it as well as the engines.
const STRONGER_JETS: float = 1.75

## How much room a main drive socket has.
##
## The generator's own bulk ceiling, so **no engine the game can roll is
## ever too big for a main socket**. Measured before it was set: over
## 40000 engine rolls, 2.6% came out bigger than the 3.5 every main
## socket used to have -- every one of them the pilot's best find of the
## hour and none of them installable anywhere, because the loot table
## pays for thrust with bulk (`oversized`, `buffered`) and the sockets
## were sized for the stock engines rather than for the rolls.
##
## The same number on every hull, the interceptor included, because a
## socket that refuses a plain gimballed drive is not hull character, it
## is a hull that cannot be upgraded. What a big engine costs is still
## paid: bulk is mass (`EngineMount.MASS_PER_BULK`), mass is thrust per
## kilo and a shifted centre of mass, and the small sockets -- torque
## 0.8, strafe 1.0, nose retro 2.5 -- are untouched, so `compact` still
## has somewhere to matter.
const MAIN_DRIVE_SOCKET: float = 8.0

## A right angle, written once: every side-facing mount is one of these.
const LEFT: float = -PI * 0.5
const RIGHT: float = PI * 0.5
const AFT: float = PI


## Every preset, in the order the tool offers them.
##
## `scale` on a mount multiplies the engine's thrust **and** its bulk, so
## a bigger engine is a heavier one: a table that scaled only the thrust
## would be offering free power, which is the one thing a sandbox must not
## quietly do (IDEAS.md section 14).
static func all() -> Array[Dictionary]:
	return [
		{
			"name": "dart (stock)",
			"blurb": "four torque jets, a main drive, a retro and two strafe",
			"hull": &"dart",
			"mounts": _stock_mounts(),
			"guns": ["autocannon"],
		},
		{
			"name": "dart, stronger jets",
			"blurb": scaled_blurb(STRONGER_JETS),
			"hull": &"dart",
			"mounts": _scaled(_stock_mounts(), STRONGER_JETS),
			"guns": ["autocannon"],
		},
		{
			"name": "twin gimbal (force couple)",
			"blurb": "two steerable nozzles, nose and tail: the moments add, the thrusts cancel",
			# A symmetric hull on purpose. The two nozzles only cancel
			# while their arms about the centre of mass are equal, and the
			# centre of mass follows the hull: on a triangle it sits aft
			# of the middle and the pair stops being a pair.
			"hull": &"rhombus",
			"mounts": [
				{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
						"engine": "gimbal", "centered": true},
				# Nose nozzle, pointing the other way: it is the retro and
				# the other half of the couple at the same time.
				{"name": "NoseDrive", "size": MAIN_DRIVE_SOCKET,
					"at": Vector2(0, -13), "turn": AFT, "engine": "gimbal"},
			],
			"guns": ["pulse"],
		},
		{
			"name": "single gimbal (drifts)",
			"blurb": "rotation out of the gimballed main drive, and nothing else turns it",
			"hull": &"broad_dart",
			"mounts": [
				{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
						"engine": "gimbal", "centered": true},
				{"name": "StrafeLeftThruster",
					"engine": "thruster"},
				{"name": "StrafeRightThruster",
					"engine": "thruster"},
				{"name": "NoseReverseThruster",
					"engine": "retro"},
			],
			"guns": ["beam"],
		},
		{
			"name": "interceptor",
			"blurb": "light and nimble, two cannon, a hold worth nothing",
			"hull": &"interceptor",
			"mounts": [
				{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
					"engine": "main", "scale": 0.8},
				{"name": "NoseLeftTorque",
					"engine": "torque", "scale": 1.4},
				{"name": "NoseRightTorque",
					"engine": "torque", "scale": 1.4},
				{"name": "TailLeftTorque",
					"engine": "torque", "scale": 1.4},
				{"name": "TailRightTorque",
					"engine": "torque", "scale": 1.4},
				{"name": "StrafeLeftThruster",
					"engine": "thruster"},
				{"name": "StrafeRightThruster",
					"engine": "thruster"},
				{"name": "NoseReverseThruster",
					"engine": "retro"},
			],
			"guns": [
				"pulse",
				"pulse",
			],
		},
		{
			"name": "freighter",
			"blurb": "a big hold, a heavy hull, wide legs and little power per kilo",
			"hull": &"freighter",
			"mounts": [
				{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
					"engine": "main", "scale": 1.4},
				{"name": "NoseLeftTorque",
					"engine": "torque"},
				{"name": "NoseRightTorque",
					"engine": "torque"},
				{"name": "TailLeftTorque",
					"engine": "torque"},
				{"name": "TailRightTorque",
					"engine": "torque"},
				{"name": "StrafeLeftThruster",
					"engine": "thruster"},
				{"name": "StrafeRightThruster",
					"engine": "thruster"},
				{"name": "NoseReverseThruster",
					"engine": "retro"},
			],
			"guns": ["rocket"],
		},
		{
			"name": "bare hull",
			"blurb": "the main drive and nothing else -- the configuration report has plenty to say",
			"hull": &"dart",
			"mounts": [
				{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
					"engine": "main"},
			],
			"guns": [],
		},
	]


static func _stock_mounts() -> Array[Dictionary]:
	return [
		{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
			"engine": "main"},
		{"name": "NoseLeftTorque",
			"engine": "torque"},
		{"name": "NoseRightTorque",
			"engine": "torque"},
		{"name": "TailLeftTorque",
			"engine": "torque"},
		{"name": "TailRightTorque",
			"engine": "torque"},
		{"name": "StrafeLeftThruster",
			"engine": "thruster"},
		{"name": "StrafeRightThruster",
			"engine": "thruster"},
		{"name": "NoseReverseThruster",
			"engine": "retro"},
	]


## How much of a thrust increase is paid for in bulk.
##
## Not all of it: a bigger engine of the same design is heavier, and not
## in proportion, or there would be no reason to want one. Seven tenths,
## which is a decision and the only reason this number exists.
const BULK_SHARE: float = 0.7


## What scaling an engine by `factor` does to its bulk.
##
## Its own function because **a blurb was written by hand against it and
## got it wrong**: a preset advertised as "50% heavier" at a thrust factor
## of 1.75 is 52.5% heavier, because the share is applied to the increase
## rather than to the whole. Now the sentence is computed from the same
## expression the engine is, so the two cannot disagree again.
static func bulk_factor(scale: float) -> float:
	return 1.0 + (scale - 1.0) * BULK_SHARE


## The sentence that goes with a scaled preset, in the figures it will
## actually fly with.
static func scaled_blurb(factor: float) -> String:
	return "the same layout, every engine %.0f%% stronger and %.1f%% heavier" % [
		(factor - 1.0) * 100.0, (bulk_factor(factor) - 1.0) * 100.0,
	]


static func _scaled(mounts: Array[Dictionary], factor: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mount: Dictionary in mounts:
		var copy: Dictionary = mount.duplicate()
		copy["scale"] = float(copy.get("scale", 1.0)) * factor
		out.append(copy)
	return out


## The preset with this name, or an empty dictionary.
static func preset(preset_name: String) -> Dictionary:
	for entry: Dictionary in all():
		if entry["name"] == preset_name:
			return entry
	return {}


## Rebuilds a ship as one of these, in place.
##
## In place rather than by swapping in another scene, because everything
## pointing at this ship -- the camera, the HUDs, the editor, the streaming
## manager -- would have to be told, and a sandbox that invalidates half
## the game's references is a sandbox that crashes instead of teaching.
static func apply(ship: Ship, wanted: Dictionary) -> bool:
	# **Checked before anything comes off.** This used to strip the engines
	# and the guns and then look for the hull, so a preset naming a hull
	# that does not exist left the pilot with a bare fuselage and an error
	# in the log -- a refit that fails has to fail having changed nothing,
	# because the ship it was refitting is the one the player is flying.
	var fault: String = fault_in(wanted)
	if not fault.is_empty():
		# Reported and returned, not pushed as an engine error. A refused
		# refit is a refused operation carrying its reason -- the same
		# shape as `JumpController.blocked_by` -- and the guard against a
		# malformed preset shipping is the test that walks `all()` and
		# asks `fault_in` of each, which fails a build rather than
		# printing a line into a log nobody reads.
		print("refit refused: %s" % fault)
		return false

	var scene: PackedScene = load(MOUNT_SCENE) as PackedScene
	var hull: HullData = hull_of(wanted)

	for child: Node in ship.get_children():
		if child is EngineMount or child is Hardpoint:
			ship.remove_child(child)
			child.queue_free()

	# Where the hull says each of its places is, by name. A preset names a
	# role -- NoseLeftTorque, StrafeRightThruster -- and the hull decides
	# where that lands, exactly as it already did for drives and guns.
	# Torque and strafe positions used to be literals in the table below,
	# which meant a hull could not be reshaped without editing GDScript.
	var places: Dictionary = {}
	for slot: Dictionary in hull.slots():
		places[String(slot["name"])] = slot

	for entry: Dictionary in wanted["mounts"]:
		if entry["name"] == "MainDrive":
			_add_main_drives(ship, scene, hull, entry)
			continue
		var mount: EngineMount = scene.instantiate() as EngineMount
		mount.name = String(entry["name"])
		var place: Dictionary = places.get(mount.name, {})
		mount.size = float(entry.get("size", SOCKET_FOR.get(
			place.get("kind", &""), 1.0
		)))
		# The hull first, and the preset's own only for a mount the hull
		# has no place for -- the forward-facing nozzle on the twin-gimbal
		# ship is one, and until a hull can describe that it stays here.
		mount.position = place["at"] if not place.is_empty() else entry["at"]
		mount.rotation = (
			float(place["turn"]) if not place.is_empty()
			else float(entry.get("turn", 0.0))
		)
		mount.thrust_direction = Vector2.UP
		mount.installed = _engine(String(entry["engine"]), float(entry.get("scale", 1.0)))
		ship.add_child(mount)

	# Guns go in the hull's hardpoints and nowhere else. The preset says which
	# weapons it carries, in order; the hull says where the places are, and the
	# weapons fill them front first, then the sides, then astern.
	#
	# So the list is **weapon names and nothing else**. It used to be a list
	# of entries carrying a hardpoint name and a position as well, neither
	# of which was ever read: two fields that looked like they placed a gun
	# and did not, which is worse than no fields at all.
	var weapons: Array[WeaponData] = []
	for gun: Variant in wanted["guns"]:
		weapons.append(load(WEAPONS[String(gun)]) as WeaponData)
	var next_weapon: int = 0
	for slot: Dictionary in hull.slots():
		# Every place that takes an **engine** is skipped, not just the
		# drives: this read `== SLOT_DRIVE` until the hull learned about
		# torque jets, strafe thrusters and the nose reverse, and then
		# quietly fitted a gun to each of the seven. `SOCKET_FOR` is the
		# same predicate `add_hull_slots` uses, so the two loops cannot
		# come to different conclusions about what a place is for.
		if SOCKET_FOR.has(slot["kind"]):
			continue
		var gun: Hardpoint = _hardpoint(slot)
		if next_weapon < weapons.size():
			gun.weapon = weapons[next_weapon]
			next_weapon += 1
		ship.add_child(gun)
	if next_weapon < weapons.size():
		push_warning("preset %s has %d more guns than the hull has hardpoints" % [
			wanted["name"], weapons.size() - next_weapon,
		])

	# The hull is named, not described. It used to be an outline, a hold
	# and a pair of feet written out in every preset -- three of which flew
	# the same dart and had to agree about it by hand.
	ship.hull = hull
	ship.hull_outline = hull.outline
	# Zero on a hull means "this shape does not say", which the hull's own
	# field documents and this used to ignore -- a refit onto one of the
	# creative-tool shapes handed the ship a hold of nothing.
	if hull.cargo_capacity > 0.0:
		ship.hull_cargo_capacity = hull.cargo_capacity
	if ship.gear != null and not hull.legs.is_empty():
		ship.gear.legs = hull.legs.duplicate()
	var drawn: Polygon2D = ship.get_node_or_null("Hull") as Polygon2D
	if drawn != null:
		drawn.polygon = ship.hull_outline

	add_hull_slots(ship, hull)

	ship.collect_parts()
	ship._build_contact_points()
	ship._build_collision_shape()
	ship.rebuild_control_groups(false)
	return true


## The hull a preset names, resolved. Either a `HullData` outright -- which
## is what the creative tool hands over for a shape that exists only in
## memory -- or a name out of the catalogue.
static func hull_of(wanted: Dictionary) -> HullData:
	var named: Variant = wanted.get("hull")
	if named is HullData:
		return named as HullData
	return HullData.of(named) if named != null else null


## What is wrong with this preset, or "" when nothing is.
##
## One function, so `apply` and anything that wants to offer a preset
## cannot come to different conclusions about whether it is usable -- the
## same shape as `JumpController.blocked_by`. It checks everything `apply`
## is about to read and nothing else: a field no longer read is a field
## that should not be here to check (see `guns`).
static func fault_in(wanted: Dictionary) -> String:
	var title: String = String(wanted.get("name", "<unnamed>"))
	if not wanted.has("name"):
		return "a preset with no name"
	if hull_of(wanted) == null:
		return "%s names no hull" % title
	if not (wanted.get("mounts") is Array):
		return "%s has no mounts" % title
	# What the hull offers, by name, so a mount can be checked against it
	# rather than against a rule written out twice.
	var offered: Dictionary = {}
	for slot: Dictionary in hull_of(wanted).slots():
		offered[String(slot["name"])] = slot
	for entry: Variant in wanted["mounts"]:
		if not (entry is Dictionary):
			return "%s has a mount that is not an entry" % title
		var mount: Dictionary = entry
		for needed: String in ["name", "engine"]:
			if not mount.has(needed):
				return "%s has a mount with no %s" % [title, needed]
		if not ENGINES.has(String(mount["engine"])):
			return "%s wants engine %s, which there is none of" % [
				title, mount["engine"],
			]
		# A mount needs a position of its own only where the hull has no
		# place by that name. Drives, torque jets, strafe thrusters and
		# the nose reverse all come off the hull now; what is left in the
		# table is the odd one the hull cannot describe yet, such as the
		# forward-facing nozzle on the twin-gimbal ship.
		var named: String = String(mount["name"])
		if named != "MainDrive" and not offered.has(named) and not mount.has("at"):
			return "%s has a mount %s with nowhere to be" % [title, named]
		if not mount.has("size") and not SOCKET_FOR.has(
			(offered.get(named, {}) as Dictionary).get("kind", &"")
		):
			return "%s has a mount %s with no socket size" % [title, named]
	if not (wanted.get("guns") is Array):
		return "%s has no gun list" % title
	for gun: Variant in wanted["guns"]:
		if not WEAPONS.has(String(gun)):
			return "%s wants weapon %s, which there is none of" % [title, gun]
	return ""


## The preset's main drive, put into the hull's side drive slots -- or into the
## centre one, whole, when the entry says `centered`: a nozzle that steers by
## swinging on the centre line is a different ship from a pair.
##
## Engines go in slots and nowhere else, so the position in the preset's table
## is ignored: the hull says where the places are. The centre slot stays empty
## and the drive is split across the pair either side of it, each taking half
## the thrust and half the bulk, so the total is what the preset declared and
## the pair pushes straight along the ship.
static func _add_main_drives(ship: Ship, scene: PackedScene, hull: HullData, entry: Dictionary) -> void:
	var centered: bool = bool(entry.get("centered", false))
	var sides: Array[Dictionary] = []
	for slot: Dictionary in hull.slots_of(HullData.SLOT_DRIVE):
		if is_zero_approx((slot["at"] as Vector2).x) == centered:
			sides.append(slot)
	if sides.is_empty():
		return
	var share: float = 1.0 / float(sides.size())
	for slot: Dictionary in sides:
		var mount: EngineMount = scene.instantiate() as EngineMount
		mount.name = String(slot["name"])
		mount.size = float(entry["size"])
		mount.position = slot["at"]
		mount.rotation = float(slot["turn"])
		mount.thrust_direction = Vector2.UP
		mount.installed = _engine_share(
			String(entry["engine"]), float(entry.get("scale", 1.0)), share
		)
		ship.add_child(mount)


## One part of an engine, for a drive that is split over several mounts.
static func _engine_share(key: String, scale: float, share: float) -> EngineData:
	var whole: EngineData = _engine(key, scale)
	var part: EngineData = whole.duplicate() as EngineData
	part.max_thrust *= share
	part.bulk *= share
	return part


## Gives the ship every place the hull offers that it does not already have:
## empty drive mounts and empty hardpoints, named by the hull.
##
## A place is filled when a node of its name exists, so the same call serves a
## preset that was just built and a ship that came with only some of them.
static func add_hull_slots(ship: Ship, hull: HullData) -> void:
	var scene: PackedScene = load(MOUNT_SCENE) as PackedScene
	for slot: Dictionary in hull.slots():
		if ship.has_node(NodePath(String(slot["name"]))):
			continue
		if SOCKET_FOR.has(slot["kind"]):
			# Every engine place the hull offers and the preset left
			# empty, drives included: a socket with nothing in it is the
			# ship telling the pilot where something could go.
			var mount: EngineMount = scene.instantiate() as EngineMount
			mount.name = String(slot["name"])
			mount.size = float(SOCKET_FOR[slot["kind"]])
			mount.position = slot["at"]
			mount.rotation = float(slot["turn"])
			mount.thrust_direction = Vector2.UP
			ship.add_child(mount)
		else:
			ship.add_child(_hardpoint(slot))


## An empty hardpoint at one of the hull's places.
static func _hardpoint(slot: Dictionary) -> Hardpoint:
	var gun: Hardpoint = Hardpoint.new()
	gun.name = String(slot["name"])
	gun.position = slot["at"]
	gun.rotation = float(slot["turn"])
	return gun


## An engine from the table, scaled if the preset asked for a bigger one.
##
## Duplicated before scaling: the resources are shared, and a preset that
## scaled the original would make every later ship in the session inherit
## the change.
static func _engine(key: String, scale: float) -> EngineData:
	var base: EngineData = load(ENGINES[key]) as EngineData
	if is_equal_approx(scale, 1.0):
		return base
	var copy: EngineData = base.duplicate() as EngineData
	copy.max_thrust *= scale
	# Heavier as well as stronger. Scaling only the thrust would be free
	# power, which is the one thing a sandbox must not quietly hand out.
	copy.bulk *= bulk_factor(scale)
	return copy
