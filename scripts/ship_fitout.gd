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
			"guns": [{"name": "NoseHardpoint", "at": Vector2(0, -14), "weapon": "autocannon"}],
		},
		{
			"name": "dart, stronger jets",
			"blurb": "the same layout, every engine 75% stronger and 50% heavier",
			"hull": &"dart",
			"mounts": _scaled(_stock_mounts(), 1.75),
			"guns": [{"name": "NoseHardpoint", "at": Vector2(0, -14), "weapon": "autocannon"}],
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
						"at": Vector2(0, 13), "engine": "gimbal", "centered": true},
				# Nose nozzle, pointing the other way: it is the retro and
				# the other half of the couple at the same time.
				{"name": "NoseDrive", "size": MAIN_DRIVE_SOCKET,
					"at": Vector2(0, -13), "turn": AFT, "engine": "gimbal"},
			],
			"guns": [{"name": "NoseHardpoint", "at": Vector2(0, -17), "weapon": "pulse"}],
		},
		{
			"name": "single gimbal (drifts)",
			"blurb": "rotation out of the gimballed main drive, and nothing else turns it",
			"hull": &"broad_dart",
			"mounts": [
				{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
						"at": Vector2(0, 12), "engine": "gimbal", "centered": true},
				{"name": "StrafeLeftThruster", "size": 1.0, "at": Vector2(9, 1.75),
					"turn": LEFT, "engine": "thruster"},
				{"name": "StrafeRightThruster", "size": 1.0, "at": Vector2(-9, 1.75),
					"turn": RIGHT, "engine": "thruster"},
				{"name": "NoseReverseThruster", "size": 2.5, "at": Vector2(0, -14),
					"turn": AFT, "engine": "retro"},
			],
			"guns": [{"name": "NoseHardpoint", "at": Vector2(0, -16), "weapon": "beam"}],
		},
		{
			"name": "interceptor",
			"blurb": "light and nimble, two cannon, a hold worth nothing",
			"hull": &"interceptor",
			"mounts": [
				{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
					"at": Vector2(0, 9), "engine": "main", "scale": 0.8},
				{"name": "NoseLeftTorque", "size": 0.8, "at": Vector2(-6, -11), "turn": RIGHT,
					"engine": "torque", "scale": 1.4},
				{"name": "NoseRightTorque", "size": 0.8, "at": Vector2(6, -11), "turn": LEFT,
					"engine": "torque", "scale": 1.4},
				{"name": "TailLeftTorque", "size": 0.8, "at": Vector2(-6, 11), "turn": RIGHT,
					"engine": "torque", "scale": 1.4},
				{"name": "TailRightTorque", "size": 0.8, "at": Vector2(6, 11), "turn": LEFT,
					"engine": "torque", "scale": 1.4},
				{"name": "StrafeLeftThruster", "size": 1.0, "at": Vector2(7, 0), "turn": LEFT,
					"engine": "thruster"},
				{"name": "StrafeRightThruster", "size": 1.0, "at": Vector2(-7, 0), "turn": RIGHT,
					"engine": "thruster"},
				{"name": "NoseReverseThruster", "size": 2.5, "at": Vector2(0, -15), "turn": AFT,
					"engine": "retro"},
			],
			"guns": [
				{"name": "LeftHardpoint", "at": Vector2(-5, -10), "weapon": "pulse"},
				{"name": "RightHardpoint", "at": Vector2(5, -10), "weapon": "pulse"},
			],
		},
		{
			"name": "freighter",
			"blurb": "a big hold, a heavy hull, wide legs and little power per kilo",
			"hull": &"freighter",
			"mounts": [
				{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
					"at": Vector2(0, 6), "engine": "main", "scale": 1.4},
				{"name": "NoseLeftTorque", "size": 0.8, "at": Vector2(-12, -14), "turn": RIGHT,
					"engine": "torque"},
				{"name": "NoseRightTorque", "size": 0.8, "at": Vector2(12, -14), "turn": LEFT,
					"engine": "torque"},
				{"name": "TailLeftTorque", "size": 0.8, "at": Vector2(-15, 5), "turn": RIGHT,
					"engine": "torque"},
				{"name": "TailRightTorque", "size": 0.8, "at": Vector2(15, 5), "turn": LEFT,
					"engine": "torque"},
				{"name": "StrafeLeftThruster", "size": 1.0, "at": Vector2(15, -5), "turn": LEFT,
					"engine": "thruster"},
				{"name": "StrafeRightThruster", "size": 1.0, "at": Vector2(-15, -5), "turn": RIGHT,
					"engine": "thruster"},
				{"name": "NoseReverseThruster", "size": 2.5, "at": Vector2(0, -16), "turn": AFT,
					"engine": "retro"},
			],
			"guns": [{"name": "NoseHardpoint", "at": Vector2(0, -18), "weapon": "rocket"}],
		},
		{
			"name": "bare hull",
			"blurb": "the main drive and nothing else -- the configuration report has plenty to say",
			"hull": &"dart",
			"mounts": [
				{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
					"at": Vector2(0, 10), "engine": "main"},
			],
			"guns": [],
		},
	]


