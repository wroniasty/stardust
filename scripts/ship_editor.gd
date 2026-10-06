class_name ShipEditor
extends CanvasLayer
## MAUX1: the prototype ship editor. Cargo, hold, and every place a module can
## go, on one screen.
##
## The quick swap on Tab stays what it is -- one slot, no pause, a decision
## taken while still flying. This is the other half: somewhere to look at the
## whole ship, see what fitting a module would actually do, and stow or throw
## away what is not wanted. It pauses, because reading a schematic while
## falling is not a decision, it is an accident.
##
## Looking is free; changing is not. The screen opens anywhere -- planning a
## refit on the way home is a reasonable thing to do -- but bolting a module
## on needs the ship on the ground. That gives a landing pad a purpose beyond
## being somewhere not to die, without the screen refusing to open and
## refusing to say why. Throwing something overboard stays available in
## flight: dumping ballast under pressure is exactly the decision worth
## having.
##
## The schematic is generated from the same data the ship flies on -- the hull
## collision polygon and the mount nodes' own positions -- never drawn by
## hand. A hand-drawn one would have been wrong the moment the torque cross
## moved, which happened twice while the bulk work was going in.

## Opaque, not nearly-opaque. At 0.95 the debug overlay behind still came
## through as readable grey text: five percent of bright green on near-black
## is twice the panel's own brightness.

## Dims the world behind the panels, so the screen reads as "the game has
## stopped" rather than as a window left open over it.

## A mount the selected module will not go into. Readable, but plainly not a
## candidate.

const FONT_SIZE: int = 8
const ROW: float = 10.0
const PAD: float = 5.0

## How far one press swings a hardpoint's rest direction. Five degrees: fine
## enough to place a gun deliberately, coarse enough that pointing one across
## the ship is not a hundred presses.
const AIM_STEP: float = deg_to_rad(5.0)

## How long the arc wedge is drawn on the schematic, in panel pixels.
const ARC_LENGTH: float = 16.0

## Side of a slot on the schematic, and of the ring drawn round the chosen
## one so it reads as a target rather than as a slightly bigger slot.
##
## A slot is a box rather than a dot because a dot can only say "here".
## A box has an inside, and the inside can say what kind of socket this is
## and whether anything is in it -- which is what the pilot came to the
## schematic to find out, and what used to take a line of text each.
const SLOT: float = 11.0
const SLOT_RING: float = 15.0

## How much of the box the glyph inside it takes.
const GLYPH: float = 3.2

## A cell of the hold grid, and the pitch between two of them.
##
## Bigger than a slot box, because a slot is read in place on a
## schematic and these are read as a row: the eye needs the frame to
## carry a colour as well as the shape it holds.
const ICON: float = 14.0
const ICON_STEP: float = ICON + 3.0

## The shapes this screen draws things as.
##
## One vocabulary, reached from two directions: a socket asks what kind
## of thing goes in it, an icon asks what kind of thing this is, and
## both get the same silhouette. Written out as an enum rather than
## left as two parallel if-ladders, because the day they disagree is
## the day a tank in the hold and a tank in its bay stop looking like
## the same object.
enum Glyph { NONE, ENGINE, GUN, CELL, DISH, RING, DRUM, CHIP, STRUT, MOD }

var _ship: Ship = null
var _canvas: Control = null

## Index into _items(): the hold first, then the cargo bay.
var _pick: int = 0

## Index into _targets(): which of the mounts the selected module fits is
## highlighted. Wrapped on every redraw, so a slot disappearing under it
## cannot leave the cursor pointing at nothing.
var _slot: int = 0

## Last line of feedback, from a fit, a stow or a refusal.
var _notice: String = ""

## A fitted module the pilot clicked to read, when nothing carried would go
## there. Cleared the moment something is selected in the list: two things
## claiming the card at once is one too many.
var _inspecting: Resource = null

## The slot whose name is on the schematic, put there by a click. The boxes
## say what kind and whether occupied without being read; the name is the
## part a pilot asks for, so it waits to be asked.
##
## The only node this screen holds on to between frames, and it is held
## across something that destroys nodes: a refit frees every mount and
## builds new ones. Cleared on `Ship.configuration_changed` for that
## reason, and checked for still existing anyway -- see `_captions()`.
var _named: Node = null

## What fitting the selected module into the highlighted slot would do,
## worked out by fitting it, measuring, and putting things back. Cached
## against the selection rather than recomputed every frame: the answer only
## changes when the selection does, and a speculative rebuild per frame is
## work nobody asked for.
var _preview: PackedStringArray = PackedStringArray()
var _preview_key: String = ""




## The twelve colours every screen draws from (UI_STYLE section 3). This
## file used to spell out its own, which is how three screens ended up
## with two panel fills, two borders and three ambers a pixel apart.
var _ink: Palette = Palette.current()

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Takes the mouse while it is open, and only then: the node is hidden the
	# rest of the time, so the game never loses a click to an unseen panel.
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_on_click)
	_canvas.draw.connect(_draw_editor)
	add_child(_canvas)
	_canvas.hide()


func bind(ship: Ship) -> void:
	_ship = ship
	# A refit throws away every mount and makes new ones, so anything this
	# screen remembered by node is gone. The ship already announces it.
	if ship != null and not ship.configuration_changed.is_connected(_forget_slots):
		ship.configuration_changed.connect(_forget_slots)


## Drops a remembered slot that the ship no longer has.
##
## Only when it has really gone, so that fitting a module -- which also
## rebuilds, and keeps every mount -- does not blank the caption the pilot
## just clicked for.
func _forget_slots() -> void:
	if _named != null and not _all_mounts().has(_named):
		_named = null


func is_open() -> bool:
	return _canvas.visible


func toggle() -> void:
	if is_open():
		close()
		return
	_pick = 0
	_slot = 0
	_notice = ""
	_canvas.show()
	PauseGate.hold_exclusive(self, get_tree())


func close() -> void:
	_canvas.hide()
	PauseGate.release(self, get_tree())


func _process(_delta: float) -> void:
	if is_open():
		_refresh_preview()
		_canvas.queue_redraw()
	else:
		# Guard against leaving the game paused with nothing on screen to
		# explain it. Releases only this screen's own claim -- releasing
		# everyone's is what broke the pause when there were two screens.
		PauseGate.release(self, get_tree())


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_editor"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_open():
		return

	if event.is_action_pressed(&"ui_cancel"):
		close()
	elif event.is_action_pressed(&"ui_down"):
		_pick += 1
		_slot = 0
	elif event.is_action_pressed(&"ui_up"):
		_pick -= 1
		_slot = 0
	elif event.is_action_pressed(&"ui_right"):
		_slot += 1
	elif event.is_action_pressed(&"ui_left"):
		_slot -= 1
	elif event.is_action_pressed(&"loadout_fit"):
		_fit()
	elif event.is_action_pressed(&"loadout_drop"):
		_jettison()
	elif event.is_action_pressed(&"editor_stow"):
		_stow()
	elif event.is_action_pressed(&"editor_aim_ccw"):
		_turn_mount(-AIM_STEP)
	elif event.is_action_pressed(&"editor_aim_cw"):
		_turn_mount(AIM_STEP)
	elif event.is_action_pressed(&"editor_trigger"):
		_swap_trigger()
	else:
		return
	get_viewport().set_input_as_handled()


