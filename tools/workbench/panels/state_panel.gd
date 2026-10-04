class_name BenchStatePanel
extends VBoxContainer
## States a ship can be in, switched on by hand.
##
## Two kinds, and the panel keeps them apart. Some the ship keeps by itself
## (hull integrity, engine health, fuel): the slider writes them and the
## ship carries on from there. Others it recomputes every tick (heat, air,
## starlight): those go through `BenchPins`, with a checkbox to let go.
##
## The readout at the top is what the ship holds *now*, not what a slider
## says. When the two disagree, the simulation has overruled the form, and
## that is worth being able to see.

## Rows for what the ship recomputes: field, caption, top of the range.
const PINNED_ROWS: Array[Dictionary] = [
	{"key": &"hull_heat", "caption": "ciepło kadłuba", "top": 1.0},
	{"key": &"air_density", "caption": "gęstość powietrza", "top": 1.0},
	{"key": &"star_flux", "caption": "światło gwiazdy", "top": 1.5},
]

## What a held control sends, so the bench can press it for you.
const HOLDS: Array[Dictionary] = [
	{"action": &"thrust_forward", "caption": "ciąg do przodu"},
	{"action": &"brake", "caption": "hamulec"},
	{"action": &"boost", "caption": "doładowanie"},
]

var _bench: Workbench = null
var _ship: Ship = null

var _readout: Label = null
var _integrity: HSlider = null
var _fuel: HSlider = null
var _energy: HSlider = null
var _impact_speed: SpinBox = null
var _engine_box: VBoxContainer = null
var _pin_sliders: Dictionary = {}
var _pin_checks: Dictionary = {}


func bind(bench: Workbench, ship: Ship) -> void:
	_bench = bench
	_ship = ship
	_build()
	_ship.configuration_changed.connect(_refresh_deferred)
	_refresh_engines()


func _build() -> void:
	_readout = Label.new()
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_readout)

	add_child(BenchForm.heading("kadłub"))
	_integrity = BenchForm.slider(0.0, 1.0, 0.01, 1.0)
	_integrity.value_changed.connect(_on_integrity)
	add_child(BenchForm.labelled("integralność", _integrity))
	add_child(BenchForm.button("napraw kadłub", _on_repair_hull))

	add_child(BenchForm.heading("przypięte (statek liczy je sam)"))
	for row: Dictionary in PINNED_ROWS:
		_build_pinned_row(row)

	add_child(BenchForm.heading("zasoby"))
	_fuel = BenchForm.slider(0.0, 1.0, 0.01, 1.0)
	_fuel.value_changed.connect(func(v: float) -> void: _ship.fuel = v * _ship.fuel_capacity())
	add_child(BenchForm.labelled("paliwo", _fuel))
	add_child(BenchForm.check("paliwo bez końca", func(on: bool) -> void:
		_bench.pins.endless_fuel = on))
	_energy = BenchForm.slider(0.0, 1.0, 0.01, 1.0)
	_energy.value_changed.connect(func(v: float) -> void: _ship.energy = v * _ship.energy_capacity())
	add_child(BenchForm.labelled("energia", _energy))
	add_child(BenchForm.check("energia bez końca", func(on: bool) -> void:
		_bench.pins.endless_energy = on))

	add_child(BenchForm.heading("silniki (zdrowie)"))
	_engine_box = VBoxContainer.new()
	add_child(_engine_box)
	var engine_buttons: HBoxContainer = HBoxContainer.new()
	engine_buttons.add_child(BenchForm.button("uszkodź jeden", _on_break_engine))
	engine_buttons.add_child(BenchForm.button("napraw", _on_repair_engines))
	add_child(engine_buttons)

	add_child(BenchForm.heading("zdarzenia"))
	_impact_speed = SpinBox.new()
	_impact_speed.min_value = 0.0
	_impact_speed.max_value = 400.0
	_impact_speed.step = 10.0
	_impact_speed.value = 100.0
	add_child(BenchForm.labelled("prędkość [px/s]", _impact_speed))
	add_child(BenchForm.button("uderz w skałę", _on_impact))
	add_child(BenchForm.button("zniszcz statek", _on_destroy))
	add_child(BenchForm.check("podwozie wysunięte", _on_gear))

	add_child(BenchForm.heading("trzymaj klawisz"))
	for hold: Dictionary in HOLDS:
		var action: StringName = hold["action"]
		add_child(BenchForm.check(String(hold["caption"]), func(on: bool) -> void:
			_bench.hold(action, on)))

	add_child(BenchForm.heading("całość"))
	add_child(BenchForm.button("odpnij wszystko i napraw", _on_clear))


