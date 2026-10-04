class_name OrdnanceVoice
extends Node2D
## Broń i teren: wystrzał, lot, trafienie w skałę kontra w próżnię.
##
## The clearest demonstration of the vacuum rule in the game, and the
## reason this is one node rather than two. A shot and its impact are
## the same event seen from two places:
##
## - the **shot** is conducted. The gun is bolted to the hull you are
##   sitting in, so you hear it fire on an airless moon.
## - the **hit** is airborne. It happens out there, against somebody
##   else's rock, so on that same airless moon you watch the crater
##   appear in silence.
##
## Nothing had to be built for that. `Soundscape` already sells an
## airborne sound by the air there is; the only decision here is which
## path each of the two takes, and getting it the other way round would
## make a dead moon sound like a quarry.

## Which sound a weapon makes, keyed on its `type`: three samples for
## six kinds, because what makes a gun sound unlike a beam is the
## mechanism and a siege slug is a pulse repeater at a different size.
## The table decides, not this file -- the same arrangement the nozzle
## pictures have lived under since V0.
const SHOTS: String = "res://resources/fx/sounds/weapon_shot.tres"
const TERRAIN: String = "res://resources/fx/sounds/terrain.tres"
const MOTORS_TABLE: String = "res://resources/fx/sounds/missile.tres"

## Muzzle speed that fires a shot at the top of its pitch range.
## Faster rounds read higher, slower ones lower, which is the cheapest
## way to make a siege slug and an autocannon tell themselves apart.
const REFERENCE_SPEED: float = 900.0

## Crater radius at which a hit is as loud as it gets.
const REFERENCE_CRATER: float = 40.0

## How long after the hit the hole settles, in seconds, and how loud.
## Late enough to be a second event rather than a tail on the first.
const SETTLE_DELAY: Vector2 = Vector2(0.18, 0.45)
const SETTLE_VOLUME: float = 0.45

## Most missiles given a motor at once. A pool, because a launcher
## with a mod on it can put six in the air inside a second.
const MOTORS: int = 6

@export var ship_path: NodePath

var _ship: Ship = null
var _shots: SoundTable = null
var _terrain: SoundTable = null
var _motor: SoundStrip = null

## Missile -> the voice following it.
var _flying: Dictionary = {}
var _spare: Array[AudioStreamPlayer2D] = []

## Hits waiting to settle: { "at": Vector2, "in": float, "share": float }.
var _settling: Array[Dictionary] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## A voice that lets go of its loop on the way out, for the same reason
## `EngineChoir` has one: a looping stream still referenced at exit is
## something `check.ps1` cannot tell apart from a leak that matters.
class Motor extends AudioStreamPlayer2D:
	func _exit_tree() -> void:
		stop()
		stream = null


func _ready() -> void:
	_rng.randomize()
	_shots = load(SHOTS) as SoundTable
	_terrain = load(TERRAIN) as SoundTable
	var motors: SoundTable = load(MOTORS_TABLE) as SoundTable
	_motor = motors.pick() if motors != null else null

	for i: int in range(MOTORS):
		var voice: Motor = Motor.new()
		voice.bus = String(Soundscape.BUS_SFX)
		voice.stream = _motor.stream if _motor != null else null
		add_child(voice)
		_spare.append(voice)

	_ship = get_node_or_null(ship_path) as Ship
	if _ship != null:
		# Hardpoints are scene children that outlive a refit -- only the
		# weapon in them changes -- so this is connected once and never
		# rebuilt, unlike the engine voices.
		for gun: Hardpoint in _ship.hardpoints:
			gun.fired.connect(_on_fired)

	var manager: Node = get_node_or_null("/root/StreamingManager")
	if manager != null and manager.has_signal("body_awake"):
		manager.body_awake.connect(_on_body_awake)
	for planet: Node in get_tree().get_nodes_in_group(GravityWell.GROUP):
		_watch(planet)


func _on_body_awake(_body: SystemBody, node: Node2D) -> void:
	_watch(node)


func _watch(node: Node) -> void:
	var planet: Planet = node as Planet
	if planet != null and not planet.carved.is_connected(_on_carved):
		planet.carved.connect(_on_carved)


func _physics_process(delta: float) -> void:
	advance(delta)


