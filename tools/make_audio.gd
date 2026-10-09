extends SceneTree
## Builds the audio buses and a full set of placeholder samples.
##   godot --headless --path . --script res://tools/make_audio.gd
##
## Same reason the sprites are generated: the point is to have the right
## **set** of sounds, on the right buses, at the right lengths, so the
## plumbing can be built and tested before anybody records anything. Most
## of what is here is four lines of arithmetic and is meant to be replaced.
##
## The three engine loops are the part that already has been: they are
## cut out of two recordings in `assets/audio` rather than synthesised,
## and everything this tool does to them is aimed at changing as little
## as possible about how they sound.
##
## Once, not twice, unlike the sprites: an `AudioStreamWAV` carries its own
## samples, so a `.tres` needs no import pass behind it.

const BUSES: Array[StringName] = [&"Master", &"Sfx", &"Ambient", &"Ui"]

const LAYOUT: String = "res://resources/audio/bus_layout.tres"
const SOUNDS: String = "res://resources/audio"

## Where the tables live. Beside the look tables, in the presentation
## layer, for the reason the look tables are there: no module resource
## carries a sample any more than it carries a texture.
const TABLES: String = "res://resources/fx/sounds"

const RATE: int = 22050

## Where the recordings live, against `resources/audio` for what is
## built out of them. Two directories because they are two kinds of
## thing: one is an input nobody should edit in place, the other is
## output this tool will overwrite without asking.
const SOURCES: String = "res://assets/audio"

## The rate the recordings came in at. They leave at `RATE`.
##
## Resampling down costs nothing here, which had to be checked rather
## than assumed: both takes are steeply band limited and measure 70 dB
## down by 2 kHz and 97 dB by 4 kHz, so 22 kHz is still eleven times
## the room they need even with the torque jet pitched up to 1.4.
const SOURCE_RATE: int = 44100

## Taps in the filter that band limits a recording before it is
## resampled. An odd number, so there is a centre.
const TAPS: int = 33

## How much of the tail is folded back into the head to close a loop.
##
## These recordings join at **zero** -- they fade in over about 0.4 s
## and fade out again -- so the fault they carry is not the click the
## last pair had but a dip: measured second by second, the first and
## the last of the ten are 2 dB under the body. The loops are cut out
## of the steady middle for that reason, and a cut has two arbitrary
## ends, which is what this closes.
const CROSSFADE: float = 0.09

## The loudest a built loop may get, and how long the limiter takes to
## pull the gain down ahead of a peak and let it back afterwards.
const CEILING: float = 0.97
const LIMIT_ATTACK: float = 0.004
const LIMIT_RELEASE: float = 0.060

## What all three engine loops are levelled to.
##
## One figure for the three rather than three, because the difference
## between a drive and a thruster now lives in the strip volumes --
## which is the right place for it: a volume is a number the workbench
## can turn while the game runs, and a sample is not.
##
## 0.30 and not the 0.40 the old synthesised drive sat at, and that is
## the limiter's doing rather than a preference. At 0.40 these need
## between 3.6 and 4.5 dB taken off their peaks, and whatever is
## doing that holding starts to be heard; at 0.30 it is 1.1 to 2.0 dB
## and nothing is. The whole
## engine section is 2.4 dB quieter than it was, in exact proportion,
## and the section was already the one at risk of running out of
## headroom when eight nozzles are lit at once.
const LOOP_RMS: float = 0.30


## Recordings already folded to mono, so three loops out of two
## takes do that work twice rather than six times.
var _recordings: Dictionary = {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SOUNDS))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TABLES))
	_build_buses()
	_build_samples()
	quit(0)


## Four buses, and a low-pass on the one that carries the world.
##
## The filter is the whole reason the bus split exists rather than
## everything going to Master. `Soundscape` drives its cutoff from
## `air_density`, so thin air is literally muffled and vacuum is nearly
## silent -- and the interface, which is not in the world, is on its own
## bus where none of that reaches it.
func _build_buses() -> void:
	# Built by setting the live server up and then asking it for a layout,
	# rather than by writing the resource out by hand. The hand-written
	# version is a nest of indices, and the server already knows the shape.
	AudioServer.set_bus_count(BUSES.size())
	for i: int in range(BUSES.size()):
		AudioServer.set_bus_name(i, BUSES[i])
		if i > 0:
			AudioServer.set_bus_send(i, BUSES[0])
	# Cleared before it is added, because the live server this is built
	# from **already has the saved layout loaded**: the project points
	# at it in `project.godot`, so the second run of this tool put a
	# second low-pass on the Sfx bus, the third a third, and the file
	# grew every time. `Soundscape` only ever drives effect zero, so the
	# extras sat there wide open doing nothing -- harmless, invisible,
	# and permanent.
	var sfx: int = BUSES.find(&"Sfx")
	while AudioServer.get_bus_effect_count(sfx) > 0:
		AudioServer.remove_bus_effect(sfx, 0)
	var muffle: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
	muffle.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(sfx, muffle)

	var error: int = ResourceSaver.save(AudioServer.generate_bus_layout(), LAYOUT)
	if error != OK:
		push_error("could not write %s (%d)" % [LAYOUT, error])
		return
	print("audio: %d buses -> %s" % [BUSES.size(), LAYOUT])


