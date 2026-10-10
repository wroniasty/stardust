@tool
class_name SpriteStrip
extends Resource
## Jeden obrazek -- albo kilka klatek jednego -- i miejsce, w ktorym siedzi
## jego punkt zaczepienia.
##
## Columns are frames and rows are animations, which is the whole format:
## a sheet, not a folder of numbered PNGs and not a SpriteFrames per
## animation. One file per **part** means the import rule is a rule rather
## than a decision per asset, and it means a still picture and a six-frame
## flame are the same kind of thing with `frames` set to one or six.
##
## It was one file per animation until a part needed two of them -- a gun
## that is idle and firing, a leg that is stowed and cycling. Rows extend
## the format in the direction it already pointed rather than adding a
## second kind of thing beside it, and a file with one row is exactly what
## it was: `rows` at one and no clips is today's behaviour, number for
## number.

## The strip. Width must divide evenly by `frames`.
@export var texture: Texture2D = null

## How many columns the file holds, which is the length of a row.
@export var frames: int = 1

## How many rows, which is how many animations.
@export var rows: int = 1

## The animations, by name. Empty means the whole sheet is one
## animation, which is what every file that predates this has.
##
## A clip that names no row and no length gets row zero and the full
## width, so adding a second animation to a part costs one entry rather
## than two.
@export var clips: Array[StripClip] = []

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
	return texture != null and frames >= 1 and rows >= 1


## The named animation, or the whole sheet when there is none.
##
## Never null: a caller that asks for a clip a part does not have gets
## the part's default rather than a crash, because a look table and a
## driver are written by different people and a missing name should
## show as "it did not animate" and not as a stopped game.
func clip(named: StringName = &"") -> StripClip:
	for one: StripClip in clips:
		if one != null and (named == &"" or one.name == named):
			return one
	return StripClip.new()


## Whether this part actually has the named animation, which is the
## question `clip` deliberately does not answer.
func has_clip(named: StringName) -> bool:
	for one: StripClip in clips:
		if one != null and one.name == named:
			return true
	return false


## How many frames that clip runs for: its own length, or the row's.
func frames_of(one: StripClip) -> int:
	if one == null or one.frames <= 0:
		return frames
	return mini(one.frames, frames)


## And how fast at full drive: the clip's figure, or the part's.
func rate_of(one: StripClip) -> float:
	if one == null or one.rate <= 0.0:
		return full_rate
	return one.rate


## Size of one frame, in texels.
func frame_size() -> Vector2i:
	if not is_valid():
		return Vector2i.ZERO
	return Vector2i(texture.get_width() / frames, texture.get_height() / rows)


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
