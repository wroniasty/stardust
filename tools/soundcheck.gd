extends Node
## Odpala po kolei każdy dźwięk i wypisuje, co zagrało.
##   godot --headless --path . tools/soundcheck.tscn --quit-after 2
##
## The point is the table, not the noise. "Vacuum is quiet" is a rule with
## three cases and two of them are silence, so the only way to see that it
## is working -- especially headless, where nothing can be heard at all --
## is to ask for every combination and print the answer.

const SAMPLES: Array[String] = [
	"thump", "crack", "tick", "bed",
	"engine_ignite", "engine_cut",
	"hull_grind", "hull_creak", "gear_servo", "gear_touch", "deny", "explode", "respawn",
	"shot_gun", "shot_beam", "shot_launch", "rock_hit", "rock_settle",
]

## What a throttle setting sounds like, per kind of engine. The loops
## are not in the table above because they are never "played": they
## run, and what is worth printing about them is the curve.
const THROTTLES: Array[float] = [0.0, 0.25, 0.5, 1.0]

const AIRS: Array[float] = [0.0, 0.15, 1.0]


func _ready() -> void:
	var sound: Soundscape = Soundscape.new()
	add_child(sound)

	print("sound check: '+' played, '.' silenced by the air")
	print("%-8s %-10s %s" % ["sample", "path", "  ".join(_air_heads())])
	for name: String in SAMPLES:
		var stream: AudioStream = load("res://resources/audio/%s.tres" % name)
		for path: Soundscape.Path in [
			Soundscape.Path.CONDUCTED,
			Soundscape.Path.AIRBORNE,
			Soundscape.Path.INTERFACE,
		]:
			var row: PackedStringArray = PackedStringArray()
			for air: float in AIRS:
				sound.density = air
				row.append("    %s   " % ("+" if sound.play(
					stream, Vector2.ZERO, path
				) else "."))
			print("%-8s %-10s %s" % [
				name, Soundscape.Path.keys()[int(path)].to_lower(), "".join(row),
			])

	print("")
	for air: float in AIRS:
		sound.set_muffle(air)
		var bus: int = AudioServer.get_bus_index("Sfx")
		var muffle: AudioEffectLowPassFilter = (
			AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
		)
		print("air %.2f -> cutoff %6.0f Hz" % [air, muffle.cutoff_hz])

	_engine_table()
	_path_table()

	# Freed rather than left to the quit. A player still holding a stream
	# at exit is reported as a leaked resource, and `tools/check.ps1`
	# greps the output for exactly that word.
	for voice: Node in sound.get_children():
		(voice as AudioStreamPlayer2D).stream = null
	sound.free()
	get_tree().quit()


## Which way every sound in every table reaches the ear.
##
## The one field nobody can check by listening, printed so it can be
## checked by looking. Getting conducted and airborne the wrong way
## round is invisible in an atmosphere and wrong everywhere else: a
## gun that fell silent in vacuum, a crater that did not.
func _path_table() -> void:
	print("")
	print("sound tables: which way each one reaches the ear")
	print("%-14s %-10s %-11s %6s  %s" % ["table", "entry", "path", "vol", "pitch"])
	for name: String in [
		"engine_loop", "engine_event", "hull", "weapon_shot", "terrain", "missile",
	]:
		var table: SoundTable = load("res://resources/fx/sounds/%s.tres" % name)
		if table == null:
			continue
		for entry: Array in _entries_of(table):
			var strip: SoundStrip = entry[1]
			print("%-14s %-10s %-11s %6.2f  %.2f..%.2f" % [
				name, entry[0],
				Soundscape.Path.keys()[int(strip.path)].to_lower(),
				strip.volume, strip.pitch.x, strip.pitch.y,
			])


## Every strip in a table with something to call it by.
func _entries_of(table: SoundTable) -> Array[Array]:
	var out: Array[Array] = []
	for key: Variant in table.by_key:
		out.append([String(key), table.by_key[key]])
	for affix: Variant in table.by_affix:
		out.append(["+%s" % affix, table.by_affix[affix]])
	for i: int in range(table.variants.size()):
		out.append(["#%d" % i, table.variants[i]])
	if table.fallback != null:
		out.append(["fallback", table.fallback])
	return out


## What each kind of engine does as the throttle opens.
##
## The torque row is the one to read. A main drive at a steady command
## sits at a steady level; an impulse engine at the same command is
## switched fully on and fully off tick by tick, so its level swings,
## and the spread printed here is that swing. If it ever goes flat, the
## response time has been smoothed into a hum.
func _engine_table() -> void:
	var ship: Ship = (load("res://scenes/ship.tscn") as PackedScene).instantiate() as Ship
	ship.use_player_input = false
	add_child(ship)
	var choir: EngineChoir = EngineChoir.new()
	add_child(choir)
	choir._ship = ship
	choir.rebuild()

	print("")
	print("engines: mean loudness at each throttle, and how much it swings")
	print("%-20s %-10s %s" % ["mount", "kind", "  ".join(_throttle_heads())])
	for engine: EngineInstance in ship.engines:
		var row: PackedStringArray = PackedStringArray()
		for asked: float in THROTTLES:
			engine.target_throttle = asked
			engine.throttle = asked
			var low: float = INF
			var high: float = 0.0
			var total: float = 0.0
			var counted: int = 0
			for tick: int in range(120):
				engine.advance(1.0 / 60.0)
				choir.sing(1.0 / 60.0)
				if tick < 40:
					continue
				var heard: float = choir.level_of(engine.mount.name)
				low = minf(low, heard)
				high = maxf(high, heard)
				total += heard
				counted += 1
			# The mean, not the midpoint of the range. A jet pulsing
			# between nothing and full has the same midpoint whatever
			# its duty cycle, so the first version of this column read
			# the same at a quarter throttle as at a half -- which is
			# the one thing about an impulse engine worth seeing.
			row.append("%5.2f ±%4.2f " % [
				total / float(maxi(counted, 1)), (high - low) * 0.5,
			])
		engine.target_throttle = 0.0
		engine.throttle = 0.0
		print("%-20s %-10s %s" % [
			engine.mount.name,
			EngineData.Type.keys()[int(engine.data.type)].to_lower(),
			"".join(row),
		])
	choir.free()
	ship.free()


func _throttle_heads() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for asked: float in THROTTLES:
		out.append("thr %.2f  " % asked)
	return out


func _air_heads() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for air: float in AIRS:
		out.append("air %.2f" % air)
	return out
