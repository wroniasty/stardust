class_name Soundscape
extends Node
## The only place anything in this game makes a sound through.
##
## VISUALS.md section 2 states the decision this whole class exists to
## implement: **vacuum is quiet.** In space you hear only what travels
## through the ship's own structure -- its engines, and things hitting it.
## Everything else is carried by air, and where there is no air there is
## nothing to carry it.
##
## That is not a mixing preference. It makes entering an atmosphere the
## moment the world starts to sound, so a pilot learns the air model by ear
## before ever reading it off the HUD -- and it means `air_density`, a
## number the simulation has computed every tick since M1, is doing a
## second job for free.
##
## Listens, never writes. Nothing in the simulation knows this exists.

## How a sound reaches the ear, which is the only question this class
## really asks about any of them.
enum Path {
	## Through the hull: engines, impacts, the gear coming down. Audible in
	## vacuum, because the ear is inside the same structure.
	CONDUCTED,
	## Through the air: everything out in the world. Silent in vacuum.
	AIRBORNE,
	## Through neither. The interface is not in the world and is not
	## subject to its weather; a menu that went quiet in space would be a
	## menu that had misunderstood the rule.
	INTERFACE,
}

const BUS_SFX: StringName = &"Sfx"
const BUS_AMBIENT: StringName = &"Ambient"
const BUS_UI: StringName = &"Ui"

## What the low-pass on Sfx is set to in vacuum and in thick air.
##
## Not silence at the bottom end: a conducted sound in vacuum is not
## absent, it is **dull** -- all the high frequencies are in the air that
## is not there, and what is left comes up through the frame. Three hundred
## hertz is a thud you feel rather than a sound you hear.
const MUFFLED_HZ: float = 320.0
const OPEN_HZ: float = 20000.0

## Quietest an airborne sound gets before it is simply not played. Below
## this the voice is spent on something nobody can hear.
const INAUDIBLE: float = 0.02

## How many one-shots can overlap. A pool, because a game that allocates a
## player per gunshot allocates a player per gunshot.
const VOICES: int = 16

## The one in the scene, for the fx nodes that need to make a noise and
## have no path to it.
##
## A static rather than a group lookup: there is exactly one of these and
## it is asked from code that runs per shot, so a scene-tree search would
## be a search per shot.
static var _current: Soundscape = null


## The soundscape, or null in a scene that has none -- which the tests and
## the standalone tools are, so every caller has to cope.
static func of() -> Soundscape:
	return _current


@export var ship_path: NodePath

var _ship: Ship = null
var _voices: Array[AudioStreamPlayer2D] = []
var _next: int = 0

## Air density as the mixer sees it, 0..1. Smoothed, because the ship can
## cross a few hundred metres of atmosphere in a tick and a cutoff that
## jumped with it would be heard as a click rather than as arriving.
var density: float = 0.0

## Seconds for the air to catch up. Short enough to feel like entry, long
## enough not to zip.
const AIR_RESPONSE: float = 0.25


func _ready() -> void:
	_current = self
	_ship = get_node_or_null(ship_path) as Ship
	for i: int in range(VOICES):
		var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		voice.bus = String(BUS_SFX)
		add_child(voice)
		_voices.append(voice)


func _exit_tree() -> void:
	if _current == self:
		_current = null


func _physics_process(delta: float) -> void:
	if _ship == null:
		return
	var wanted: float = clampf(_ship.air_density, 0.0, 1.0)
	density = lerpf(density, wanted, clampf(delta / AIR_RESPONSE, 0.0, 1.0))
	set_muffle(density)
	# The layer switch, applied at the mixer rather than at every call.
	# One place, and it catches anything that makes a noise without going
	# through `play()` -- which is the point of having a switch at all.
	var master: int = AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, not Presentation.is_on())


## Points the low-pass at an air density, 0..1.
##
## Public and ungated, like `ShipSkin.paint()` and `CameraShake.throw()`:
## the gate belongs to the tick, and a headless test has to be able to ask
## what the filter was set to.
func set_muffle(air: float) -> void:
	var bus: int = AudioServer.get_bus_index(String(BUS_SFX))
	if bus < 0 or AudioServer.get_bus_effect_count(bus) < 1:
		return
	var muffle: AudioEffectLowPassFilter = (
		AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	)
	if muffle == null:
		return
	# Exponential in the cutoff, because hearing is: halfway between 320 Hz
	# and 20 kHz by frequency is nowhere near halfway by ear.
	muffle.cutoff_hz = MUFFLED_HZ * pow(OPEN_HZ / MUFFLED_HZ, clampf(air, 0.0, 1.0))


## How loud something of this kind is, here, right now, 0..1.
##
## The rule, in one function. Conducted sound does not care about the air
## and interface sound does not live in the world; only what has to travel
## through air is sold by how much there is.
func carries(path: Path) -> float:
	match path:
		Path.AIRBORNE:
			return density
		_:
			return 1.0


## Plays a `SoundStrip` once: the sound decides its own path, volume
## and pitch, and the caller only says where and how hard.
##
## The reason this exists rather than four arguments at every call
## site: `path` is the field that is invisible when it is wrong. A gun
## marked airborne falls silent in vacuum and a crater marked
## conducted is heard across a dead system, and neither shows up in an
## atmosphere, which is where anybody testing by ear would be. As an
## argument it was three chances to mistype in three different files.
##
## `share` is the caller's own 0..1 reading of how hard the thing
## happened -- impact speed, crater size, muzzle velocity -- and the
## strip decides what that does to the pitch.
func play_strip(
	strip: SoundStrip,
	at: Vector2,
	share: float = 1.0,
	volume_scale: float = 1.0,
) -> bool:
	if strip == null or not strip.is_valid():
		return false
	return play(
		strip.stream,
		at,
		strip.path,
		strip.volume * volume_scale,
		strip.pitch_at(share),
	)


## Plays one sound once, at a place in the world.
##
## Returns whether a voice was spent on it, which is what
## `tools/soundcheck.tscn` reports and what the tests assert on: a rule
## that silences things has to be checkable, and "did you hear that" does
## not work headless.
##
## Deliberately **not** gated on `Presentation.is_on()`. The switch is
## applied once, at the master bus, in the tick above -- so it catches
## anything that makes a noise without coming through here, and so this
## function stays a pure statement of the air rule that a test can drive.
func play(
	stream: AudioStream,
	at: Vector2,
	path: Path = Path.CONDUCTED,
	volume: float = 1.0,
	pitch: float = 1.0,
) -> bool:
	if stream == null:
		return false
	var share: float = carries(path) * clampf(volume, 0.0, 4.0)
	if share < INAUDIBLE:
		return false

	var voice: AudioStreamPlayer2D = _voices[_next % maxi(_voices.size(), 1)]
	_next += 1
	voice.bus = String(BUS_UI if path == Path.INTERFACE else BUS_SFX)
	voice.stream = stream
	voice.global_position = at
	voice.volume_db = linear_to_db(share)
	voice.pitch_scale = clampf(pitch, 0.1, 4.0)
	voice.play()
	return true
