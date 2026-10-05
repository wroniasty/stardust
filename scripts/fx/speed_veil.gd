class_name SpeedVeil
extends CanvasLayer
## Rush: blur and streaks, when the ship is fast and there is air to carry them.
##
## The sibling of `TransitVeil` and deliberately the opposite kind of
## thing. A jump is an event that takes the screen away for two
## seconds; this is a **condition** the pilot flies in, sometimes for
## minutes, so it has to be readable through. That one difference
## decides everything about it: subtle at the top end, nothing at the
## centre of the frame, and gone the moment either of its two causes
## does.
##
## **Air times speed**, not speed. Three hundred metres a second in
## vacuum is a Tuesday; the same in thick air is the thing that heats
## the hull and tears the trails off it. Using speed alone would put a
## blur on a ship coasting between planets, where there is nothing to
## rush past and nothing to feel.

## Air-times-speed at which the effect is as strong as it gets.
##
## The same product the drag, the hull heating and the condensation
## trails already read, so what a pilot sees is what is acting on
## them. Measured against `Contrail.reference_flow`, which is the one
## that was tuned first.
const REFERENCE_FLOW: float = 260.0

## How strong it is allowed to get. Well under one: the jump veil may
## take the screen, this may not.
const STRONGEST: float = 0.55

## Seconds for it to follow the flow. Slow enough that a gust of drag
## does not strobe, fast enough that pulling up out of a dive clears
## the screen while it still matters.
const RESPONSE: float = 0.22

## Below this nothing is drawn at all, and the layer is hidden rather
## than running at zero: a full-screen read that resolves to exactly
## what was there is a cost paid for nothing.
const FAINTEST: float = 0.01

@export var ship_path: NodePath

var _ship: Ship = null
var _canvas: ColorRect = null
var _strength: float = 0.0


func _ready() -> void:
	# Under the HUDs and under the jump veil. A pilot reading the
	# altimeter on short finals must not read it through this.
	layer = 8
	_canvas = ColorRect.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.color = Color(1.0, 1.0, 1.0, 1.0)
	var paint: ShaderMaterial = ShaderMaterial.new()
	paint.shader = load("res://shaders/rush.gdshader") as Shader
	_canvas.material = paint
	add_child(_canvas)
	_canvas.hide()
	_ship = get_node_or_null(ship_path) as Ship


## How hard the air is going past, 0..1, before smoothing.
##
## Ungated and public, like every other presentation decision here:
## the gate belongs in the tick, and a curve that could only be read
## with a window open is a curve with no tests.
func wanted() -> float:
	if _ship == null or not is_instance_valid(_ship):
		return 0.0
	# Through the air, not through the system. A ship parked on a turning
	# planet is carried along with the air it is sitting in, and a screen
	# that streaked while the legs were down was reading the carriage.
	var flow: float = _ship.air_density * _ship.airspeed()
	return clampf(flow / REFERENCE_FLOW, 0.0, 1.0) * STRONGEST


## How strong it is right now, after smoothing.
func strength() -> float:
	return _strength


## Which way the view is travelling, in screen space.
##
## Through the canvas transform rather than worked out by hand, so the
## camera's rotation is carried for free -- the approach camera turns
## the whole view on short finals, and a smear that ignored that would
## run sideways across the screen at exactly the moment the pilot is
## trying to read it.
func drift(to_screen: Transform2D) -> Vector2:
	if _ship == null or not is_instance_valid(_ship):
		return Vector2.UP
	var going: Vector2 = to_screen.basis_xform(_ship.air_velocity())
	if going.length_squared() < 0.0001:
		return Vector2.UP
	# Screen space has y downwards and the shader works in UV, which
	# agrees; no flip is needed and adding one was the first bug here.
	return going.normalized()


func _process(delta: float) -> void:
	if _canvas == null:
		return
	var target: float = wanted() if Presentation.is_on() else 0.0
	_strength = lerpf(_strength, target, clampf(delta / RESPONSE, 0.0, 1.0))
	_canvas.visible = _strength > FAINTEST
	if not _canvas.visible:
		return
	var paint: ShaderMaterial = _canvas.material
	paint.set_shader_parameter("strength", _strength)
	paint.set_shader_parameter("drift", drift(get_viewport().get_canvas_transform()))
