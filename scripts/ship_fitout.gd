class_name ShipFitout
extends RefCounted
## Whole ships, as data: where the mounts are and what is bolted into them.
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
			"blurb": "cztery dysze obrotowe, główny napęd, retro i dwa boczne",
			"hull": [Vector2(0, -12), Vector2(-8, 10), Vector2(8, 10)],
			"cargo": 11.0,
			"legs": [Vector2(-9, 13), Vector2(9, 13)],
			"mounts": _stock_mounts(),
			"guns": [{"name": "NoseHardpoint", "at": Vector2(0, -14), "weapon": "autocannon"}],
		},
		{
			"name": "dart, mocniejsze dysze",
			"blurb": "ten sam układ, każdy silnik o 75% mocniejszy i o połowę cięższy",
			"hull": [Vector2(0, -12), Vector2(-8, 10), Vector2(8, 10)],
			"cargo": 11.0,
			"legs": [Vector2(-9, 13), Vector2(9, 13)],
			"mounts": _scaled(_stock_mounts(), 1.75),
			"guns": [{"name": "NoseHardpoint", "at": Vector2(0, -14), "weapon": "autocannon"}],
		},
		{
			"name": "gimbal podwójny (para sił)",
			"blurb": "dwie wychylane dysze, dziób i rufa: momenty się dodają, ciągi znoszą",
			# Symmetric on purpose. The two nozzles only cancel while their
			# arms about the centre of mass are equal, and the centre of
			# mass follows the hull: on a triangle it sits aft of the
			# middle and the pair stops being a pair.
			"hull": [Vector2(0, -15), Vector2(-9, 0), Vector2(0, 15), Vector2(9, 0)],
			"cargo": 9.0,
			"legs": [Vector2(-8, 14), Vector2(8, 14)],
			"mounts": [
				{"name": "MainDrive", "size": 3.5, "at": Vector2(0, 13), "engine": "gimbal"},
				# Nose nozzle, pointing the other way: it is the retro and
				# the other half of the couple at the same time.
				{"name": "NoseDrive", "size": 3.5, "at": Vector2(0, -13), "turn": AFT,
					"engine": "gimbal"},
			],
			"guns": [{"name": "NoseHardpoint", "at": Vector2(0, -17), "weapon": "pulse"}],
		},
		{
			"name": "gimbal pojedynczy (dryfuje)",
			"blurb": "obrót z wychylanej dyszy głównej, nic poza nią nie kręci",
			"hull": [Vector2(0, -14), Vector2(-9, 12), Vector2(9, 12)],
			"cargo": 11.0,
			"legs": [Vector2(-10, 15), Vector2(10, 15)],
			"mounts": [
				{"name": "MainDrive", "size": 3.5, "at": Vector2(0, 12), "engine": "gimbal"},
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
			"name": "przechwytujący",
			"blurb": "lekki i zwrotny, dwa działka, ładownia na nic",
			"hull": [Vector2(0, -15), Vector2(-7, 9), Vector2(7, 9)],
			"cargo": 4.0,
			"legs": [Vector2(-7, 11), Vector2(7, 11)],
			"mounts": [
				{"name": "MainDrive", "size": 3.0, "at": Vector2(0, 9), "engine": "main",
					"scale": 0.8},
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
			"name": "frachtowiec",
			"blurb": "duża ładownia, ciężki kadłub, szerokie nogi i mało mocy na kilogram",
			"hull": [
				Vector2(-13, -16), Vector2(13, -16), Vector2(16, 6), Vector2(-16, 6),
			],
			"cargo": 42.0,
			"legs": [Vector2(-15, 9), Vector2(15, 9)],
			"mounts": [
				{"name": "MainDrive", "size": 3.5, "at": Vector2(0, 6), "engine": "main",
					"scale": 1.4},
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
			"name": "kadłub bez niczego",
			"blurb": "sam napęd główny — raport konfiguracji ma co powiedzieć",
			"hull": [Vector2(0, -12), Vector2(-8, 10), Vector2(8, 10)],
			"cargo": 11.0,
			"legs": [Vector2(-9, 13), Vector2(9, 13)],
			"mounts": [
				{"name": "MainDrive", "size": 3.5, "at": Vector2(0, 10), "engine": "main"},
			],
			"guns": [],
		},
	]


static func _stock_mounts() -> Array[Dictionary]:
	return [
		{"name": "MainDrive", "size": 3.5, "at": Vector2(0, 10), "engine": "main"},
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
	for entry: Dictionary in preset["mounts"]:
		var mount: EngineMount = scene.instantiate() as EngineMount
		mount.name = String(entry["name"])
		mount.size = float(entry["size"])
		mount.position = entry["at"]
		mount.rotation = float(entry.get("turn", 0.0))
		mount.thrust_direction = Vector2.UP
		mount.installed = _engine(String(entry["engine"]), float(entry.get("scale", 1.0)))
		ship.add_child(mount)

	for entry: Dictionary in preset["guns"]:
		var gun: Hardpoint = Hardpoint.new()
		gun.name = String(entry["name"])
		gun.position = entry["at"]
		gun.weapon = load(WEAPONS[entry["weapon"]]) as WeaponData
		ship.add_child(gun)

	ship.hull_outline = PackedVector2Array(preset["hull"])
	ship.hull_cargo_capacity = float(preset["cargo"])
	if ship.gear != null:
		var legs: Array[Vector2] = []
		for leg: Vector2 in preset["legs"]:
			legs.append(leg)
		ship.gear.legs = legs
	var drawn: Polygon2D = ship.get_node_or_null("Hull") as Polygon2D
	if drawn != null:
		drawn.polygon = ship.hull_outline

	ship.collect_parts()
	ship._build_contact_points()
	ship._build_collision_shape()
	ship.rebuild_control_groups(false)


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