## Whether the ship is somewhere a module can be changed.
##
## Standing still counts, however the ship came to be standing still: on its
## legs on a planet, or tied up at a station. The second half of that was
## written down here as a promise before there was anything to dock to, and
## now there is.
##
## The quick swap on Tab is deliberately **not** gated the same way, and the
## difference is the point of having both screens. That one is a single
## carried module into a single compatible slot, with the world still
## running -- a decision made while something is going wrong, which is the
## whole reason LoadoutScreen does not pause. This one is every slot at
## once, on a paused schematic, and that is yard work.
func can_refit() -> bool:
	if _ship == null:
		return false
	return (
		_ship.flight_mode == Ship.FlightMode.LANDED
		or _ship.flight_mode == Ship.FlightMode.DOCKED
	)


## What the corner of the panel says about why fitting is or is not
## available. Three states rather than two: "fitting after landing" was a
## half-truth the moment a dock would also do.
func _where_it_stands() -> String:
	if _ship == null:
		return "NO SHIP"
	match _ship.flight_mode:
		Ship.FlightMode.DOCKED:
			return "DOCKED - fitting available"
		Ship.FlightMode.LANDED:
			return "ON THE GROUND - fitting available"
		_:
			# Short on purpose: it is drawn in the corner of the lower
			# panel, beside the comparison, and the long version ran over
			# it. Says what to do rather than where it could be done,
			# which is also the more useful half.
			return "IN FLIGHT - dock or land"


## Everything the pilot can act on, hold first. One list rather than two
## panels to tab between: whichever module is selected, the keys mean the
## same thing.
func _items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _ship == null:
		return out
	if _ship.carried != null:
		out.append({"item": _ship.carried, "rarity": _ship.carried_rarity, "held": true})
	for entry: Dictionary in _ship.cargo:
		out.append({"item": entry["item"], "rarity": int(entry["rarity"]), "held": false})
	return out


func _selected() -> Dictionary:
	var items: Array[Dictionary] = _items()
	if items.is_empty():
		return {}
	_pick = posmod(_pick, items.size())
	return items[_pick]


## Mounts the selected module will go into. Asked of the mounts themselves,
## so the editor cannot drift from what fitting actually allows.
func _targets() -> Array[Node]:
	var out: Array[Node] = []
	var picked: Dictionary = _selected()
	if picked.is_empty() or _ship == null:
		return out
	var item: Resource = picked["item"]
	if item is WeaponData:
		for mount: Hardpoint in _ship.hardpoints:
			if mount.can_fit(item as WeaponData):
				out.append(mount)
	elif item is EngineData:
		for mount: EngineMount in _ship.engine_mounts():
			if _ship.mount_accepts(mount, item as EngineData):
				out.append(mount)
	elif item is GearData:
		if _ship.gear != null:
			out.append(_ship.gear)
	elif item is ShotModData:
		# A mod goes into a gun, not into a socket on the hull, so the
		# targets are the weapons with a slot free rather than the mounts.
		for mount: Hardpoint in _ship.hardpoints:
			if mount.weapon != null and mount.mods.size() < mount.weapon.mod_slots:
				out.append(mount)
	else:
		# Everything that goes in a bay. One pass rather than one branch
		# per kind: the bay already knows what it takes, and the editor
		# deciding instead was the editor keeping a second copy of a list
		# the hull was already holding.
		for bay: ModuleBay in _ship.bays:
			if bay.fits(item as ModuleData):
				out.append(bay)
	return out


## The ones with a real place on the hull, which are the ones the
## schematic can honestly draw where they are.
func _hull_mounts() -> Array[Node]:
	var out: Array[Node] = []
	if _ship == null:
		return out
	for mount: EngineMount in _ship.engine_mounts():
		out.append(mount)
	for mount: Hardpoint in _ship.hardpoints:
		out.append(mount)
	return out


## And the ones that are volumes inside it. A generator, a computer and
## the gear sit within a few pixels of each other on the hull, because
## that is where they are; drawn there, their boxes overlap into an
## unclickable heap. They get the column down the edge instead.
func _internal_mounts() -> Array[Node]:
	var out: Array[Node] = []
	if _ship == null:
		return out
	for bay: ModuleBay in _ship.bays:
		out.append(bay)
	if _ship.gear != null:
		out.append(_ship.gear)
	return out


## Every place a module could go, fitted or not, for the schematic.
func _all_mounts() -> Array[Node]:
	var out: Array[Node] = []
	if _ship == null:
		return out
	for mount: EngineMount in _ship.engine_mounts():
		out.append(mount)
	for mount: Hardpoint in _ship.hardpoints:
		out.append(mount)
	for bay: ModuleBay in _ship.bays:
		out.append(bay)
	if _ship.gear != null:
		out.append(_ship.gear)
	return out


## Why this slot will not take this item, or an empty string when it
## will.
##
## Named rather than counted: "no" is not an answer anybody can fly on,
## and the two reasons a socket refuses an engine are not close
## together. The wrong kind is a mistake; too bulky is a decision about
## the hull, and the number is what tells the pilot whether a different
## socket would do.
## Whatever the pilot is holding or has picked out of cargo, or null.
func _held_item() -> Resource:
	var picked: Dictionary = _selected()
	return null if picked.is_empty() else picked["item"] as Resource


func _refusal(slot: Node, item: Resource) -> String:
	if item == null:
		return ""
	if slot is EngineMount and item is EngineData:
		var mount: EngineMount = slot as EngineMount
		var engine: EngineData = item as EngineData
		if mount.fits(engine):
			return ""
		if not mount.accepts(engine.type):
			return "%s does not take that kind" % mount.name
		return "too bulky for %s: %.2f against %.2f" % [
			mount.name, engine.bulk, mount.size
		]
	if slot is ModuleBay and item is ModuleData:
		var bay: ModuleBay = slot as ModuleBay
		var module: ModuleData = item as ModuleData
		if bay.fits(module):
			return ""
		if not bay.accepts(module):
			return "%s does not take that kind" % bay.name
		return "too bulky for %s: %.2f against %.2f" % [
			bay.name, module.bulk, bay.size
		]
	return ""


