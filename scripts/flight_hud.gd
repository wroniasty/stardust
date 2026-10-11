class_name FlightHud
extends CanvasLayer
## What the pilot flies by, drawn rather than spelled out.
##
## Replaces a column of eight text rows. The rows were honest and they were
## slow to read: "PERI -1651 / APO 693" is two numbers a pilot has to build
## a picture from, every time, while about to land. The picture is the
## thing they actually want, so the HUD draws it -- the planet, the conic,
## and a dot at each end of it -- and keeps the numbers beside it for the
## ones that are genuinely numbers.
##
## Two widgets, and which one is up says where you are. Inside a well the
## question is "what is this orbit doing"; outside it the question is
## "which way am I going and how fast", and an orbit diagram around a
## planet you are not near would be answering neither.
##
## Every value here is one the landing check actually uses (IDEAS.md
## section 7). This is the game saying what it is about to judge you on.

const FONT_SIZE: int = 8
const ROW: float = 10.0


## Slope and descent turn amber at this fraction of what the gear will take.
const CAUTION_FRACTION: float = 0.6

## The bars in the ship corner: hull, heat, energy, jump drive.
##
## Eleven tall, which is the font plus a pixel of air either side --
## the figure is written **on** the bar now rather than in a row under
## it, which is what pays for the height. A labelled row and a bar were
## two readouts of one number sitting one above the other; the bar is
## the one that answers at a glance, so the number moved into it and
## the label went. Four unlabelled bars in a fixed order are learned
## once, and after that a colour at a height is the reading.
## Every bar this panel can show, in the order it shows them.
##
## Written down once because without labels the order **is** the
## identity of a bar, and because the panel has to be tall enough for
## all of them at once -- which is a fact about this list rather than a
## number to keep in step with it by hand.
const BARS: Array[StringName] = [&"hull", &"heat", &"energy", &"fuel", &"jump"]

## How many bars the ship panel is allowed to grow to.
##
## Five today, with room kept for three more. The tape below reserves
## against **this** rather than against what is on screen, so a bar
## arriving -- heat coming up, a drive charging -- does not shove the
## altitude scale down the screen at the moment it is being read.
const BARS_ROOM: int = 8

const BAR_HEIGHT: float = 11.0

## One pixel between them, which is what five bars in a sixty pixel
## panel leaves: `5 * (11 + 1)` is exactly sixty. The height went to
## the bars rather than to the gaps because the height is what holds
## the figure.
const BAR_GAP: float = 1.0

## How much air the figure gets either side of itself, inside the plate
## it is written on, and how solid that plate is.
##
## The glyphs themselves cannot be made smaller, which is worth writing
## down because it looks like a setting and is not: the face is a
## bitmap at eight pixels with `FIXED_SIZE_SCALE_INTEGER_ONLY`
## (`UiFont`), so 5, 6, 7 and 8 all render identically -- measured --
## and the next size down from eight is nothing. What the figure can
## give back is the weight of what it sits on, so the plate is thin
## and see-through rather than a black box.
const BAR_TEXT_PAD: float = 1.0
const BAR_PLATE_OPACITY: float = 0.55

## How energy and fuel are printed. Finer than whole units because
## both are read while deciding whether there is enough for one more
## of something, and the last one is where that question lives.
const ENERGY_FORMAT: String = "%.1f"
const FUEL_FORMAT: String = "%.2f"

## The warning band: where it sits, and how much air it gets.
##
## A fixed place whether or not there is anything in it, which is the
## point of it. A pilot who has to find the red is a pilot reading the
## panel to discover that something is wrong, and by then they have
## spent the quarter second the warning was buying them.
const WARNING_TOP: float = 19.0
const WARNING_HEIGHT: float = 11.0
const WARNING_PAD: float = 4.0

## How much of the band's ground is lit, pulsing and between pulses.
## Never nothing: the band going dark would be the band disappearing,
## and half of a square wave is a long time to be invisible.
const WARNING_LIT: float = 0.42
const WARNING_DIM: float = 0.14

## The orbit diagram: a square, with the text column beside it.
## How high the altitude tape reaches, in design pixels.
##
## Three thousand because that is the band a descent is flown in: the
## approach lock takes the camera at six hundred, the landing check
## starts caring well inside that, and above three thousand the exact
## figure matters less than the fact that it is a long way down -- which
## the cursor parked at the top says without a number.
##
## A fixed band rather than one that follows the ship, because the
## whole point of a tape over a row of digits is that the **position**
## means something. A scale that rescales itself is a scale the eye has
## to read before it can be used.
const TAPE_TOP: float = 3000.0

## Minor ticks every this far, with a labelled one every fourth.
const TAPE_STEP: float = 250.0
const TAPE_MAJOR: int = 4

## How each figure in the instrument corner is printed.
##
## Constants rather than literals at the call site, because the check
## that they fit their panel has to be able to ask for the widest thing
## each one can produce. A format changed in place and not here is one
## the fit check goes on measuring the old version of.
const SPEED_FORMAT: String = "%.0f"
const DESCENT_FORMAT: String = "%+.1f"

## The largest each of those can ever have to print.
##
## Facts about flying rather than about the strings: a ship can be
## doing tens of thousands of pixels a second out of a well, and a
## descent rate past four digits is a crash that has already happened.
## The band is sized from them, so a format that prints wider gets a
## wider band instead of running off the side of one.
const SPEED_WIDEST: float = 99999.0
const DESCENT_WIDEST: float = -9999.0

## And the pull, which is the third figure under the tape.
##
## Acceleration in design pixels per second squared, which is the unit
## everything else about flying is already in: thrust against mass
## comes out in it, and so does the descent rate's own rate of change.
## A pilot reading "my drive gives 40 and this world pulls 12" can do
## the arithmetic that decides whether they are going to be able to
## lift off again.
const GRAVITY_FORMAT: String = "%.1f"
const GRAVITY_WIDEST: float = 999.9

## How much air the figures get below the scale, and how tall each of
## their boxes is.
##
## The gap is the whole font, because the scale's own bottom label sits
## on its last tick: without it the zero of the altitude band and the
## first figure were in the same pixels, which is what this was
## reported as.
const TAPE_FIGURE_GAP: float = 8.0
const TAPE_FIGURE_ROW: float = 12.0

## How solid the plate behind a figure is. Barely there on purpose: it
## is a hint of a panel rather than a panel, because this one sits on
## the starfield rather than in a corner.
const TAPE_FIGURE_FILL: float = 0.10

## The orbit dial. Forty-six rather than sixty-six, because the
## untouchable field leaves a corner 116 px wide and the apsides have
## to stand beside the picture rather than under it.
const DIAL: float = 46.0

## The heading dial out in the open, where there is no orbit to draw.
const ARROW_DIAL: float = 40.0

## How much world shows through a panel.
const PANEL_OPACITY: float = 0.86

