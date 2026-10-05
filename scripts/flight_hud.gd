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

## The hull bar, across the top. Wide enough to read a few per cent off at
## a glance, which is the only thing a bar is better at than a number.
## Narrow enough to sit between the debug overlay's two columns, which is
## where the top of the screen is free even with F7 on.
const BAR_HEIGHT: float = 5.0

## The heat bar under it, thinner because it is the second question.
const HEAT_HEIGHT: float = 3.0
const HEAT_GAP: float = 2.0

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
## The orbit dial. Forty-six rather than sixty-six, because the
## untouchable field leaves a corner 116 px wide and the apsides have
## to stand beside the picture rather than under it.
const DIAL: float = 46.0

## The heading dial out in the open, where there is no orbit to draw.
const ARROW_DIAL: float = 40.0

## How much world shows through a panel.
const PANEL_OPACITY: float = 0.86

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
var _canvas: Control = null


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
var _hull: UiValue = UiValue.new(1.0)
var _speed: UiValue = UiValue.new(1.0)
var _altitude: UiValue = UiValue.new(1.0)
var _descent: UiValue = UiValue.new(0.1)
var _slope: UiValue = UiValue.new(deg_to_rad(0.1))


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


func bind(ship: Ship) -> void:
	_ship = ship
	# Fresh readings for a fresh hull. Kept across the swap they would
	# spend the first tenth of a second easing over from whatever the
	# last ship was doing, which is a readout lying during the one
	# moment a pilot is certain to be looking at it.
	_hull = UiValue.new(1.0)
	_speed = UiValue.new(1.0)
	_altitude = UiValue.new(1.0)
	_descent = UiValue.new(0.1)
	_slope = UiValue.new(deg_to_rad(0.1))


func _process(delta: float) -> void:
	_read(delta)
	if _canvas != null:
		_canvas.queue_redraw()


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
	if planet.has_ground():
		_slope.feed((planet as Planet).slope_at(_ship.global_position), delta)


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

	_draw_ship_corner(font, _panel(view, UiFrame.Slot.SHIP))
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
	_draw_warning_band(font, view)


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
	var bar: Rect2 = Rect2(Vector2(at.position.x, y), Vector2(at.size.x, BAR_HEIGHT))
	_canvas.draw_rect(
		Rect2(bar.position, Vector2(roundf(at.size.x * health), BAR_HEIGHT)), colour, true
	)
	_canvas.draw_rect(bar, _ink.edge, false, 1.0)
	y += BAR_HEIGHT + 2.0
	y = _draw_heat(at.position.x, y, at.size.x)

	UiDraw.row(
		_canvas, font, Vector2(at.position.x, y + float(UiFont.BODY)), at.size.x,
		"HULL", "%.0f" % _hull.stepped(), colour, _ink.label, "%",
	)
	y += ROW

	# Emergency power up here rather than down in the instruments: it
	# is the one reading a pilot wants while looking at the ground
	# coming up. Shown when asked for and refused as well as when
	# running -- "nothing happened when I pressed it" has to have an
	# answer on the screen, and the answer is an empty pool.
	if _ship.boost_command:
		UiDraw.row(
			_canvas, font, Vector2(at.position.x, y + float(UiFont.BODY)), at.size.x,
			"BOOST", "ON" if _ship.boost_active else "--",
			_ink.caution if _ship.boost_active else _ink.alarm, _ink.label,
		)
		y += ROW
	_draw_dock(font, Vector2(at.position.x, y + float(UiFont.BODY)), at.size.x)


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


