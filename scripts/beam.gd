class_name Beam
extends Node2D
## A laser shot: the damage lands instantly along a ray, and this is only
## what is left on screen afterwards.
##
## Not a projectile, because nothing travels. Treating it as one would mean a
## round moving faster than the tick it was fired in, which is a lie the
## contact sampling would have to be taught to tolerate. Instead the ray is
## resolved at the trigger and the line fades (IDEAS.md section 4).

## Where it starts and stops, in world space.
var from: Vector2 = Vector2.ZERO
var to: Vector2 = Vector2.ZERO
var colour: Color = Color(1.0, 0.45, 0.35)
var seconds: float = 0.06

var _left: float = 0.0


func _ready() -> void:
	_left = seconds
	top_level = true
	queue_redraw()


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	# Fades over its short life rather than blinking out, so a fast weapon
	# reads as a stutter of light instead of a strobe.
	var fade: float = clampf(_left / maxf(seconds, 0.001), 0.0, 1.0)
	draw_line(to_local(from), to_local(to), Color(colour, fade), 1.0)
	draw_line(to_local(from), to_local(to), Color(Color.WHITE, fade * 0.5), 0.5)
