class_name Art
extends RefCounted
## Gdzie mieszka decyzja o rozdzielczości: ile texeli przypada na jeden piksel
## układu, i czym to jest filtrowane po drodze na ekran.
##
## Decision record, because this one is easy to get wrong twice.
##
## 640x360 stays the **layout** unit: the HUD is written for it, UI_STYLE.md
## section 2 is written for it, and nothing below changes that. What it stops
## being is a pixel budget for textures, and the reason is the stretch mode
## the project already uses. `canvas_items` renders at the window's own
## resolution -- the docs say it plainly, "there is no longer a 1:1
## correspondence between sprite pixels and screen pixels" -- so a texture
## with more texels in it genuinely shows more detail. A 24x32 ship gets 72x96
## real pixels at 1080p and has 24x32 to fill them with.
##
## The second reason is the one that settles it. The ship rotates freely
## through 360 degrees and we are not pre-rendering rotation frames, so there
## is no angle at which a low-resolution sprite sits on the pixel grid. It is
## resampled every frame whatever we do; the only question is whether it is
## resampled from enough material.
##
## Hence: world art is drawn at FACTOR times the layout size and displayed at
## 1/FACTOR. Three, because 1080p is exactly three times 640x360, so on the
## commonest screen one texel is one pixel and nothing is resampled at all.
##
## And hence the filter split below, which is the part that keeps UI_STYLE
## honest rather than breaking it.

## Texels per design pixel, for anything that lives in the world.
##
## One number, and reversing this decision is changing it: the placeholder
## generator reads it, the sprites read it, the gallery reads it.
const FACTOR: int = 3

## What a world sprite's `scale` has to be for one design pixel to come out
## one design pixel.
const WORLD_SCALE: float = 1.0 / float(FACTOR)

## How world art is filtered, and why it is not Nearest.
##
## Measured, not assumed. The camera runs `ShipCamera.ZOOM_LEVELS` 1.7 down to
## 0.55, multiplied by the speed term down to 0.7, so the camera alone spans
## 1.7 .. 0.385. The window multiplies that by 2 at 720p and 6 at 4K. One
## texel therefore lands on anything from a quarter of a screen pixel to three
## and a half of them -- a 13x range, inside one session, on one sprite.
##
## Nearest has no answer at either end of that: it drops texels on the way
## down and makes uneven blocks on the way up, and on a hull that is rotating
## it does both while crawling. Mipmaps are what the minification half needs
## and there is no pixel grid left to protect on the magnification half.
const WORLD_FILTER: CanvasItem.TextureFilter = (
	CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
)

## How interface art is filtered, and why it is still Nearest.
##
## The HUD never rotates, never zooms and sits at scale 1.0 by the grid law.
## It is the one place where a design pixel really is a pixel, so it is drawn
## at 1:1, filtered Nearest, and UI_STYLE.md section 2 goes on meaning exactly
## what it says. The contradiction that looked like it was in the grid law was
## really the world borrowing a rule written for the panel.
const UI_FILTER: CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_NEAREST

## Empty texels round every world sprite, which is one design pixel.
##
## Not zero. A sprite with its silhouette hard against the edge of its frame
## has nowhere for WORLD_FILTER to fade into, so it comes out with a bright
## rim on two sides -- and that artefact reads as a drawing mistake rather
## than as a packing one. Here rather than in the generator, because the skin
## has to know it too: what sits a texel inside the frame is where a part
## actually ends.
const MARGIN: int = FACTOR

## Where the two kinds of art live, kept apart on disk because they are
## authored at different sizes and a file in the wrong folder is a file at the
## wrong resolution.
const WORLD_DIR: String = "res://assets/art/world"
const UI_DIR: String = "res://assets/art/ui"
