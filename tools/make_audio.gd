extends SceneTree
## Buduje magistrale dźwiękowe i komplet placeholderowych próbek.
##   godot --headless --path . --script res://tools/make_audio.gd
##
## Same reason the sprites are generated: the point is to have the right
## **set** of sounds, on the right buses, at the right lengths, so the
## plumbing can be built and tested before anybody records anything. Every
## sample here is four lines of arithmetic and is meant to be replaced.
##
## Once, not twice, unlike the sprites: an `AudioStreamWAV` carries its own
## samples, so a `.tres` needs no import pass behind it.

const BUSES: Array[StringName] = [&"Master", &"Sfx", &"Ambient", &"Ui"]

const LAYOUT: String = "res://resources/audio/bus_layout.tres"
const SOUNDS: String = "res://resources/audio"

const RATE: int = 22050


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SOUNDS))
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


## A big drive: a low fundamental with its harmonics, and enough noise
## over the top that it reads as combustion rather than as an organ.
func _drive_loop() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 101
	var length: int = RATE
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		var tone: float = (
			sin(TAU * 52.0 * at) * 0.50
			+ sin(TAU * 104.0 * at) * 0.22
			+ sin(TAU * 157.0 * at) * 0.10
		)
		out.append(tone + rng.randf_range(-1.0, 1.0) * 0.16)
	return out


## An attitude thruster: almost all noise, almost no tone. Small and
## sharp, because that is what it is -- the loudness curve has to be
## able to put one of these next to a main drive without them merging.
func _thruster_loop() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 202
	var length: int = RATE / 2
	var rolling: float = 0.0
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		# A one-pole smoother on the noise, which is the cheapest way to
		# get hiss rather than static: white noise at 22 kHz is a fizz
		# and has no size to it at all.
		rolling = lerpf(rolling, rng.randf_range(-1.0, 1.0), 0.35)
		out.append(rolling * 0.75 + sin(TAU * 420.0 * at) * 0.08)
	return out


## A torque jet: harsh and buzzy, because an impulse engine is.
##
## The pulsing itself is **not** in here. The simulation switches these
## fully on and fully off, tick by tick, at a rate that is the throttle
## it was asked for -- so the modulation is already in the code, and
## baking a second one into the sample would beat against it.
func _torque_loop() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 303
	var length: int = RATE / 2
	for i: int in range(length):
		var at: float = float(i) / float(RATE)
		# A squared-off tone rather than a sine: a jet that has only two
		# states should not sound like something with a dial.
		var square: float = 1.0 if sin(TAU * 138.0 * at) >= 0.0 else -1.0
		out.append(square * 0.34 + rng.randf_range(-1.0, 1.0) * 0.22)
	return out


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
	print("audio: %-6s %5.2f s -> %s" % [name, float(samples.size()) / float(RATE), path])