static func _stock_mounts() -> Array[Dictionary]:
	return [
		{"name": "MainDrive", "size": MAIN_DRIVE_SOCKET,
			"at": Vector2(0, 10), "engine": "main"},
		{"name": "NoseLeftTorque", "size": 0.8, "at": Vector2(-8, -10), "turn": RIGHT,
			"engine": "torque"},
		{"name": "NoseRightTorque", "size": 0.8, "at": Vector2(8, -10), "turn": LEFT,
			"engine": "torque"},
		{"name": "TailLeftTorque", "size": 0.8, "at": Vector2(-8, 13.5), "turn": RIGHT,
			"engine": "torque"},
		{"name": "TailRightTorque", "size": 0.8, "at": Vector2(8, 13.5), "turn": LEFT,
			"engine": "torque"},
		{"name": "StrafeLeftThruster", "size": 1.0, "at": Vector2(9, 1.75), "turn": LEFT,
			"engine": "thruster"},
		{"name": "StrafeRightThruster", "size": 1.0, "at": Vector2(-9, 1.75), "turn": RIGHT,
			"engine": "thruster"},
		{"name": "NoseReverseThruster", "size": 2.5, "at": Vector2(0, -12), "turn": AFT,
			"engine": "retro"},
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
static func apply(ship: Ship, preset: Dictionary) -> void:
	for child: Node in ship.get_children():
		if child is EngineMount or child is Hardpoint:
			ship.remove_child(child)
			child.queue_free()

	var scene: PackedScene = load(MOUNT_SCENE) as PackedScene
	# The hull first: where its places are decides where the main drives go.
	var named: Variant = preset["hull"]
	var hull: HullData = named as HullData if named is HullData else HullData.of(named)
	if hull == null:
		push_error("preset %s names no hull" % preset["name"])
		return

	for entry: Dictionary in preset["mounts"]:
		if entry["name"] == "MainDrive":
			_add_main_drives(ship, scene, hull, entry)
			continue
		var mount: EngineMount = scene.instantiate() as EngineMount
		mount.name = String(entry["name"])
		mount.size = float(entry["size"])
		mount.position = entry["at"]
		mount.rotation = float(entry.get("turn", 0.0))
		mount.thrust_direction = Vector2.UP
		mount.installed = _engine(String(entry["engine"]), float(entry.get("scale", 1.0)))
		ship.add_child(mount)

	# Guns go in the hull's hardpoints and nowhere else. The preset says which
	# weapons it carries, in order; the hull says where the places are, and the
	# weapons fill them front first, then the sides, then astern. A preset's own
	# position for a gun is not read.
	var weapons: Array[WeaponData] = []
	for entry: Dictionary in preset["guns"]:
		weapons.append(load(WEAPONS[entry["weapon"]]) as WeaponData)
	var next_weapon: int = 0
	for slot: Dictionary in hull.slots():
		if slot["kind"] == HullData.SLOT_DRIVE:
			continue
		var gun: Hardpoint = _hardpoint(slot)
		if next_weapon < weapons.size():
			gun.weapon = weapons[next_weapon]
			next_weapon += 1
		ship.add_child(gun)
	if next_weapon < weapons.size():
		push_warning("preset %s has %d more guns than the hull has hardpoints" % [
			preset["name"], weapons.size() - next_weapon,
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
		if slot["kind"] == HullData.SLOT_DRIVE:
			var mount: EngineMount = scene.instantiate() as EngineMount
			mount.name = String(slot["name"])
			mount.size = MAIN_DRIVE_SOCKET
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
	copy.bulk *= 1.0 + (scale - 1.0) * 0.7
	return copy