## Four placeholders, one per shape of sound the game makes.
##
## A thump, a crack, a tick and a bed. Not four events -- four *shapes*, so
## that every event S1 onwards adds has something of the right character to
## borrow until it gets its own.
func _build_samples() -> void:
	_store(_thump(), "thump")
	_store(_crack(), "crack")
	_store(_tick(), "tick")
	_store(_bed(), "bed", true)
	_build_engines()
	_build_hull()
	_build_ordnance()
	_build_tables()


## One loop per kind of engine, and the two events that bracket them.
##
## Per kind rather than per engine, because what makes a main drive
## sound different from an attitude thruster is what it **is**, not
## which one it is: the pitch and the loudness come off the simulation
## every tick, so two drives of the same kind at different throttles
## already sound different without two samples.
##
## All three loop a whole number of cycles, or the loop point clicks --
## which on a sound that is running for minutes at a time is the only
## defect anybody would ever notice.
func _build_engines() -> void:
	_store(_drive_loop(), "engine_main", true)
	_store(_thruster_loop(), "engine_thruster", true)
	_store(_torque_loop(), "engine_torque", true)
	_store(_ignite(), "engine_ignite")
	_store(_cut(), "engine_cut")


## What the hull itself does: being hit, being put down on its feet,
## being refused, and coming apart.
##
## The impact is deliberately **not** one sample per severity. A tap and
## a crash are the same event at different speeds, and `hull_impact`
## carries the speed -- so the pitch and the loudness do the work, and
## the grind is layered on above a threshold rather than replacing
## anything. One more sample per severity would be three numbers nobody
## could keep in step.
func _build_hull() -> void:
	_store(_grind(), "hull_grind")
	_store(_creak(), "hull_creak")
	_store(_servo(), "gear_servo")
	_store(_clunk(), "gear_touch")
	_store(_deny(), "deny")
	_store(_balk(), "drive_balk")
	_store(_blast(), "explode")
	_store(_revive(), "respawn")


## Guns, and what they do to the ground.
##
## Three shots rather than one per weapon, for the same reason there is
## one engine loop per kind: what makes an autocannon sound unlike a
## beam is what it **is**, and the pitch carries the rest. A siege slug
## and a pulse repeater are the same mechanism at different sizes.
func _build_ordnance() -> void:
	_store(_gunshot(), "shot_gun")
	_store(_beamshot(), "shot_beam")
	_store(_launch(), "shot_launch")
	_store(_rock_hit(), "rock_hit")
	_store(_rock_settle(), "rock_settle")
	_store(_motor(), "missile_motor", true)
	_store(_dynamo(), "engine_dynamo", true)


## A gun: a hard transient and almost nothing after it.
func _gunshot() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1010
	var length: int = int(RATE * 0.11)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var crack: float = exp(-at * 55.0)
		var body: float = exp(-at * 16.0)
		out.append(
			rng.randf_range(-1.0, 1.0) * crack * 0.7
			+ sin(TAU * lerpf(220.0, 90.0, minf(at * 9.0, 1.0)) * at) * body * 0.45
		)
	return out


## A beam: no transient at all. The whole point of a hitscan weapon is
## that nothing leaves the barrel, so it should not sound like
## something did -- it hums and stops.
func _beamshot() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var length: int = int(RATE * 0.18)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var along: float = float(i) / float(length)
		var shape: float = minf(along * 10.0, 1.0) * (1.0 - along) * (1.0 - along)
		out.append(
			(sin(TAU * 740.0 * at) * 0.5 + sin(TAU * 1123.0 * at) * 0.25) * shape
		)
	return out


## A launcher: a soft thump and a motor catching.
func _launch() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1111
	var length: int = int(RATE * 0.3)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var along: float = float(i) / float(length)
		var pop: float = exp(-at * 30.0)
		# Swelling after the pop, which is the motor: a launcher is two
		# events close together and it reads wrong as one.
		var catch_: float = clampf((along - 0.15) * 2.2, 0.0, 1.0) * (1.0 - along)
		out.append(
			sin(TAU * 110.0 * at) * pop * 0.5 + rng.randf_range(-1.0, 1.0) * catch_ * 0.5
		)
	return out


