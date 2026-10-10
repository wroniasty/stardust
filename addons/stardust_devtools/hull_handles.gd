@tool
class_name HullHandles
extends RefCounted
## Co w kadlubie da sie zlapac mysza: jeden rekord na przeciagalny punkt.
##
## The hull editor's model, deliberately kept apart from its drawing and
## from the editor API. Everything here is a pure function of a `HullData`,
## so the smoke test can move a point and then ask the resource where it
## went, rather than open a window. That matters because the parts of a GUI
## tool that rot silently are exactly the parts that touch the game's data
## model (DEVTOOLS.md rule 6).
##
## A handle is a dictionary rather than a class because that is the shape
## the rest of the game passes records in -- `HullData.slots()` returns the
## same kind of thing -- and because it has to survive being copied into an
## undo snapshot.

## Every editable array on a hull, in drawing order: what the resource
## calls it, which `HullData` kind it feeds, and how many entries the rest
## of the game counts on.
##
## `wanted` is a claim, not a limit. The editor will happily add a fifth
## torque jet, because a hull nobody can reshape is the problem this tool
## exists to fix -- but a hull with **fewer** places than a preset names
## leaves a mount homeless, and that is worth saying while the mouse is
## still down rather than at the next smoke test.
const FIELDS: Array[Dictionary] = [
	{
		"field": &"outline", "kind": &"", "caption": "obrys",
		"wanted": 0, "least": 3,
	},
	{
		"field": &"legs", "kind": &"", "caption": "nogi",
		"wanted": 0, "least": 0,
	},
	{
		"field": &"drive_slots", "kind": HullData.SLOT_DRIVE, "caption": "main drive",
		"wanted": HullData.DRIVE_SLOTS, "least": 0,
	},
	{
		"field": &"front_slots", "kind": HullData.SLOT_FRONT, "caption": "dziala przod",
		"wanted": HullData.FRONT_HARDPOINTS, "least": 0,
	},
	{
		"field": &"side_slots", "kind": HullData.SLOT_SIDE, "caption": "dziala burty",
		"wanted": HullData.SIDE_HARDPOINTS, "least": 0,
	},
	{
		"field": &"rear_slots", "kind": HullData.SLOT_REAR, "caption": "dzialo rufa",
		"wanted": HullData.REAR_HARDPOINTS, "least": 0,
	},
	{
		"field": &"torque_slots", "kind": HullData.SLOT_TORQUE, "caption": "torque",
		"wanted": HullData.TORQUE_SLOTS, "least": 0,
	},
	{
		"field": &"strafe_slots", "kind": HullData.SLOT_STRAFE, "caption": "strafe",
		"wanted": HullData.STRAFE_SLOTS, "least": 0,
	},
	{
		"field": &"retro_slots", "kind": HullData.SLOT_RETRO, "caption": "retro",
		"wanted": HullData.RETRO_SLOTS, "least": 0,
	},
]

## The plain fields a hull also carries, copied by `snapshot` so that an
## undo or a revert puts back the whole resource rather than its geometry.
const PLAIN_FIELDS: Array[StringName] = [&"id", &"display_name", &"cargo_capacity"]


## What `FIELDS` says about one array, or an empty dictionary.
static func spec_for(field: StringName) -> Dictionary:
	for entry: Dictionary in FIELDS:
		if entry["field"] == field:
			return entry
	return {}


## Which array feeds a `HullData` kind, so anything keyed by field --
## the palette, the counters -- can be asked about a kind instead.
static func field_for_kind(kind: StringName) -> StringName:
	for entry: Dictionary in FIELDS:
		if entry["kind"] == kind and kind != &"":
			return entry["field"]
	return &""


## What the .tres actually says, as a loose copy nobody can write back
## through by accident.
static func read(hull: HullData, field: StringName) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if field == &"outline":
		for point: Vector2 in hull.outline:
			out.append(point)
		return out
	var got: Variant = hull.get(field)
	if got is Array:
		out.assign(got as Array)
	return out


