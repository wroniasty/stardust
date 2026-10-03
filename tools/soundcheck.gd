extends Node
## Odpala po kolei każdy dźwięk i wypisuje, co zagrało.
##   godot --headless --path . tools/soundcheck.tscn --quit-after 2
##
## The point is the table, not the noise. "Vacuum is quiet" is a rule with
## three cases and two of them are silence, so the only way to see that it
## is working -- especially headless, where nothing can be heard at all --
## is to ask for every combination and print the answer.

const SAMPLES: Array[String] = ["thump", "crack", "tick", "bed"]

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

	# Freed rather than left to the quit. A player still holding a stream
	# at exit is reported as a leaked resource, and `tools/check.ps1`
	# greps the output for exactly that word.
	for voice: Node in sound.get_children():
		(voice as AudioStreamPlayer2D).stream = null
	sound.free()
	get_tree().quit()


func _air_heads() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for air: float in AIRS:
		out.append("air %.2f" % air)
	return out