func _fit() -> void:
	var targets: Array[Node] = _targets()
	var picked: Dictionary = _selected()
	if targets.is_empty() or picked.is_empty():
		_notice = "nowhere to fit that"
		return

	if not can_refit():
		_notice = "fitting only on the ground - land, or use Tab in flight"
		return

	var slot: Node = targets[posmod(_slot, targets.size())]
	var item: Resource = picked["item"]

	# Asked **before** the item leaves the hold, which is the whole of
	# this fix. `Ship.fit_engine` says "I will not take this" by handing
	# the item straight back, so the refusal arrives in the same return
	# slot as "here is what came out" -- and the code below, which
	# cannot tell those two apart, filed the item in cargo and reported
	# a successful fit. The pilot was told it worked.
	var refusal: String = _refusal(slot, item)
	if not refusal.is_empty():
		_notice = refusal
		return

	var before: ConfigurationReport = _ship.configuration()

	# Out of wherever it was, so the ship is never holding two copies of it.
	if bool(picked["held"]):
		_ship.release()
	else:
		_ship.cargo.remove_at(_pick - (1 if _ship.carried != null else 0))

	var removed: Resource = null
	if slot is Hardpoint and item is ShotModData:
		# Plugging a mod in is not a swap -- nothing comes back out -- so it
		# takes the item and leaves `removed` null.
		if not (slot as Hardpoint).add_mod(item as ShotModData):
			_ship.take(item, 0)
			_notice = "no free socket in that weapon"
			return
	elif slot is Hardpoint:
		removed = (slot as Hardpoint).fit(item as WeaponData)
	elif slot is EngineMount:
		removed = _ship.fit_engine(slot as EngineMount, item as EngineData)
	elif slot is ModuleBay:
		var bay: ModuleBay = slot as ModuleBay
		removed = bay.installed
		bay.installed = item as ModuleData
	elif slot is LandingGear:
		var legs: LandingGear = slot as LandingGear
		removed = legs.installed
		legs.installed = item as GearData

	# Whatever came out goes back to the bay, or to the hold when the bay is
	# full. Never nowhere: a swap must always be reversible.
	if removed != null:
		if Ship.module_bulk(removed) <= _ship.cargo_free():
			_ship.cargo.append({"item": removed, "rarity": 0})
		elif not _ship.take(removed, 0):
			_ship.jettison()
			_notice = "hold and cargo both full - the old module goes overboard"
	_ship.rebuild_control_groups(false)
	_ship.cargo_changed.emit()

	var delta: PackedStringArray = _ship.configuration().compare(before)
	_notice = "fitted in %s - %s" % [
		slot.name, "no change to the controls" if delta.is_empty() else ", ".join(delta),
	]


## Works out what fitting would do without committing to it: bolt the module
## in, measure, put everything back exactly as it was.
##
## Only engines move the control groups -- a weapon is compared on its own
## numbers instead, further down -- so this is the engine half of the answer.
func _refresh_preview() -> void:
	var picked: Dictionary = _selected()
	var targets: Array[Node] = _targets()
	var key: String = "%d/%d/%d" % [_pick, _slot, targets.size()]
	if key == _preview_key:
		return
	_preview_key = key
	_preview = PackedStringArray()
	if picked.is_empty() or targets.is_empty():
		return

	var mount: EngineMount = targets[posmod(_slot, targets.size())] as EngineMount
	var candidate: EngineData = picked["item"] as EngineData
	if mount == null or candidate == null:
		return

	var before: ConfigurationReport = _ship.configuration()
	var previous: EngineData = mount.installed
	mount.installed = candidate
	_ship.rebuild_control_groups(false)
	_preview = _ship.configuration().compare(before)
	mount.installed = previous
	_ship.rebuild_control_groups(false)


## The one-line answer to "is this better", for whichever kind of module is
## selected. Engines are compared through the control groups, because where
## an engine goes decides what it does; a weapon is the same gun wherever it
## is bolted, so it is compared against the gun already in the slot.
func _verdict() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var targets: Array[Node] = _targets()
	var picked: Dictionary = _selected()
	if targets.is_empty() or picked.is_empty():
		return out
	var slot: Node = targets[posmod(_slot, targets.size())]

	# Nothing for a gun. The card beside it already gives every number and
	# its difference, and a second, coarser summary of the same swap is one
	# reading too many to cross-check.
	if slot is Hardpoint:
		return out

	out.append("%s: %s" % [
		slot.name, "no change to the controls" if _preview.is_empty() else ", ".join(_preview),
	])
	return out


## Swings the highlighted hardpoint's rest direction.
##
## Where a gun sits belongs to the hull, not to the gun, so it is set here
## and never rolled with the weapon.
func _turn_mount(by: float) -> void:
	var slot: Hardpoint = _highlighted() as Hardpoint
	if slot == null:
		_notice = "rotation is set on a weapon socket"
		return
	slot.rotation = wrapf(slot.rotation + by, -PI, PI)
	_notice = "%s aims %.0f deg off the nose" % [slot.name, rad_to_deg(slot.rotation)]


## Moves the highlighted hardpoint to the other trigger.
func _swap_trigger() -> void:
	var slot: Hardpoint = _highlighted() as Hardpoint
	if slot == null:
		_notice = "a trigger is assigned to a weapon socket"
		return
	slot.trigger = 1 - slot.trigger
	_notice = "%s on the %s trigger" % [slot.name, "left" if slot.trigger == 0 else "right"]


## The mount the slot cursor is on, whatever kind it is. Falls back to the
## whole schematic so a mount can still be adjusted with an empty hold.
func _highlighted() -> Node:
	var targets: Array[Node] = _targets()
	if not targets.is_empty():
		return targets[posmod(_slot, targets.size())]
	var mounts: Array[Node] = _all_mounts()
	return null if mounts.is_empty() else mounts[posmod(_slot, mounts.size())]


func _stow() -> void:
	var picked: Dictionary = _selected()
	if picked.is_empty() or not bool(picked["held"]):
		_notice = "only what is in the hold can be stowed"
		return
	_notice = "stowed in cargo" if _ship.stow() else "cargo has no room for that"


func _jettison() -> void:
	var picked: Dictionary = _selected()
	if picked.is_empty():
		return
	if not bool(picked["held"]):
		# Everything leaves by the same door, so there is one jettison path
		# and one place the world hears about it.
		var index: int = _pick - (1 if _ship.carried != null else 0)
		if _ship.carried != null:
			_notice = "empty the hold first"
			return
		_ship.retrieve(index)
	_ship.jettison()
	_notice = "thrown overboard"


