extends Node
## Fires every armed hardpoint of the stock ship and checks the round starts
## where the hardpoint is, not somewhere fixed on the hull:
##   godot --headless --path . res://tools/fire_check.tscn
## A scene rather than a --script, for the autoloads the ship reads.

var _frames: int = 0
var _failed: bool = false
var _ship: Ship = null


func _ready() -> void:
	_ship = (load("res://scenes/ship.tscn") as PackedScene).instantiate() as Ship
	_ship.use_player_input = false
	add_child(_ship)
	var container: Node2D = Node2D.new()
	container.add_to_group(Ship.PROJECTILE_GROUP)
	add_child(container)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 3:
		var armed: int = 0
		for gun: Hardpoint in _ship.hardpoints:
			if gun.weapon == null:
				continue
			armed += 1
			# Moved and turned so a fixed point on the hull and a point on the
			# hardpoint cannot be the same place by accident.
			var container: Node = _ship.projectile_container()
			var before: int = container.get_child_count()
			gun._cooldown = 0.0
			_ship.energy = 1000.0
			var round: Projectile = gun.fire(Vector2.ZERO, container, _ship)
			if round != null:
				var off: float = round.global_position.distance_to(gun.global_position)
				_check(off < 0.01, "%s fires from itself (%.3f px off, at %s)" % [gun.name, off, gun.position])
			else:
				_check(container.get_child_count() > before, "%s fired something" % gun.name)
		_check(armed >= 1, "the stock ship has an armed hardpoint (%d)" % armed)
		print("fire check: ", "FAILED" if _failed else "ok")
		get_tree().quit(1 if _failed else 0)


func _check(condition: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FAIL", what])
	if not condition:
		_failed = true
