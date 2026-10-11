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
		_check_a_jettison_becomes_a_crate(world)
		print("menu check: ", "FAILED" if _failed else "ok")
		get_tree().quit(1 if _failed else 0)


## The whole way through, in the one harness that has a real world.
##
## This is where the missing wire would have been caught. The unit
## tests check that `jettison()` hands the module back and that a crate
## falls properly once something ejects it; what neither of them can
## see is that nothing in the game was listening, because the listener
## is on `World` and `World` needs autoloads -- so it only exists in a
## scene run like this one.
##
## The claim is end to end on purpose: throw something, and there is a
## crate in the world holding it.
func _check_a_jettison_becomes_a_crate(world: World) -> void:
	if world == null:
		return
	var ship: Ship = (world.player as Player).ship
	if ship == null:
		return
	var before: int = get_tree().get_nodes_in_group(LootCrate.LOOT_GROUP).size()
	# A gun of its own, held by identity rather than by type: this world
	# already has crates on its shelves and some of them hold guns, so
	# "a crate with a WeaponData in it" found one of those and reported
	# a crate three thousand pixels away as the one just thrown.
	var mine: WeaponData = WeaponData.new()
	_check(ship.take(mine), "a module goes into the hold")
	ship.jettison()
	var crates: Array[Node] = get_tree().get_nodes_in_group(LootCrate.LOOT_GROUP)
	_check(
		crates.size() == before + 1,
		"and throwing it overboard leaves a crate in the world (%d, was %d)" % [
			crates.size(), before,
		],
	)
	var thrown: LootCrate = null
	for node: Node in crates:
		var crate: LootCrate = node as LootCrate
		if crate != null and crate.item == mine:
			thrown = crate
	_check(
		thrown != null and thrown.loose
		and thrown.global_position.distance_to(ship.global_position) < 200.0,
		"with the module in it, loose, and next to the ship (%s)" % [
			"missing" if thrown == null else "%.0f px" % [
				thrown.global_position.distance_to(ship.global_position),
			],
		],
	)


func _check(condition: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FAIL", what])
	if not condition:
		_failed = true
