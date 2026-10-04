class_name EngineChoir
extends Node2D
## Engines are heard: one loop per type, loudness and pitch off what they are doing.
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
## **Which loop, how loud, at what pitch and how fast it follows all
## come out of a `SoundTable`**, not out of this file. That was the
## second attempt: the first held them in four parallel arrays indexed
## by the type enum, which is the under-built half of what the art
## layer already does. A picture goes through `LookTable` and can be
## changed by an affix; a noise went through an array and could not,
## so an `overbored` drive looked different and sounded identical.
##
## One strip per **kind**, not per engine. What makes a main drive
## sound unlike an attitude thruster is what it is, and two drives of
## the same kind at different throttles already differ without a
## second recording -- the difference is coming off the numbers.

## Relative loudness at full flow, indexed by `EngineData.Type`:
## MAIN, TORQUE, THRUSTER.
##
## An array rather than a dictionary keyed by the enum, because a
## `const Dictionary` in GDScript has to be constant-foldable and this
## project has already been bitten once by discovering which things are
## not.
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

const LOOPS: String = "res://resources/fx/sounds/engine_loop.tres"
const EVENTS: String = "res://resources/fx/sounds/engine_event.tres"

@export var ship_path: NodePath

var _ship: Ship = null

## Mount name -> the voice holding its loop, and how loud it is now.
var _voices: Dictionary = {}
var _level: Dictionary = {}
var _phase: Dictionary = {}

## Which strip each mount is running, so the tick does not have to ask
## the table sixty times a second for an answer that only changes on a
## refit.
var _strips: Dictionary = {}

var _loops: SoundTable = null
var _events: SoundTable = null


func _ready() -> void:
	_loops = load(LOOPS) as SoundTable
	_events = load(EVENTS) as SoundTable

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
		# Asked afresh every rebuild, never cached across one: a refit
		# can put a different engine in the same mount, and an affix
		# is part of what chooses the loop.
		var strip: SoundStrip = (
			_loops.pick(engine.data) if _loops != null else null
		)
		_strips[key] = strip
		if _voices.has(key):
			(_voices[key] as AudioStreamPlayer2D).stream = (
				strip.stream if strip != null else null
			)
			continue
		var voice: Loop = Loop.new()
		voice.bus = String(Soundscape.BUS_SFX)
		voice.stream = strip.stream if strip != null else null
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
		_strips.erase(key)


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
	_strips.clear()
	_loops = null
	_events = null


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
		var strip: SoundStrip = _strips.get(key, null)
		if strip == null or not strip.is_valid():
			continue

		# Boost can push the flow past one, and it should be heard: the
		# nozzle really is throwing three times as much.
		var flow: float = maxf(engine.exhaust_flow(), 0.0)
		var want: float = minf(flow, 2.0) * strip.volume
		var ease: float = clampf(delta / maxf(strip.response, 0.001), 0.0, 1.0)
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
		voice.pitch_scale = clampf(strip.pitch_at(flow) * wobble, 0.1, 4.0)


## How loud one engine's loop is right now, 0 upwards. For the tests and
## for `tools/soundcheck.tscn`.
func level_of(mount: StringName) -> float:
	return float(_level.get(mount, 0.0))


func voice_count() -> int:
	return _voices.size()


func _on_ignited(engine: EngineInstance) -> void:
	_bracket(engine, &"ignite")


func _on_cut(engine: EngineInstance) -> void:
	_bracket(engine, &"cut")


## The one-shots at either end of a burn.
##
## Through `Soundscape`, not through the engine's own voice: a loop is
## a thing that is true for a while and an ignition is a thing that
## happens, and playing the second on the first would mean stopping the
## loop to do it.
func _bracket(engine: EngineInstance, which: StringName) -> void:
	var mixer: Soundscape = Soundscape.of()
	if mixer == null or _events == null:
		return
	# Scaled by the loop's own loudness, so a thruster catching is as
	# much quieter than a main drive catching as the two are while
	# running. One number, in one place.
	var running: SoundStrip = _strips.get(engine.mount.name, null)
	mixer.play_strip(
		_events.pick(null, which),
		engine.mount.global_position,
		1.0,
		running.volume if running != null else 1.0,
	)