## The controls, down the bottom left: one labelled button per thing
## the pilot can switch.
##
## Words rather than drawn glyphs. A seven-pixel square can carry a
## symbol a pilot has to learn; three letters they already know carry
## themselves, and `SAS`, `PRG`, `DEO` are the shorthand the subject
## comes with. The glyphs were the earlier answer and they were asked
## to go.
##
## The same width as the figures under the tape, because they stand in
## the same column of the screen and two stacks of boxes an unequal
## width apart read as two things with nothing to do with each other.
const CONTROL_HEIGHT: float = 12.0
const CONTROL_GAP: float = 1.0

## How solid the ground under an available button is. Barely there, in
## the same way the figures under the tape are: these sit on the
## world, not in a panel.
const CONTROL_FILL: float = 0.10

## How big a glyph is drawn inside a switch: a little over a third of
## the square either side of centre, so the stroke never touches the
## border that carries the state.
const SWITCH_GLYPH: float = 5.5

## How the planet is drawn in the diagram, and the apsis dots.
const PLANET_DOT: float = 2.5
const APSIS_DOT: float = 1.8

## Half-width of the square that marks the ship on the dial.
##
## A square and not a dot, because there are three marks on that dial
## and two of them were already dots -- one of them in the same green
## the ship was drawn in, a fifth of a pixel bigger. Shape carries which
## is which and colour carries what it is doing, the same way round as
## the scanner's triangle, diamond and cross.
const SHIP_MARK: float = 1.8

## How far apart the two apsides have to be on the dial before they are
## worth marking separately, in pixels. Below it they are the same place
## and the vector that aims them is noise -- see `GravityWell.CIRCULAR`.
##
## Faded in across this distance rather than switched on at it. A hard
## threshold is a flicker of its own: an orbit sitting on the line would
## strobe both dots on and off, tick after tick, which is the fault this
## constant exists to stop.
const APSIS_SPREAD: float = 2.0

## Segments the conic is drawn with. Sixty-four is smooth at sixty-six
## pixels across and cheap enough to do every frame.
const CONIC_STEPS: int = 64

## A ship in orbit gets a thicker line and a word for it.
##
## The line alone was the first attempt and it was not enough, which a
## pilot said before I noticed: a colour is a shade you have to remember,
## and one pixel of extra thickness is a shade you have to remember with
## a reference beside it. The word is unambiguous and costs five
## characters of a panel that has room for them.
##
## Nothing is said for a suborbital path, because that is the normal state
## of a ship taking off or coming in to land -- saying it would be noise
## on the one line meant to carry news, and the red periapsis says it
## anyway.
const ORBIT_WIDTH: float = 2.5
const TRACK_WIDTH: float = 1.0
const STATE_WORDS: Dictionary = {
	GravityWell.OrbitState.ORBIT: "ORBIT",
	GravityWell.OrbitState.DECAYING: "DECAY",
	GravityWell.OrbitState.ESCAPE: "ESCAPE",
}

## The transfer arrow, for when there is no well to be in.
const ARROW_LENGTH: float = 15.0
const ARROW_HEAD: float = 4.0

var _ship: Ship = null
var _rig: MiningRig = null
var _canvas: Control = null

## The drive, for the charge bar. Handed in rather than looked up: the
## controller belongs to the world, not to the ship, and a panel that
## went hunting for it would be a panel with no tests.
var _jump: JumpController = null





## The twelve colours every screen draws from (UI_STYLE section 3). This
## file used to spell out its own, which is how three screens ended up
## with two panel fills, two borders and three ambers a pixel apart.
var _ink: Palette = Palette.current()

## Every reading that is both drawn and printed, which on this panel is
## all of them (UI_STYLE section 7). The quantum is the step the figure
## counts in: a pixel for a height, a tenth for a rate.
##
## Fed once a frame in `_process` and read in the draw. That split is
## not tidiness -- a draw can run twice for one frame or not at all for
## a skipped one, so a smoothing fed from inside it would advance at
## whatever rate the renderer happened to feel like.
## How long the energy bar stays framed in red after a refused shot,
## and how many notches it will draw before they stop being countable.
## Both came up here with the bar from `EnergyHud`.
const REFUSAL_FLASH: float = 0.35
const MAX_NOTCHES: int = 24

## Seconds left of that flash.
var _refused_for: float = 0.0

var _hull: UiValue = UiValue.new(1.0)
var _speed: UiValue = UiValue.new(1.0)
var _altitude: UiValue = UiValue.new(1.0)
var _descent: UiValue = UiValue.new(0.1)


func _ready() -> void:
	layer = 10
	# Keeps drawing while the tree is paused, so the planet configurator can
	# rebuild a world and show its numbers without unpausing. A readout that
	# freezes with stale values is worse than no readout.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)


## What is under the legs, for the ORE row. Handed in rather than looked
## up, like everything else here, and allowed to be null: a HUD with no
## rig simply has nothing to say about the ground.
func watch_ground(rig: MiningRig) -> void:
	_rig = rig


## The jump drive this panel watches charge. Allowed to be null: a
## world without one simply never grows the fourth bar.
func watch_jump(jump: JumpController) -> void:
	_jump = jump


func bind(ship: Ship) -> void:
	if _ship != null and is_instance_valid(_ship) and _ship.shot_refused.is_connected(_on_refused):
		_ship.shot_refused.disconnect(_on_refused)
	_ship = ship
	if _ship != null:
		_ship.shot_refused.connect(_on_refused)
	# Fresh readings for a fresh hull. Kept across the swap they would
	# spend the first tenth of a second easing over from whatever the
	# last ship was doing, which is a readout lying during the one
	# moment a pilot is certain to be looking at it.
	_hull = UiValue.new(1.0)
	_speed = UiValue.new(1.0)
	_altitude = UiValue.new(1.0)
	_descent = UiValue.new(0.1)


func _on_refused() -> void:
	_refused_for = REFUSAL_FLASH


func _process(delta: float) -> void:
	_refused_for = maxf(_refused_for - delta, 0.0)
	_read(delta)
	if _canvas != null:
		_canvas.queue_redraw()
	# The ship has to know the pointer is over a switch, because firing
	# is polled rather than driven by events: `Ship.read_player_input`
	# asks `Input.is_action_pressed("ship_fire")`, so consuming the click
	# here would stop the panel's own handler and not the guns.
	if _ship != null and is_instance_valid(_ship):
		_ship.ui_grabs_pointer = _over_panel(_canvas.get_local_mouse_position())








## Clicks on the computer panel, and nothing else on this layer.
##
## On the `CanvasLayer` rather than on a `Control` tree, because the
## panel is drawn rather than built: UI_STYLE section 12 says a widget
## has no node of its own, and seven `Button`s would be seven nodes
## carrying themes, focus and a tab order into a HUD that wants none of
## it. The cost is this function, which is the hit test the nodes would
## have done.
func _input(event: InputEvent) -> void:
	if _ship == null or not is_instance_valid(_ship) or _canvas == null:
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	# The event's own position, mapped into the canvas, rather than
	# wherever the pointer happens to be now. They agree in a running
	# game and they are not the same question: one is "where was this
	# click", the other "where is the mouse", and a handler that asks
	# the second is a handler that cannot be driven by a synthesised
	# event -- which is how this was found.
	var local: InputEventMouseButton = (
		_canvas.make_input_local(click) as InputEventMouseButton
	)
	if local != null and press_at(local.position):
		get_viewport().set_input_as_handled()


