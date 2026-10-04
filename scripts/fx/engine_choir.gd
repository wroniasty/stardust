class_name EngineChoir
extends Node2D
## Silniki słychać: pętla na typ, głośność i wysokość z tego, co robią.
##
## One looping voice per fitted engine, placed at its nozzle, with the
## loudness and the pitch read off the simulation every tick. Nothing
## here is scripted: a drive spooling up is a drive spooling up because
## `exhaust_flow()` says so, and a drive that cuts out goes quiet
## because the flow did.
##
## **Conducted, always.** Engines are the clearest case of the vacuum
## rule (IDEAS.md section 14): you hear them through the structure you
## are sitting in, so they do not fade with the air. Everything else
## the ship does is argued about; this one is not.
##
## One sample per **kind**, not per engine. What makes a main drive
## sound unlike an attitude thruster is what it is, and two drives of
## the same kind at different throttles already differ without a second
## recording -- the difference is coming off the numbers.

## Relative loudness at full flow, indexed by `EngineData.Type`:
## MAIN, TORQUE, THRUSTER.
##
## An array rather than a dictionary keyed by the enum, because a
## `const Dictionary` in GDScript has to be constant-foldable and this
## project has already been bitten once by discovering which things are
## not.
const LOUDNESS: Array[float] = [1.00, 0.42, 0.50]

## Pitch at a trickle and at full, per kind. A main drive climbs a long
## way because spooling is most of its character; a torque jet barely
## moves, because it has only two states and the pitch is not where its
## character lives.
const PITCH_LOW: Array[float] = [0.70, 0.92, 0.95]
const PITCH_HIGH: Array[float] = [1.20, 1.08, 1.28]

## Seconds for the loudness to follow the flow, per kind.
##
## The torque figure is the interesting one and it is deliberately
## almost nothing. The simulation switches an impulse engine fully on
## and fully off, tick by tick, at a rate that is the throttle it was
## asked for -- so **the modulation is already in the code**, and a
## response fast enough to let it through is what makes a torque jet
## sound like a torque jet. Smooth it like a main drive and it turns
## into a hum.
const RESPONSE: Array[float] = [0.10, 0.012, 0.045]

## Below this a voice is paused rather than played silently. Sixteen
## engines mixing nothing is sixteen streams being decoded for nothing.
const QUIETEST: float = 0.015

## How far a wrecked engine's pitch wanders, and how fast.
##
## The **gaps** are not here: a failing engine already drops out in the
## simulation, which takes the flow down, which takes the loudness with
## it. Only the wandering had to be added, because nothing in the model
## wobbles.
const WOBBLE_DEPTH: float = 0.14
const WOBBLE_HZ: float = 11.0

## How loud the one-shots at either end are.
const EVENT_VOLUME: float = 0.7

const LOOPS: Array[String] = [
	"res://resources/audio/engine_main.tres",
	"res://resources/audio/engine_torque.tres",
	"res://resources/audio/engine_thruster.tres",
]

@export var ship_path: NodePath

var _ship: Ship = null

## Mount name -> the voice holding its loop, and how loud it is now.
var _voices: Dictionary = {}
var _level: Dictionary = {}
var _phase: Dictionary = {}

var _streams: Array[AudioStream] = []
var _ignite: AudioStream = null
var _snuff: AudioStream = null


func _ready() -> void:
	for path: String in LOOPS:
		_streams.append(load(path) as AudioStream)
	_ignite = load("res://resources/audio/engine_ignite.tres") as AudioStream
	_snuff = load("res://resources/audio/engine_cut.tres") as AudioStream

	_ship = get_node_or_null(ship_path) as Ship
	if _ship == null:
		return
	_ship.engine_ignited.connect(_on_ignited)
	_ship.engine_cut.connect(_on_cut)
	# Rebuilt on a refit, because an `EngineInstance` is a pairing the
	# ship throws away and remakes: a voice held against the old one is
	# a loop playing for an engine that is not there.
	_ship.configuration_changed.connect(rebuild)
	rebuild()


