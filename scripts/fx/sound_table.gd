@tool
class_name SoundTable
extends Resource
## Jak brzmi rzecz — wyliczone z tego, czym ta rzecz jest.
##
## `LookTable` for the ear, deliberately the same file with the same
## four ways of answering, because the question is the same one. A
## bigger engine gets a bigger noise for the reason it gets a bigger
## bell: the sound is a readout, not decoration, and two statistically
## identical engines that sound different for no reason are noise a
## pilot stops listening to.
##
## The table lives in the presentation layer and reads the item, never
## the other way round. **No module resource carries a sample**, the
## same way none carries a texture, so the loot generator needs to know
## nothing about any of this -- a rolled engine gets the right loop
## because its `type` and its affixes are what choose it.
##
## That symmetry is the point. The sound layer was built first as a
## flat array indexed by the type enum, which is the under-built half
## of this: an `overbored` drive looked different and sounded
## identical, because the picture went through a table and the noise
## did not.

## Property read off the subject to pick a variant by size. Empty when
## this table does not select that way. An enum serves as well as a
## measurement: `type` is an int and the thresholds are 0, 1, 2.
@export var stat: StringName = &""

## Ascending. Variant i applies from thresholds[i] up to thresholds[i + 1].
@export var thresholds: PackedFloat32Array = PackedFloat32Array()

## One per threshold, same order.
@export var variants: Array[SoundStrip] = []

## Exact lookups, for things named rather than measured: an event, a
## kind, a key the caller passes in. Beats the stat when it hits.
@export var by_key: Dictionary = {}

## What an affix sounds like, because the affix explains what is being
## heard: "overbored" is a bigger bell and should be a bigger noise.
##
## First match in **this table's** order wins, not the item's, for the
## same reason it does in `LookTable`: an item's affix list is in roll
## order, which ranks nothing.
@export var by_affix: Dictionary = {}

## Used when nothing else matches. A table with only this is a table
## for a thing that makes exactly one noise, which is most of them.
@export var fallback: SoundStrip = null


## The sound for `subject`, or null when this table has nothing to say.
##
## Order is: the key the caller named, then an affix, then the
## measurement, then the fallback. Narrowest answer first, so a named
## exception is never overruled by a threshold that happens to cover
## it.
func pick(subject: Object = null, key: StringName = &"") -> SoundStrip:
	if key != &"" and by_key.has(key):
		return by_key[key] as SoundStrip

	if subject != null and not by_affix.is_empty():
		var worn: Array = _affixes_of(subject)
		for affix: Variant in by_affix:
			if worn.has(affix):
				return by_affix[affix] as SoundStrip

	if subject != null and stat != &"" and not variants.is_empty():
		var value: Variant = subject.get(String(stat))
		if value != null:
			return by_value(float(value))

	return fallback


## The variant a bare number selects, with no item to read it off.
func by_value(value: float) -> SoundStrip:
	if variants.is_empty():
		return fallback
	var chosen: int = 0
	for i: int in range(mini(thresholds.size(), variants.size())):
		if value >= thresholds[i]:
			chosen = i
	return variants[chosen]


## Every strip this table can hand out, for a test to walk.
func every_strip() -> Array[SoundStrip]:
	var out: Array[SoundStrip] = []
	for strip: SoundStrip in variants:
		out.append(strip)
	for key: Variant in by_key:
		out.append(by_key[key] as SoundStrip)
	for affix: Variant in by_affix:
		out.append(by_affix[affix] as SoundStrip)
	if fallback != null:
		out.append(fallback)
	return out


## Affix names worn by `subject`, as a plain array.
func _affixes_of(subject: Object) -> Array:
	if not ("affixes" in subject):
		return []
	var worn: Variant = subject.get("affixes")
	return worn if worn is Array else []
