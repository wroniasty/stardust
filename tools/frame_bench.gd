extends Node
## What a thing in the world costs per frame. Run as an autoload, with:
##   godot --path . --fixed-fps 60 --quit-after 30000
## adding Bench="*res://tools/frame_bench.gd" to [autoload] first, or
## headless with the same line to get the CPU side on its own.
##
## **Method, which is the part worth keeping.** The first attempt at this
## used `Performance.TIME_PROCESS` plus `TIME_PHYSICS_PROCESS` in an
## ordinary windowed run, and reported 42 ms a frame with nothing on
## screen and 8.9 ms with forty projectiles in the air. Those counters in
## a vsync-limited loop are not a measure of how much work was done --
## they are a measure of where the engine happened to account for the
## wait, and they sent me off reporting that a projectile cost 0.9 ms
## when it costs about seven microseconds.
##
## So: wall clock, `--fixed-fps` so the loop runs flat out, vsync off,
## hundreds of frames per case, and a count that is set rather than
## inferred. Then the only way to be wrong is arithmetic.
##
## The cases vary one thing at a time, because "projectiles are
## expensive" is four hypotheses wearing one coat: the script, the swept
## terrain test, the light each one carries, and the Area2D.

const COUNTS: Array[int] = [0, 10, 20, 40, 80, 160]

## Frames thrown away before each case is measured, then frames measured.
## The discard matters: spawning eighty nodes is itself work, and it is
## not the work being measured.
const SETTLE_FRAMES: int = 40
const SAMPLE_FRAMES: int = 400

## What each case switches off, against the whole round.
const CASES: Array[String] = ["whole", "nosweep", "nolight", "bare"]

var _ship: Ship = null
var _world: Node = null
var _home: Vector2 = Vector2.ZERO
var _rounds: Array[Node] = []

var _plan: Array[Dictionary] = []
var _case: int = -1
var _waited: int = 0
var _taken: int = 0
var _last: int = 0
var _total: int = 0
var _frames: Array[int] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Or the wall clock measures how long the monitor made us wait.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _process(_delta: float) -> void:
	if _ship == null:
		_world = get_tree().root.get_node_or_null("World")
		if _world == null:
			return
		var player: Node = _world.get_node_or_null("Player")
		_ship = (player as Player).ship if player != null else null
		if _ship != null:
			_ship.use_player_input = false
		return
	if _plan.is_empty():
		_build_plan()
		return

	var now: int = Time.get_ticks_usec()
	var elapsed: int = now - _last
	_last = now

	if _waited < SETTLE_FRAMES:
		_waited += 1
		return
	if _taken < SAMPLE_FRAMES:
		_total += elapsed
		_frames.append(elapsed)
		_taken += 1
		return

	_report()
	_begin_case()


func _build_plan() -> void:
	var planet: Planet = Planet.nearest(get_tree(), _ship.global_position)
	# The position, not the node. Cases move the ship, moving the ship
	# streams the planet out, and the next case then dereferences
	# something already freed -- which is how the first run of this
	# crashed halfway through.
	_home = planet.global_position + Vector2(0.0, -(planet.surface_radius + 2500.0))
	for case: String in CASES:
		for count: int in COUNTS:
			_plan.append({"case": case, "count": count})
	print("rounds | round is  | us/frame | median | 99th pct |   worst | per round")
	_begin_case()


func _begin_case() -> void:
	for shot: Node in _rounds:
		if is_instance_valid(shot):
			shot.free()
	_rounds.clear()
	_case += 1
	if _case >= _plan.size():
		get_tree().quit()
		return

	var entry: Dictionary = _plan[_case]
	var kind: String = entry["case"]
	_ship.respawn(_home, Vector2.ZERO)

	var scene: PackedScene = load("res://scenes/projectile.tscn") as PackedScene
	var count: int = int(entry["count"])
	for i: int in range(count):
		var shot: Projectile = scene.instantiate() as Projectile
		# Long-lived and harmless: the bench is about what a round costs
		# while it is in the air, not about what it does when it lands.
		shot.lifetime = 600.0
		shot.damage = 0.0
		var angle: float = TAU * float(i) / float(maxi(count, 1))
		shot.velocity = Vector2.from_angle(angle) * 40.0
		_world.add_child(shot)
		shot.global_position = _home + Vector2.from_angle(angle) * 140.0
		if kind == "nosweep" or kind == "bare":
			shot._planet = null
		if kind == "nolight" or kind == "bare":
			for child: Node in shot.get_children():
				if child is GlowLight:
					child.queue_free()
		_rounds.append(shot)

	_waited = 0
	_taken = 0
	_total = 0
	_frames.clear()
	_last = Time.get_ticks_usec()


func _report() -> void:
	var entry: Dictionary = _plan[_case]
	var count: int = int(entry["count"])
	var average: float = float(_total) / float(_taken)
	var sorted: Array[int] = _frames.duplicate()
	sorted.sort()
	# The baseline of each block of counts, so "per round" is the slope
	# rather than the average divided by the count -- which at ten rounds
	# reads as ten times the real figure.
	var base: float = float(_plan[_case - count_index()].get("measured", average))
	_plan[_case]["measured"] = average
	print("%6d | %-9s | %8.0f | %6d | %8d | %7d | %s" % [
		count, entry["case"], average,
		sorted[sorted.size() / 2], sorted[int(float(sorted.size()) * 0.99)],
		sorted[sorted.size() - 1],
		"--" if count == 0 else "%.1f us" % ((average - base) / float(count)),
	])


## How far back in the plan this case's own zero-round baseline is.
func count_index() -> int:
	return _case % COUNTS.size()
