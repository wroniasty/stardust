@tool
class_name HullView
extends Control
## Wspolny widok: wspolrzedne kadluba na ekran, siatka, kadrowanie.
##
## Two docks draw a hull -- the one that edits its shape and the one that
## shows what a preset bolts onto it -- and both need the same answer to
## "where on screen is this point". That is all this is: the transform,
## the grid it implies, and the framing. What is drawn through it, and
## whether anything can be dragged, is the subclass's business.
##
## Extracted rather than copied because the two had already diverged
## once: a `Control` does not clip what `_draw` puts outside its own
## rect, and a canvas that forgot `clip_contents` painted a hull across
## the whole editor window.

const BACKDROP: Color = Color(0.09, 0.10, 0.13)
const GRID_FAINT: Color = Color(1.0, 1.0, 1.0, 0.05)
const GRID_STRONG: Color = Color(1.0, 1.0, 1.0, 0.11)
const AXIS: Color = Color(1.0, 1.0, 1.0, 0.22)

const MIN_ZOOM: float = 2.0
const MAX_ZOOM: float = 80.0

var _zoom: float = 11.0
var _origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	# A `Control` does not clip what `_draw` puts outside its own rect,
	# and this draws at hull coordinates times a zoom: a hull opened at
	# the wrong zoom painted its outline, its handles and its grid across
	# the file list, the inspector and the dock beside it.
	clip_contents = true
	resized.connect(_on_view_resized)


func _on_view_resized() -> void:
	# Keep following the size until somebody takes the view over, so a
	# dock laid out at one height and then given its real one still shows
	# the hull.
	if not view_is_held():
		fit()
	queue_redraw()


## Whether somebody has taken the view over by hand. A read-only preview
## never does; an editable canvas does the moment it is panned or zoomed.
func view_is_held() -> bool:
	return false


## What the view has to fit on screen, in hull coordinates. The subclass
## says what its picture is made of.
func framed_points() -> Array[Vector2]:
	return []


func to_screen(at: Vector2) -> Vector2:
	return _origin + at * _zoom


func to_hull(at: Vector2) -> Vector2:
	return (at - _origin) / _zoom


## Frame everything, with a margin.
func fit() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	var points: Array[Vector2] = framed_points()
	var box: Rect2 = Rect2(Vector2(-10.0, -10.0), Vector2(20.0, 20.0))
	if not points.is_empty():
		box = Rect2(points[0], Vector2.ZERO)
		for at: Vector2 in points:
			box = box.expand(at)
	box = box.grow(3.0)
	var span: Vector2 = box.size.max(Vector2(1.0, 1.0))
	_zoom = clampf(minf(size.x / span.x, size.y / span.y), MIN_ZOOM, MAX_ZOOM)
	_origin = size * 0.5 - box.get_center() * _zoom
	queue_redraw()


## Zoom about a point on screen, keeping what is under it where it is.
func zoom_about(at: Vector2, by: float) -> void:
	var before: Vector2 = to_hull(at)
	_zoom = clampf(_zoom * by, MIN_ZOOM, MAX_ZOOM)
	_origin = at - before * _zoom
	queue_redraw()


func pan_by(delta: Vector2) -> void:
	_origin += delta
	queue_redraw()


## Hull units, not screen pixels: a grid whose meaning changes as you
## zoom tells you nothing about the numbers you are typing into a .tres.
func draw_grid() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	var step: float = 1.0
	while step * _zoom < 7.0:
		step *= 5.0
	var top_left: Vector2 = to_hull(Vector2.ZERO)
	var bottom_right: Vector2 = to_hull(size)
	var x: float = floorf(top_left.x / step) * step
	while x <= bottom_right.x:
		var strong: bool = is_zero_approx(fmod(absf(x), step * 5.0))
		var column: float = to_screen(Vector2(x, 0.0)).x
		draw_line(
			Vector2(column, 0.0), Vector2(column, size.y),
			GRID_STRONG if strong else GRID_FAINT, 1.0,
		)
		x += step
	var y: float = floorf(top_left.y / step) * step
	while y <= bottom_right.y:
		var strong_row: bool = is_zero_approx(fmod(absf(y), step * 5.0))
		var row: float = to_screen(Vector2(0.0, y)).y
		draw_line(
			Vector2(0.0, row), Vector2(size.x, row),
			GRID_STRONG if strong_row else GRID_FAINT, 1.0,
		)
		y += step
	var zero: Vector2 = to_screen(Vector2.ZERO)
	draw_line(Vector2(zero.x, 0.0), Vector2(zero.x, size.y), AXIS, 1.0)
	draw_line(Vector2(0.0, zero.y), Vector2(size.x, zero.y), AXIS, 1.0)