## Gives every fitted engine a voice, and takes back the ones nobody is
## using any more.
func rebuild() -> void:
	if _ship == null:
		return
	var wanted: Dictionary = {}
	for engine: EngineInstance in _ship.engines:
		var key: StringName = engine.mount.name
		wanted[key] = true
		if _voices.has(key):
			continue
		var voice: Loop = Loop.new()
		voice.bus = String(Soundscape.BUS_SFX)
		voice.stream = _streams[clampi(int(engine.data.type), 0, _streams.size() - 1)]
		voice.volume_db = linear_to_db(QUIETEST)
		voice.autoplay = false
		add_child(voice)
		_voices[key] = voice
		_level[key] = 0.0
		_phase[key] = 0.0
	for key: Variant in _voices.keys():
		if wanted.has(key):
			continue
		(_voices[key] as Node).queue_free()
		_voices.erase(key)
		_level.erase(key)
		_phase.erase(key)


## A voice that lets go of its loop on the way out.
##
## The release has to be here, on the player, rather than on the choir
## that owns it. A looping stream still referenced at exit is a
## resource Godot complains about and `check.ps1` greps for -- the
## soundcheck tool learned that first -- and clearing them from the
## parent does not work, because children are freed before their
## parent's `_exit_tree` ever runs. Eight engines, three loops, three
## complaints, and not a leak that costs anything at runtime: what it
## costs is the check's ability to tell this apart from one that does.
class Loop extends AudioStreamPlayer2D:
	func _exit_tree() -> void:
		stop()
		stream = null


func _exit_tree() -> void:
	_streams.clear()
	_ignite = null
	_snuff = null


func _physics_process(delta: float) -> void:
	sing(delta)


## One tick of every loop. Ungated and public, like everything else in
## this layer: the switch is thrown once at the master bus in
## `Soundscape`, and a mix that could only be read with a window open is
## a mix with no tests.
func sing(delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	for engine: EngineInstance in _ship.engines:
		var key: StringName = engine.mount.name
		if not _voices.has(key):
			continue
		var voice: AudioStreamPlayer2D = _voices[key]
		var kind: int = clampi(int(engine.data.type), 0, LOUDNESS.size() - 1)

		# Boost can push the flow past one, and it should be heard: the
		# nozzle really is throwing three times as much.
		var flow: float = maxf(engine.exhaust_flow(), 0.0)
		var want: float = minf(flow, 2.0) * LOUDNESS[kind]
		var ease: float = clampf(delta / maxf(RESPONSE[kind], 0.001), 0.0, 1.0)
		var now: float = lerpf(float(_level[key]), want, ease)
		_level[key] = now

		var hurt: float = 1.0 - clampf(engine.health, 0.0, 1.0)
		var turning: float = float(_phase[key]) + TAU * WOBBLE_HZ * delta
		_phase[key] = fmod(turning, TAU)
		var wobble: float = 1.0 + sin(turning) * WOBBLE_DEPTH * hurt

		voice.global_position = engine.mount.global_position
		# Stopped rather than paused when there is nothing to hear.
		#
		# A paused player is still a playback registered with the audio
		# server, and eight of those outlive the shutdown long enough
		# for Godot to report their streams as still in use -- which
		# `check.ps1` cannot tell apart from a leak that matters. A
		# stopped one holds nothing. Restarting the loop from its
		# beginning is no loss either: a drive catching should sound
		# like a drive catching.
		if now < QUIETEST:
			if voice.playing:
				voice.stop()
			continue
		if not voice.playing:
			voice.play()
		voice.volume_db = linear_to_db(clampf(now, QUIETEST, 2.0))
		voice.pitch_scale = clampf(
			lerpf(PITCH_LOW[kind], PITCH_HIGH[kind], minf(flow, 1.0)) * wobble, 0.1, 4.0
		)


## How loud one engine's loop is right now, 0 upwards. For the tests and
## for `tools/soundcheck.tscn`.
func level_of(mount: StringName) -> float:
	return float(_level.get(mount, 0.0))


func voice_count() -> int:
	return _voices.size()


func _on_ignited(engine: EngineInstance) -> void:
	_bracket(engine, _ignite)


func _on_cut(engine: EngineInstance) -> void:
	_bracket(engine, _snuff)


## The one-shots at either end of a burn.
##
## Through `Soundscape`, not through the engine's own voice: a loop is
## a thing that is true for a while and an ignition is a thing that
## happens, and playing the second on the first would mean stopping the
## loop to do it.
func _bracket(engine: EngineInstance, sample: AudioStream) -> void:
	var mixer: Soundscape = Soundscape.of()
	if mixer == null or sample == null:
		return
	var kind: int = clampi(int(engine.data.type), 0, LOUDNESS.size() - 1)
	mixer.play(
		sample,
		engine.mount.global_position,
		Soundscape.Path.CONDUCTED,
		EVENT_VOLUME * LOUDNESS[kind],
	)