## Something hitting rock, and the rock losing.
func _rock_hit() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1212
	var length: int = int(RATE * 0.26)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		out.append(
			(rng.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * 130.0 * at) * 0.4)
			* exp(-at * 18.0)
		)
	return out


## And the hole settling afterwards: loose stuff running back down the
## sides. Quiet, long, and the reason a crater reads as a hole rather
## than as a dent.
func _rock_settle() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1313
	var length: int = int(RATE * 0.7)
	var rolling: float = 0.0
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		rolling = lerpf(rolling, rng.randf_range(-1.0, 1.0), 0.25)
		# Grainy rather than smooth: a trickle of gravel is many small
		# events, so the envelope is chopped rather than a clean decay.
		var grain: float = 0.55 + 0.45 * sin(TAU * 23.0 * at + sin(TAU * 7.0 * at))
		out.append(rolling * grain * exp(-at * 3.4) * 0.5)
	return out


## A missile under power. Thin, because it is small and far away more
## often than not.
func _motor() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1414
	var length: int = RATE / 2
	var rolling: float = 0.0
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		rolling = lerpf(rolling, rng.randf_range(-1.0, 1.0), 0.45)
		out.append(rolling * 0.55 + sin(TAU * 260.0 * at) * 0.12)
	return out


## An engine with a generator strapped to it: the burn with a whine
## riding on top of it. A cross-stat affix should be a cross-stat
## noise, or the strangest thing a pilot can find is the one thing
## they cannot hear.
func _dynamo() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1515
	var length: int = RATE
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var burn: float = sin(TAU * 58.0 * at) * 0.34 + rng.randf_range(-1.0, 1.0) * 0.14
		# A whole number of cycles, or the loop clicks -- 480 and 721
		# both divide the second.
		var whine: float = (
			sin(TAU * 480.0 * at) * 0.16 + sin(TAU * 721.0 * at) * 0.08
		)
		out.append(burn + whine)
	return out


## Metal dragging on rock: noise with a slow flutter over it, so it
## reads as a surface being scraped rather than as a hiss.
func _grind() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 606
	var length: int = int(RATE * 0.42)
	var rolling: float = 0.0
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		rolling = lerpf(rolling, rng.randf_range(-1.0, 1.0), 0.5)
		var flutter: float = 0.6 + 0.4 * sin(TAU * 37.0 * at)
		out.append(rolling * flutter * exp(-at * 3.0) * 0.9)
	return out


## A hull settling: a low groan that goes nowhere.
func _creak() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var length: int = int(RATE * 0.55)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var along: float = float(i) / float(length)
		# Bowed in the middle: a creak starts, strains and lets go,
		# which a plain decay does not do.
		var swell: float = sin(PI * along)
		var hz: float = lerpf(88.0, 76.0, along)
		out.append((sin(TAU * hz * at) * 0.7 + sin(TAU * hz * 2.7 * at) * 0.2) * swell * 0.5)
	return out


## The gear coming down: a servo whine, flat and mechanical.
func _servo() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 707
	var length: int = int(RATE * 0.6)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var along: float = float(i) / float(length)
		# Eased at both ends, because a motor that starts and stops at
		# full volume reads as a click either side of a tone.
		var shape: float = minf(along * 8.0, minf(1.0, (1.0 - along) * 8.0))
		var hz: float = 330.0 + 18.0 * sin(TAU * 9.0 * at)
		out.append((sin(TAU * hz * at) * 0.5 + rng.randf_range(-1.0, 1.0) * 0.1) * shape)
	return out


## Feet on ground: a dull clunk with no ring to it.
func _clunk() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 808
	var length: int = int(RATE * 0.18)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var fade: float = exp(-at * 26.0)
		out.append((sin(TAU * 96.0 * at) * 0.7 + rng.randf_range(-1.0, 1.0) * 0.35) * fade)
	return out


