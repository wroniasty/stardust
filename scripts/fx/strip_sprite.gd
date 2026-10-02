class_name StripSprite
extends Sprite2D
## Sprite pokazujacy jedna klatke paska -- przesuwana przez tego, kto go
## napedza, nie przez wlasny zegar.
##
## An AnimatedSprite2D would do this with SpriteFrames, and was not used for
## two reasons. SpriteFrames stores the frame rate, and ASSETLIST.md says the
## rate is a reading off the ship rather than a property of the file -- an fps
## in the resource that every caller then overrides is a number that has to be
## set and means nothing. And every AnimatedSprite2D runs its own timer, where
## this runs none: the skin that owns these ticks all of them from the one
## `_process` it already has.

var strip: SpriteStrip = null

## Frames per second right now. Zero holds the current frame, which is what a
## still picture and a shut-down engine have in common.
var rate: float = 0.0

var _phase: float = 0.0


## Shows `new_strip`, setting the scale, the filter and the pivot from it.
##
## Everything about how a strip is displayed comes off the strip, so there is
## no second place where a world sprite could be given the interface filter or
## left at scale one. That mistake does not error; it just makes one object in
## the scene three times too big.
func show_strip(new_strip: SpriteStrip) -> void:
	strip = new_strip
	if new_strip == null or not new_strip.is_valid():
		texture = null
		visible = false
		return
	texture = new_strip.texture
	hframes = maxi(new_strip.frames, 1)
	frame = 0
	_phase = 0.0
	centered = false
	offset = -new_strip.pivot
	scale = Vector2.ONE * (Art.WORLD_SCALE if new_strip.in_world else 1.0)
	texture_filter = Art.WORLD_FILTER if new_strip.in_world else Art.UI_FILTER
	# Additive through the material rather than through a modulate: a flame
	# has to add light to what is behind it, and a bright colour over a dark
	# background is not the same thing as light added to it.
	if new_strip.additive:
		var burn: CanvasItemMaterial = CanvasItemMaterial.new()
		burn.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = burn
	else:
		material = null
	visible = true


## Runs the animation on for `delta` at the rate that was last set.
##
## Called by the driver, not by the engine. A one-frame strip costs the
## branch and nothing else.
func advance(delta: float) -> void:
	if strip == null or strip.frames <= 1 or rate <= 0.0:
		return
	_phase = fposmod(_phase + rate * delta, float(strip.frames))
	frame = int(_phase)


## Points the animation at `fraction` of whatever drives it.
##
## The one place where "the rate is a reading, not a setting" is actually
## implemented: the strip says how fast it runs at full, the caller says how
## full it is, and nothing else gets an opinion.
##
## Not clamped at the top. One is full for most things and the ceiling was
## free, right up against an engine on emergency power -- which is at three,
## and whose flame has to look like it.
func drive(fraction: float) -> void:
	if strip == null:
		return
	rate = strip.full_rate * maxf(fraction, 0.0)