## One sample of everything the panel shows, once a frame.
##
## The arithmetic lives here and only here. It used to sit inside the
## draw, which meant the orbit panel worked out the descent rate and
## nothing else could see it; now the draw reads what was sampled and
## does no sums of its own.
func _read(delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	_hull.feed(clampf(_ship.hull_integrity, 0.0, 1.0) * 100.0, delta)
	_speed.feed(_ship.linear_velocity.length(), delta)

	var planet: GravityWell = host()
	if planet == null:
		return
	_altitude.feed(planet.height_above_terrain(_ship.global_position), delta)
	# Against the ground, which moves on a spinning planet: the same
	# quantity the landing check uses, so the two cannot disagree.
	var up: Vector2 = (_ship.global_position - planet.global_position).normalized()
	var relative: Vector2 = _ship.linear_velocity - planet.surface_velocity_at(
		_ship.global_position
	)
	_descent.feed(-relative.dot(up), delta)


## The body whose well the ship is actually in, or null out in the dark.
##
## Nearest is not the same question. The old readout showed a planet's
## numbers from anywhere in the system, because the nearest planet is
## always some planet; what matters is whether its gravity reaches here,
## because outside that the conic it would draw is not the path the ship
## is on.
##
## The body whose well the ship is in, and only if it is a body with
## ground on it.
##
## The star is left out deliberately, and it was in for one commit. Under
## patched wells a ship between the orbits really is falling round the
## star on an exact conic, so the panel was honest -- and useless. It was
## up the whole time, because there is nowhere in a system that is not
## inside the star's reach, and a readout that is always on is a readout
## nobody looks at. An orbit diagram earns its place when there is
## something to arrive at; crossing between planets, the question is
## which way and how fast, and that is the transfer widget's job.
func host() -> GravityWell:
	if _ship == null or not is_instance_valid(_ship):
		return null
	var local: GravityWell = GravityWell.local_at(get_tree(), _ship.global_position)
	return local if local != null and local.has_ground() else null


func _draw_hud() -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	var font: Font = ModuleData.card_font()
	var view: Vector2 = _canvas.size
	var well: GravityWell = host()

	# No slab behind the bars. Each one is already a filled rectangle
	# with a border, so a panel under them was a box inside a box --
	# and four of them fill the corner, which leaves the backing
	# showing only as a dark seam between bars.
	_draw_ship_corner(font, UiFrame.inside(UiFrame.slot(view, UiFrame.Slot.SHIP)))
	if well != null:
		_draw_world_corner(font, _panel(view, UiFrame.Slot.WORLD), well)
	# The instruments get the only full border in the interface: at
	# landing they lie over terrain, which is the messiest ground the
	# game owns, and corner brackets vanish into it.
	_draw_instrument_corner(font, _panel(view, UiFrame.Slot.INSTRUMENTS, true), well)
	# The context corner is left undrawn while there is nothing to put
	# in it. An empty panel is not restraint -- it is a box that
	# teaches the eye to skip that part of the screen, which is the one
	# habit an interface must not train.
	_draw_altitude_tape(font, view, well)
	_draw_controls(font)
	_draw_warning_band(font, view)




## Where the controls are, in canvas pixels.
##
## Worked out here and nowhere else, which is the rule this panel keeps
## learning: the draw uses it to draw, the press uses it to hit-test,
## and `_process` uses it to tell the ship the pointer is busy. Three
## readers is exactly how many copies of a layout it takes for one to
## drift.
##
## They grow **upwards** from the bottom left corner. That corner is
## the one the frame law gives to the momentary, and what the ship is
## being made to do is exactly that -- and growing up rather than along
## is what lets eight of them be a column at a width the eye can read,
## instead of a grid of squares at a width it cannot.
func control_layout() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _ship == null or not is_instance_valid(_ship) or _canvas == null:
		return out
	var font: Font = ModuleData.card_font()
	var wide: float = band_width(font)
	var box: FlightComputerData = _ship.computer()
	var step: float = CONTROL_HEIGHT + CONTROL_GAP
	var at: float = controls_top(_canvas.size)
	for one: Dictionary in FlightAssists.ALL:
		var kind: int = int(one["kind"])
		out.append({
			"kind": kind,
			"box": Rect2(Vector2(UiFrame.EDGE, at), Vector2(wide, CONTROL_HEIGHT)),
			"offered": FlightAssists.offered_by(kind, box),
			"says": FlightAssists.code(kind),
		})
		at += step
	return out


## How far up the screen the controls reach, so the tape knows where to
## stop.
## Takes the view rather than reading the canvas, because `tape_box`
## takes one too and the two have to agree about how big the screen
## is: asked one way and answered the other, the tape ran down over
## the controls in every check that passed a size by hand.
func controls_top(view: Vector2) -> float:
	return (
		view.y - UiFrame.EDGE
		- float(FlightAssists.ALL.size()) * (CONTROL_HEIGHT + CONTROL_GAP)
	)


## Whether a point is over something that can be clicked.
func _over_panel(at: Vector2) -> bool:
	for one: Dictionary in control_layout():
		if (one["box"] as Rect2).has_point(at):
			return true
	return false


## A press at a point on the canvas, and whether the controls took it.
##
## Split from `_input` so a test can press the thing a pilot presses.
## The first version of this was the hit test inside the input handler,
## which a headless check can only exercise by moving a mouse it has
## not got -- so the check would have measured the layout and called it
## a button.
func press_at(at: Vector2) -> bool:
	for one: Dictionary in control_layout():
		if not (one["box"] as Rect2).has_point(at):
			continue
		# A button for something this ship cannot do is still a button
		# a click lands on: it keeps its place so the column cannot
		# reshuffle, `toggle_assist` refuses it, and taking the click
		# anyway is what stops the guns going off on a dead control.
		_ship.toggle_assist(int(one["kind"]))
		return true
	return false


## The controls themselves: one labelled button each.
##
## Three states, and they are the law's three read as controls rather
## than as readings (UI_STYLE section 12, trap 2): the ship cannot do
## this, it can and it is off, it can and it is on. A button for
## something the fitted box has not got keeps its place rather than
## being dropped, so the column means the same thing on every ship.
func _draw_controls(font: Font) -> void:
	for one: Dictionary in control_layout():
		var cell: Rect2 = one["box"]
		var offered: bool = bool(one["offered"])
		var on: bool = offered and _ship.is_latched(int(one["kind"]))
		var ink: Color = _ink.inert
		var edge: Color = _ink.grid
		if on:
			# Yellow on green, which is the one place in the interface
			# those two appear as a pair. A lone amber **value** means
			# trouble and still does; a filled green chip with a bright
			# legend on it is a switch that is down, and nothing else
			# on screen looks like it.
			_canvas.draw_rect(cell, _ink.over(_ink.ok, 0.85), true)
			ink = _ink.caution
			edge = _ink.caution
		elif offered:
			_canvas.draw_rect(cell, _ink.over(_ink.panel, CONTROL_FILL), true)
			ink = _ink.value
			edge = _ink.edge
		UiDraw.bracket(_canvas, cell, edge)
		var says: String = String(one["says"])
		_canvas.draw_string(
			font,
			UiDraw.snap(Vector2(
				cell.position.x + (cell.size.x - UiDraw.text_width(font, says)) * 0.5,
				cell.position.y + (cell.size.y + float(UiFont.BODY)) * 0.5 - 1.0,
			)),
			says,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, ink,
		)





## One panel in its slot, handing back the room left inside it.
func _panel(view: Vector2, which: int, edged: bool = false) -> Rect2:
	var box: Rect2 = UiFrame.slot(view, which)
	UiDraw.panel(
		_canvas,
		box,
		_ink.over(_ink.panel, PANEL_OPACITY),
		_ink.edge if edged else _ink.grid,
		UiFrame.corner(which),
		edged,
	)
	return UiFrame.inside(box)


## Top left: what will kill me.
##
## Hull as a bar, because hull is the one reading whose *trend* matters
## more than its value -- nobody flies on 63 per cent, they fly on
## "still most of it" or "nearly gone", and a length says that without
## being read.
func _draw_ship_corner(font: Font, at: Rect2) -> void:
	var health: float = clampf(_hull.smooth() * 0.01, 0.0, 1.0)
	var colour: Color = _ink.ok
	if health < 0.25:
		colour = _ink.alarm
	elif health < CAUTION_FRACTION:
		colour = _ink.caution

	var y: float = at.position.y
	for one: Dictionary in ship_bars():
		var box: Rect2 = Rect2(
			Vector2(at.position.x, y), Vector2(at.size.x, BAR_HEIGHT)
		)
		y = _draw_bar(font, box, float(one["fill"]), one["ink"], String(one["says"]))
		match StringName(one["kind"]):
			&"heat":
				_draw_burn_mark(box)
			&"energy":
				_draw_notches(box)

	# Emergency power up here rather than down in the instruments: it
	# is the one reading a pilot wants while looking at the ground
	# coming up. Shown when asked for and refused as well as when
	# running -- "nothing happened when I pressed it" has to have an
	# answer on the screen, and the answer is an empty pool.
	# The two rows below the bars are conditional and so are two of the
	# bars, so in the worst case -- hot, charging, boosting, alongside
	# a dock -- there is no room left for them. Dropped rather than
	# drawn past the bottom edge, where they would land on the
	# altitude tape.
	if _ship.boost_command and y + ROW <= at.end.y:
		UiDraw.row(
			_canvas, font, Vector2(at.position.x, y + float(UiFont.BODY)), at.size.x,
			"BOOST", "ON" if _ship.boost_active else "--",
			_ink.caution if _ship.boost_active else _ink.alarm, _ink.label,
		)
		y += ROW
	if y + ROW <= at.end.y:
		_draw_dock(font, Vector2(at.position.x, y + float(UiFont.BODY)), at.size.x)


## One bar with its figure on it, and where the next one starts.
##
## The figure is right-aligned inside the bar and takes its colour from
## **what is under it**: the panel's own dark where the fill has
## reached it, the bar's colour where it has not. One comparison, and
## it is what keeps a number legible at both ends of a bar that is
## bright at one end and nearly black at the other.
func _draw_bar(
	font: Font, box: Rect2, filled: float, ink: Color, says: String
) -> float:
	_canvas.draw_rect(box, _ink.over(_ink.scrim, 0.75), true)
	var across: float = roundf(box.size.x * clampf(filled, 0.0, 1.0))
	if across > 0.0:
		_canvas.draw_rect(
			Rect2(box.position, Vector2(across, box.size.y)), ink, true
		)
	_canvas.draw_rect(box, _ink.edge, false, 1.0)
	if not says.is_empty():
		# Centred, on a plate of its own. The first version put the
		# figure at the right-hand end and chose its colour from
		# whether the fill had reached it, which is one comparison and
		# two ways to be nearly unreadable: pale ink on a bright bar,
		# and a number that changes colour as the bar fills past it.
		# A plate costs one rectangle and is legible over anything.
		var wide: float = UiDraw.text_width(font, says)
		var left: float = roundf(box.position.x + (box.size.x - wide) * 0.5)
		_canvas.draw_rect(
			Rect2(
				Vector2(left - BAR_TEXT_PAD, box.position.y + 1.0),
				Vector2(wide + BAR_TEXT_PAD * 2.0, box.size.y - 2.0),
			),
			_ink.over(_ink.scrim, BAR_PLATE_OPACITY),
			true,
		)
		_canvas.draw_string(
			font,
			UiDraw.snap(Vector2(
				left, box.position.y + (box.size.y + float(UiFont.BODY)) * 0.5 - 1.0
			)),
			says,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, _ink.value,
		)
	return box.end.y + BAR_GAP




## Which bars the ship panel is showing, top to bottom.
##
## A list rather than four calls in a row, because what is worth
## checking about them is exactly what a list says and a sequence of
## draws does not: that the order is fixed, and that the two
## conditional ones come up when they should. Each entry is
## `{kind, fill, ink, says}`.
##
## Hull, energy and fuel are always there -- they are what ends a
## flight, and UI_STYLE section 12 forbids a build hiding any of them.
## Heat is absent at zero, because a gauge reading nothing through
## ordinary flight is a gauge the pilot learns to skip. The drive is
## absent unless it is charging, which is the only time it has
## anything to say.
func ship_bars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _ship == null or not is_instance_valid(_ship):
		return out

	var health: float = clampf(_hull.smooth() * 0.01, 0.0, 1.0)
	var hull_ink: Color = _ink.ok
	if health < 0.25:
		hull_ink = _ink.alarm
	elif health < CAUTION_FRACTION:
		hull_ink = _ink.caution
	out.append({
		"kind": &"hull", "fill": health, "ink": hull_ink,
		"says": "%.0f%%" % _hull.stepped(),
	})

	var heat: float = clampf(_ship.hull_heat, 0.0, 1.0)
	if heat > 0.01:
		out.append({
			"kind": &"heat", "fill": heat,
			"ink": _ink.alarm if heat >= Ship.BURN_HEAT else _ink.caution,
			"says": "%.0f%%" % (heat * 100.0),
		})

	# Energy and fuel say **how much**, not what fraction. A percentage
	# is the right answer for hull and for heat, which have no units a
	# pilot acts on; these two have, and the decisions are "can I take
	# another shot" and "can I get there" -- neither of which is a
	# share of anything.
	var capacity: float = _ship.energy_capacity()
	if capacity > 0.0:
		var charge: float = clampf(_ship.energy / capacity, 0.0, 1.0)
		out.append({
			"kind": &"energy", "fill": charge,
			"ink": _ink.inert if _ship.energy_waiting() else _ink.nav,
			"says": ENERGY_FORMAT % _ship.energy,
		})

	var tank: float = _ship.fuel_capacity()
	if tank > 0.0:
		out.append({
			"kind": &"fuel", "fill": clampf(_ship.fuel / tank, 0.0, 1.0),
			"ink": _ink.caution if _ship.fuel < tank * 0.2 else _ink.ok,
			"says": FUEL_FORMAT % _ship.fuel,
		})

	if _jump != null and is_instance_valid(_jump):
		if _jump.phase == JumpController.Phase.CHARGING:
			out.append({
				"kind": &"jump", "fill": _jump.progress(), "ink": _ink.accent,
				"says": "%.0f%%" % (_jump.progress() * 100.0),
			})
	return out


## The line on the heat bar where the hull starts burning.
func _draw_burn_mark(box: Rect2) -> void:
	var mark: float = roundf(box.position.x + box.size.x * Ship.BURN_HEAT)
	_canvas.draw_line(
		Vector2(mark, box.position.y - 1.0), Vector2(mark, box.end.y + 1.0),
		_ink.alarm, 1.0,
	)


## The energy bar notched at the cost of a shot, and framed in red when
## one has just been refused.
##
## The notches are the rule UI_STYLE section 6 makes for this one bar,
## and the reason it is not merely a percentage: a pilot reads "three
## left" off them and decides whether to hold the trigger. The figure
## written on it is the pool, which is a different question.
func _draw_notches(box: Rect2) -> void:
	var capacity: float = _ship.energy_capacity()
	var cost: float = shot_cost()
	if capacity > 0.0 and cost > 0.0:
		var notches: int = int(capacity / cost)
		if notches <= MAX_NOTCHES:
			for i: int in range(1, notches + 1):
				var x: float = box.position.x + box.size.x * (cost * float(i) / capacity)
				if x < box.end.x - 0.5:
					_canvas.draw_line(
						Vector2(x, box.position.y), Vector2(x, box.end.y),
						_ink.scrim, 1.0,
					)
	if _refused_for <= 0.0:
		return
	# A second frame outside the first: a colour change alone is easy
	# to miss in a firefight.
	_canvas.draw_rect(box, _ink.alarm, false, 1.0)
	_canvas.draw_rect(
		box.grow(2.0), Color(_ink.alarm, _refused_for / REFUSAL_FLASH), false, 1.0
	)


## The cost of one shot from the cheapest gun aboard, which is what a
## notch is worth. The cheapest rather than the first, so the notches
## never promise fewer shots than the ship can actually take.
func shot_cost() -> float:
	var cheapest: float = 0.0
	for hardpoint: Hardpoint in _ship.hardpoints:
		if hardpoint.weapon == null or hardpoint.weapon.energy_cost <= 0.0:
			continue
		if cheapest <= 0.0 or hardpoint.weapon.energy_cost < cheapest:
			cheapest = hardpoint.weapon.energy_cost
	return cheapest




## Whether a dock will have you, and which of the two numbers is being
## failed. "No" is not an answer anybody can fly on.
func _draw_dock(font: Font, at: Vector2, width: float) -> void:
	var says: String = ""
	var colour: Color = _ink.ok
	if _ship.flight_mode == Ship.FlightMode.DOCKED:
		says = "tied" if _ship.fully_serviced() else "repairing"
		colour = _ink.ok if _ship.fully_serviced() else _ink.caution
	elif not _ship.last_dock_rejection.is_empty():
		says = _ship.last_dock_rejection
		colour = _ink.caution
	if says.is_empty():
		return
	UiDraw.row(_canvas, font, at, width, "DOCK", says, colour, _ink.label)




## Top right: where I am. The conic, the two apsides, and when the next
## one arrives.
func _draw_world_corner(font: Font, at: Rect2, planet: GravityWell) -> void:
	var dial: Rect2 = Rect2(at.position, Vector2(DIAL, DIAL))
	var orbit: GravityWell.OrbitState = planet.orbit_state(
		_ship.global_position, _ship.linear_velocity
	)
	var shape: Dictionary = planet.orbit_shape(_ship.global_position, _ship.linear_velocity)
	if _ship.flight_mode != Ship.FlightMode.LANDED:
		_draw_conic(dial, planet, shape, orbit)
	else:
		# Landed: there is no coasting conic to draw, only where you are.
		_canvas.draw_circle(dial.get_center(), PLANET_DOT, _ink.nav)
		_canvas.draw_arc(dial.get_center(), DIAL * 0.5 - 3.0, 0.0, TAU, 48, _ink.nav, 1.0)

	var x: float = dial.end.x + 4.0
	var width: float = at.end.x - x
	var y: float = at.position.y + float(UiFont.BODY)
	var landed: bool = landed_now()
	UiDraw.row(
		_canvas, font, Vector2(x, y), width, "PERI",
		_apsis_text(planet, shape["periapsis"], landed), _orbit_colour(orbit), _ink.label,
	)
	y += ROW
	UiDraw.row(
		_canvas, font, Vector2(x, y), width, "APO",
		_apsis_text(planet, shape["apoapsis"], landed), _apoapsis_colour(shape), _ink.label,
	)
	y += ROW
	# Which apsis comes first, and how long until it does. One line
	# rather than two: the question up here is "what happens next", the
	# other apsis is half an orbit away, and the heights above already
	# say which of them is which. Blank when there is nothing to count
	# to, because a zero would read as "now".
	if not landed:
		var due: Vector2 = planet.seconds_to_apsis(
			_ship.global_position, _ship.linear_velocity
		)
		if due.y < due.x:
			_text(font, Vector2(x, y), "APO %s" % _countdown_text(due.y),
				_apoapsis_colour(shape))
		elif not is_inf(due.x):
			_text(font, Vector2(x, y), "PER %s" % _countdown_text(due.x),
				_orbit_colour(orbit))
	y += ROW
	if not planet.has_ground():
		UiDraw.row(
			_canvas, font, Vector2(x, y), width, "NAME",
			planet.catalogue_name(), _ink.value, _ink.label,
		)

	# The state of the track as a word, along the bottom of the panel.
	# Inside the dial it used to sit on the orbit ring it was
	# describing, in the same colour, which is a word you have to
	# already know is there in order to read it.
	if not landed:
		var says: String = state_text(orbit)
		if not says.is_empty():
			_text(font, Vector2(at.position.x, at.end.y), says, _orbit_colour(orbit))


## Bottom right: what I am doing now, and the only panel with a border.
func _draw_instrument_corner(font: Font, at: Rect2, planet: GravityWell) -> void:
	var y: float = at.position.y + float(UiFont.BODY)
	if planet == null:
		_draw_heading(at)
		var x: float = at.position.x + ARROW_DIAL + 4.0
		var width: float = at.end.x - x
		UiDraw.row(
			_canvas, font, Vector2(x, y), width, "V",
			"%.0f" % _speed.stepped(), _ink.ok, _ink.label,
		)
		y += ROW
		UiDraw.row(
			_canvas, font, Vector2(x, y), width, "GEAR",
			_gear_text(), _gear_colour(), _ink.label,
		)
		y += ROW
		_text(font, Vector2(x, y), "in transit", _ink.label)
		return

	# How high, how fast and how fast down are one instrument now and
	# live together on the tape. What is left here is the pair of
	# states a pilot has to be able to see without asking: what the
	# legs are doing, and what is under them.
	#
	# The gear whether or not there is ground, because a star is
	# exactly where leaving the legs out is a mistake worth seeing.
	UiDraw.row(
		_canvas, font, Vector2(at.position.x, y), at.size.x, "GEAR",
		_gear_text(), _gear_colour(), _ink.label,
	)
	y += ROW
	if planet.has_ground():
		_draw_ore(font, Vector2(at.position.x, y), at.size.x)
	_draw_warning(font, Rect2(at.position - Vector2(UiFrame.PAD, UiFrame.PAD), at.size))


## How the tape words a height: thousands as `3k`, the rest plainly.
##
## The band runs to three thousand and the panel is a hundred and ten
## pixels wide, so four digits of label beside four of readout is most
## of it. `3k` costs two characters and says the same thing on a scale
## whose only labels are round thousands.
func _tape_label(value: float) -> String:
	if absf(value) >= 1000.0 and is_zero_approx(fmod(value, 1000.0)):
		return "%.0fk" % (value / 1000.0)
	return "%.0f" % value


## The altitude tape, down the left edge between the two panels there.
##
## Not in a corner, and that is what it is for. The four corners answer
## four questions in a fixed place; height on an approach is not a
## figure to be looked up but a thing to be watched, and the band
## between the ship panel and the context panel is two hundred pixels
## of screen edge that answers nothing. A tape wants height far more
## than it wants width.
##
## Anchored to the edge rather than to where it was sketched, which was
## a few pixels further right: the pilot's untouchable 400x220 starts
## at x 120, and an instrument leaning into it is the one thing
## UI_STYLE section 5 forbids outright.
##
## No panel behind it. Every other readout sits on a dimmed slab
## because it is a block of text; this is a line and some ticks, and
## two hundred pixels of slab down the side of the screen would be the
## heaviest thing in the interface, holding the lightest.
func _draw_altitude_tape(font: Font, view: Vector2, well: GravityWell) -> void:
	if well == null:
		return
	var box: Rect2 = tape_box(font, view)
	if box.size.y <= 0.0:
		return

	# The figures at the foot of the scale. They belong to the same
	# instrument: height, speed, the rate the first is changing and
	# what is pulling on it are one reading taken four ways, and a
	# pilot on finals is looking at one place rather than four corners.
	var stats: Array[Dictionary] = tape_figures()
	var figures: float = (
		float(stats.size()) * TAPE_FIGURE_ROW + TAPE_FIGURE_GAP
	)
	# The scale takes only as much width as it needs; the band is wider
	# so that a figure has somewhere to sit past the line.
	var scale: Rect2 = Rect2(
		box.position,
		Vector2(
			spine_offset(font)
			+ UiDraw.ladder_label_room(font, Vector2(0.0, TAPE_TOP), _tape_label),
			box.size.y - figures,
		),
	)
	if well.has_ground():
		UiDraw.ladder(
			_canvas, font, scale,
			_altitude.stepped(), Vector2(0.0, TAPE_TOP), TAPE_STEP, TAPE_MAJOR,
			_ink.value, _ink.accent, _ink.label, _tape_label,
		)
	# Split on the scale's own line: the label to its left, the value
	# to its right. Two readouts stacked under one another want one
	# vertical to share, and the only honest one available is the line
	# that is already drawn -- so the figures ask the ladder where it
	# put its spine rather than both guessing at the same fraction.
	var spine: float = UiDraw.ladder_spine(
		font, scale, Vector2(0.0, TAPE_TOP), _tape_label
	)
	var y: float = box.end.y - float(stats.size()) * TAPE_FIGURE_ROW
	for one: Dictionary in stats:
		var cell: Rect2 = Rect2(
			Vector2(box.position.x, y), Vector2(box.size.x, TAPE_FIGURE_ROW - 1.0)
		)
		# A hint of a plate and four corners, because this one sits on
		# the starfield rather than in a panel: the brackets say where
		# the reading ends without spending the four lines a frame
		# costs (UI_STYLE section 5).
		_canvas.draw_rect(cell, _ink.over(_ink.panel, TAPE_FIGURE_FILL), true)
		UiDraw.bracket(_canvas, cell, _ink.grid)
		_canvas.draw_string(
			font,
			UiDraw.snap(Vector2(
				cell.position.x + 2.0, cell.position.y + float(UiFont.BODY)
			)),
			String(one["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, _ink.label,
		)
		var says: String = String(one["says"])
		_canvas.draw_string(
			font,
			UiDraw.snap(Vector2(
				cell.end.x - 2.0 - UiDraw.text_width(font, says),
				cell.position.y + float(UiFont.BODY),
			)),
			says,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, one["ink"],
		)
		y += TAPE_FIGURE_ROW
	_tape_spine = spine


## Where the scale's line fell on the last draw, so a check can ask
## whether the figures under it are split on the same vertical.
var _tape_spine: float = 0.0


## The figures under the scale, top to bottom.
##
## A list for the same reason the ship panel's bars are one: the order
## is fixed and the box has to be tall enough for all of them, which is
## a fact about this list rather than a number kept in step with it.
func tape_figures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _ship == null or not is_instance_valid(_ship):
		return out
	out.append({
		"label": "SPD", "says": SPEED_FORMAT % _speed.stepped(), "ink": _ink.value,
	})
	# The colour off the smoothed value rather than the printed one: a
	# descent rate sitting on a threshold would otherwise swap colours
	# every frame, which is the loudest thing a HUD can do.
	out.append({
		"label": "V/S", "says": DESCENT_FORMAT % -_descent.stepped(),
		"ink": _descent_colour(_descent.smooth()),
	})
	out.append({
		"label": "GRAV",
		"says": GRAVITY_FORMAT % _ship.get_applied_gravity().length(),
		"ink": _ink.label,
	})
	return out


## Where the tape goes: the left edge, between the two panels on it.
##
## Public so a check can ask, because what matters about this one is
## entirely where it is -- clear of both panels and clear of the
## pilot's field.
func tape_box(font: Font, view: Vector2) -> Rect2:
	var gap: float = UiFrame.PAD * 2.0
	var inside: Rect2 = UiFrame.inside(UiFrame.slot(view, UiFrame.Slot.SHIP))
	# Below room for every bar the ship panel is allowed to grow to,
	# not below the bars it happens to be showing: a tape that moved
	# down when the hull got hot would be a tape the eye has to find
	# again at the moment it is being read.
	var under_bars: float = (
		inside.position.y + float(BARS_ROOM) * (BAR_HEIGHT + BAR_GAP) + gap
	)
	# And above the controls, which grow up from the bottom corner.
	var over_controls: float = controls_top(view) - gap
	return Rect2(
		Vector2(UiFrame.EDGE, under_bars),
		Vector2(band_width(font), maxf(over_controls - under_bars, 0.0)),
	)


## How far from the band's left edge the scale's line stands.
##
## The figures under the scale are split on that line -- label left of
## it, value right -- so it has to clear the wider of two things: the
## room the cursor's own figure needs on the ladder's left, and the
## widest label a figure can carry.
func spine_offset(font: Font) -> float:
	var band: Vector2 = Vector2(0.0, TAPE_TOP)
	var cursor_side: float = (
		UiDraw.ladder_width(font, band, "99999", _tape_label)
		- UiDraw.ladder_label_room(font, band, _tape_label)
	)
	var widest_label: float = 0.0
	for one: Array in FIGURE_WIDTHS:
		widest_label = maxf(widest_label, UiDraw.text_width(font, one[0]) + 3.0)
	return maxf(cursor_side, widest_label)


## How wide the whole thing is: the scale's line, plus whichever needs
## more room to the right of it -- the scale's own labels or a figure.
##
## Sized from both rather than from the ladder alone, which is what let
## a value cross the line it is supposed to start after.
func band_width(font: Font) -> float:
	var band: Vector2 = Vector2(0.0, TAPE_TOP)
	var widest_value: float = 0.0
	for one: Array in FIGURE_WIDTHS:
		widest_value = maxf(widest_value, UiDraw.text_width(font, one[1]))
	return spine_offset(font) + maxf(
		UiDraw.ladder_label_room(font, band, _tape_label), widest_value + 4.0
	)


## Every figure under the scale at its widest: the label, and the
## largest thing its format can print.
##
## One table, because three things size themselves from it -- where the
## line stands, how wide the band is, and the check that both are
## right.
const FIGURE_WIDTHS: Array[Array] = [
	["SPD", "99999"], ["V/S", "-9999.0"], ["GRAV", "999.9"],
]


## What is in the ground here, in one row.
##
## Blank while flying and over bare rock, because a row that always says
## something is a row that says nothing: "no ore here" printed over every
## square inch of every world would train the pilot to stop reading it.
## The one case it must speak for is **buried** -- ore the pilot is
## standing on and cannot have is the whole reason carving the crust is
## prospecting rather than vandalism, and nothing else in the game would
## ever tell them.
func _draw_ore(font: Font, at: Vector2, width: float) -> void:
	if _rig == null or not is_instance_valid(_rig):
		return
	var found: Dictionary = _rig.readout()
	var kind: int = int(found.get("kind", -1))
	if kind < 0:
		return
	var snag: int = int(found["snag"])
	var says: String = "%d" % int(found["left"])
	var ink: Color = _ink.ok if bool(found["digging"]) else _ink.value
	if snag == MiningRig.Snag.BURIED:
		# How deep, as a share of the crust band, because that is the
		# number that says how much digging is left.
		says = "deep %.0f%%" % (float(found["depth"]) * 100.0)
		ink = _ink.caution
	elif snag != MiningRig.Snag.NONE:
		says = MiningRig.snag_name(snag)
		ink = _ink.label
	UiDraw.row(
		_canvas, font, at, width, Stores.kind_name(kind).to_upper().left(4),
		says, ink, _ink.label,
	)


## Which way the ship is going, for when there is no orbit to draw.
func _draw_heading(at: Rect2) -> void:
	var centre: Vector2 = (
		at.position + Vector2(ARROW_DIAL, ARROW_DIAL) * 0.5
	).round()
	_canvas.draw_arc(centre, ARROW_DIAL * 0.5 - 2.0, 0.0, TAU, 24, _ink.edge, 1.0)
	if _ship.linear_velocity.length() <= 0.01:
		return
	var along: Vector2 = _ship.linear_velocity.normalized().rotated(-_view_rotation())
	var tip: Vector2 = (centre + along * ARROW_LENGTH).round()
	_canvas.draw_line(centre, tip, _ink.ok, 1.0)
	for side: float in [-1.0, 1.0]:
		_canvas.draw_line(
			tip, (tip - along.rotated(side * 0.4) * ARROW_HEAD).round(), _ink.ok, 1.0
		)


## A countdown a pilot can act on.
##
## Seconds while they are worth counting, minutes after that: "in 412s"
## is a number you have to divide before it means anything, and by the
## time it is that far off the exact second has stopped mattering.
func _countdown_text(seconds: float) -> String:
	if seconds < 100.0:
		return "%.0fs" % seconds
	if seconds < 6000.0:
		return "%.0fm" % (seconds / 60.0)
	return "%.1fh" % (seconds / 3600.0)


## An apsis as a height above the nominal surface.
##
## Above the nominal surface rather than above the ground under the ship:
## an apsis happens somewhere else on the planet, where the ground is a
## different height, so the only honest common reference is the radius the
## planet is named by.
func _apsis_text(planet: GravityWell, value: float, landed: bool) -> String:
	if landed:
		return "--"
	if is_inf(value):
		return "ESC"
	# Thousands above ten thousand. A corner panel is 116 px wide and
	# six digits of apsis is most of its text column; past ten thousand
	# the last three of them are not a reading anybody acts on.
	var height: float = value - planet.surface_radius
	if absf(height) < 10000.0:
		return "%.0f" % height
	return "%.1fk" % (height * 0.001)


## The conic, with the planet at its focus and a dot at each end of it.
func _draw_conic(
	dial: Rect2, planet: GravityWell, shape: Dictionary, orbit: GravityWell.OrbitState
) -> void:
	var focus: Vector2 = dial.get_center()
	var periapsis: float = float(shape["periapsis"])
	var apoapsis: float = float(shape["apoapsis"])
	var eccentricity_vector: Vector2 = shape["eccentricity"]
	var eccentricity: float = eccentricity_vector.length()
	var arm: Vector2 = _ship.global_position - planet.global_position

	# Nothing further out than the well is worth drawing: past it the ship
	# is not on this conic any more, it has left.
	var reach: float = maxf(
		minf(apoapsis, planet.influence_radius), maxf(arm.length(), planet.surface_radius)
	)
	var to_dial: float = (DIAL * 0.5 - 3.0) / maxf(reach, 1.0)

	# Turned with the view, like the map: a direction on the dial is the
	# direction you would fly if you pointed the nose that way.
	var turn: float = -_view_rotation()
	var periapsis_angle: float = (
		eccentricity_vector.angle() if eccentricity > 0.0001 else arm.angle()
	)

	# The planet is a dot at the focus, and the ground is a ring at its own
	# radius. Drawn as a filled disc first, and that was wrong: on final
	# approach apoapsis is a few hundred metres up, so the disc filled the
	# dial and swallowed the very track the pilot was reading. A ring says
	# the same thing about scale and leaves the inside visible, which is
	# where a suborbital conic lives.
	_canvas.draw_circle(focus, PLANET_DOT, _ink.nav)
	var ground_ring: float = planet.surface_radius * to_dial
	if ground_ring > PLANET_DOT + 1.0:
		_canvas.draw_arc(focus, ground_ring, 0.0, TAU, 48, _ink.nav, 1.0)

	var colour: Color = _orbit_colour(orbit)
	var width: float = ORBIT_WIDTH if orbit == GravityWell.OrbitState.ORBIT else TRACK_WIDTH
	var track: PackedVector2Array = PackedVector2Array()
	for step: int in range(CONIC_STEPS + 1):
		var theta: float = TAU * float(step) / float(CONIC_STEPS) - PI
		var r: float = Planet.conic_radius(periapsis, eccentricity, theta)
		if is_inf(r) or r > reach:
			# The open end of a hyperbola, or the part of an ellipse that
			# reaches past the well. Broken rather than clamped: a line
			# drawn along the rim would read as an orbit that hugs it.
			if track.size() > 1:
				_canvas.draw_polyline(track, colour, width)
			track = PackedVector2Array()
			continue
		track.append(focus + Vector2.from_angle(theta + periapsis_angle + turn) * r * to_dial)
	if track.size() > 1:
		_canvas.draw_polyline(track, colour, width)

	# The apsides, and only while they are in different places. On a
	# nearly circular orbit the eccentricity vector that aims them is a
	# small difference of large numbers: its direction is noise, so both
	# dots swing right round the ring from one tick to the next. That is
	# the flicker this was reported as, and it is worth saying that the
	# conic never moved -- a circle looks the same whichever way you aim
	# it, so the dots were the only thing that could be seen doing it.
	# Two dots a pixel apart would carry nothing anyway: the ring already
	# says the height is the same all the way round.
	var spread: float = (apoapsis - periapsis) * to_dial
	var shown: float = clampf((spread - APSIS_SPREAD) / APSIS_SPREAD, 0.0, 1.0)
	if shown > 0.0:
		_dot(
			focus + Vector2.from_angle(periapsis_angle + turn) * periapsis * to_dial,
			Color(colour, colour.a * shown),
		)
		if not is_inf(apoapsis):
			_dot(
				focus + Vector2.from_angle(periapsis_angle + turn + PI) * apoapsis * to_dial,
				Color(_ink.ok, _ink.ok.a * shown),
			)
	# Where the ship is on it, which is what turns a shape into a
	# position. A square in the brightest ink: it used to be a circle in
	# the apoapsis green, which is how a pilot ended up with three dots
	# and no way of telling which was which.
	var here: Vector2 = (focus + arm.rotated(turn) * to_dial).round()
	_canvas.draw_rect(
		Rect2(here - Vector2(SHIP_MARK, SHIP_MARK), Vector2(SHIP_MARK, SHIP_MARK) * 2.0),
		_ink.value,
	)


## An apsis mark, snapped to the canvas grid.
##
## The snap is the whole of this function and it is not fussiness. The
## mark is under four pixels across and the canvas is 640x360 before the
## window scales it up three or four times, so a centre that moves by a
## third of a pixel rasterises differently and arrives on screen as a
## mark that changes shape every frame. The orbit's elements do wobble
## that much from tick to tick -- gravity here is patched with a falloff
## at the rim rather than being a clean inverse square -- so the
## sub-pixel position never settles on its own. On the grid there is
## nothing left to shimmer.
func _dot(at: Vector2, colour: Color) -> void:
	_canvas.draw_circle(at.round(), APSIS_DOT, colour)


## The one thing wrong, in the one place a warning is ever shown.
##
## The ground pulses and the word does not, which is UI_STYLE section 7
## and the rule worth repeating: a number that is missing half the time
## is missing exactly when it is wanted. Only the red pulses -- amber
## states its case once and goes on stating it, and if both flashed the
## pulse would stop meaning "now".
func _draw_warning_band(font: Font, view: Vector2) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	var trouble: Dictionary = UiWarning.worst(_ship, host())
	if trouble.is_empty():
		return

	var says: String = trouble["says"]
	var alarm: bool = int(trouble["level"]) == UiWarning.Level.ALARM
	var ink: Color = _ink.alarm if alarm else _ink.caution
	var width: float = _width(font, says) + WARNING_PAD * 2.0
	var box: Rect2 = Rect2(
		Vector2(roundf((view.x - width) * 0.5), WARNING_TOP),
		Vector2(roundf(width), WARNING_HEIGHT),
	)
	var share: float = (
		WARNING_LIT if (not alarm or UiDraw.pulse()) else WARNING_DIM
	)
	_canvas.draw_rect(box, Color(ink, share), true)
	UiDraw.bracket(_canvas, box, ink)
	_text(
		font,
		Vector2(box.position.x + WARNING_PAD, box.end.y - 3.0),
		says,
		_ink.value,
	)


## Why the landing was refused, as a mark rather than a sentence. The
## reason is the news; "WAVE OFF" was a label on news the colour already
## carried.
## What this trajectory is called, or nothing when it has no news.
func state_text(orbit: GravityWell.OrbitState) -> String:
	return String(STATE_WORDS.get(orbit, ""))


func landed_now() -> bool:
	return _ship != null and _ship.flight_mode == Ship.FlightMode.LANDED


func warning() -> String:
	if _ship == null or not is_instance_valid(_ship):
		return ""
	return _ship.last_landing_rejection


func _draw_warning(font: Font, box: Rect2) -> void:
	if warning().is_empty():
		return
	var at: Vector2 = Vector2(box.position.x + 4.0, box.position.y - 4.0)
	_canvas.draw_line(at + Vector2(0.0, -6.0), at + Vector2(0.0, -2.0), _ink.alarm, 2.0)
	_canvas.draw_line(at + Vector2(0.0, -0.5), at, _ink.alarm, 2.0)
	_text(font, at + Vector2(5.0, 0.0), warning().to_upper(), _ink.alarm)


func _text(font: Font, at: Vector2, text: String, colour: Color) -> void:
	_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)


func _width(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


func _view_rotation() -> float:
	var camera: Camera2D = get_viewport().get_camera_2d()
	return 0.0 if camera == null else camera.get_screen_rotation()


func _orbit_colour(orbit: GravityWell.OrbitState) -> Color:
	match orbit:
		GravityWell.OrbitState.SUBORBITAL:
			return _ink.alarm
		GravityWell.OrbitState.DECAYING:
			return _ink.caution
		GravityWell.OrbitState.ESCAPE:
			return _ink.value
		_:
			return _ink.ok


func _apoapsis_colour(shape: Dictionary) -> Color:
	return _ink.value if is_inf(float(shape["apoapsis"])) else _ink.ok


func _gear_text() -> String:
	if _ship.gear == null:
		return "  NONE"
	if _ship.gear.is_deployed():
		return "  DOWN"
	if _ship.gear.is_stowed():
		return "    UP"
	return "  %3.0f%%" % (_ship.gear.extension * 100.0)


func _gear_colour() -> Color:
	if _ship.gear == null:
		return _ink.alarm
	if _ship.gear.is_deployed():
		return _ink.ok
	return _ink.value if _ship.gear.is_stowed() else _ink.caution




func _descent_colour(descent: float) -> Color:
	if _ship.gear == null or descent <= 0.0:
		return _ink.value
	if descent > _ship.gear.vertical_limit():
		return _ink.alarm
	return _ink.caution if descent > _ship.gear.vertical_limit() * CAUTION_FRACTION else _ink.ok