## No. Two short falling blips, which is the shape of a refusal in every
## cockpit anyone has ever sat in.
## A hyperdrive that tries and does not go.
##
## Three beats, and the shape is the joke: a whine winding up, a cough
## where it should have fired, and the whine sagging away flat. A
## single descending tone would read as a power-down; what this has to
## read as is a thing that was about to work.
func _balk() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var length: int = int(RATE * 0.95)
	var wind: float = 0.42
	var cough: float = 0.52
	var phase: float = 0.0
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var hz: float = 0.0
		var level: float = 0.0
		if at < wind:
			# Winding up, and a little sharp of true at the top so it
			# sounds like it is straining rather than arriving.
			var up: float = at / wind
			hz = lerpf(210.0, 760.0, up * up)
			level = 0.25 + 0.45 * up
		elif at < cough:
			# The cough: broadband, short, and louder than either side.
			hz = 120.0
			level = 0.8 * (1.0 - (at - wind) / (cough - wind))
		else:
			# Sagging away, under the pitch it started at: whatever was
			# spinning has nothing left to spin against.
			var down: float = (at - cough) / maxf(0.95 - cough, 0.001)
			hz = lerpf(430.0, 90.0, sqrt(down))
			level = 0.5 * (1.0 - down) * (1.0 - down)
		phase += TAU * hz / float(RATE)
		var tone: float = sin(phase) * 0.7 + sin(phase * 2.01) * 0.2
		var grit: float = (randf() * 2.0 - 1.0) * (0.5 if at >= wind and at < cough else 0.08)
		out.append(clampf((tone + grit) * level, -1.0, 1.0))
	return out


func _deny() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var length: int = int(RATE * 0.2)
	var gap: int = int(RATE * 0.055)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var within: int = i if i < gap else i - gap
		var inside: float = float(within) / float(gap)
		var blip: float = 0.0
		if inside <= 1.0:
			blip = sin(TAU * (520.0 if i < gap else 390.0) * at) * (1.0 - inside)
		out.append(blip * 0.55)
	return out


## Coming apart: everything at once, then a long tail.
func _blast() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 909
	var length: int = RATE
	var rolling: float = 0.0
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		rolling = lerpf(rolling, rng.randf_range(-1.0, 1.0), 0.6)
		# Two decays: a crack that is gone in a tenth of a second over a
		# rumble that takes a second. One rate cannot be both.
		var snap: float = exp(-at * 22.0)
		var roll: float = exp(-at * 2.2)
		out.append(
			rolling * snap * 0.8 + sin(TAU * lerpf(70.0, 30.0, minf(at, 1.0)) * at) * roll * 0.6
		)
	return out


## Back in one piece: a tone climbing out of nothing and stopping.
func _revive() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var length: int = int(RATE * 0.5)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var along: float = float(i) / float(length)
		var hz: float = lerpf(180.0, 520.0, along * along)
		var shape: float = minf(along * 6.0, 1.0) * (1.0 - along * along * 0.8)
		out.append(sin(TAU * hz * at) * shape * 0.5)
	return out


## The main drive and the braking bell: `engine_level_3`.
##
## Low, and that is the whole of why it is on these two and not on the
## thrusters: a quarter of its energy in each of the 20-60, 60-120 and
## 120-250 Hz bands, centroid 121 Hz. A reverse engine is a main
## engine pointed the other way and is the same `MAIN` type, so it
## picks up the same loop without being named anywhere.
func _drive_loop() -> PackedFloat32Array:
	return _engine_loop("engine_level_3", 3.0, 2.2)


## The rotational jets: `engine_level_1`, from late in the take.
##
## The same recording as the strafe thrusters, deliberately: a torque
## jet and a manoeuvring thruster are the same machine pointed
## differently. What separates them is in the table -- the jet is the
## smallest engine in the game at 160 N against the thrusters' 180 to
## 500, so it is pitched up, and it follows the throttle in twelve
## milliseconds where they take forty-five.
##
## It is **not** brightened any more. The loop that was here was, and
## for a reason that held: a four second rumble turns to mud when the
## simulation chops it at twenty hertz. This recording is already a
## narrow band around 400 Hz with nothing under 120 and nothing over
## 1 kHz, and a high pass through it would take 88% of the sound away
## and hand back something that is no longer the take.
func _torque_loop() -> PackedFloat32Array:
	return _engine_loop("engine_level_1", 5.6, 2.2)


## The strafe thrusters: `engine_level_1`, from early in the take.
##
## A different window rather than the same one, so that two engines
## of different kinds firing together are two sounds and not one
## sound played twice.
func _thruster_loop() -> PackedFloat32Array:
	return _engine_loop("engine_level_1", 2.5, 2.2)


## A window of a recording, closed into a loop at the game's rate.
##
## The window comes out of the **middle** of the ten seconds. Both
## takes fade in and out, and a loop with a fade in it breathes once
## a cycle -- which is a worse fault than the click the last pair had,
## because a click can be mistaken for part of an engine and a swell
## cannot.
func _engine_loop(source: String, from: float, seconds: float) -> PackedFloat32Array:
	var cut: PackedFloat32Array = _slice(_source(source), from, seconds)
	return _levelled(_seamless(_resampled(cut), CROSSFADE), LOOP_RMS)


