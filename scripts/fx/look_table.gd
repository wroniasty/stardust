@tool
class_name LookTable
extends Resource
## Ktory obrazek dostaje rzecz -- wyliczony z tego, czym ta rzecz jest.
##
## This is ASSETLIST.md section "Wyglad wynika z cech" as a file. Nothing here
## rolls a die. A stronger engine gets a bigger flame because it is stronger,
## the same way a blue star is blue because it is heavy: the picture is a
## readout. Two statistically identical engines that look different for no
## reason are noise, and a pilot stops reading the screen after an hour of it.
##
## The table lives in the presentation layer and reads the item, never the
## other way round. No module resource carries a texture, so the loot
## generator needs to know nothing about any of this -- a rolled engine gets
## the right nozzle because its `type` and `max_thrust` are what choose it.

## Property read off the subject to pick a variant by size. Empty when this
## table does not select that way.
##
## An enum works here as well as a measurement does: `type` is an int and the
## thresholds are 0, 1, 2. That is deliberate -- "pick by a number on the
## item" covers both bindings with one mechanism.
@export var stat: StringName = &""

## Ascending. Variant i applies from thresholds[i] up to thresholds[i + 1].
@export var thresholds: PackedFloat32Array = PackedFloat32Array()

## One per threshold, same order.
@export var variants: Array[SpriteStrip] = []

## Exact lookups, for things named rather than measured: a hull, a kind of
## module, a key the caller passes in. Beats the stat when it hits.
@export var by_key: Dictionary = {}

## Looks an affix brings with it, because the affix explains what is being
## seen: "steerable" gets a nozzle on a joint, "overbored" a bigger bell.
##
## First match in **this table's** order wins, not the item's. Once affixes
## carry weights (M3.5) this becomes "the rarest one wins"; until then the
## author's order is the only ranking there is, and an item's affix list is in
## roll order, which ranks nothing.
@export var by_affix: Dictionary = {}

## Used when nothing else matches. A table with only this is a table for a
## part that has exactly one look, which is most of them.
@export var fallback: SpriteStrip = null


## The picture for `subject`, or null when this table has nothing to say.
##
## Order is: the key the caller named, then an affix, then the measurement,
## then the fallback. Narrowest answer first, so a named exception is never
## overruled by a threshold that happens to cover it.
func pick(subject: Object = null, key: StringName = &"") -> SpriteStrip:
	if key != &"" and by_key.has(key):
		return by_key[key] as SpriteStrip

	if subject != null and not by_affix.is_empty():
		var worn: Array = _affixes_of(subject)
		for affix: Variant in by_affix:
			if worn.has(affix):
				return by_affix[affix] as SpriteStrip

	if subject != null and stat != &"" and not variants.is_empty():
		var value: Variant = subject.get(String(stat))
		if value != null:
			return by_value(float(value))

	return fallback


## The variant a bare number selects, with no item to read it off.
func by_value(value: float) -> SpriteStrip:
	if variants.is_empty():
		return fallback
	var chosen: int = 0
	for i: int in range(mini(thresholds.size(), variants.size())):
		if value >= thresholds[i]:
			chosen = i
	return variants[chosen]


## Every strip this table can hand out, for a test to walk.
func every_strip() -> Array[SpriteStrip]:
	var out: Array[SpriteStrip] = []
	for strip: SpriteStrip in variants:
		out.append(strip)
	for key: Variant in by_key:
		out.append(by_key[key] as SpriteStrip)
	for affix: Variant in by_affix:
		out.append(by_affix[affix] as SpriteStrip)
	if fallback != null:
		out.append(fallback)
	return out


## Affix names worn by `subject`, as a plain array.
##
## Guarded rather than assumed, because a table can be handed any
## subject at all -- including none.
##
## This used to say that only `WeaponData` carried affixes and that
## every engine entry in `by_affix` was therefore inert. That stopped
## being true in M3.5, when `affixes` moved onto `ModuleData` and the
## engine generator started keeping its roll; the `steerable` nozzle
## has been live since. `SoundTable` leans on the same thing to give a
## `dynamo` engine its own loop.
func _affixes_of(subject: Object) -> Array:
	if not ("affixes" in subject):
		return []
	var worn: Variant = subject.get("affixes")
	return worn if worn is Array else []