## Heat, as a second bar under the hull, and only when there is any.
## Returns where the next thing starts.
##
## Hidden at zero deliberately. In ordinary flight it would be an empty
## box that never moves, and a gauge the pilot has learned to ignore is
## worse than no gauge at all. It appears on the first hot air or the
## first sunlight and brings its own threshold mark, so "how close am I
## to burning" is answered by looking rather than by remembering a
## number.
func _draw_heat(left: float, top: float, width: float) -> float:
	var heat: float = clampf(_ship.hull_heat, 0.0, 1.0)
	if heat <= 0.01:
		return top
	var frame: Rect2 = Rect2(left, top, width, HEAT_HEIGHT)
	var burning: bool = heat >= Ship.BURN_HEAT
	var colour: Color = _ink.alarm if burning else _ink.caution
	_canvas.draw_rect(
		Rect2(frame.position, Vector2(roundf(width * heat), HEAT_HEIGHT)), colour, true
	)
	_canvas.draw_rect(frame, _ink.edge, false, 1.0)
	var mark: float = roundf(left + width * Ship.BURN_HEAT)
	_canvas.draw_line(Vector2(mark, top - 1.0), Vector2(mark, frame.end.y + 1.0), _ink.alarm, 1.0)
	# No word here. Heat used to label itself the moment it passed the
	# mark, which put one warning in one place and every other warning
	# somewhere else, so a pilot had to know the screen rather than
	# know the spot. The band owns that case now and calls it BURN.
	return frame.end.y + 2.0


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

	UiDraw.row(
		_canvas, font, Vector2(at.position.x, y), at.size.x, "ALT",
		"%.0f" % _altitude.stepped(), _ink.value, _ink.label,
	)
	y += ROW
	# The colour off the smoothed value rather than the printed one: a
	# descent rate sitting on a threshold would otherwise swap colours
	# every frame, which is the loudest thing a HUD can do.
	UiDraw.row(
		_canvas, font, Vector2(at.position.x, y), at.size.x, "V/S",
		"%+.1f" % -_descent.stepped(), _descent_colour(_descent.smooth()), _ink.label,
	)
	y += ROW
	# The last two rows are about touching down and there is nothing to
	# touch down on over a star. Left blank rather than filled with
	# zeros: a slope of 0.0 degrees over a star reads as flat ground,
	# which is a worse answer than no answer.
	if planet.has_ground():
		UiDraw.row(
			_canvas, font, Vector2(at.position.x, y), at.size.x, "SLOPE",
			"%.1f" % rad_to_deg(_slope.stepped()),
			_slope_colour(absf(_slope.smooth())), _ink.label, "d",
		)
		y += ROW
		UiDraw.row(
			_canvas, font, Vector2(at.position.x, y), at.size.x, "GEAR",
			_gear_text(), _gear_colour(), _ink.label,
		)
	_draw_warning(font, Rect2(at.position - Vector2(UiFrame.PAD, UiFrame.PAD), at.size))


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
	var scale: float = (DIAL * 0.5 - 3.0) / maxf(reach, 1.0)

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
	var ground_ring: float = planet.surface_radius * scale
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
		track.append(focus + Vector2.from_angle(theta + periapsis_angle + turn) * r * scale)
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
	var spread: float = (apoapsis - periapsis) * scale
	var shown: float = clampf((spread - APSIS_SPREAD) / APSIS_SPREAD, 0.0, 1.0)
	if shown > 0.0:
		_dot(
			focus + Vector2.from_angle(periapsis_angle + turn) * periapsis * scale,
			Color(colour, colour.a * shown),
		)
		if not is_inf(apoapsis):
			_dot(
				focus + Vector2.from_angle(periapsis_angle + turn + PI) * apoapsis * scale,
				Color(_ink.ok, _ink.ok.a * shown),
			)
	# Where the ship is on it, which is what turns a shape into a
	# position. A square in the brightest ink: it used to be a circle in
	# the apoapsis green, which is how a pilot ended up with three dots
	# and no way of telling which was which.
	var here: Vector2 = (focus + arm.rotated(turn) * scale).round()
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


func _slope_colour(slope: float) -> Color:
	if _ship.gear == null:
		return _ink.value
	if slope > _ship.gear.slope_limit():
		return _ink.alarm
	return _ink.caution if slope > _ship.gear.slope_limit() * CAUTION_FRACTION else _ink.ok


func _descent_colour(descent: float) -> Color:
	if _ship.gear == null or descent <= 0.0:
		return _ink.value
	if descent > _ship.gear.vertical_limit():
		return _ink.alarm
	return _ink.caution if descent > _ship.gear.vertical_limit() * CAUTION_FRACTION else _ink.ok