## A click picks whatever is under it: a row in the list, or a mount on the
## schematic. Only mounts the selected module fits can be picked, because the
## slot cursor indexes the list of those and pointing it at anything else
## would mean two ways of saying "nowhere".
func _on_click(event: InputEvent) -> void:
	var press: InputEventMouseButton = event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	if click_at(press.position):
		_canvas.accept_event()


## Turns a point on screen into a selection. Public so the behaviour can be
## driven without a mouse or a rendered frame. True when something was hit.
func click_at(at: Vector2) -> bool:
	if _ship == null:
		return false
	var panels: Dictionary = _panels()

	for i: int in range(_items().size()):
		if _icon_rect(i, panels["hold"]).has_point(at):
			_pick = i
			_slot = 0
			return true

	var where: Dictionary = slot_positions(panels)
	var targets: Array[Node] = _targets()
	for mount: Node in _all_mounts():
		if not slot_rect(where[mount], SLOT_RING).has_point(at):
			continue
		# Clicking a slot is how its name is asked for now.
		_named = mount
		var index: int = targets.find(mount)
		if index >= 0:
			_slot = index
			return true

		# Not a target. Clicking a socket is a statement of intent, so a
		# socket that will not have it has to say so -- this used to
		# **clear** the notice and leave the aim on whatever was aimed at
		# before, which is how a pilot clicked the reverse mount, was
		# told nothing, pressed fit, and put an oversized thruster
		# through their main drive at a 72% loss of forward authority.
		var refusal: String = _refusal(mount, _held_item())
		if _fitted_in(mount) != null:
			# There is something in it worth reading either way: clicking
			# a module should show that module.
			_inspecting = _fitted_in(mount)
		_notice = (
			refusal if not refusal.is_empty()
			else ("" if _fitted_in(mount) != null else "%s is empty" % mount.name)
		)
		return true
	return false


## Where the panels go. A function of the viewport and nothing else, so a
## click can be resolved without waiting for a frame to have been drawn --
## the earlier version read back what the last _draw left behind, which
## made mouse input untestable and wrong before the first frame.
##
## Six regions in two rows, from the MAUX4 sketch. The shape of it is the
## argument: a refit is one question asked in two halves -- *what have I
## got* down the left, *where does it go* in the middle -- and then one
## comparison across the bottom, both cards side by side, because a swap
## you have to look at in two goes is two readings taken a moment apart.
##
## | | |
## |---|---|
## | `hold` | what is aboard, as icons |
## | `stores` | spare parts and stardust, under it |
## | `plan` | the schematic, and everything bolted to the hull |
## | `bays` | the internal sockets, in a column down the edge |
## | `facts` | what the ship can do |
## | `carried` / `fitted` | the two cards of the comparison |
func _panels() -> Dictionary:
	var view: Vector2 = _canvas.size
	var edge: float = 6.0
	var left: float = snappedf(view.x * 0.26, 1.0)
	var strip: float = SLOT + PAD * 2.0
	var top: float = snappedf(view.y * 0.62, 1.0)
	# Two rows of readings and a line about what they cost: enough that
	# the panel says something, little enough that the hold keeps the
	# column it needs for icons.
	var stores: float = ROW * 3.0 + PAD * 2.0

	var hold: Rect2 = Rect2(edge, edge, left, top - edge - stores - edge * 0.5)
	var plan_x: float = hold.end.x + edge
	var plan_w: float = view.x - plan_x - strip - edge * 2.0
	var bottom: Rect2 = Rect2(
		edge, top + edge, view.x - edge * 2.0, view.y - top - edge * 2.0
	)
	# A third each. The longest card in the game is a legendary missile at
	# seventeen rows, which is why the bottom row is not thinner.
	var card_w: float = (bottom.size.x - left - edge * 2.0) * 0.5
	return {
		"view": view,
		"hold": hold,
		"stores": Rect2(edge, hold.end.y + edge * 0.5, left, stores),
		"plan": Rect2(plan_x, edge, plan_w, top - edge),
		"bays": Rect2(plan_x + plan_w + edge, edge, strip, top - edge),
		"facts": Rect2(bottom.position, Vector2(left, bottom.size.y)),
		"carried": Rect2(
			bottom.position.x + left + edge, bottom.position.y, card_w, bottom.size.y
		),
		"fitted": Rect2(
			bottom.position.x + left + edge * 2.0 + card_w,
			bottom.position.y,
			card_w,
			bottom.size.y,
		),
	}


## Maps a point in the ship's own frame onto the schematic, fitting the hull
## and every mount into the panel with room for the names beside the dots.
func _plan_placement(plan: Rect2) -> Callable:
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2.ZERO)
	var first: bool = true
	for point: Vector2 in _ship.hull_outline:
		bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
		first = false
	for mount: Node in _all_mounts():
		bounds = bounds.expand((mount as Node2D).position)
	bounds = bounds.grow(2.0)

	# Room for the slot boxes and the traverse arcs standing off the hull,
	# and for the one caption a click puts up. It used to reserve over half
	# the width because every mount printed its name beside it; with the
	# names gone the ship gets the panel, which is what makes a slot big
	# enough to draw anything inside.
	var room: Vector2 = plan.size - Vector2(
		plan.size.x * 0.18 + SLOT_RING * 2.0, PAD * 4.0 + float(FONT_SIZE) + SLOT_RING
	)
	var scale: float = minf(room.x / bounds.size.x, room.y / bounds.size.y)
	var origin: Vector2 = plan.position + Vector2(plan.size.x * 0.5, plan.size.y * 0.55)
	var centre: Vector2 = bounds.get_center()
	return func(p: Vector2) -> Vector2:
		return origin + (p - centre) * scale


func _draw_editor() -> void:
	# Fixed-width throughout: every panel here is a padded column list, and
	# the card in the info panel is the same one the quick swap draws.
	var font: Font = ModuleData.card_font()
	if font == null or _ship == null:
		return
	var panels: Dictionary = _panels()

	_canvas.draw_rect(Rect2(Vector2.ZERO, panels["view"] as Vector2), _ink.over(_ink.scrim, 0.72))
	for key: String in ["hold", "stores", "plan", "bays", "facts", "carried", "fitted"]:
		_panel(panels[key])
	_draw_hold(font, panels["hold"])
	_draw_stores(font, panels["stores"])
	_draw_plan(font, panels["plan"])
	_draw_bays(font, panels["bays"])
	_draw_facts(font, panels["facts"])
	_draw_cards(font, panels["carried"], panels["fitted"])


func _panel(rect: Rect2) -> void:
	_canvas.draw_rect(rect, _ink.panel)
	_canvas.draw_rect(rect, _ink.edge, false, 1.0)


func _width(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


func _text(font: Font, at: Vector2, text: String, colour: Color) -> void:
	_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)