## One recording, as mono samples at `SOURCE_RATE`.
##
## Mono because these are positional: an engine is heard at its own
## nozzle, and `AudioStreamPlayer2D` has nothing useful to do with two
## channels. Both takes are wide, and that turns out to be the safe
## case rather than the dangerous one -- the two sides correlate at
## 0.09, which is to say not at all, so there is no delayed copy of
## anything to cancel against. Measured across 60 Hz to 1.2 kHz the
## fold costs 0.13 dB and combs nothing.
func _source(name: String) -> PackedFloat32Array:
	if _recordings.has(name):
		return _recordings[name]
	var out: PackedFloat32Array = PackedFloat32Array()
	var clip: AudioStreamWAV = load("%s/%s.wav" % [SOURCES, name]) as AudioStreamWAV
	if clip == null:
		push_error("no recording %s" % name)
		return out
	# Raw 16-bit or nothing. Godot's wav importer defaults to a
	# compressed format, and `data` is then the compressed bytes --
	# which decode as noise and come out the wrong length, quietly.
	# The `.import` beside each recording says `compress/mode=0`; this
	# is what notices when it stops saying it.
	if clip.format != AudioStreamWAV.FORMAT_16_BITS:
		push_error(
			"%s is imported as format %d, not 16-bit PCM: set compress/mode=0"
			% [name, clip.format]
		)
		return out
	var bytes: PackedByteArray = clip.data
	var channels: int = 2 if clip.stereo else 1
	var frames: int = bytes.size() / (2 * channels)
	out.resize(frames)
	for i: int in range(frames):
		var total: float = 0.0
		for channel: int in range(channels):
			total += float(bytes.decode_s16((i * channels + channel) * 2)) / 32768.0
		out[i] = total / float(channels)
	# Three loops come out of two takes, and folding ten seconds of
	# stereo down costs more than everything else in this file put
	# together.
	_recordings[name] = out
	return out


## A window of a recording, in seconds, at the rate it came in at.
func _slice(samples: PackedFloat32Array, from: float, seconds: float) -> PackedFloat32Array:
	var first: int = clampi(int(from * SOURCE_RATE), 0, maxi(samples.size() - 1, 0))
	var last: int = mini(first + int(seconds * SOURCE_RATE), samples.size())
	return samples.slice(first, last)


## `SOURCE_RATE` down to `RATE`, band limited on the way.
##
## The band limiting is the part that is easy to leave out and wrong
## to leave out: decimating straight away folds everything above the
## new Nyquist back down into the sound as a mirror image of itself,
## and the mirror does not sound like anything that was recorded.
## These two takes have nothing up there to fold -- 123 dB down by
## 8 kHz -- so skipping it would have worked by luck, and the next
## recording handed to this tool will not be so quiet.
func _resampled(samples: PackedFloat32Array) -> PackedFloat32Array:
	if samples.is_empty() or SOURCE_RATE == RATE:
		return samples
	var half: int = TAPS / 2
	# In cycles per **source** sample, a little under the new Nyquist
	# so the skirt has somewhere to fall.
	var cut: float = 0.45 * float(RATE) / float(SOURCE_RATE)
	var taps: PackedFloat32Array = PackedFloat32Array()
	taps.resize(TAPS)
	var total: float = 0.0
	for i: int in range(TAPS):
		var n: int = i - half
		var value: float = (
			2.0 * cut if n == 0 else sin(TAU * cut * float(n)) / (PI * float(n))
		)
		# Hann, because a bare sinc cut off after 33 taps rings.
		value *= 0.5 - 0.5 * cos(TAU * float(i) / float(TAPS - 1))
		taps[i] = value
		total += value
	for i: int in range(TAPS):
		taps[i] /= total

	var step: float = float(SOURCE_RATE) / float(RATE)
	var length: int = int(float(samples.size()) / step)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(length)
	for i: int in range(length):
		var at: float = float(i) * step
		var k: int = int(at)
		var along: float = at - float(k)
		# Filtered only where a sample is being taken, rather than
		# everywhere and then mostly thrown away: the same answer for
		# half the work at 2:1, and the interpolation below is skipped
		# entirely when the ratio is whole, which it is.
		var value: float = _tapped(samples, taps, k)
		if along > 0.0001:
			value = value * (1.0 - along) + _tapped(samples, taps, k + 1) * along
		out[i] = value
	return out


## One band-limited sample. Off the ends it reads zero, which puts a
## 0.7 ms fade on each end of a window -- shorter than the crossfade
## that is about to cover it.
func _tapped(samples: PackedFloat32Array, taps: PackedFloat32Array, at: int) -> float:
	var half: int = taps.size() / 2
	var total: float = 0.0
	for t: int in range(taps.size()):
		var k: int = at + t - half
		if k < 0 or k >= samples.size():
			continue
		total += samples[k] * taps[t]
	return total


