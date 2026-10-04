class_name BenchDummies
extends Node2D
## Targets to shoot at: real ships with nobody flying them.
##
## Real because that is what a round hits. Projectiles and beams hurt
## whatever `Ship` they touch and seekers look for the `ships` group, so a
## dummy built from anything else would test a gun against a world the game
## does not have. These are frozen in place (or walked round a ring by
## hand), put back whole after dying, and watched for the one thing the
## bench wants from them: how much damage went in, and how fast.

enum Motion { STILL, ORBIT }

const SHIP_SCENE: PackedScene = preload("res://scenes/ship.tscn")

## A dead target stays dead this long, so the kill is visible.
const RESPAWN_DELAY: float = 1.2

## The span damage per second is averaged over. Long enough to smooth a
## burst weapon's gaps, short enough to follow a change of gun.
const WINDOW: float = 5.0

var motion: Motion = Motion.STILL
var radius: float = 300.0

## Radians per second round the ring, when orbiting.
var orbit_rate: float = 0.25

var kills: int = 0
var hits: int = 0
var total_damage: float = 0.0

## One entry per target: its ship, its place on the ring, the hull it had
## when last looked at.
var _slots: Array[Dictionary] = []

## (seconds, damage) pairs inside the averaging window.
var _log: Array[Vector2] = []


func count() -> int:
	return _slots.size()


## Replaces the current targets with `number` new ones, evenly round a ring.
func spawn(number: int) -> void:
	clear()
	for i: int in range(number):
		var angle: float = TAU * float(i) / float(maxi(number, 1))
		var target: Ship = SHIP_SCENE.instantiate() as Ship
		target.use_player_input = false
		target.name = "Dummy%d" % i
		add_child(target)
		target.freeze = true
		target.global_position = Vector2.from_angle(angle) * radius
		target.reset_physics_interpolation()
		target.destroyed.connect(_on_destroyed.bind(target))
		_slots.append({"ship": target, "angle": angle, "seen": 1.0})


func clear() -> void:
	for slot: Dictionary in _slots:
		(slot["ship"] as Ship).queue_free()
	_slots.clear()


func reset_counts() -> void:
	kills = 0
	hits = 0
	total_damage = 0.0
	_log.clear()


## Damage per second over the last `WINDOW` seconds.
func damage_per_second() -> float:
	var now: float = Time.get_ticks_msec() / 1000.0
	var sum: float = 0.0
	for entry: Vector2 in _log:
		if now - entry.x <= WINDOW:
			sum += entry.y
	return sum / WINDOW


func _physics_process(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	while not _log.is_empty() and now - _log[0].x > WINDOW:
		_log.pop_front()

	for slot: Dictionary in _slots:
		var target: Ship = slot["ship"] as Ship
		if motion == Motion.ORBIT and not target.is_destroyed():
			slot["angle"] = float(slot["angle"]) + orbit_rate * delta
			target.global_position = Vector2.from_angle(float(slot["angle"])) * radius
		elif motion == Motion.STILL and not target.is_destroyed():
			target.global_position = Vector2.from_angle(float(slot["angle"])) * radius

		var integrity: float = target.hull_integrity
		var seen: float = float(slot["seen"])
		if integrity < seen:
			hits += 1
			total_damage += seen - integrity
			_log.append(Vector2(now, seen - integrity))
		slot["seen"] = integrity


func _on_destroyed(_at: Vector2, _velocity: Vector2, target: Ship) -> void:
	kills += 1
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_revive.bind(target))


## Back in the same place, whole, and frozen again: `respawn` thaws the
## body, which is right for a pilot and wrong for a target.
func _revive(target: Ship) -> void:
	if not is_instance_valid(target):
		return
	target.respawn(target.global_position, Vector2.ZERO)
	target.freeze = true
	for slot: Dictionary in _slots:
		if slot["ship"] == target:
			slot["seen"] = 1.0