func _build_pinned_row(row: Dictionary) -> void:
	var key: StringName = row["key"]
	var box: VBoxContainer = VBoxContainer.new()
	var slider: HSlider = BenchForm.slider(0.0, float(row["top"]), 0.01, 0.0)
	var check: CheckBox = BenchForm.check("%s: przypnij" % row["caption"], func(on: bool) -> void:
		if on:
			_bench.pins.pin(key, _pin_sliders[key].value)
		else:
			_bench.pins.unpin(key))
	# Moving the slider is the request to pin it. A slider that did nothing
	# until a second control was ticked would read as broken.
	slider.value_changed.connect(func(v: float) -> void:
		_bench.pins.pin(key, v)
		_pin_checks[key].set_pressed_no_signal(true))
	_pin_sliders[key] = slider
	_pin_checks[key] = check
	box.add_child(check)
	box.add_child(slider)
	add_child(box)


func _process(_delta: float) -> void:
	if _ship == null or not is_visible_in_tree():
		return
	_readout.text = "kadłub %.0f%%  ciepło %.2f\npowietrze %.2f  gwiazda %.2f\npaliwo %.0f/%.0f  energia %.0f/%.0f\nprędkość %.0f px/s" % [
		_ship.hull_integrity * 100.0, _ship.hull_heat,
		_ship.air_density, _ship.star_flux,
		_ship.fuel, _ship.fuel_capacity(), _ship.energy, _ship.energy_capacity(),
		_ship.linear_velocity.length(),
	]


func _refresh_deferred() -> void:
	_refresh_engines.call_deferred()


## One health slider per engine, read off the ship as it is now.
func _refresh_engines() -> void:
	for child: Node in _engine_box.get_children():
		_engine_box.remove_child(child)
		child.queue_free()
	for engine: EngineInstance in _ship.engines:
		var slider: HSlider = BenchForm.slider(0.0, 1.0, 0.01, engine.health)
		slider.value_changed.connect(func(v: float) -> void: engine.health = v)
		_engine_box.add_child(BenchForm.labelled(String(engine.mount.name), slider))


## Integrity is the ship's own to keep, so this writes it and says so.
##
## Going through `take_damage` for the fall to zero, because that is the
## door the death path hangs off; every way of dying that skipped it would
## be a way of dying the sound and the wreck never heard about.
func _on_integrity(value: float) -> void:
	if value <= 0.0:
		_ship.take_damage(_ship.hull_integrity + 1.0, "bench")
		return
	_ship.hull_integrity = value
	_ship.hull_changed.emit(value)


func _on_repair_hull() -> void:
	_ship.repair_hull()
	_integrity.set_value_no_signal(1.0)


func _on_break_engine() -> void:
	if _ship.engines.is_empty():
		return
	var victim: EngineInstance = _ship.engines[randi() % _ship.engines.size()]
	victim.health = clampf(victim.health - 0.35, 0.0, 1.0)
	_refresh_engines()


func _on_repair_engines() -> void:
	_ship.repair_engines()
	_refresh_engines()


## An impact with nothing to hit: the same signal and the same cost the
## terrain would have produced, so the camera, the dust and the hull's voice
## all answer to it as they would to rock.
func _on_impact() -> void:
	var speed: float = float(_impact_speed.value)
	var on_legs: bool = _ship.gear != null and _ship.gear.is_deployed()
	var damage: float = _ship.impact_damage(speed, on_legs)
	_ship.hull_impact.emit(speed, damage)
	_ship.take_damage(damage, "impact")
	_integrity.set_value_no_signal(_ship.hull_integrity)


func _on_destroy() -> void:
	_ship.take_damage(_ship.hull_integrity + 1.0, "bench")


func _on_gear(on: bool) -> void:
	if _ship.gear != null:
		_ship.gear.set_deployed(on)


func _on_clear() -> void:
	_bench.pins.clear()
	for key: StringName in _pin_checks:
		(_pin_checks[key] as CheckBox).set_pressed_no_signal(false)
		(_pin_sliders[key] as HSlider).set_value_no_signal(0.0)
	_ship.repair_hull()
	_ship.repair_engines()
	_ship.energy = _ship.energy_capacity()
	_ship.fuel = _ship.fuel_capacity()
	_integrity.set_value_no_signal(1.0)
	_refresh_engines()
