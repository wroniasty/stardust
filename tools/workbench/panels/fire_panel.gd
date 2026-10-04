class_name BenchFirePanel
extends VBoxContainer
## Pulling the trigger, and something to pull it at.
##
## The triggers are held through the Input Map, so the ship's own reading of
## the mouse button is what runs and the guns aim at the cursor the way they
## do in flight. The weapon readout is what the gun on each hardpoint
## *claims*; the damage readout is what the targets actually lost. The two
## are meant to agree, and the day they stop is the day this panel earns its
## keep.

const MOTION_NAMES: Array[String] = ["still", "circling"]

var _bench: Workbench = null
var _ship: Ship = null

var _number: SpinBox = null
var _distance: SpinBox = null
var _motion: OptionButton = null
var _guns_box: VBoxContainer = null
var _results: Label = null


func bind(bench: Workbench, ship: Ship) -> void:
	_bench = bench
	_ship = ship
	_build()
	_ship.configuration_changed.connect(_refresh_deferred)
	_refresh_guns()


func _build() -> void:
	add_child(BenchForm.heading("trigger"))
	add_child(BenchForm.check("hold fire (LMB)", func(on: bool) -> void:
		_bench.hold(&"ship_fire", on)))
	add_child(BenchForm.check("hold secondary fire (RMB)", func(on: bool) -> void:
		_bench.hold(&"ship_fire_secondary", on)))
	add_child(BenchForm.note("Guns aim at the mouse cursor."))

	add_child(BenchForm.heading("targets"))
	_number = SpinBox.new()
	_number.min_value = 1
	_number.max_value = 12
	_number.value = 3
	add_child(BenchForm.labelled("how many", _number))
	_distance = SpinBox.new()
	_distance.min_value = 80
	_distance.max_value = 1500
	_distance.step = 20
	_distance.value = 300
	add_child(BenchForm.labelled("distance", _distance))
	_motion = OptionButton.new()
	for motion_name: String in MOTION_NAMES:
		_motion.add_item(motion_name)
	_motion.item_selected.connect(func(i: int) -> void:
		_bench.dummies.motion = i as BenchDummies.Motion)
	add_child(BenchForm.labelled("motion", _motion))
	add_child(BenchForm.button("set up targets", _on_spawn))
	add_child(BenchForm.button("clear the targets", _bench.dummies.clear))
	add_child(BenchForm.button("reset the counters", _bench.dummies.reset_counts))

	_results = Label.new()
	_results.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_results)

	add_child(BenchForm.heading("guns (as declared)"))
	_guns_box = VBoxContainer.new()
	add_child(_guns_box)


func _on_spawn() -> void:
	_bench.dummies.radius = float(_distance.value)
	_bench.dummies.spawn(int(_number.value))


func _process(_delta: float) -> void:
	if _ship == null or not is_visible_in_tree():
		return
	var dummies: BenchDummies = _bench.dummies
	_results.text = "targets: %d\nhits %d  destroyed %d\ndamage %.2f  (%.3f / s)" % [
		dummies.count(), dummies.hits, dummies.kills,
		dummies.total_damage, dummies.damage_per_second(),
	]


func _refresh_deferred() -> void:
	_refresh_guns.call_deferred()


## One block per gun, from the weapon as mounted: mods included, because
## the effective weapon is what leaves the barrel.
func _refresh_guns() -> void:
	for child: Node in _guns_box.get_children():
		_guns_box.remove_child(child)
		child.queue_free()
	if _ship.hardpoints.is_empty():
		_guns_box.add_child(BenchForm.note("no hardpoints"))
		return
	for hardpoint: Hardpoint in _ship.hardpoints:
		var weapon: WeaponData = hardpoint.effective()
		if weapon == null:
			continue
		var cost: float = hardpoint.energy_cost()
		var drain: float = cost * weapon.rounds_per_second
		var lasts: String = "for ever"
		if drain > 0.0:
			lasts = "%.1f s" % (_ship.energy_capacity() / drain)
		var label: Label = Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s\n  %.2f/s x %.3f = %.3f/s\n  cost %.1f, range %.0f, the pool lasts %s" % [
			String(hardpoint.name), weapon.rounds_per_second, weapon.damage,
			weapon.damage_per_second(), cost, weapon.range_px, lasts,
		]
		_guns_box.add_child(label)
