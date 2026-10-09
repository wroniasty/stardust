class_name ShipPreset
extends Resource
## Gotowy statek jako zasob: kadlub, silniki, dziala i zatoki na moduly.
##
## These were a table in `ShipFitout.all()` -- seven dictionaries of
## dictionaries, with engines and weapons named by short strings resolved
## through two more tables. That table was the last thing about a ship
## that could only be changed by editing GDScript, which is the same
## complaint that moved hulls into `resources/hulls` and the torque jets
## into the hulls.
##
## What a preset is, now that it is all four parts: a hull, which engine
## sits in which of the hull's places, which guns it carries, and how many
## module bays it has and how big. The last of those used to live in
## `ship.tscn` as five hand-placed nodes, which meant the interceptor
## described as "a hold worth nothing" had exactly the freighter's module
## capacity and no way to say otherwise.
##
## Still sandbox presets rather than a catalogue the game draws from. What
## they are for is finding out what the control model does with a shape it
## was not tuned on: the gimbal-only ship is the one that found the
## control groups could not count a gimbal at all.

## Stable, file-safe name. What a save or a setting stores, so renaming
## the display name does not change which ship a player comes back to.
@export var id: StringName = &""

## What the pilot is shown, in the menu and the refit list.
@export var display_name: String = "ship"

## The sentence under the name. What this ship is *for*, not a repeat of
## its numbers.
##
## Plain text, with one exception worth knowing about: `engine_scale`
## appends its own sentence, computed from the figure the engines are
## actually built with. A preset advertised by hand as "50% heavier" at a
## thrust factor of 1.75 is 52.5% heavier, and that sentence was wrong in
## the table for exactly as long as it was written out separately.
@export_multiline var blurb: String = ""

## The shape, as the resource rather than as a name. A preset cannot
## name a hull that is not there.
@export var hull: HullData = null

## Which engine goes in which of the hull's places.
@export var mounts: Array[MountFit] = []

## The guns it carries, in order. The hull says where the hardpoints are
## and these fill them front first, then the sides, then astern -- so this
## is weapons and nothing else. It used to carry a hardpoint name and a
## position as well, neither of which was ever read.
@export var guns: Array[WeaponData] = []

## How many module bays, how big, and what is in them.
@export var bays: Array[BayFit] = []

## Where this sits in the menu.
##
## A directory listing is alphabetical, and the first entry is the one a
## new pilot is offered: without this, "bare hull" -- a ship built with
## one engine on purpose, so the configuration report has something to
## complain about -- would head the list. The authored order was a fact
## about the old table that a filename cannot carry.
@export var order: int = 100

## Multiplies every mount's own scale.
##
## One number for "the same layout, stronger engines", which is what the
## stronger-jets preset is. Here rather than copied into eight mounts
## because the blurb is computed from it: one figure driving both the
## engines and the sentence about them is the only arrangement in which
## they cannot disagree.
@export var engine_scale: float = 1.0


## The sentence shown with this ship, including the part computed from
## `engine_scale` when it is not one.
func caption() -> String:
	if is_equal_approx(engine_scale, 1.0):
		return blurb
	var scaled: String = ShipFitout.scaled_blurb(engine_scale)
	return scaled if blurb.is_empty() else "%s -- %s" % [blurb, scaled]


## How much engine this mount actually gets: its own scale and the
## preset's together.
func scale_of(fit: MountFit) -> float:
	return fit.scale * engine_scale
