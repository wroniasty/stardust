class_name EnergyHud
extends CanvasLayer
## The energy bar. It has to say three things, and none of them is a number of
## units (IDEAS.md section 14).
##
## How many shots are left, so the bar is notched at the cost of the fitted
## weapon and the pilot counts notches rather than reading a percentage.
## Whether the pool is waiting out the silence or actually filling, because a
## bar that has stopped and a bar that is climbing mean different things to
## someone deciding whether to hold the trigger. And that a shot was refused,
## at once, or a dead trigger reads as a stuck key.

const WIDTH: float = 148.0
const HEIGHT: float = 7.0
## Clear of the bottom of the screen by enough to leave the scanner's ring
## alone: at 10 px the bar sat straight through the markers and their
## distances, and two readouts in the same pixels are neither.
const MARGIN: float = 28.0

const FRAME: Color = Color(0.36, 0.41, 0.49)
const EMPTY: Color = Color(0.07, 0.09, 0.12, 0.85)
## Filling and waiting are different colours because they are different
## states, not different amounts.
const CHARGING: Color = Color(0.36, 0.78, 1.00)
const WAITING: Color = Color(0.34, 0.45, 0.58)
const NOTCH: Color = Color(0.05, 0.07, 0.10, 0.85)
const REFUSED: Color = Color(1.00, 0.35, 0.30)

## Seconds a refusal stays visible. Long enough to be seen at sixty rounds a
## minute, short enough not to blur into the next one.
const REFUSAL_FLASH: float = 0.35

## Don't notch a bar into more slivers than the eye can count; past this the
## weapon is cheap enough that shots are not the unit any more.
const MAX_NOTCHES: int = 24

var _ship: Ship = null
var _canvas: Control = null
var _refused_for: float = 0.0


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_bar)
	add_child(_canvas)


func bind(ship: Ship) -> void:
	if _ship != null and _ship.shot_refused.is_connected(_on_refused):
		_ship.shot_refused.disconnect(_on_refused)
	_ship = ship
	if _ship != null:
		_ship.shot_refused.connect(_on_refused)


func _on_refused() -> void:
	_refused_for = REFUSAL_FLASH


func _process(delta: float) -> void:
	_refused_for = maxf(_refused_for - delta, 0.0)
	if _canvas != null:
		_canvas.queue_redraw()


## The cost of one shot from the cheapest gun aboard, which is what a notch is
## worth. The cheapest rather than the first, so the notches never promise
## fewer shots than the ship can actually take.
func shot_cost() -> float:
	var cheapest: float = 0.0
	for hardpoint: Hardpoint in _ship.hardpoints:
		if hardpoint.weapon == null or hardpoint.weapon.energy_cost <= 0.0:
			continue
		if cheapest <= 0.0 or hardpoint.weapon.energy_cost < cheapest:
			cheapest = hardpoint.weapon.energy_cost
	return cheapest


func _draw_bar() -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	var capacity: float = _ship.energy_capacity()
	if capacity <= 0.0:
		return

	var view: Vector2 = _canvas.size
	var box: Rect2 = Rect2(
		(view.x - WIDTH) * 0.5, view.y - MARGIN - HEIGHT, WIDTH, HEIGHT
	)
	_canvas.draw_rect(box, EMPTY)

	var filled: float = clampf(_ship.energy / capacity, 0.0, 1.0)
	if filled > 0.0:
		_canvas.draw_rect(
			Rect2(box.position, Vector2(box.size.x * filled, box.size.y)),
			WAITING if _ship.energy_waiting() else CHARGING,
		)

	# Notched at the cost of a shot, so what the pilot reads off the bar is
	# how many they have left.
	var cost: float = shot_cost()
	if cost > 0.0:
		var notches: int = int(capacity / cost)
		if notches <= MAX_NOTCHES:
			for i: int in range(1, notches + 1):
				var x: float = box.position.x + box.size.x * (cost * float(i) / capacity)
				if x < box.end.x - 0.5:
					_canvas.draw_line(
						Vector2(x, box.position.y), Vector2(x, box.end.y), NOTCH, 1.0
					)

	var edge: Color = REFUSED if _refused_for > 0.0 else FRAME
	_canvas.draw_rect(box, edge, false, 1.0)
	if _refused_for > 0.0:
		# A second, wider frame: at seven pixels tall a colour change alone is
		# easy to miss in a firefight.
		_canvas.draw_rect(box.grow(2.0), Color(REFUSED, _refused_for / REFUSAL_FLASH), false, 1.0)