## What the ship is actually built on: the resource's own list, or the
## frame `default_positions()` derives for a kind the resource says
## nothing about.
static func shown(hull: HullData, field: StringName) -> Array[Vector2]:
	var mine: Array[Vector2] = read(hull, field)
	if not mine.is_empty():
		return mine
	var kind: StringName = spec_for(field).get("kind", &"")
	if kind == &"":
		return mine
	var frame: Array[Vector2] = []
	frame.assign(hull.default_positions().get(kind, []))
	return frame


## Whether this hull declares this array itself, or is flying on the
## derived frame. Drawn ghosted when it is the frame.
static func declares(hull: HullData, field: StringName) -> bool:
	return not read(hull, field).is_empty()


## Put a list back on the hull, typed the way the resource wants it.
##
## `outline` is packed and the rest are typed arrays, and handing a plain
## Array to either loses the type on save, so the conversion lives here
## once instead of at every call site.
static func write(hull: HullData, field: StringName, points: Array[Vector2]) -> void:
	if field == &"outline":
		hull.outline = PackedVector2Array(points)
		return
	var typed: Array[Vector2] = []
	typed.assign(points)
	hull.set(field, typed)


## Every grabbable point on this hull, in drawing order.
##
## Each is `{field, index, at, label, kind, turn, derived}`. `derived`
## marks a point that is not in the file yet: it is what the game would
## use, drawn faint, and the moment anyone drags it the whole kind is
## written down.
##
## The label and the facing are taken from `HullData.slots()` rather than
## worked out again here, which is the whole trick. A torque jet dragged
## across the middle of the bounding box is renamed by the game's own
## rule, under the cursor, and a strafe thruster's arrow crosses to the
## far side because the game says it does -- so the picture cannot
## disagree with the ship that will be built from it. Outline points and
## legs have no such name, so they get their index.
static func of(hull: HullData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in FIELDS:
		var field: StringName = entry["field"]
		var kind: StringName = entry["kind"]
		var points: Array[Vector2] = shown(hull, field)
		# An if rather than a ternary: `x if c else []` is statically a
		# plain Array, and assigning that to `Array[Dictionary]` throws at
		# runtime for every outline point and leg.
		var marks: Array[Dictionary] = []
		if kind != &"":
			marks = hull.slots_of(kind)
		var derived: bool = not declares(hull, field)
		for i: int in range(points.size()):
			var label: String = ""
			var turn: float = 0.0
			if i < marks.size():
				label = String(marks[i]["name"])
				turn = marks[i]["turn"]
			elif kind == &"":
				label = "%s%d" % ["P" if field == &"outline" else "noga ", i + 1]
			out.append({
				"field": field,
				"index": i,
				"at": points[i],
				"label": label,
				"kind": kind,
				"turn": turn,
				"derived": derived,
			})
	return out


## What each point of this array is called on the finished ship.
static func labels(hull: HullData, field: StringName) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for handle: Dictionary in of(hull):
		if handle["field"] == field:
			out.append(handle["label"])
	return out


## Which handle is closest to a point, or -1 when none is within `within`.
##
## Later handles win ties, so the small engines bolted outside the hull
## stay grabbable where they sit on top of an outline vertex.
static func nearest(handles: Array[Dictionary], at: Vector2, within: float) -> int:
	var best: int = -1
	var closest: float = within
	for i: int in range(handles.size()):
		var gap: float = (handles[i]["at"] as Vector2).distance_to(at)
		if gap <= closest:
			closest = gap
			best = i
	return best


## Move one point. Returns false when the index is stale.
##
## Dragging a derived handle writes the whole kind down first, because
## half a frame is not a thing `HullData` can express: `slots()` takes the
## resource's list **or** the default, never a mix. So touching one jet of
## a hull that never declared any turns all four into data -- which is
## what the person doing the dragging meant.
static func move(hull: HullData, field: StringName, index: int, to: Vector2) -> bool:
	var points: Array[Vector2] = shown(hull, field)
	if index < 0 or index >= points.size():
		return false
	points[index] = to
	write(hull, field, points)
	return true


## Add a point, and return where it landed in the array.
static func add(hull: HullData, field: StringName, at: Vector2) -> int:
	var points: Array[Vector2] = shown(hull, field)
	points.append(at)
	write(hull, field, points)
	return points.size() - 1


## Whether a point can go at all, asked before anything is changed so a
## refused removal does not land on the undo stack as a step back to
## where you already are.
static func can_erase(hull: HullData, field: StringName, index: int) -> bool:
	var points: Array[Vector2] = shown(hull, field)
	if index < 0 or index >= points.size():
		return false
	return points.size() > int(spec_for(field).get("least", 0))


## Drop a point. Refuses to take the outline below a triangle, which is
## the one removal that would leave a hull nothing can be computed from.
static func erase(hull: HullData, field: StringName, index: int) -> bool:
	if not can_erase(hull, field, index):
		return false
	var points: Array[Vector2] = shown(hull, field)
	points.remove_at(index)
	write(hull, field, points)
	return true


## Put a point into the outline between two existing ones, so a shape can
## grow detail where it is needed rather than only at the end of the list.
static func insert(hull: HullData, field: StringName, index: int, at: Vector2) -> void:
	var points: Array[Vector2] = shown(hull, field)
	points.insert(clampi(index, 0, points.size()), at)
	write(hull, field, points)


## Which outline edge a point is nearest, named by the vertex it starts
## at, together with how far away it is. `{"edge": int, "gap": float}`.
static func nearest_edge(hull: HullData, at: Vector2) -> Dictionary:
	var points: Array[Vector2] = shown(hull, &"outline")
	var out: Dictionary = {"edge": -1, "gap": INF}
	for i: int in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var gap: float = at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b))
		if gap < float(out["gap"]):
			out = {"edge": i, "gap": gap}
	return out