## The hold, as a grid of icons rather than as a list of sentences.
##
## The sketch asks for this and the reason is the one the schematic
## already proved: a slot box says kind and occupancy without being
## read, and a line of text says the same thing after it has been read.
## Twelve items are twelve lines of grey or twelve shapes, and only one
## of those can be taken in at a glance.
##
## The frame is the rarity and the silhouette is the kind, which is two
## facts in no words at all. The name is on the card below, where the
## pilot is already looking once they have clicked.
func _draw_hold(font: Font, rect: Rect2) -> void:
	var x: float = rect.position.x + PAD
	var y: float = rect.position.y + PAD + float(FONT_SIZE)
	var used: float = _ship.cargo_used()
	var room: float = _ship.cargo_capacity()
	_text(font, Vector2(x, y), "HOLD", _ink.label)
	_text(
		font,
		Vector2(rect.end.x - PAD - _width(font, "%.1f / %.1f" % [used, room]), y),
		"%.1f / %.1f" % [used, room],
		_ink.alarm if used > room else _ink.value,
	)

	var items: Array[Dictionary] = _items()
	if items.is_empty():
		_text(font, Vector2(x, y + ROW * 1.5), "empty", _ink.inert)
		return
	for i: int in range(items.size()):
		_draw_hold_icon(items[i], _icon_rect(i, rect), i == _pick)


## One cell of the grid, and where it is. Public for the same reason the
## slot boxes are: the click and the picture have to be the same picture.
func _icon_rect(index: int, rect: Rect2) -> Rect2:
	var columns: int = maxi(int((rect.size.x - PAD * 2.0) / ICON_STEP), 1)
	var home: Vector2 = rect.position + Vector2(PAD, PAD + ROW * 1.6)
	return Rect2(
		home + Vector2(
			float(index % columns) * ICON_STEP, float(index / columns) * ICON_STEP
		),
		Vector2(ICON, ICON),
	)


func _draw_hold_icon(entry: Dictionary, box: Rect2, picked: bool) -> void:
	var item: Resource = entry["item"]
	var module: ModuleData = item as ModuleData
	var grade: Color = (
		ModuleData.RARITY_COLORS[0] if module == null else module.rarity_color()
	)
	# The frame carries the rarity, so the glyph inside can carry the
	# kind without the two fighting for the same channel.
	_canvas.draw_rect(box, Color(grade, 0.14), true)
	_canvas.draw_rect(box, grade, false, 1.0)
	if bool(entry["held"]):
		# What is in the hands rather than in the bay. A bracket, which
		# is what this interface uses everywhere for "the one in play".
		UiDraw.bracket(_canvas, box.grow(2.0), _ink.accent, 3.0)
	if picked:
		_canvas.draw_rect(box.grow(1.0), _ink.caution, false, 1.0)
	_draw_item_glyph(box.get_center(), item, _ink.value if picked else grade)


## What is aboard by the unit, and what it is for.
##
## Two readings rather than a bar each: these have no capacity of their
## own -- the hold is their capacity, and it is already drawn above
## them. A bar with no end is a bar that lies about where the end is.
func _draw_stores(font: Font, rect: Rect2) -> void:
	var width: float = rect.size.x - PAD * 2.0
	var y: float = rect.position.y + PAD + float(FONT_SIZE)
	for kind: int in [Stores.Kind.SPARE_PARTS, Stores.Kind.STARDUST]:
		UiDraw.row(
			_canvas,
			font,
			Vector2(rect.position.x + PAD, y),
			width,
			Stores.kind_name(kind),
			"%d" % _ship.carrying(kind as Stores.Kind),
			_ink.value if _ship.carrying(kind as Stores.Kind) > 0 else _ink.inert,
			_ink.label,
		)
		y += ROW
	# What breaking the selected thing down would give, where the pilot
	# is looking when they are deciding whether it is worth keeping.
	var picked: Dictionary = _selected()
	var place: Refinery.Place = Refinery.place_of(_ship)
	if picked.is_empty():
		_text(font, Vector2(rect.position.x + PAD, y), "%s" % Refinery.place_name(place), _ink.inert)
		return
	_text(
		font,
		Vector2(rect.position.x + PAD, y),
		"scrap: %d parts, %s" % [
			Refinery.parts_from(picked["item"] as Resource, place),
			Refinery.place_name(place),
		],
		_ink.label,
	)


## The internal sockets, in a column down the edge.
##
## They are volumes inside the hull rather than points on it, so drawing
## them where they really are put five boxes within a few pixels of each
## other and needed a whole fanning-out routine to make them clickable.
## The sketch's answer is better than that routine: give them a list,
## and leave the schematic to the things that genuinely have a place on
## the ship.
func _draw_bays(font: Font, rect: Rect2) -> void:
	_text(font, rect.position + Vector2(PAD, PAD + float(FONT_SIZE)), "M", _ink.label)
	var targets: Array[Node] = _targets()
	var where: Dictionary = slot_positions(_panels())
	for mount: Node in _internal_mounts():
		var fits: bool = targets.has(mount)
		var chosen: bool = mount == _highlighted()
		_draw_slot(
			where[mount],
			mount,
			_ink.caution if chosen else (_ink.ok if fits else _ink.inert),
			chosen,
		)


## What the ship can do, which is the question the schematic cannot
## answer: where a module goes decides what it does, and the sum of all
## of them is a different reading from any one card.
func _draw_facts(font: Font, rect: Rect2) -> void:
	var width: float = rect.size.x - PAD * 2.0
	var x: float = rect.position.x + PAD
	var y: float = rect.position.y + PAD + float(FONT_SIZE)
	_text(font, Vector2(x, y), "SHIP", _ink.label)
	y += ROW * 1.4
	var rows: Array[Array] = [
		["mass", "%.1f" % _ship.mass, ""],
		["hull", "%.0f" % (_ship.hull_integrity * 100.0), "%"],
		["fuel", "%.0f" % _ship.fuel, ""],
		["jumps", "%d / %d" % [_ship.charges, _ship.charge_capacity()], ""],
	]
	for row: Array in rows:
		UiDraw.row(
			_canvas, font, Vector2(x, y), width,
			String(row[0]), String(row[1]),
			_ink.value, _ink.label, String(row[2]),
		)
		y += ROW
	# Why fitting is or is not available, which belongs with the ship
	# rather than with the item: it is a fact about where it is standing.
	_text(font, Vector2(x, rect.end.y - PAD), _where_it_stands(), _ink.label)