## Folds the tail back into the head so the loop joins without a step.
##
## The result is shorter than what went in by exactly the crossfade,
## which is the point: the samples that used to be at the end are now
## mixed into the beginning, so the last sample runs into the first
## the way any two neighbours do.
func _seamless(samples: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var fade: int = mini(int(seconds * RATE), samples.size() / 3)
	if fade <= 0:
		return samples
	var length: int = samples.size() - fade
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(length)
	for i: int in range(length):
		if i >= fade:
			out[i] = samples[i]
			continue
		# Equal-power rather than linear: two uncorrelated noises
		# crossfaded by amplitude dip in the middle, and an engine
		# loop that got quieter once a second would be worse than the
		# step this is removing.
		var along: float = float(i) / float(fade)
		out[i] = (
			samples[i] * sqrt(along) + samples[length + i] * sqrt(1.0 - along)
		)
	return out


## Brings a loop to a target RMS without letting it over the ceiling.
##
## The ceiling is held by a limiter now and not by a waveshaper, and
## that swap is the one measured decision in this file. These takes
## have a 13 dB crest factor -- the shape of noise, not of the
## square-ish synthesis they replace -- so bending every sample
## through `tanh` to reach the same loudness laid distortion products
## 24 dB under the sound, in a band where the recording itself is
## 47 dB down. Audible grit, on a take handed over with "it has to
## sound like this". A limiter reaches the same figure 30 dB cleaner,
## because it moves the gain and leaves the waveform alone.
##
## Applied to the **original** each pass, never to the previous
## result: stacking compression compounds it, and the version of this
## that did undershot every target by more than a dB.
func _levelled(samples: PackedFloat32Array, target_rms: float) -> PackedFloat32Array:
	if samples.is_empty():
		return samples
	var out: PackedFloat32Array = samples
	var gain: float = target_rms / maxf(_rms_of(samples), 0.0001)
	for attempt: int in range(6):
		out = _limited(samples, gain)
		var landed: float = _rms_of(out)
		if absf(landed - target_rms) < target_rms * 0.005:
			break
		gain *= target_rms / maxf(landed, 0.0001)
	return out


## A peak limiter, in two passes over the buffer.
##
## Backwards first, so the gain is already down by the time a peak
## arrives instead of catching up after it. That is all lookahead is,
## and done offline it costs a traverse rather than a delay line.
## Forwards second, so the gain comes back over sixty milliseconds
## rather than snapping. Neither pass ever lets the gain exceed what
## the sample itself allows, so the ceiling is exact and not
## approached.
func _limited(samples: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	var length: int = samples.size()
	var held: PackedFloat32Array = PackedFloat32Array()
	held.resize(length)
	var attack: float = 1.0 / maxf(LIMIT_ATTACK * float(RATE), 1.0)
	var release: float = 1.0 / maxf(LIMIT_RELEASE * float(RATE), 1.0)
	var run: float = 1.0
	for i: int in range(length - 1, -1, -1):
		var want: float = minf(
			CEILING / maxf(absf(samples[i] * gain), 0.000001), 1.0
		)
		run = minf(want, run + attack)
		held[i] = run
	run = 1.0
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(length)
	for i: int in range(length):
		run = minf(held[i], run + release)
		out[i] = samples[i] * gain * run
	return out


## Root mean square of a buffer, which is what loudness follows far
## more closely than the peak does.
func _rms_of(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in samples:
		total += value * value
	return sqrt(total / float(samples.size()))


## Catching: noise swelling and a pitch climbing out of nothing.
func _ignite() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 404
	var length: int = int(RATE * 0.22)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var along: float = float(i) / float(length)
		# Swelling, not decaying, which is the whole difference between
		# this and everything else in the file: an ignition is the one
		# sound in the game that gets louder as it goes.
		var swell: float = along * along
		var hz: float = lerpf(60.0, 190.0, along)
		out.append((sin(TAU * hz * at) * 0.5 + rng.randf_range(-1.0, 1.0) * 0.5) * swell)
	return out


## And going out: the opposite, short.
func _cut() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 505
	var length: int = int(RATE * 0.16)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var along: float = float(i) / float(length)
		var fade: float = (1.0 - along) * (1.0 - along)
		var hz: float = lerpf(170.0, 55.0, along)
		out.append((sin(TAU * hz * at) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.3) * fade)
	return out


## Something heavy arriving: a low tone that drops as it dies.
func _thump() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var length: int = int(RATE * 0.26)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var fade: float = exp(-at * 14.0)
		# The pitch falls as well as the volume, which is most of what
		# makes a hit sound like mass rather than like a beep.
		var hz: float = lerpf(120.0, 48.0, clampf(at / 0.26, 0.0, 1.0))
		out.append(sin(TAU * hz * at) * fade * 0.9)
	return out


## Something breaking: noise with a fast edge and no tone at all.
func _crack() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var length: int = int(RATE * 0.12)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		out.append(rng.randf_range(-1.0, 1.0) * exp(-at * 40.0) * 0.8)
	return out


## The interface: short, bright, and nothing like the world.
func _tick() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var length: int = int(RATE * 0.045)
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		out.append(sin(TAU * 1760.0 * at) * exp(-at * 90.0) * 0.5)
	return out


## A bed to loop under an engine: two tones a hair apart, so they beat
## against each other and the loop does not read as a loop.
func _bed() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	# A whole number of cycles of both tones, or the loop point clicks.
	var length: int = RATE
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var tone: float = sin(TAU * 70.0 * at) * 0.45 + sin(TAU * 105.0 * at) * 0.25
		out.append(tone + rng.randf_range(-1.0, 1.0) * 0.12)
	return out


## The tables: which sound a thing gets, worked out from what it is.
##
## `SoundTable` is `LookTable` for the ear and these are its contents.
## Written here rather than by hand for the same reason the look
## tables are generated: a table of twenty entries maintained in the
## inspector is twenty chances to point at the wrong file.
##
## **Every path is decided here, once.** Conducted for things bolted
## to the hull you sit in, airborne for things happening out there,
## interface for things that are not in the world at all. That is the
## one field nobody can check by ear, because getting it backwards is
## invisible in an atmosphere.
func _build_tables() -> void:
	_store_table(_engine_table(), "engine_loop")
	_store_table(_engine_event_table(), "engine_event")
	_store_table(_hull_table(), "hull")
	_store_table(_weapon_table(), "weapon_shot")
	_store_table(_terrain_table(), "terrain")
	_store_table(_missile_table(), "missile")


## One loop per kind of engine, and one affix that changes the machine.
##
## The variants are indexed by `EngineData.Type`, which is why the
## thresholds are 0, 1, 2: "pick by a number on the item" covers an
## enum as well as a measurement.
##
## Only `dynamo` is in `by_affix`, and that is a deliberate limit
## rather than a thin table. An affix entry **replaces the whole
## strip**, response included, so it suits an affix that changes what
## the machine is and not one that scales it: an engine with a
## generator strapped to it really is a different noise, while an
## `overbored` torque jet is still an impulse engine and would lose
## its chuff to whatever response the affix brought.
func _engine_table() -> SoundTable:
	var table: SoundTable = SoundTable.new()
	table.stat = &"type"
	table.thresholds = PackedFloat32Array([0.0, 1.0, 2.0])
	# All three loops leave the generator at the same loudness, so
	# these volumes are the whole of the balance between a drive and a
	# jet -- where it is worth having, because a volume is a number the
	# workbench can turn while the game is running. The figures are not
	# chosen: they are what keeps the three in exactly the proportion
	# they were tuned to when the loops were synthesised and each
	# carried its own level.
	table.variants = [
		# MAIN: climbs a long way, because spooling is most of its
		# character, and follows slowly because it is heavy.
		_strip("engine_main", 1.00, Vector2(0.70, 1.20), 0.100, true),
		# TORQUE: barely moves in pitch and follows almost instantly.
		# Twelve milliseconds is the whole difference between a jet and
		# a hum -- the simulation is already switching it on and off
		# tick by tick, and this decides whether that gets through.
		#
		# Pitched a third up, and that is what makes it a different
		# machine from the one below it: the two share a recording, and
		# a torque jet is the smallest engine in the game.
		_strip("engine_torque", 0.38, Vector2(1.22, 1.40), 0.012, true),
		_strip("engine_thruster", 0.26, Vector2(0.95, 1.28), 0.045, true),
	]
	table.by_affix = {
		# Down with the rest of the section, so a dynamo-fitted engine is
		# no louder against its neighbours than it was.
		&"dynamo": _strip("engine_dynamo", 0.47, Vector2(0.80, 1.30), 0.060, true),
	}
	table.fallback = table.variants[2]
	return table


## The two events bracketing a burn. Conducted: you are inside the
## structure they happen to.
func _engine_event_table() -> SoundTable:
	var table: SoundTable = SoundTable.new()
	table.by_key = {
		&"ignite": _strip("engine_ignite", 0.70, Vector2.ONE),
		&"cut": _strip("engine_cut", 0.70, Vector2.ONE),
	}
	return table


## What the hull does. Two of these are **interface** sounds and the
## rest are conducted, which is the distinction this table exists to
## hold: a landing refusal and a revival happen in the cockpit, not in
## the world, so they are heard in vacuum.
func _hull_table() -> SoundTable:
	var table: SoundTable = SoundTable.new()
	table.by_key = {
		# Falling pitch, deliberately: an impact drops as it gets
		# harder, and that is most of what makes a hit read as mass
		# rather than as volume.
		&"knock": _strip("thump", 1.0, Vector2(1.45, 0.72)),
		&"grind": _strip("hull_grind", 1.0, Vector2(0.90, 1.10)),
		&"creak": _strip("hull_creak", 0.35, Vector2(0.85, 1.20)),
		&"servo": _strip("gear_servo", 0.50, Vector2.ONE),
		&"touch": _strip("gear_touch", 0.80, Vector2(0.92, 1.08)),
		&"blast": _strip("explode", 1.00, Vector2.ONE),
		&"deny": _strip(
			"deny", 0.60, Vector2.ONE, 0.1, false, Soundscape.Path.INTERFACE
		),
		&"revive": _strip(
			"respawn", 0.70, Vector2.ONE, 0.1, false, Soundscape.Path.INTERFACE
		),
	}
	return table


## One shot per weapon type, six types sharing three samples: what
## makes a gun sound unlike a beam is the mechanism, and the pitch
## carries the rest. Conducted, every one: the gun is bolted to the
## hull you are sitting in, so it fires on an airless moon.
func _weapon_table() -> SoundTable:
	var table: SoundTable = SoundTable.new()
	table.stat = &"type"
	table.thresholds = PackedFloat32Array([0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
	var gun: SoundStrip = _strip("shot_gun", 0.70, Vector2(0.72, 1.35))
	var launch: SoundStrip = _strip("shot_launch", 0.70, Vector2(0.85, 1.10))
	table.variants = [
		gun,
		# A beam has no transient, because nothing leaves the barrel.
		_strip("shot_beam", 0.70, Vector2(0.92, 1.12)),
		launch,
		launch,
		launch,
		_strip("shot_gun", 0.60, Vector2(1.10, 1.60)),
	]
	table.fallback = gun
	return table


## What a shot does to the ground. **Airborne, both of them**, and
## that is the whole point of the pair: the hit happens out there
## against somebody else's rock, so on an airless moon the crater
## appears in silence while the gun that made it was heard.
func _terrain_table() -> SoundTable:
	var table: SoundTable = SoundTable.new()
	table.by_key = {
		&"hit": _strip(
			"rock_hit", 1.0, Vector2(1.25, 0.80), 0.1, false,
			Soundscape.Path.AIRBORNE
		),
		&"settle": _strip(
			"rock_settle", 0.45, Vector2(0.85, 1.15), 0.1, false,
			Soundscape.Path.AIRBORNE
		),
	}
	return table


## A missile under power. Airborne, because it is out there.
func _missile_table() -> SoundTable:
	var table: SoundTable = SoundTable.new()
	table.fallback = _strip(
		"missile_motor", 0.55, Vector2(0.92, 1.10), 0.1, true,
		Soundscape.Path.AIRBORNE
	)
	return table


func _strip(
	sample: String,
	volume: float,
	pitch: Vector2,
	response: float = 0.1,
	loops: bool = false,
	path: Soundscape.Path = Soundscape.Path.CONDUCTED,
) -> SoundStrip:
	var strip: SoundStrip = SoundStrip.new()
	strip.stream = load("%s/%s.tres" % [SOUNDS, sample]) as AudioStream
	if strip.stream == null:
		push_error("no sample %s" % sample)
	strip.path = path
	strip.volume = volume
	strip.pitch = pitch
	strip.response = response
	strip.loops = loops
	return strip


func _store_table(table: SoundTable, name: String) -> void:
	var path: String = "%s/%s.tres" % [TABLES, name]
	var error: int = ResourceSaver.save(table, path)
	if error != OK:
		push_error("could not write %s (%d)" % [path, error])
		return
	print("table: %-14s %d entries -> %s" % [
		name, table.every_strip().size(), path,
	])


## Writes one sample out as a 16 bit mono AudioStreamWAV.
func _store(samples: PackedFloat32Array, name: String, loops: bool = false) -> void:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))

	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loops:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()

	var path: String = "%s/%s.tres" % [SOUNDS, name]
	var error: int = ResourceSaver.save(wav, path)
	if error != OK:
		push_error("could not write %s (%d)" % [path, error])
		return
	var peak: float = 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	print("audio: %-16s %5.2f s  peak %.2f rms %.3f -> %s" % [
		name, float(samples.size()) / float(RATE), peak, _rms_of(samples), path,
	])
