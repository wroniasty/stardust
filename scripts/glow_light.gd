class_name GlowLight
extends PointLight2D
## A light that something in the world casts: a tracer, a burning engine,
## the flash of an explosion.
##
## These are the lights worth having in a game with no normal maps. A 2D
## light has no idea which way a surface faces, so it cannot make a
## terminator -- that is why the day and night sides are shaded from the
## star's direction instead, in the planet's shaders and in
## `GravityWell.daylight_at`. What a light *can* do is put a pool of
## brightness somewhere, and a pool of brightness is exactly what a
## projectile crossing a dark landscape should leave behind it.
##
## The texture is built here rather than imported, for the same reason
## nothing else in this project is a sprite: a radial falloff is four
## lines of gradient and an asset is a file to keep in step.

## Side of the generated texture, in texels. Small on purpose -- it is a
## smooth blob stretched over hundreds of pixels, so resolution buys
## nothing and the filter smooths what is left.
const TEXTURE_SIZE: int = 64

## How sharply the pool falls off. Above one the middle stays bright and
## the edge gives up quickly, which is what a small intense source looks
## like; at one it is a flat ramp and reads as fog.
const FALLOFF: float = 2.2

static var _shared: Texture2D = null


## The radial falloff every glow uses, made once.
static func blob() -> Texture2D:
	if _shared != null:
		return _shared
	var image: Image = Image.create_empty(
		TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBAF
	)
	var middle: float = float(TEXTURE_SIZE - 1) * 0.5
	for y: int in range(TEXTURE_SIZE):
		for x: int in range(TEXTURE_SIZE):
			var away: float = Vector2(float(x) - middle, float(y) - middle).length() / middle
			var strength: float = pow(clampf(1.0 - away, 0.0, 1.0), FALLOFF)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, strength))
	_shared = ImageTexture.create_from_image(image)
	return _shared


## Makes a light of `reach` pixels in `colour`, ready to be added as a
## child of whatever is doing the glowing.
static func make(colour: Color, reach: float, strength: float = 1.0) -> GlowLight:
	var light: GlowLight = GlowLight.new()
	light.texture = blob()
	light.color = colour
	light.energy = strength
	light.reach(reach)
	# Added, not mixed: a light in space is something arriving on top of
	# what is already there, and mixing would wash the colour out of
	# whatever it falls on instead of brightening it.
	light.blend_mode = Light2D.BLEND_MODE_ADD
	return light


## Sets how far the pool reaches, in world pixels from the middle.
func reach(pixels: float) -> void:
	texture_scale = maxf(pixels, 1.0) * 2.0 / float(TEXTURE_SIZE)