## One tick: the motors that are flying, and the holes still settling.
##
## Ungated and public like the rest of the layer. The switch is thrown
## once at the master bus.
func advance(delta: float) -> void:
	_follow_missiles()
	var still: Array[Dictionary] = []
	for hole: Dictionary in _settling:
		hole["in"] = float(hole["in"]) - delta
		if float(hole["in"]) > 0.0:
			still.append(hole)
			continue
		var mixer: Soundscape = Soundscape.of()
		if mixer != null and _terrain != null:
			mixer.play_strip(
				_terrain.pick(null, &"settle"),
				hole["at"],
				_rng.randf(),
				SETTLE_VOLUME * float(hole["share"]),
			)
	_settling = still


## Gives every missile in the air a motor, and takes the motor back
## when it stops being in the air.
##
## Walked rather than hooked, because a missile is born and dies in the
## middle of a frame and has no signals of its own -- and because
## adding some to it would be the presentation layer reaching into the
## thing it is supposed to be watching.
func _follow_missiles() -> void:
	var container: Node = get_tree().get_first_node_in_group(Ship.PROJECTILE_GROUP)
	var seen: Dictionary = {}
	if container != null:
		for round_node: Node in container.get_children():
			var missile: Missile = round_node as Missile
			if missile == null:
				continue
			seen[missile] = true
			if _flying.has(missile):
				(_flying[missile] as Node2D).global_position = missile.global_position
				continue
			if _spare.is_empty():
				continue
			var voice: AudioStreamPlayer2D = _spare.pop_back()
			voice.global_position = missile.global_position
			voice.volume_db = linear_to_db(
				_carried(_motor.volume if _motor != null else 0.55)
			)
			voice.pitch_scale = _rng.randf_range(0.92, 1.1)
			voice.play()
			_flying[missile] = voice
	for missile: Variant in _flying.keys():
		if seen.has(missile) and is_instance_valid(missile):
			continue
		var done: AudioStreamPlayer2D = _flying[missile]
		done.stop()
		_spare.append(done)
		_flying.erase(missile)


## How loud a running sound is from here. A loop cannot go through
## `play_strip()` -- that spends a voice on a one-shot -- so it asks
## the rule itself, by the path its own strip names.
func _carried(volume: float) -> float:
	var mixer: Soundscape = Soundscape.of()
	var path: Soundscape.Path = (
		_motor.path if _motor != null else Soundscape.Path.AIRBORNE
	)
	var share: float = mixer.carries(path) if mixer != null else 1.0
	return maxf(volume * share, 0.0001)


## The gun going off: conducted, because it is bolted to the hull you
## are sitting in. Audible on an airless moon, which is the point.
func _on_fired(at: Vector2, _direction: Vector2, weapon: WeaponData) -> void:
	var mixer: Soundscape = Soundscape.of()
	if mixer == null or weapon == null or _shots == null:
		return
	# The weapon itself is handed to the table, so an affix could
	# change what a gun sounds like the way one already changes what a
	# nozzle looks like. Nothing claims that today; the seam is here.
	mixer.play_strip(
		_shots.pick(weapon),
		at,
		clampf(weapon.muzzle_speed / REFERENCE_SPEED, 0.0, 1.0),
	)


## And the hit: airborne, because it happens out there against somebody
## else's rock. On that same airless moon the crater appears in silence,
## and that is the rule working rather than a bug.
func _on_carved(point: Vector2, radius: float) -> void:
	var mixer: Soundscape = Soundscape.of()
	if mixer == null or _terrain == null:
		return
	var share: float = clampf(radius / REFERENCE_CRATER, 0.15, 1.0)
	mixer.play_strip(_terrain.pick(null, &"hit"), point, share, share)
	# The hole settling is a second event, late enough not to be heard
	# as a tail on the first. A crater that stopped making noise the
	# instant it appeared would read as a dent.
	_settling.append({
		"at": point,
		"in": _rng.randf_range(SETTLE_DELAY.x, SETTLE_DELAY.y),
		"share": share,
	})


## How many missiles have a motor right now. For the tests.
func motors_running() -> int:
	return _flying.size()


## How many holes are still waiting to settle.
func settling() -> int:
	return _settling.size()
