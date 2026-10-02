class_name SpriteStrip
extends Resource
## Jeden obrazek -- albo kilka klatek jednego -- i miejsce, w ktorym siedzi
## jego punkt zaczepienia.
##
## The frames are columns of one file, which is the whole format: a strip,
## not a folder of numbered PNGs and not a SpriteFrames per animation. One
## file per animation means the import rule is a rule rather than a decision
## per asset, and it means a still picture and a six-frame flame are the same
## kind of thing with `frames` set to one or six.

## The strip. Width must divide evenly by `frames`.
@export var texture: Texture2D = null

## How many columns the file holds.
@export var frames: int = 1

## Where the thing's own origin sits inside a frame, in texels from the
## frame's top-left corner.
##
## Stored rather than assumed to be the centre, because almost nothing is
## centred on its origin: a nozzle hangs aft of its mount, a gun stands
## forward of its hardpoint, a plume starts at the nozzle's lip. Getting this
## wrong does not look like a wrong pivot, it looks like the part is bolted on
## crooked, which is much harder to spot.
@export var pivot: Vector2 = Vector2.ZERO

## Frames per second **when whatever drives this is at full**.
##
## Not a contradiction of the rule that the rate is data: what reaches the
## screen is this times the fraction the driver hands over, so a drive at a
## quarter throttle flickers at a quarter of the speed. What this number is
## for is that a four-frame plume and a twelve-frame beacon do not run at the
## same speed at full either, and that difference belongs to the picture.
@export var full_rate: float = 12.0

## How far past the pivot, along the frame's own down, whatever hangs off
## this part begins -- in design pixels.
##
## A nozzle's exit plane, in other words, and zero on anything nothing hangs
## off. Stated by the part rather than measured off its pixels: the skin
## would otherwise have to guess where a bell ends from where its opaque
## texels stop, and the first piece of real art with a flared lip or a soft
## edge would quietly move every flame on the ship.
@export var exit: float = 0.0

## Whether this is drawn additively. True for anything that makes its own
## light -- flames, beams, muzzle flashes -- which is also the set of things
## that must not be darkened by the night side (see ShipSkin).
@export var additive: bool = false

## True for world art authored at Art.FACTOR, false for interface art
## authored 1:1. Decides the scale and the filter, so a strip cannot be
## displayed at the wrong one by accident.
@export var in_world: bool = true


func is_valid() -> bool:
	return texture != null and frames >= 1


## Size of one frame, in texels.
func frame_size() -> Vector2i:
	if not is_valid():
		return Vector2i.ZERO
	return Vector2i(texture.get_width() / frames, texture.get_height())


## Size of one frame in design pixels, which is what it will measure on the
## 640x360 grid.
func design_size() -> Vector2:
	var texels: Vector2i = frame_size()
	var factor: float = float(Art.FACTOR) if in_world else 1.0
	return Vector2(texels) / factor


## Whether the pivot is actually inside the frame. Checked by a test rather
## than trusted: a pivot outside its frame draws the part somewhere near the
## ship instead of on it, and reads as a physics bug.
func pivot_is_sane() -> bool:
	var texels: Vector2i = frame_size()
	return (
		pivot.x >= 0.0 and pivot.y >= 0.0
		and pivot.x <= float(texels.x) and pivot.y <= float(texels.y)
	)