## The schematic, built from the hull polygon and the mount positions so it
## cannot disagree with the ship it describes.
func _draw_plan(font: Font, rect: Rect2) -> void:
	_text(font, rect.position + Vector2(PAD, PAD + float(FONT_SIZE)), "SCHEMATIC", _ink.label)

	var hull: PackedVector2Array = _ship.hull_outline
	var mounts: Array[Node] = _all_mounts()
	if hull.size() < 3:
		return

	var place: Callable = _plan_placement(rect)
	var where: Dictionary = slot_positions(_panels())
	var origin: Vector2 = rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.55)

	var outline: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull:
		outline.append(place.call(point))
	_canvas.draw_colored_polygon(outline, _ink.edge)
	outline.append(outline[0])
	_canvas.draw_polyline(outline, _ink.grid, 1.0)

	var targets: Array[Node] = _targets()
	var chosen: Node = null
	if not targets.is_empty():
		_slot = posmod(_slot, targets.size())
		chosen = targets[_slot]

	for mount: Node in _hull_mounts():
		var at: Vector2 = where[mount]
		var fits: bool = targets.has(mount)
		var colour: Color = _ink.caution if mount == chosen else (_ink.ok if fits else _ink.inert)
		var gun: Hardpoint = mount as Hardpoint
		if gun != null:
			_draw_arc_for(gun, at)
		_draw_slot(at, mount, colour, mount == chosen)

	# One name at a time, where a name used to hang off every mount. Eleven
	# captions on a schematic this size is a wall of text the eye has to
	# read before it can find anything; the boxes say kind and occupancy
	# without being read at all, and the name is what a click is for.
	#
	# The arrow-chosen slot is named too, or stepping through targets with
	# the keyboard would be stepping blind.
	for mount: Node in _captions(chosen, mounts):
		_draw_slot_caption(font, where[mount], mount, origin, rect)


## Which slots get their name drawn: the one the arrows are on, and the one
## that was clicked, in that order and never the same one twice.
##
## Built by appending rather than as an array literal, which is not style.
## `[chosen, _named]` throws while the array is being built if `_named` has
## been freed -- before the loop body can reach the guard that would have
## skipped it. That is how this was found: a wall of
## "previously freed object into a TypedArray" once a frame after a refit,
## with the check that was supposed to prevent it sitting right there,
## three lines too late.
func _captions(chosen: Node, mounts: Array[Node]) -> Array[Node]:
	var out: Array[Node] = []
	if chosen != null and mounts.has(chosen):
		out.append(chosen)
	# Validity first: a freed node cannot even be compared into a typed
	# array, so it must not reach one.
	if _named != null and is_instance_valid(_named) and _named != chosen:
		if mounts.has(_named):
			out.append(_named)
	return out


## The full name of one slot, hung outward so it clears the hull.
##
## Clamped into the panel rather than given a margin to live in: the ship is
## drawn as large as the panel allows now, so a caption near the edge has to
## give way to the edge instead of the ship giving way to the caption.
func _draw_slot_caption(font: Font, at: Vector2, mount: Node, origin: Vector2, rect: Rect2) -> void:
	var caption: String = mount.name
	var gun: Hardpoint = mount as Hardpoint
	if gun != null:
		caption = "%s %s" % [mount.name, "L" if gun.trigger == 0 else "P"]
		if gun.weapon != null and gun.weapon.mod_slots > 0:
			caption += " %d/%d" % [gun.mods.size(), gun.weapon.mod_slots]
	var width: float = _width(font, caption)
	var label: Vector2 = at + Vector2(SLOT_RING * 0.5 + 2.0, float(FONT_SIZE) * 0.4)
	if at.x < origin.x - 0.5:
		label.x = at.x - SLOT_RING * 0.5 - 2.0 - width
	label.x = clampf(label.x, rect.position.x + PAD, rect.end.x - PAD - width)
	_text(font, label, caption, _ink.caution)


## One slot: a box that says what kind of socket it is and what is in it.
##
## Four things at once, and none of them written down. The border is whether
## this is somewhere the carried module could go. The fill is whether
## anything is in it, in the colour of how good that thing is. The glyph is
## what kind of socket it is. The ring is which one the arrows are on.
func _draw_slot(at: Vector2, mount: Node, colour: Color, chosen: bool) -> void:
	var box: Rect2 = slot_rect(at)
	var fitted: ModuleData = _fitted_in(mount) as ModuleData
	if fitted != null:
		# Rarity, not a generic "occupied" grey: a legendary drive and a
		# common one are the same shape and a different decision.
		_canvas.draw_rect(box, Color(fitted.rarity_color(), 0.35), true)
	if chosen:
		_canvas.draw_rect(slot_rect(at, SLOT_RING), colour, false, 1.0)
	_canvas.draw_rect(box, colour, false, 1.0)
	_draw_slot_glyph(at, mount, colour if fitted != null else Color(colour, 0.5))


## The glyph for a kind of socket. Silhouettes rather than letters, because
## at eleven pixels a letter is three pixels of stem and every letter looks
## like every other one.
func _draw_slot_glyph(at: Vector2, mount: Node, colour: Color) -> void:
	var engine: EngineMount = mount as EngineMount
	if engine != null:
		# An arrow along the force, not the plume: the question an editor is
		# asked is which way this pushes the ship. Taken from the mount's own
		# accessor, because the convention for folding in the node's rotation
		# should live in one place and this is not it.
		var along: Vector2 = engine.force_direction()
		_draw_kind_glyph(
			at, Glyph.ENGINE, colour, Vector2.DOWN if along.is_zero_approx() else along
		)
		return
	var gun: Hardpoint = mount as Hardpoint
	if gun != null:
		_draw_weapon_glyph(at, gun.weapon, colour)
		return
	_draw_kind_glyph(at, _glyph_for_mount(mount), colour)


## Which shape a socket wears. The bays, which are the ones a mount and
## an item agree about.
func _glyph_for_mount(mount: Node) -> Glyph:
	if mount is GeneratorBay:
		return Glyph.CELL
	if mount is ScannerBay:
		return Glyph.DISH
	if mount is JumpDriveBay:
		return Glyph.RING
	if mount is TankBay:
		return Glyph.DRUM
	if mount is ComputerBay:
		return Glyph.CHIP
	if mount is LandingGear:
		return Glyph.STRUT
	return Glyph.NONE


## And which shape a loose module wears, which has to be the same one.
func _glyph_for_item(item: Resource) -> Glyph:
	if item is EngineData:
		return Glyph.ENGINE
	if item is WeaponData:
		return Glyph.GUN
	if item is GeneratorData:
		return Glyph.CELL
	if item is ScannerData:
		return Glyph.DISH
	if item is JumpDriveData:
		return Glyph.RING
	if item is TankData:
		return Glyph.DRUM
	if item is FlightComputerData:
		return Glyph.CHIP
	if item is GearData:
		return Glyph.STRUT
	if item is ShotModData:
		return Glyph.MOD
	return Glyph.NONE


