extends Node
## Walks the main menu the way a player would and checks the world that comes
## out of it:
##   godot --headless --path . res://tools/menu_check.tscn
## A scene rather than a --script, because the menu and the world read
## autoloads, which a bare SceneTree script cannot compile against.

var _frames: int = 0
var _failed: bool = false


func _ready() -> void:
	var menu: MainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	get_tree().root.add_child.call_deferred(menu)
	get_tree().set_deferred("current_scene", menu)


func _process(_delta: float) -> void:
	_frames += 1
	var menu: MainMenu = get_tree().current_scene as MainMenu
	if _frames == 3 and menu != null:
		_check(menu._ships.item_count == ShipFitout.all().size(), "one row per preset")
		menu._seed_field.text = "12ab34"
		menu._on_seed_edited(menu._seed_field.text)
		_check(menu._seed_field.text == "1234", "the seed field keeps only digits (%s)" % menu._seed_field.text)
		menu._on_randomize()
		_check(menu._seed_field.text.to_int() > 0, "randomize fills in a number")
		menu._seed_field.text = "4242"
		menu._ships.select(4)
		menu.start()
	if _frames == 30:
		_check(GameSettings.chosen, "the menu recorded its choice")
		_check(Galaxy.galaxy_seed == 4242, "the world built the galaxy from the typed seed (%d)" % Galaxy.galaxy_seed)
		var world: World = get_tree().current_scene as World
		_check(world != null, "the world is the current scene")
		if world != null:
			var ship: Ship = (world.player as Player).ship
			_check(ship != null and ship.hull != null and ship.hull.id == &"interceptor", "the picked ship was built (%s)" % [ship.hull.id if ship != null and ship.hull != null else "none"])
			_check(ship != null and ship.hardpoints.size() >= 2, "and it has its guns")
		print("menu check: ", "FAILED" if _failed else "ok")
		get_tree().quit(1 if _failed else 0)


func _check(condition: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FAIL", what])
	if not condition:
		_failed = true