## How many of each kind this hull offers against how many the game wants,
## with the consequence spelled out.
##
## Each entry is `{field, caption, have, wanted, declared, note}`, where an
## empty note means nothing is wrong. Short of the wanted count a preset's
## named mount has nowhere to go and `ShipFitout.fault_in` will say so; over
## it the extra place is simply unused, which is harmless and worth knowing
## before someone wonders why their fifth jet does nothing.
static func tally(hull: HullData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in FIELDS:
		var field: StringName = entry["field"]
		var have: int = shown(hull, field).size()
		var wanted: int = entry["wanted"]
		var note: String = ""
		if have < int(entry["least"]):
			note = "za malo na wielokat"
		elif wanted > 0 and have < wanted:
			note = "brakuje %d - mount bez miejsca" % (wanted - have)
		elif wanted > 0 and have > wanted:
			note = "%d ponad plan - nieuzywane" % (have - wanted)
		out.append({
			"field": field,
			"caption": entry["caption"],
			"have": have,
			"wanted": wanted,
			"declared": declares(hull, field),
			"note": note,
		})
	return out


## Everything a hull is, as plain values. The one copy mechanism in the
## tool: undo pushes these, revert restores one, and save writes one onto
## the resource the editor actually has loaded.
static func snapshot(hull: HullData) -> Dictionary:
	var out: Dictionary = {}
	for named: StringName in PLAIN_FIELDS:
		out[named] = hull.get(named)
	for entry: Dictionary in FIELDS:
		out[entry["field"]] = read(hull, entry["field"])
	return out


## And the way back. `plain` false restores only the geometry, which is
## what saving does: the dock draws shapes and never shows `display_name`
## or `cargo_capacity`, so it has no business writing them back over
## whatever the inspector did with them while it was open.
static func restore(hull: HullData, snap: Dictionary, plain: bool = true) -> void:
	if plain:
		for named: StringName in PLAIN_FIELDS:
			if snap.has(named):
				hull.set(named, snap[named])
	for entry: Dictionary in FIELDS:
		var field: StringName = entry["field"]
		if not snap.has(field):
			continue
		var points: Array[Vector2] = []
		points.assign(snap[field])
		write(hull, field, points)


## A loose hull carrying the same values, for editing without touching the
## resource the editor has open until someone presses save.
static func copy_of(hull: HullData) -> HullData:
	var out: HullData = HullData.new()
	restore(out, snapshot(hull))
	return out


## Whether two hulls say the same thing, which is what the dirty marker
## is asking.
static func same(a: HullData, b: HullData) -> bool:
	var mine: Dictionary = snapshot(a)
	var theirs: Dictionary = snapshot(b)
	for key: Variant in mine:
		if not theirs.has(key) or mine[key] != theirs[key]:
			return false
	return true