## A module in the hold, drawn as the thing it is.
func _draw_item_glyph(at: Vector2, item: Resource, colour: Color) -> void:
	var kind: Glyph = _glyph_for_item(item)
	if kind == Glyph.GUN:
		_draw_weapon_glyph(at, item as WeaponData, colour)
		return
	_draw_kind_glyph(at, kind, colour)


## The shapes themselves, and the only place any of them is drawn.
func _draw_kind_glyph(
	at: Vector2, kind: Glyph, colour: Color, along: Vector2 = Vector2.DOWN
) -> void:
	if kind == Glyph.ENGINE:
		var across: Vector2 = along.orthogonal() * GLYPH * 0.8
		_canvas.draw_colored_polygon(PackedVector2Array([
			at + along * GLYPH, at - along * GLYPH + across, at - along * GLYPH - across,
		]), colour)
		return
	if kind == Glyph.MOD:
		# A plug: a small square with two pins, which is what a mod is --
		# a thing that goes into something else.
		var body: Vector2 = Vector2(GLYPH, GLYPH) * 0.7
		_canvas.draw_rect(Rect2(at - body, body * 2.0), colour, false, 1.0)
		for side: float in [-0.4, 0.4]:
			_canvas.draw_line(
				Vector2(at.x + side * GLYPH * 2.0, at.y + body.y),
				Vector2(at.x + side * GLYPH * 2.0, at.y + GLYPH * 1.4),
				colour,
				1.0,
			)
		return
	if kind == Glyph.CELL:
		# Cell plates, long and short, the way a battery is drawn.
		for row: Array in [[-1.0, 1.0], [0.0, 0.5], [1.0, 1.0]]:
			var half: float = GLYPH * float(row[1])
			var y: float = at.y + float(row[0]) * GLYPH * 0.7
			_canvas.draw_line(Vector2(at.x - half, y), Vector2(at.x + half, y), colour, 1.0)
		return
	if kind == Glyph.DISH:
		# A dish: an arc looking forward off a stem.
		_canvas.draw_arc(at, GLYPH, PI * 1.15, PI * 1.85, 10, colour, 1.0)
		_canvas.draw_line(at, at + Vector2(0.0, GLYPH), colour, 1.0)
		return
	if kind == Glyph.RING:
		# A ring with a line through it: the thing you go through, drawn
		# as the thing it does rather than as the box it lives in.
		_canvas.draw_arc(at, GLYPH * 0.8, 0.0, TAU, 12, colour, 1.0)
		_canvas.draw_line(
			at - Vector2(GLYPH * 1.3, 0.0), at + Vector2(GLYPH * 1.3, 0.0), colour, 1.0
		)
		return
	if kind == Glyph.DRUM:
		# A drum: a box with a band across it.
		var body: Vector2 = Vector2(GLYPH * 0.8, GLYPH)
		_canvas.draw_rect(Rect2(at - body, body * 2.0), colour, false, 1.0)
		_canvas.draw_line(
			Vector2(at.x - body.x, at.y), Vector2(at.x + body.x, at.y), colour, 1.0
		)
		return
	if kind == Glyph.CHIP:
		# A chip: a die with legs down both sides.
		_canvas.draw_rect(Rect2(at - Vector2(GLYPH, GLYPH) * 0.7, Vector2(GLYPH, GLYPH) * 1.4),
			colour, false, 1.0)
		for side: float in [-1.0, 1.0]:
			for step: float in [-0.5, 0.5]:
				var y: float = at.y + step * GLYPH
				_canvas.draw_line(
					Vector2(at.x + side * GLYPH * 0.7, y),
					Vector2(at.x + side * GLYPH * 1.3, y),
					colour,
					1.0,
				)
		return
	if kind == Glyph.STRUT:
		# A strut on a pad, the same shape the legs are drawn on the hull.
		_canvas.draw_line(at - Vector2(0.0, GLYPH), at + Vector2(0.0, GLYPH), colour, 1.0)
		_canvas.draw_line(
			at + Vector2(-GLYPH, GLYPH), at + Vector2(GLYPH, GLYPH), colour, 1.0
		)


## What a gun mount has in it, or that it has nothing.
##
## Three families rather than the six types, because at eleven pixels the
## difference between a pulse gun and an autocannon is not drawable -- and
## it is not the question either. What a pilot reads off a schematic is
## whether that mount throws something, burns something or launches
## something, and the card answers the rest.
func _draw_weapon_glyph(at: Vector2, weapon: WeaponData, colour: Color) -> void:
	if weapon == null:
		# An empty socket, deliberately not a sight: nothing here aims.
		_canvas.draw_arc(at, GLYPH * 0.75, 0.0, TAU, 10, colour, 1.0)
		return
	if weapon.is_beam():
		# One unbroken line, which is what a beam is.
		_canvas.draw_line(
			at - Vector2(0.0, GLYPH * 1.3), at + Vector2(0.0, GLYPH * 1.3), colour, 1.0
		)
		return
	if weapon.is_missile():
		# A dart on its tail.
		_canvas.draw_colored_polygon(PackedVector2Array([
			at + Vector2(0.0, -GLYPH), at + Vector2(GLYPH * 0.7, GLYPH * 0.2),
			at + Vector2(-GLYPH * 0.7, GLYPH * 0.2),
		]), colour)
		_canvas.draw_line(
			at + Vector2(0.0, GLYPH * 0.2), at + Vector2(0.0, GLYPH), colour, 1.0
		)
		return
	# A crosshair for anything that throws a round: what a gun is for, rather
	# than what it looks like.
	_canvas.draw_line(at - Vector2(GLYPH, 0.0), at + Vector2(GLYPH, 0.0), colour, 1.0)
	_canvas.draw_line(at - Vector2(0.0, GLYPH), at + Vector2(0.0, GLYPH), colour, 1.0)


## The box a slot occupies on the schematic. Public because the click test
## and the drawing must agree about it, and the way to make sure they do is
## to have one of them.
func slot_rect(at: Vector2, side: float = SLOT) -> Rect2:
	return Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side))


## The slot whose name a click put on the schematic, if any. Public so the
## test can read the visible consequence of a click rather than infer it.
func named_slot() -> Node:
	return _named


## The schematic's panel. Public so a click can be aimed at a slot without
## the caller reproducing the layout.
func plan_rect() -> Rect2:
	return _panels()["plan"]


