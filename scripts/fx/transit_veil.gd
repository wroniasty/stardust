class_name TransitVeil
extends CanvasLayer
## The veil over a jump: what hides one system being swapped for another.
##
## The only effect in the game with a job rather than a look. The old
## system is freed and the next one built halfway through the crossing,
## and this is what is over the screen while that happens: at the middle
## it has to be opaque enough that a world vanishing and another
## appearing reads as one event.
##
## So the shape of the curve is the design, not a taste. It rises while
## the drive spools, so the pilot can see the thing charging; it is at
## full across the swap and stays there for the rest of the transit; and
## it clears on arrival, which is why arrival is a state rather than an
## instant.

## How bright it gets while the drive is only charging. Visible, and
## nowhere near enough to fly blind through -- a pilot can still see what
## is about to hit them and cancel.
const CHARGE_PEAK: float = 0.22

## Where in the transit the veil reaches full. The swap is at the middle
## (`JumpController.SWAP_AT`), so this has to be at or before it.
const FULL_BY: float = 0.5

var _jump: JumpController = null
var _canvas: ColorRect = null


func _ready() -> void:
	# Above the world and the HUDs, below the panels that pause the game:
	# a jump cannot start while the editor is open, but the map can be up
	# when one lands.
	layer = 15
	_canvas = ColorRect.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.color = Color(1.0, 1.0, 1.0, 1.0)
	var paint: ShaderMaterial = ShaderMaterial.new()
	paint.shader = load("res://shaders/transit.gdshader") as Shader
	_canvas.material = paint
	add_child(_canvas)
	_canvas.hide()


func bind(jump: JumpController) -> void:
	_jump = jump


## How strong the effect should be right now, 0..1.
##
## Public and ungated, like every other presentation decision in this
## project: the gate belongs to the tick, and a curve that could only be
## read with a window open is a curve with no tests. Sixth time.
func strength() -> float:
	if _jump == null:
		return 0.0
	var along: float = _jump.progress()
	match _jump.phase:
		JumpController.Phase.CHARGING:
			return CHARGE_PEAK * along
		JumpController.Phase.TRANSIT:
			# Full by the swap and held there. Falling away afterwards
			# would start clearing the screen while the new system is
			# still coming up, which is the one thing this is for.
			return lerpf(CHARGE_PEAK, 1.0, clampf(along / FULL_BY, 0.0, 1.0))
		JumpController.Phase.ARRIVAL:
			return 1.0 - along
		_:
			return 0.0


func _process(_delta: float) -> void:
	if _canvas == null:
		return
	var how: float = strength() if Presentation.is_on() else 0.0
	# Hidden rather than drawn at zero: the shader samples the screen
	# every frame it is visible, and a full-screen read that resolves to
	# "exactly what was there" is a cost paid for nothing.
	_canvas.visible = how > 0.002
	if _canvas.visible:
		(_canvas.material as ShaderMaterial).set_shader_parameter("strength", how)