## Where every slot is drawn, keyed by the mount. Public for the same reason
## as slot_rect: the click and the picture have to be the same picture.
##
## Two answers, because there are two kinds of question. Things bolted to
## the hull are drawn where they are, spread apart only as far as they
## have to be to stay clickable. Things inside it get the column down the
## edge -- they are volumes rather than points, and pretending otherwise
## is what made five boxes land on one spot and needed a whole
## fanning-out routine to undo.
##
## On the drawing only, either way. The nodes themselves carry mass, and
## moving one to tidy a picture would move the centre of mass.
func slot_positions(panels: Dictionary) -> Dictionary:
	var plan: Rect2 = panels["plan"]
	var place: Callable = _plan_placement(plan)
	var out: Dictionary = {}
	var taken: Array[Vector2] = []
	for mount: Node in _hull_mounts():
		out[mount] = _free_near(place.call((mount as Node2D).position), taken, plan)
		taken.append(out[mount])
	var strip: Rect2 = panels["bays"]
	var at: Vector2 = strip.position + Vector2(strip.size.x * 0.5, PAD + ROW * 2.0)
	for mount: Node in _internal_mounts():
		out[mount] = at
		at += Vector2(0.0, SLOT + 4.0)
	return out


## A place for one slot: its own, or the nearest free one that is still
## on the panel.
##
## Spread **about** the spot and sideways when a column fills, which took
## three goes to get right. Marching always downwards worked while the
## hull had three internal bays; with five it walked the landing gear a
## pixel past the bottom edge, and a slot drawn outside the schematic is
## a slot nobody can click. Alternating up and down fixed that and ran
## into the real limit: fifteen boxes eleven pixels tall do not fit in
## one column of a panel a hundred and fifty-eight pixels high, so the
## gear ended up at the top of the ship it hangs under. The panel is four
## hundred pixels wide and was using none of it.
##
## On the schematic only. The nodes themselves carry mass, and moving one
## to tidy a drawing would move the centre of mass.
func _free_near(home: Vector2, taken: Array[Vector2], plan: Rect2) -> Vector2:
	var at: Vector2 = home
	for attempt: int in range(1, 48):
		if not _collides(at, taken) and plan.encloses(slot_rect(at)):
			return at
		var step: int = attempt % 12
		var column: int = attempt / 12
		var rung: float = float((step + 1) / 2) * SLOT * 0.6
		at = home + Vector2(
			float((column + 1) / 2) * SLOT * 1.25 * (1.0 if column % 2 == 1 else -1.0),
			rung if step % 2 == 1 else -rung,
		)
	return at


func _collides(at: Vector2, taken: Array[Vector2]) -> bool:
	for other: Vector2 in taken:
		if slot_rect(at).intersects(slot_rect(other)):
			return true
	return false


## The wedge a gun can cover, from its rest direction. A number in a panel
## does not tell a pilot whether the nose gun reaches behind the wing; a
## wedge on the schematic does.
func _draw_arc_for(gun: Hardpoint, at: Vector2) -> void:
	var arc: float = gun.traverse()
	var rest: float = gun.rotation - PI * 0.5
	var colour: Color = Color(_ink.ok, 0.35) if gun.trigger == 0 else Color(_ink.caution, 0.35)
	# Standing off the box rather than starting at its centre. Drawn from the
	# centre, the two edge lines cross the slot and meet on the glyph, which
	# left the mount showing an arc and no longer showing what was in it.
	var inner: float = SLOT * 0.75
	var outer: float = inner + ARC_LENGTH
	if arc <= 0.0:
		# A fixed gun still shows which way it looks, as one line: the
		# absence of an arc is information too.
		_canvas.draw_line(
			at + Vector2.from_angle(rest) * inner,
			at + Vector2.from_angle(rest) * outer,
			colour,
			1.0,
		)
		return
	_canvas.draw_arc(at, outer, rest - arc, rest + arc, 16, colour, 1.0)
	for edge: float in [rest - arc, rest + arc]:
		_canvas.draw_line(
			at + Vector2.from_angle(edge) * inner,
			at + Vector2.from_angle(edge) * outer,
			colour,
			1.0,
		)


## The comparison, as the two panels the sketch asks for.
##
## Side by side and always both, which is the whole of why it is two
## panels now: a swap is a question about the difference between two
## things, and one you have to look at in two goes is two readings
## taken a moment apart. The left is what you are holding, the right is
## what is in the socket you are aiming at.
func _draw_cards(font: Font, carried: Rect2, fitted: Rect2) -> void:
	var x: float = carried.position.x + PAD
	var y: float = carried.position.y + PAD + float(FONT_SIZE)
	var picked: Dictionary = _selected()
	var floor_y: float = carried.end.y - PAD - ROW
	var replacing: Resource = _fitted_in(_highlighted())

	_text(font, Vector2(x, y), "CARRYING", _ink.label)
	y += ROW * 1.4
	if picked.is_empty():
		_text(font, Vector2(x, y), "nothing picked", _ink.inert)
	else:
		_inspecting = null
		for line: String in _card(picked["item"] as Resource, replacing):
			if y > floor_y:
				break
			_text(font, Vector2(x, y), line, _ink.value)
			y += ROW
	if not _notice.is_empty():
		_text(font, Vector2(x, carried.end.y - PAD), _notice, _ink.caution)

	# The right-hand side is what happens if you do it: what is in the
	# socket now, and what the ship would become.
	var rx: float = fitted.position.x + PAD
	var ry: float = fitted.position.y + PAD + float(FONT_SIZE)
	var shown: Resource = replacing if replacing != null else _inspecting
	_text(font, Vector2(rx, ry), "FITTED", _ink.label)
	ry += ROW * 1.4
	if shown == null:
		_text(font, Vector2(rx, ry), "socket is empty", _ink.inert)
	else:
		for line: String in _card(shown, null):
			if ry > fitted.end.y - PAD - ROW:
				break
			_text(font, Vector2(rx, ry), line, _ink.inert)
			ry += ROW
	ry += ROW * 0.4
	for line: String in _verdict():
		if ry > fitted.end.y - PAD - ROW:
			break
		_text(font, Vector2(rx, ry), line, _ink.ok)
		ry += ROW
	_text(font, Vector2(rx, fitted.end.y - PAD), _keys(), _ink.label)


func _keys() -> String:
	return "arrows: pick   F: fit   S: stow   , .: turn   G: trigger   Bksp: overboard"


func _label(item: Resource) -> String:
	var module: ModuleData = item as ModuleData
	return "module" if module == null else module.title()


## What is fitted in a mount, whichever kind of mount it is.
func _fitted_in(slot: Node) -> Resource:
	if slot is Hardpoint:
		return (slot as Hardpoint).weapon
	if slot is EngineMount:
		return (slot as EngineMount).installed
	if slot is ModuleBay:
		return (slot as ModuleBay).installed
	if slot is LandingGear:
		return (slot as LandingGear).installed
	return null


## The card for a module, from the module itself. `against` is what it would
## replace, which puts the difference on every row.
func _card(item: Resource, against: Resource) -> PackedStringArray:
	var module: ModuleData = item as ModuleData
	if module == null:
		return PackedStringArray(["unknown module"])
	return module.card_lines(against as ModuleData)

