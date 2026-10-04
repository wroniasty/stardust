class_name Ship
extends RigidBody2D
## A ship: a rigid body plus a set of engine mounts.
##
## Steering is not scripted and engines have no assigned roles. The pilot names
## one of six commands, ShipControl works out from the geometry which engines
## serve it and how strongly, and the solver does the rest. Move an engine and
## its job moves with it; break one and the ship flies crooked, with no code
## anywhere that knows what "crooked" means (see IDEAS.md section 3).
##
## Gravity is applied by the ship itself from nearby bodies (M1.2), never by
## the physics server: gravity_scale stays 0.

## Nose direction in the ship's local frame.
const FORWARD: Vector2 = Vector2.UP

## Points of the hull tested against the terrain bitmap. The engine's own
## collision shape never meets the terrain, because the terrain is not a
## physics body (see IDEAS.md section 6): it is pixels, and these are the
## pixels we ask about. Nose and the two rear corners carry the hull outline,
## the rest stop a long edge from sinking in between corners.
## The shape the simulation uses, in the ship's own frame. Everything
## physical is derived from it and from nothing else: the contact points that
## sample the terrain, the convex shape projectiles hit, the mass, the centre
## of mass and the inertia.
##
## It is an approximation of the drawn hull, not a copy of it. The drawing and
## the shape are two different things; the outline only has to match closely
## enough not to look odd, and otherwise be cheap and predictable for the
## solver. That is why there are guidelines for drawing one -- see the
## configuration report -- rather than a solver clever enough for any shape
## (IDEAS.md section 6).
@export var hull_outline: PackedVector2Array = PackedVector2Array([
	Vector2(0, -12),
	Vector2(-8, 10),
	Vector2(8, 10),
])

## Spacing of the contact points along the outline, in pixels.
##
## Comes from the terrain, not from taste: the crust is 1.5 px per texel, so
## at four texels no terrain feature worth noticing fits between two points.
## A spike narrower than the gap slips between them and the hull either rests
## on nothing or sinks through it.
const CONTACT_STEP: float = 6.0

## Solver passes per tick, at the point count the stock hull has, and the
## ceiling. Sequential impulses converge more slowly the more contacts there
## are, so the passes grow with the outline instead of staying at a number
## chosen for a triangle.
const CONTACT_ITERATIONS: int = 4
const CONTACT_ITERATIONS_MAX: int = 10
const ITERATION_REFERENCE_POINTS: int = 6

## Projectiles are parented to the node in this group, so they stay put in the
## world instead of riding along with the ship that fired them.
const PROJECTILE_GROUP: StringName = &"projectile_container"

## Every ship joins this. A homing round asks the group what is worth
## chasing, the same way the scanner asks for celestial bodies: one
## definition of "a ship", not one per feature.
const SHIP_GROUP: StringName = &"ships"

## Below this closing speed a contact does not bounce at all, in px/s. Without
## it a resting hull keeps trading tiny impulses with the ground.
const RESTITUTION_CUTOFF: float = 30.0

## Overlap left uncorrected, in pixels, and the fraction of the rest that is
## corrected per tick. Both exist to keep positional correction from pumping
## energy into a resting ship.
const PENETRATION_SLOP: float = 0.5
const PENETRATION_CORRECTION: float = 0.6

## Mass of the bare hull per square pixel of outline.
##
## Was a flat 6.0 whatever the shape, which went unnoticed while there was
## one hull and became obvious the moment the sandbox could make another: a
## brick four times the area of the stock dart weighed exactly the same. The
## density is set so the stock outline still comes out at 6.0, so nothing
## that was tuned against it moves.
const HULL_DENSITY: float = 6.0 / 176.0

## What the bare hull weighs today. Derived, not declared.
func hull_mass() -> float:
	return maxf(_polygon_area(_hull_polygon()) * HULL_DENSITY, 0.0001)

## Floor for the angular speed at which kill rotation gives up pulsing and just
## zeroes the spin. The real threshold is computed per tick from the ship's own
## authority, because a single pulse of an impulse engine changes the spin by a
## fixed amount: if the epsilon is smaller than one pulse, every correction
## overshoots and flips the sign, and the assist chatters around zero forever
## instead of finishing. Measured on the stock ship, one pulse is worth about
## 0.04 rad/s, which is twice this floor.
const KILL_ROTATION_EPS: float = 0.02

## Safety factor on that per-pulse estimate.
const KILL_ROTATION_PULSE_MARGIN: float = 1.5

## Angular speed at or above which kill rotation asks for full counter-thrust.
##
## Well under one rad/s on purpose. Because the assist tapers proportionally,
## the spin below this point decays exponentially rather than linearly, and a
## high value spends more time crawling through the last fraction than it did
## killing the first whole radian per second. At 1.0 the stock ship needs about
## two seconds to stop 2 rad/s; at 0.2 it needs under one, which is the bar.
const KILL_ROTATION_GAIN: float = 0.2

## Legs that must be on the ground before a landing is even considered.
const MIN_LEGS_DOWN: int = 2

## How far below a leg the ground may be and still count as touched, in pixels.
##
## Standing for the suspension travel real gear would have, and not optional:
## requiring the legs to be actually buried meant waiting until one of them had
## already been in the rock long enough for the contact solver to tip the ship
## onto it. The landing was then judged on an attitude the landing itself had
## caused, and a level touchdown on flat ground came out 32 degrees off.
const LEG_CONTACT_REACH: float = 5.0

## Below this speed the brake stops the ship outright rather than chasing it.
const BRAKE_EPS: float = 2.0

## How closely the nose must already be on retrograde before the brake out
## in the open lights the drive.
##
## Tighter than the orbit assist's 0.92, for a different job: that one is
## nudging an orbit over minutes and can afford to start pushing while it
## is still coming round, where this is the key a pilot holds when they
## want the speed gone now. Eleven degrees, which is well inside what the
## heading hold settles to anyway -- it stops within a degree and a half --
## so the gate opens once and stays open rather than chattering.
const RETRO_BURN_ALIGNMENT: float = 0.98

## The pool a ship has with no generator fitted: capacity, units per second,
## seconds of silence. Deliberately miserable. A ship whose generator was
## swapped out for something that does not fit still shoots, just very badly
## -- the same reason the hold refuses loot rather than losing it. A bad
## module choice should be a poor one, not a state with no way out of it.
const HULL_RAIL_CAPACITY: float = 40.0
const HULL_RAIL_RECHARGE: float = 15.0
const HULL_RAIL_DELAY: float = 1.5

## Below this speed there is no direction of travel to point at, so the
## heading assist does nothing rather than chasing numerical noise.
const HEADING_MIN_SPEED: float = 8.0

## How close counts as pointed, in radians, and the fastest the assist will
## swing the ship. The cap keeps a light ship with strong jets from spinning
## up to something that looks like a fault.
const HEADING_EPS: float = 0.02
const HEADING_MAX_SPIN: float = 2.0

## How close to circular counts as done, in px/s. Chasing the last fraction
## would have the assist burning for ever against its own corrections.
const AUTO_ORBIT_EPS: float = 1.5

## How closely the nose must already be on the burn direction before the
## assist lights the engine. Burning while still swinging round pushes the
## ship somewhere it did not want to go and lengthens the job.
const AUTO_ORBIT_ALIGNMENT: float = 0.92

## Altitude hold: how hard it pulls back to the height it was given, and how
## hard it fights the climb rate. Without the second the ship porpoises --
## height alone is an undamped spring.
const ALTITUDE_HOLD_GAIN: float = 0.9
const ALTITUDE_HOLD_DAMP: float = 2.2

## Below this there is no orbit to lower.
const DEORBIT_MIN_SPEED: float = 20.0

## Heating. The hull warms with the power the air is dissipating, which for
## the linear damping the shells apply goes as density times speed squared.
## Tying it to the same quantity that does the braking is what stops the heat
## bar and the deceleration from telling different stories.
##
## HEAT_REFERENCE_SPEED is the speed at which a full-density atmosphere heats
## at HEAT_RATE per second; HEAT_COOLING is the constant bleed, which also sets
## the floor below which a descent never cooks the hull at all.
const HEAT_REFERENCE_SPEED: float = 300.0
const HEAT_RATE: float = 0.8
const HEAT_COOLING: float = 0.05

## And from starlight, as a fraction of what the star's own surface gets.
##
## This is the number that decides where the star's damage zone ends, and
## it does so through HEAT_COOLING rather than through a radius of its own.
## The bleed is a constant, not a fraction of the heat, so starlight does
## not warm the hull to some equilibrium -- it either out-paces the bleed,
## in which case the bar climbs all the way, or it does not, in which case
## the bar never leaves zero. The zone has a hard edge, and it is at
## `burn_radius`. At 0.15 that is 1.73 star radii, inside every planet's
## orbit in 300 sampled systems with a third to spare: an inner world has
## to be somewhere a ship can go.
const STAR_HEAT_RATE: float = 0.15

## Where a hot hull starts to be a damaged one, and how fast.
##
## The heat bar has existed since M1.6 and meant nothing: it filled up on
## reentry and the pilot could ignore it. A star you can fly into needs
## somewhere to put its damage, and inventing a second mechanism for "too
## hot" when a heat bar was already sitting there would have been two
## systems telling the same story. So the bar burns now, and reentry is
## held to the same rule as starlight -- which is what the bar was always
## claiming.
##
## BURN_RATE is the hull a pegged bar takes per second: a little over three
## seconds of full heat and the ship is gone, which from the star's surface
## is about thirteen seconds of not turning round.
const BURN_HEAT: float = 0.75
const BURN_RATE: float = 0.3


## How close to `star` a hull may sit before it starts to burn, in pixels
## from the star's centre.
##
## Derived rather than declared: it is simply where starlight starts
## beating the hull's own cooling. Inside, the bar climbs however slowly
## and the hull eventually burns; outside, starlight alone never moves it
## off zero, so a ship can sit there forever. Diving through faster than
## the bar fills is allowed, and is the intended way to go and look.
##
## The first version of this derived a settling point, `flux * rate /
## cooling`, and was wrong: the bleed is a constant and not a fraction of
## the heat, so nothing settles. The test agreed with it, because the test
## did the same arithmetic instead of asking the hull. Flying at the star
## in the running game is what found it, and the test now integrates the
## ship's own heat model rather than restating it.
static func burn_radius(star: Star) -> float:
	if star == null or STAR_HEAT_RATE <= 0.0:
		return 0.0
	return star.surface_radius * sqrt(STAR_HEAT_RATE / HEAT_COOLING)

## How much of the pool has to be there before emergency power will light,
## as a fraction of capacity. Once lit it burns the pool to nothing.
##
## A threshold alone was not enough, and the test said so: the burn pushes
## the recharge delay back every tick, so a pilot holding the key over an
## empty pool got a burst of boost roughly every second as the pool
## crawled back over the line and was emptied again. Unpredictable thrust
## during a landing is worse than no thrust.
##
## So it latches as well. One press is one burn: it lights, it runs until
## released or until the pool is dry, and after that it will not light
## again until the key has been let go. That makes it a reserve the pilot
## spends rather than a tap they lean on.
const BOOST_RESERVE: float = 0.10

## Fired on every terrain impact hard enough to hurt. M1.7 turns this into hull
## HP and death; for now it only accumulates.
signal hull_impact(impact_speed: float, damage: float)

## An engine lighting up, and the same one going out.
##
## Seam tasks for the sound track (VISUALS.md section 6): a loop can be
## driven by polling `exhaust_flow()` every tick, but an ignition is a
## thing that happens once and has to be announced once. The ship is
## where they live because the ship is what ticks the engines; nothing
## here changes how any of them behave.
signal engine_ignited(engine: EngineInstance)
signal engine_cut(engine: EngineInstance)

## Flight modes. Being landed is the only state that stops the solver; whether
## the ship is in orbit is read off its trajectory rather than switched on,
## because there is nothing for a mode to do about it (see IDEAS.md section 8).
enum FlightMode { PHYSICAL, LANDED, DOCKED }

## What a dock mends, per second.
##
## Over time rather than on arrival, so docking is a pause in the flight
## and not a button: a wrecked hull takes the best part of ten seconds to
## put right, which is long enough to be a decision about whether you can
## afford to sit still and short enough that nobody waits for it twice.
##
## Energy fills faster than the generator manages on its own, because that
## is what being plugged into something bigger than you means.
const DOCK_HULL_RATE: float = 0.12
const DOCK_ENGINE_RATE: float = 0.18
const DOCK_ENERGY_RATE: float = 3.0

## And of the tank, per second docked.
##
## Slower than the energy pool on purpose. Energy is combat's clock and
## refills itself anywhere; fuel is range's clock and only comes from a
## dock, so sitting still for it is the price of having gone a long way
## (IDEAS.md section 14). Still generous -- the wait is meant to be felt,
## not endured.
const DOCK_FUEL_RATE: float = 0.12

## Emitted when the ship touches down or leaves the ground.
signal flight_mode_changed(mode: FlightMode)

## Emitted on a touchdown the gear could not absorb. `reason` is one of
## "speed", "tilt" or "slope", which is what the HUD wants to show.
signal landing_rejected(reason: String)

## Emitted the moment the ship settles on a planet.
signal landed(planet: Planet)

## Emitted when the hull runs out, with the last position and velocity so the
## wreck can be thrown in the right direction.
signal destroyed(at: Vector2, velocity: Vector2)

## Back in one piece, somewhere else.
##
## The counterpart to `destroyed`, and the same kind of seam: a
## revival is a thing that happens once, and inferring it from the
## hull integrity jumping back to one is inferring an event from a
## number that has several other reasons to move.
signal respawned()

## Emitted whenever the hull changes, for the HUD.
signal hull_changed(integrity: float)

## Emitted when what is bolted to the hull changes: an engine fitted, a gun
## swapped, a whole preset applied.
##
## A seam, in the sense VISUALS.md section 6 means: the simulation rebuilds
## its control groups for its own reasons and now says so, and the thing
## that draws the ship rebuilds its sprites off the same event instead of
## comparing the scene against itself every tick.
signal configuration_changed

## Emitted when the hold changes, so the loadout screen can redraw without
## polling.
signal hold_changed(item: Resource)

## The cargo bay changed. Separate from hold_changed because the two answer
## different questions and the editor redraws different panels for each.
signal cargo_changed()

## A shot the pool could not pay for. The HUD flashes; the sound comes with
## VISUALS.
signal shot_refused()

## The pilot threw a module overboard. The world turns it into a crate.
signal jettisoned(item: Resource, rarity: int)

## If true the ship steers itself from the player's input actions. AI ships and
## tests turn this off and write the command fields directly.
@export var use_player_input: bool = true

## Restitution: how much of the closing speed a hard hit gives back. Only
## applied above RESTITUTION_CUTOFF, so a ship sitting on the ground stays.
@export_range(0.0, 1.0) var terrain_bounce: float = 0.15

## Coulomb friction coefficient between hull and rock. Caps the tangential
## impulse at each contact, which is what stops a landed ship sliding downhill.
@export_range(0.0, 2.0) var terrain_friction: float = 0.7

## Impacts slower than this are free: a hull is built to be bumped.
@export var damage_speed_threshold: float = 60.0

## Excess over the tolerance that writes the hull off outright, in px/s.
## Squared in between, so a tap is a tap and a crash is a crash.
##
## The linear model this replaces made every arrival the same kind of event,
## only more so, and it charged the legs at two and a half times the hull's
## rate on top of a threshold fifteen px/s lower. A landing a shade too fast
## therefore cost more than flying into a hillside -- which is exactly
## backwards, because absorbing that is what legs are for.
@export var hull_writeoff_excess: float = 100.0

## The same, for an impact the legs took. Far wider: past their rated speed
## the legs bend instead of the hull breaking, and the pilot gets a bounce
## and a bill rather than a funeral.
@export var gear_writeoff_excess: float = 260.0

## How much a sideways scrape counts towards an impact, against a square-on
## hit at the same speed. Without it the damage model read only the normal
## component, so flying into a slope at two hundred px/s was a graze: most of
## that speed goes along the rock, and along the rock was free.
@export_range(0.0, 1.0) var scrape_share: float = 0.5

var engines: Array[EngineInstance] = []
var hardpoints: Array[Hardpoint] = []

## Geometry-derived control groups. Rebuilt on every configuration change.
var control: ShipControl = ShipControl.new()

## What the pilot is asking for, ShipControl.Command -> 0..1. Persistent: input
## refreshes it every tick, an AI or a test writes it once and it holds.
var commands: Dictionary = {}

## What is actually flown this tick: the pilot's commands plus whatever the
## assists add on top, rebuilt from scratch every tick.
##
## Kept separate from `commands` on purpose. When the assists wrote straight
## into the pilot's set, nothing ever cleared their entries for a ship not
## driven by input, so the brake kept pushing after the ship had stopped and
## drove it backwards instead of settling.
var active_commands: Dictionary = {}

## Assist holds, set from input or by an AI.
var kill_rotation_command: bool = false
var brake_command: bool = false

## What the ship is tied up to, or null.
var docked_at: Station = null

## Why the last dock attempt was turned down, or "". The same shape as
## `last_landing_rejection`, and for the same reason: "no" is not an
## answer a pilot can act on.
var last_dock_rejection: String = ""

## The dock just left, which will not have the ship back until it has
## gone.
##
## Docking is automatic, and the moment after undocking the ship is still
## inside the reach at zero speed -- which is exactly the condition for
## docking, so it was grabbed again on the next tick and the pilot could
## not leave. The same shape as a chord holding its keys until they are
## let go of, and the same fix: a latch rather than a timer, because the
## condition that ends it is "you have gone", which needs no number.
var _just_left: Station = null

## Held: the pilot is asking for emergency power.
var boost_command: bool = false

## Whether the engines are actually on it. Different from the ask, because
## the pool decides -- which is the whole point of boost costing something.
var boost_active: bool = false

## This press has had its burn. Cleared by letting go of the key.
var _boost_spent: bool = false

## The optional assists, engaged by the pilot and refused by the ship when
## the computer in the bay does not offer them.
var auto_orbit_command: bool = false
var auto_level_command: bool = false
var altitude_hold_command: bool = false
var deorbit_command: bool = false

## The height altitude hold was engaged at. Captured on engage rather than
## tracked, so the assist holds where the pilot decided rather than drifting
## with wherever the ship has got to.
var _held_altitude: float = -1.0

## Which way the heading assist is pointing the nose, if at all. Set from the
## Q+E+W and Q+E+S chords, and left here for an AI to drive the same way.
var heading_command: ControlChords.Chord = ControlChords.Chord.NONE

## Reads the chorded commands off the held keys.
var chords: ControlChords = ControlChords.new()

## Held-down triggers, one per group. Read by the weapons every physics
## tick. Index 0 is the primary, 1 the secondary; a mount says which it
## answers to.
var fire_command: bool = false
var fire_secondary_command: bool = false

## Where the guns are pointing, in world space. Set from the mouse by a
## pilot and from a target by an AI, so both drive the same machinery.
##
## Guns aim at a point rather than at a thing: a point is what a mouse gives,
## it is what a target's position amounts to anyway, and it is the only one
## of the two that can be aimed at empty space.
var aim_point: Vector2 = Vector2.ZERO

## How close to the cursor a ship has to be for a seeker to lock onto it,
## in screen pixels. The target's own size is added on top, because a
## freighter really is easier to point at than a fighter.
const LOCK_RADIUS: float = 48.0

## Hull condition, 1.0 intact and 0.0 destroyed.
##
## On the same 0..1 scale as hull_heat and engine health, which is what makes
## the numbers read as fractions of a ship: flying into rock at 105 px/s costs
## about a fifth of the hull, 130 px/s about half, and 160 px/s is fatal
## outright. The same speeds taken on the legs cost 0.06, 0.11 and 0.19.
var hull_integrity: float = 1.0

## Total damage taken since the last respawn, for the readout.
var accumulated_damage: float = 0.0

## Hull heat, 0..1. Climbs while braking against thick air at speed and bleeds
## off in vacuum. M2 turns a full bar into engine damage.
var hull_heat: float = 0.0

## Starlight falling on the hull, 1.0 at the star's own surface. Kept as
## state because the HUD wants it every frame and recomputing it there
## would be a second answer to the same question.
var star_flux: float = 0.0

## Air density at the hull, 0..1, refreshed every physics tick. Cached here
## because the heat model, the contrails and the HUD all want it and none of
## them should be repeating the planet lookup.
var air_density: float = 0.0

var flight_mode: FlightMode = FlightMode.PHYSICAL

## The landing gear, if this hull has any.
var gear: LandingGear = null

## Why the last touchdown was refused, for the HUD. Empty once landed.
var last_landing_rejection: String = ""

## The one module the ship is carrying loose, and how good it was. One slot,
## not an inventory: a full hold has to be dealt with before the next find,
## which keeps the loadout screen to a single decision (IDEAS.md section 4).
var carried: Resource = null


## How good the thing in the hold is. Read off the module rather than stored,
## so it cannot disagree with what is actually being carried.
var carried_rarity: int:
	get:
		var module: ModuleData = carried as ModuleData
		return module.rarity if module != null else 0

## The cargo bay: things stowed for later, measured in the same bulk unit as
## everything else. Not slots -- a capacity -- so "can I take this" is a
## question about the machine rather than about a grid, and a full bay of
## heavy modules is felt in how the ship flies.
##
## Entries are { "item": Resource, "rarity": int }, in the order they were
## stowed. Rarity rides alongside because no module Resource carries it.
var cargo: Array[Dictionary] = []

## Total bulk the cargo bay can hold, before anything a module adds. A
## property of the hull, set in the scene, because how much a ship can carry
## is the first thing that distinguishes a hauler from a fighter.
@export var hull_cargo_capacity: float = 12.0


## What the bay actually holds, hull plus whatever the fitted modules
## contribute. One place to ask, so the editor, the mass sum and the pickup
## check can never disagree about how full the ship is.
##
## Nothing adds to it yet. The line exists because a cargo module is an
## obvious find and the alternative is that `cargo_capacity` stays a constant
## every caller has to remember is not the whole story.
func cargo_capacity() -> float:
	var total: float = stat(&"cargo_capacity", hull_cargo_capacity)
	if generator_bay != null and generator_bay.installed != null:
		# A generator takes room in the hull, not only mass. Nothing else
		# does yet.
		total -= generator_bay.installed.bulk * CARGO_CROWDING
	return maxf(total, 0.0)


## How much of a fitted module's bulk comes out of the cargo bay rather than
## simply being carried. Less than one: machinery is packed into space that
## was never going to hold crates anyway.
const CARGO_CROWDING: float = 0.5

## Ship-wide numbers a module is allowed to change. A key outside this list
## is a typo in an affix table, and a typo that silently does nothing passes
## every test anyone will write -- so it is an error, loudly.
const STATS: Array[StringName] = [
	&"energy_capacity",
	&"energy_recharge",
	&"energy_delay",
	&"cargo_capacity",
	&"fuel_capacity",
]

## key -> { "add": float, "mul": float }, and key -> the modules behind it.
## Both recomputed at every refit and never per frame: a number worked out
## each tick is a number the configuration report cannot show.
var stats: Dictionary = {}
var stat_sources: Dictionary = {}

## Energy in the pool, and how long since the last spend. Combat's clock:
## it refills itself, is never bought, and cannot be saved up
## (IDEAS.md section 14).
var energy: float = 0.0
var _since_spend: float = 0.0

## Every slot on this hull, in the order the children are walked.
##
## One list rather than one field per kind, because every list that used
## to name them individually -- mass, inertia, the fitted inventory, the
## editor's schematic -- wanted all of them and none wanted a particular
## one. The named fields below are lookups into this, kept because the
## code that asks for the generator wants the generator.
var bays: Array[ModuleBay] = []

## The generator bay, if the hull has one. Found at ready like the mounts.
var generator_bay: GeneratorBay = null

## The flight computer bay, if the hull has one.
var computer_bay: ComputerBay = null

## The three that decide whether this hull can leave the system at all.
var scanner_bay: ScannerBay = null
var jump_bay: JumpDriveBay = null
var tank_bay: TankBay = null

## Fuel in the tank. Range's clock, against energy's combat one.
##
## The two never mix and that is a design rule, not an accident of
## plumbing (IDEAS.md section 14): energy refills itself, is never bought
## and cannot be saved up, so a long burst can never leave a ship unable
## to slow down. Fuel is the opposite in every one of those, which is why
## it is the thing that decides how far from a dock a pilot is willing to
## be.
var fuel: float = 0.0

## Contact points along the outline, without the gear's. Built once.
var _outline_contacts: Array[Vector2] = []

## Where the cargo sits, in the ship's frame. Placed on the stock centre of
## mass on purpose: a bay anywhere else would make loading up a balance fault
## as well as a mass gain, and nagging the pilot for picking things up would
## teach them to ignore the configuration report. Loading is felt as
## sluggishness, not as a warning.
const CARGO_BAY: Vector2 = Vector2(0.0, 1.75)

## Mass a unit of stowed bulk adds, against a fitted module's one-for-one.
## Cargo capacity is a measure of room, and a hold is built to carry what
## fits in it.
const CARGO_MASS_PER_BULK: float = 0.35


var _landed_planet: Planet = null
var _landed_angle: float = 0.0
var _landed_radius: float = 0.0
var _landed_heading: float = 0.0

## Where this hull was at the end of the previous physics tick.
##
## Kept so the presentation layer can work out where the ship is being
## **drawn**, which is not where `global_position` says it is. With
## physics interpolation on -- it is, project-wide -- a body is
## rendered between its last two physics transforms, while a script
## reading `global_position` gets the newer of the two. Anything placed
## in the world from that number therefore appears up to a full tick of
## travel ahead of the ship it belongs to: thirty pixels at 1800 px/s,
## which is a beam detaching from its own muzzle and a burst of sparks
## floating off the hull.
##
## Godot 4 has `get_global_transform_interpolated()` for 3D and nothing
## for 2D, so the two transforms have to be kept here and blended by
## hand. This is a seam task in everything but name: the presentation
## layer cannot get the number any other way.
## Two of them, shifted along each tick, rather than one recorded at
## the top of the tick. `_physics_process` runs **after** the body has
## been integrated -- measured, by finding the two identical to the
## pixel -- so reading `global_position` there gives the newer of the
## pair and never the older. The only way to hold the previous one is
## to have kept it.
var _was_at: Vector2 = Vector2.INF
var _was_facing: float = 0.0
var _now_at: Vector2 = Vector2.INF
var _now_facing: float = 0.0

var _applied_force: Vector2 = Vector2.ZERO
var _applied_torque: float = 0.0
var _gravity: Vector2 = Vector2.ZERO
var _terrain_contacts: int = 0


## Finds the parts bolted to this hull, by walking the children.
##
## Pulled out of `_ready` because the sandbox can now rebuild a ship into
## another fitout, which means the children change after it: a cached
## hardpoint list that still names nodes the refit freed is a list that
## crashes the next time anything pulls a trigger.
func collect_parts() -> void:
	hardpoints.clear()
	bays.clear()
	generator_bay = null
	computer_bay = null
	scanner_bay = null
	jump_bay = null
	tank_bay = null
	gear = null
	for child: Node in get_children():
		if child is Hardpoint:
			hardpoints.append(child as Hardpoint)
		elif child is ModuleBay:
			bays.append(child as ModuleBay)
		elif child is LandingGear:
			gear = child as LandingGear
	for bay: ModuleBay in bays:
		if bay is GeneratorBay:
			generator_bay = bay as GeneratorBay
		elif bay is ComputerBay:
			computer_bay = bay as ComputerBay
		elif bay is ScannerBay:
			scanner_bay = bay as ScannerBay
		elif bay is JumpDriveBay:
			jump_bay = bay as JumpDriveBay
		elif bay is TankBay:
			tank_bay = bay as TankBay


func _ready() -> void:
	collect_parts()
	# Set once here rather than at every landing: it never changes, and writing
	# it from _integrate_forces would be another state change the server
	# refuses mid-flush.
	add_to_group(SHIP_GROUP)
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	# Both derived from the outline, before anything asks for either.
	_build_contact_points()
	_build_collision_shape()
	rebuild_control_groups()
	# A ship starts charged and fuelled. The rebuild above only clamps
	# downwards, so without this a fresh hull would come out of the yard
	# unable to fire and unable to leave.
	energy = energy_capacity()
	fuel = fuel_capacity()
	_since_spend = energy_recharge_delay()


## Every engine mount on the hull, fitted or empty.
func engine_mounts() -> Array[EngineMount]:
	var mounts: Array[EngineMount] = []
	for child: Node in get_children():
		var mount: EngineMount = child as EngineMount
		if mount != null:
			mounts.append(mount)
	return mounts


## True if `mount` will take this engine: the right kind, and small enough to
## go in the slot. The slot is the mount's business, so ask the mount.
func mount_accepts(mount: EngineMount, data: EngineData) -> bool:
	if mount == null:
		return false
	return mount.fits(data)


## Bolts `data` into `mount` and hands back whatever came out, or hands `data`
## straight back if the mount will not take it.
##
## Rebuilds the control groups, because fitting an engine changes the mass,
## the centre of mass and what every command can do -- which is the whole
## point of engines being loot.
func fit_engine(mount: EngineMount, data: EngineData) -> EngineData:
	if not mount_accepts(mount, data):
		return data
	var previous: EngineData = mount.installed
	mount.installed = data
	rebuild_control_groups(false)
	return previous


## Takes a loose module into the hold. Returns false when the hold is full,
## which is the caller's cue to tell the pilot rather than to lose the item.
func take(item: Resource, rarity: int = -1) -> bool:
	if carried != null or item == null:
		return false
	# A caller that knows better may still say so, but nothing has to
	# remember to: the module carries its own grade.
	if rarity >= 0 and item is ModuleData:
		(item as ModuleData).rarity = rarity
	carried = item
	hold_changed.emit(carried)
	return true


## How big any module is, whichever kind it is. The one place that knows
## that both module Resources answer to the same field.
static func module_bulk(item: Resource) -> float:
	var module: ModuleData = item as ModuleData
	return module.bulk if module != null else 0.0


func cargo_used() -> float:
	var total: float = 0.0
	for entry: Dictionary in cargo:
		total += module_bulk(entry["item"] as Resource)
	return total


func cargo_free() -> float:
	return maxf(cargo_capacity() - cargo_used(), 0.0)


## Moves what is in the hold into the bay. Fails, rather than overfilling,
## when there is no room: the bay is the constraint, not a suggestion.
##
## Rebuilds the control groups, because cargo is mass and mass is handling.
func stow() -> bool:
	if carried == null or module_bulk(carried) > cargo_free():
		return false
	cargo.append({"item": carried, "rarity": carried_rarity})
	carried = null
	rebuild_control_groups(false)
	hold_changed.emit(null)
	cargo_changed.emit()
	return true


## Moves one thing out of the bay and into the hold, which must be empty.
func retrieve(index: int) -> bool:
	if carried != null or index < 0 or index >= cargo.size():
		return false
	var entry: Dictionary = cargo[index]
	cargo.remove_at(index)
	carried = entry["item"]
	rebuild_control_groups(false)
	hold_changed.emit(carried)
	cargo_changed.emit()
	return true


## Throws what is in the hold overboard. Announced rather than destroyed: who
## turns it back into a crate in the world is the world's business, and a
## jettison that annihilates the cargo is not a tactical decision, it is
## tidying up.
## How fast a jettisoned module leaves the ship, relative to the ship.
##
## Enough to be clear of the hull long before the crate will answer a pilot
## again: the hull is some twenty-five px long and the crate is deaf for two
## seconds, so at this speed it is eighty px astern by the time it can be
## picked back up. Throwing something overboard has to be a decision that
## takes effect, not a module that follows the ship around.
const EJECT_SPEED: float = 40.0


func jettison() -> Resource:
	if carried == null:
		return null
	var item: Resource = carried
	var rarity: int = carried_rarity
	release()
	jettisoned.emit(item, rarity)
	return item


## Where a jettisoned module leaves the hull: the cargo bay itself, in world
## space. Asked of the ship rather than worked out by the world, because
## where the bay is is a fact about the ship.
func eject_point() -> Vector2:
	return to_global(CARGO_BAY)


## And how fast, in world space.
##
## The ship's own velocity plus a shove out of the doors, which face aft. A
## module let go at speed keeps the speed -- what "ejected" means is the
## difference between the two, and it is the difference that has to clear
## the hull.
func eject_velocity() -> Vector2:
	return linear_velocity + transform.basis_xform(Vector2.DOWN).normalized() * EJECT_SPEED


## Empties the hold and returns what was in it.
func release() -> Resource:
	var item: Resource = carried
	carried = null
	hold_changed.emit(null)
	return item


## What this configuration can do, and what is wrong with it. Built fresh
## rather than cached: it is asked for on a rebuild and on a swap, both of
## which have just invalidated any stored answer.
func configuration() -> ConfigurationReport:
	return ConfigurationReport.of(self)


## Re-reads the fitted engines, recomputes mass, centre of mass and inertia,
## and rebuilds the control groups from the new geometry.
##
## Must be called after anything that changes the configuration: fitting or
## removing a module, or a change in mass. Not after damage: health is
## deliberately left out of the group maths so a broken engine shows up as a
## crooked ship rather than being quietly compensated for.
func rebuild_control_groups(verbose: bool = true) -> void:
	# Condition survives the rebuild. An EngineInstance is a pairing the ship
	# throws away and remakes on every refit, so without this, bolting on any
	# module anywhere would quietly repair every engine on the hull -- a free
	# repair bench in the swap screen.
	#
	# Carried by mount, and only while the same engine is still in it. An
	# engine moved to another socket comes up fresh, which is the one case
	# this gets wrong; call it bench time.
	var carried: Dictionary = {}
	for engine: EngineInstance in engines:
		carried[engine.mount.name] = {"data": engine.data, "health": engine.health}

	engines.clear()
	for child: Node in get_children():
		var mount: EngineMount = child as EngineMount
		if mount != null and mount.installed != null:
			var instance: EngineInstance = EngineInstance.new(mount.installed, mount)
			var previous: Dictionary = carried.get(mount.name, {})
			if previous.get("data") == mount.installed:
				instance.health = float(previous["health"])
			engines.append(instance)

	_aggregate_stats()
	_recompute_mass_properties()
	control.rebuild(engines, center_of_mass, mass, inertia)
	# Which allocator runs is a property of the box in the bay, read once per
	# refit rather than asked every tick.
	var box: FlightComputerData = computer()
	control.solve_allocation = (
		box != null and box.allocation == FlightComputerData.Allocation.NNLS
	)
	# Fitting a smaller generator must not leave the pool holding more than
	# the new one can. Topping it up on a swap is the other way round and
	# would make refitting a free reload.
	energy = minf(energy, energy_capacity())
	# And the same for the tank, for the same reason in both directions: a
	# smaller tank must not hold what the old one did, and swapping to a
	# bigger one must not fill it.
	fuel = minf(fuel, fuel_capacity())
	# After the rebuild, not before: whatever listens is entitled to read a
	# ship that is finished rather than one halfway through a refit.
	configuration_changed.emit()

	if verbose:
		var report: PackedStringArray = configuration().lines()
		print("%s: %s" % [name, report[0]])
		for line: String in report.slice(1):
			print("  " + line)


## Mass, centre of mass and inertia from the hull plus the fitted modules.
##
## The hull is treated as a uniform lamina over its collision polygon, so the
## numbers follow the shape instead of being guessed; modules are point masses
## at their mounts. The body is switched to a custom centre of mass because the
## default one ignores the modules entirely, and every torque in the control
## maths is measured from it.
func _recompute_mass_properties() -> void:
	var polygon: PackedVector2Array = _hull_polygon()
	var hull_centroid: Vector2 = _polygon_centroid(polygon)
	var bare: float = hull_mass()
	var hull_inertia: float = _polygon_inertia(polygon, bare, hull_centroid)

	var total_mass: float = bare
	var weighted: Vector2 = hull_centroid * bare
	for engine: EngineInstance in engines:
		var module: float = engine.mount.module_mass()
		total_mass += module
		weighted += engine.mount.position * module

	# Cargo is mass, but not at the rate a bolted-in module is. Measured at
	# one-to-one, a full hold added 75% to the ship and took 43% of its
	# acceleration: carrying anything at all turned it into a brick and the
	# hold might as well not have existed. At this rate a full hold costs
	# about a fifth of the acceleration, which is a decision rather than a
	# refusal.
	#
	# Fitted modules keep their full mass. Fitting is a swap, so the net
	# change is small, and the centre of mass sits where it does because of
	# those exact figures (IDEAS.md section 3).
	var load: float = cargo_used() * CARGO_MASS_PER_BULK
	total_mass += load
	weighted += CARGO_BAY * load

	for bay: ModuleBay in bays:
		total_mass += bay.module_mass()
		weighted += bay.position * bay.module_mass()
	if gear != null:
		total_mass += gear.module_mass()
		weighted += gear.position * gear.module_mass()

	var centre: Vector2 = weighted / maxf(total_mass, 0.0001)

	# Parallel axis theorem: the hull's own inertia about its centroid, shifted
	# to the combined centre, plus each module as a point mass.
	var total_inertia: float = hull_inertia + bare * hull_centroid.distance_squared_to(centre)
	for engine: EngineInstance in engines:
		total_inertia += engine.mount.module_mass() * engine.mount.position.distance_squared_to(centre)
	total_inertia += load * CARGO_BAY.distance_squared_to(centre)
	for bay: ModuleBay in bays:
		total_inertia += bay.module_mass() * bay.position.distance_squared_to(centre)
	if gear != null:
		total_inertia += gear.module_mass() * gear.position.distance_squared_to(centre)

	mass = total_mass
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centre
	inertia = maxf(total_inertia, 0.0001)


func _hull_polygon() -> PackedVector2Array:
	var shape_node: CollisionShape2D = get_node_or_null("HullShape") as CollisionShape2D
	if hull_outline.size() >= 3:
		return hull_outline
	# Only for a hull whose outline was never set: the collision shape is
	# derived from the outline, so reading it in preference was reading a
	# copy of the source and going stale the moment the outline changed
	# without a rebuild.
	if shape_node != null:
		var convex: ConvexPolygonShape2D = shape_node.shape as ConvexPolygonShape2D
		if convex != null and convex.points.size() >= 3:
			return convex.points
	return hull_outline


## Unsigned area of a polygon, by the shoelace sum.
func _polygon_area(polygon: PackedVector2Array) -> float:
	var twice: float = 0.0
	for i: int in range(polygon.size()):
		twice += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(twice) * 0.5


func _polygon_centroid(polygon: PackedVector2Array) -> Vector2:
	var area: float = 0.0
	var centroid: Vector2 = Vector2.ZERO
	for i: int in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var cross: float = a.cross(b)
		area += cross
		centroid += (a + b) * cross
	if absf(area) < 0.0001:
		return Vector2.ZERO
	return centroid / (3.0 * area)


## Mass moment of inertia of a uniform polygon about its own centroid.
func _polygon_inertia(polygon: PackedVector2Array, polygon_mass: float, centroid: Vector2) -> float:
	var area: float = 0.0
	var moment: float = 0.0
	for i: int in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var cross: float = a.cross(b)
		area += cross
		moment += cross * (a.dot(a) + a.dot(b) + b.dot(b))
	area *= 0.5
	if absf(area) < 0.0001:
		return polygon_mass
	# moment/12 is the polar second moment of AREA about the origin; multiplying
	# by the areal density turns it into a mass moment, then the parallel axis
	# theorem shifts it to the centroid.
	var about_origin: float = (moment / 12.0) * (polygon_mass / area)
	return maxf(about_origin - polygon_mass * centroid.length_squared(), 0.0001)


## Weapons fire here and not in _integrate_forces: that callback runs while the
## physics server is flushing queries, and adding nodes to the tree from inside
## it is not allowed.
## Input is polled here rather than in _integrate_forces, and so is the decision
## to leave the ground. A frozen body gets no _integrate_forces at all, so a
## landed ship that only listened there could never be told to take off again.
func _physics_process(delta: float) -> void:
	# Shift the pair along. After this, `_was_at` is where the renderer
	# is interpolating from and `_now_at` is where it is interpolating
	# to, which is what `drawn_transform()` blends between.
	if _now_at == Vector2.INF:
		_now_at = global_position
		_now_facing = global_rotation
	_was_at = _now_at
	_was_facing = _now_facing
	_now_at = global_position
	_now_facing = global_rotation

	if use_player_input:
		read_player_input(delta)
		# Through the canvas transform, so aiming survives the camera being
		# zoomed or turned -- the same reason the scanner takes a transform
		# rather than working in world angles.
		aim_point = get_global_mouse_position()
		fire_command = Input.is_action_pressed("ship_fire")
		fire_secondary_command = Input.is_action_pressed("ship_fire_secondary")
		if Input.is_action_just_pressed("toggle_gear") and gear != null:
			gear.set_deployed(not gear.is_deployed() and not gear.is_moving())

	if gear != null:
		gear.advance(delta)
		# Deployed legs only bite in air. Scaling by density rather than
		# switching on a boolean keeps the speed brake worthless in vacuum,
		# where a drag penalty would be nonsense.
		linear_damp = gear.drag() * gear.extension * air_density

	if flight_mode == FlightMode.LANDED:
		if _wants_translation(commands) or brake_command:
			take_off()
		else:
			_hold_landed_pose()

	_resolve_dock(delta)
	_recharge(delta)

	var container: Node = projectile_container()
	for hardpoint: Hardpoint in hardpoints:
		hardpoint.tick(delta)
		# Guns follow the cursor whether or not the trigger is down. A turret
		# that only starts turning when you shoot is a turret that is never
		# pointing at anything when you want it.
		hardpoint.aim_at(aim_point, delta)

		if not _trigger_held(hardpoint.trigger) or not hardpoint.can_fire():
			continue
		# Only the guns that can actually hit. Three mounts on one trigger is
		# three chances that one of them bears, not three rounds into the
		# hull of your own ship.
		if hardpoint.aim_state(aim_point) != Hardpoint.Aim.ON_TARGET:
			continue
		# Charged before fired: a shot either comes out whole or does not come
		# out. Half a shot is unreadable and breaks every affix reckoned on
		# damage (IDEAS.md section 14).
		# The mounted cost, not the bare weapon's: mods are paid for at the
		# trigger, which is the whole reason they cost energy at all.
		if not spend_energy(hardpoint.energy_cost()):
			# Announced, not silent. A trigger that does nothing and says
			# nothing reads as a stuck key (IDEAS.md section 14).
			shot_refused.emit()
			continue
		hardpoint.fire(linear_velocity, container, self)


## Every module bolted to the hull, with the name to blame in a report.
func fitted_modules() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child: Node in get_children():
		var mount: EngineMount = child as EngineMount
		if mount != null and mount.installed != null:
			out.append({"name": child.name, "module": mount.installed})
		var hardpoint: Hardpoint = child as Hardpoint
		if hardpoint != null and hardpoint.weapon != null:
			out.append({"name": child.name, "module": hardpoint.weapon})
		var bay: ModuleBay = child as ModuleBay
		if bay != null and bay.installed != null:
			out.append({"name": child.name, "module": bay.installed})
		var legs: LandingGear = child as LandingGear
		if legs != null and legs.installed != null:
			out.append({"name": child.name, "module": legs.installed})
	return out


## A ship-wide number with every module's say in it: base, plus every
## addition, then times every multiplier. Sums first, so a multiplier acts on
## the whole ship rather than on whatever was fitted before it.
func stat(key: StringName, base: float) -> float:
	var entry: Dictionary = stats.get(key, {})
	return (base + float(entry.get("add", 0.0))) * float(entry.get("mul", 1.0))


func _aggregate_stats() -> void:
	stats = {}
	stat_sources = {}
	for key: StringName in STATS:
		stats[key] = {"add": 0.0, "mul": 1.0}
		stat_sources[key] = []

	for entry: Dictionary in fitted_modules():
		var module: ModuleData = entry["module"]
		for key: StringName in module.stat_add:
			if _record_stat(key, entry["name"], "add", float(module.stat_add[key])):
				stats[key]["add"] = float(stats[key]["add"]) + float(module.stat_add[key])
		for key: StringName in module.stat_mul:
			if _record_stat(key, entry["name"], "mul", float(module.stat_mul[key])):
				stats[key]["mul"] = float(stats[key]["mul"]) * float(module.stat_mul[key])


## Whether `key` is a stat modules may touch. Split out so the gate can be
## checked without firing the error: a test that makes push_error go off is a
## test that fails the build, since check.ps1 scans the run for errors.
static func knows_stat(key: StringName) -> bool:
	return STATS.has(key)


func _record_stat(key: StringName, source: String, kind: String, value: float) -> bool:
	if not knows_stat(key):
		push_error("%s: module %s changes unknown stat '%s'" % [name, source, key])
		return false
	(stat_sources[key] as Array).append({"module": source, "kind": kind, "value": value})
	return true


## The flight computer fitted, or null when the ship flies on the built-in
## weight heuristic.
func computer() -> FlightComputerData:
	return computer_bay.installed as FlightComputerData if computer_bay != null else null


## The survey scanner fitted, or null for a ship that cannot see past
## the system it is in.
func scanner() -> ScannerData:
	return scanner_bay.installed as ScannerData if scanner_bay != null else null


## The jump drive fitted, or null for a ship that is not going anywhere.
func jump_drive() -> JumpDriveData:
	return jump_bay.installed as JumpDriveData if jump_bay != null else null


## The tank fitted, or null. A drive with no tank is a drive with nothing
## to burn, which is a configuration the report should talk about rather
## than one the code should prevent.
func tank() -> TankData:
	return tank_bay.installed as TankData if tank_bay != null else null


## How much fuel this hull can hold.
##
## Zero without a tank, and no hull rail to fall back on -- unlike energy,
## which every hull has a trickle of. A ship with no tank is not a ship
## with a small tank; it is a ship that is staying in this system, and
## saying so plainly is better than a litre of mystery fuel.
func fuel_capacity() -> float:
	var fitted: TankData = tank()
	return stat(&"fuel_capacity", fitted.fuel_capacity if fitted != null else 0.0)


## Takes fuel out of the tank. Returns how much it actually got, which is
## less than asked for when the tank runs dry -- the shortfall is what
## IDEAS.md section 10 turns into misjump risk rather than a refusal.
func draw_fuel(amount: float) -> float:
	var taken: float = clampf(amount, 0.0, fuel)
	fuel -= taken
	return taken


## Puts fuel in, up to the tank's capacity. Returns how much went in.
func add_fuel(amount: float) -> float:
	var room: float = maxf(fuel_capacity() - fuel, 0.0)
	var poured: float = clampf(amount, 0.0, room)
	fuel += poured
	return poured


## The generator fitted, or null when running on the hull's own rail.
func generator() -> GeneratorData:
	return generator_bay.installed as GeneratorData if generator_bay != null else null


func energy_capacity() -> float:
	var fitted: GeneratorData = generator()
	return stat(&"energy_capacity", fitted.capacity if fitted != null else HULL_RAIL_CAPACITY)


func energy_recharge_rate() -> float:
	var fitted: GeneratorData = generator()
	return stat(
		&"energy_recharge", fitted.recharge_rate if fitted != null else HULL_RAIL_RECHARGE
	)


func energy_recharge_delay() -> float:
	var fitted: GeneratorData = generator()
	return maxf(stat(
		&"energy_delay", fitted.recharge_delay if fitted != null else HULL_RAIL_DELAY
	), 0.0)


## True while the pool is waiting out the silence rather than filling. The
## HUD needs the two apart: a bar that is stopped and a bar that is climbing
## mean different things to a pilot deciding whether to hold the trigger.
func energy_waiting() -> bool:
	return _since_spend < energy_recharge_delay() and energy < energy_capacity()


## Takes `cost` from the pool if all of it is there, and returns whether it
## was. Every spend pushes the recharge back, which is what makes firing and
## charging mutually exclusive.
func spend_energy(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if energy < cost:
		return false
	energy -= cost
	_since_spend = 0.0
	return true


func _recharge(delta: float) -> void:
	var capacity: float = energy_capacity()
	_since_spend += delta
	if _since_spend < energy_recharge_delay():
		return
	energy = minf(energy + energy_recharge_rate() * delta, capacity)


## Whether the trigger a mount answers to is being pulled.
func _trigger_held(trigger: int) -> bool:
	return fire_secondary_command if trigger == 1 else fire_command


## The best any gun on `trigger` could do about the point being aimed at,
## which is what the cursor shows. Best rather than worst: the question a
## pilot is asking is "will pulling this do anything", and one gun that can
## bear is a yes.
func aim_state(trigger: int) -> Hardpoint.Aim:
	var best: Hardpoint.Aim = Hardpoint.Aim.BLOCKED
	for hardpoint: Hardpoint in hardpoints:
		if hardpoint.trigger != trigger:
			continue
		best = maxi(best, hardpoint.aim_state(aim_point)) as Hardpoint.Aim
	return best


## Whether any gun answers to this trigger at all, so the cursor can leave
## out a half nothing is wired to.
func has_trigger(trigger: int) -> bool:
	for hardpoint: Hardpoint in hardpoints:
		if hardpoint.trigger == trigger:
			return true
	return false


## Where fired rounds are parented. Falls back to the ship's own parent so a
## ship dropped into a bare scene (a test, a preview) still shoots.
func projectile_container() -> Node:
	var container: Node = get_tree().get_first_node_in_group(PROJECTILE_GROUP)
	if container != null:
		return container
	return get_parent()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if flight_mode == FlightMode.LANDED:
		return

	_resolve_commands(state)
	control.apply_commands(engines, active_commands)
	for engine: EngineInstance in engines:
		engine.advance(state.step)
		engine.mount.set_exhaust(engine.exhaust_flow())
		if engine.settle_flame():
			if engine.lit:
				engine_ignited.emit(engine)
			else:
				engine_cut.emit(engine)
	_resolve_boost(state.step)

	_applied_force = Vector2.ZERO
	_applied_torque = 0.0

	# Gravity is summed from the bodies in range rather than left to the
	# physics server, so the falloff can be ours (see IDEAS.md section 5).
	_gravity = gravity_acceleration_at(state.transform.origin)
	state.apply_central_force(_gravity * mass)

	_aim_gimbals()

	var body_rotation: float = state.transform.get_rotation()
	for engine: EngineInstance in engines:
		var local_force: Vector2 = engine.current_force()
		if local_force.is_zero_approx():
			continue
		# Confirmed against the 4.7 docs: apply_force()'s position is "the
		# offset from the body origin in global coordinates". From the ORIGIN,
		# not the centre of mass, so the mount position is only rotated, never
		# shifted. The server takes the torque about the centre of mass itself,
		# which is why center_of_mass has to be right for any of this to work.
		var force: Vector2 = local_force.rotated(body_rotation)
		var offset: Vector2 = engine.mount.position.rotated(body_rotation)
		state.apply_force(force, offset)
		_applied_force += force
		_applied_torque += (engine.mount.position - center_of_mass).rotated(body_rotation).cross(force)

	_resolve_terrain(state)
	_update_heat(state.step)


## Decides whether the engines run on emergency power this tick, and takes
## the fuel for it out of the pool.
##
## After the throttles have moved and before any force is applied, because
## what it costs depends on what the engines are actually managing: a
## drive at a quarter throttle burns a quarter as much, and a dead one
## burns nothing at all.
func _resolve_boost(step: float) -> void:
	var demand: float = 0.0
	for engine: EngineInstance in engines:
		demand += engine.boost_demand()

	if not boost_command:
		# Letting go is what rearms it.
		_boost_spent = false
		boost_active = false
	elif demand <= 0.0:
		# Asked for with the throttles shut. Nothing burns and nothing is
		# spent, so the press is still good when the pilot opens up.
		boost_active = false
	elif _boost_spent:
		boost_active = false
	elif boost_active:
		# Lit: keep it lit while there is anything left to burn, and let
		# the last tick run on whatever is in the bottom of the pool
		# rather than charging for a tick it does not deliver.
		boost_active = energy > 0.0
		if boost_active:
			spend_energy(minf(demand * step, energy))
		else:
			_boost_spent = true
	else:
		boost_active = (
			energy >= energy_capacity() * BOOST_RESERVE
			and spend_energy(demand * step)
		)
		_boost_spent = not boost_active

	for engine: EngineInstance in engines:
		engine.boosting = boost_active


## Shading the ship for the night side used to live here, as
## `_catch_the_light()`: the simulation reaching into its own Polygon2D
## every tick and setting `self_modulate`. It is `ShipSkin._hand_back()`
## now, which is a presentation node reading `daylight_at()` the same way
## it reads throttle and gear travel. Nothing about the picture changed.


## Ties up to a station, mends things while tied, and lets go.
##
## Here rather than in `_integrate_forces` for the same reason taking off
## is: a frozen body gets no `_integrate_forces` at all, so a docked ship
## that only listened there could never be told to leave.
##
## Docking is automatic once a ship is slow enough and close enough. No
## key for it, deliberately: the pilot has already said what they want by
## flying over at walking pace, and a prompt to press would be a second
## way to say the same thing. Leaving is the same gesture as taking off
## -- ask for thrust and you have it.
func _resolve_dock(delta: float) -> void:
	if flight_mode == FlightMode.DOCKED:
		if _wants_translation(commands) or brake_command:
			undock()
			return
		_mend(delta)
		if docked_at != null and is_instance_valid(docked_at):
			global_position = docked_at.global_position
			linear_velocity = Vector2.ZERO
			angular_velocity = 0.0
		else:
			# The dock streamed out from under us, which can only happen
			# a very long way from anywhere. Being adrift beats being
			# pinned to something that no longer exists.
			undock()
		return

	if flight_mode != FlightMode.PHYSICAL:
		return
	var dock: Station = Station.nearest(get_tree(), global_position)
	if dock == null:
		last_dock_rejection = ""
		_just_left = null
		return
	if _just_left != null:
		if not is_instance_valid(_just_left):
			_just_left = null
		elif global_position.distance_to(
			_just_left.global_position
		) > _just_left.dock_radius():
			_just_left = null
		else:
			last_dock_rejection = ""
			return
	# Only complain about a dock the pilot is plausibly trying for. A
	# refusal shown from half a system away is noise, and noise on a HUD
	# is a line pilots learn to stop reading.
	if global_position.distance_to(dock.global_position) > dock.dock_radius() * 2.0:
		last_dock_rejection = ""
		return
	var refused: String = dock.refusal(self)
	last_dock_rejection = refused
	if refused.is_empty():
		dock_with(dock)


## Puts the ship on the dock and freezes it there.
func dock_with(station: Station) -> void:
	if station == null or flight_mode == FlightMode.DOCKED:
		return
	docked_at = station
	last_dock_rejection = ""
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	set_deferred("freeze", true)
	flight_mode = FlightMode.DOCKED
	flight_mode_changed.emit(flight_mode)


## Lets go, and hands the ship back to the solver.
func undock() -> void:
	if flight_mode != FlightMode.DOCKED:
		return
	_just_left = docked_at
	docked_at = null
	set_deferred("freeze", false)
	freeze = false
	flight_mode = FlightMode.PHYSICAL
	flight_mode_changed.emit(flight_mode)


## What a dock does while you sit on it.
##
## The same three things the sandbox button does, only paid for in
## seconds instead of being free -- which is the whole point of there
## being somewhere to fly to.
func _mend(delta: float) -> void:
	if hull_integrity < 1.0:
		hull_integrity = minf(hull_integrity + DOCK_HULL_RATE * delta, 1.0)
		hull_changed.emit(hull_integrity)
	hull_heat = maxf(hull_heat - DOCK_HULL_RATE * delta, 0.0)
	for engine: EngineInstance in engines:
		engine.health = minf(engine.health + DOCK_ENGINE_RATE * delta, 1.0)
	energy = minf(energy + energy_capacity() * DOCK_ENERGY_RATE * delta, energy_capacity())
	# And the tank, which is what a dock is actually for. M3 left this
	# line out on purpose -- "the dock tops up energy for now, and when
	# fuel exists this is where it gets bought" -- because there was no
	# fuel to put in. There is now.
	add_fuel(fuel_capacity() * DOCK_FUEL_RATE * delta)


## True while everything a dock can mend is mended.
func fully_serviced() -> bool:
	if hull_integrity < 1.0 or energy < energy_capacity() - 0.01:
		return false
	if fuel < fuel_capacity() - 0.01:
		return false
	for engine: EngineInstance in engines:
		if engine.health < 1.0:
			return false
	return true


## Hull heating, from braking against the air and from standing too close
## to the star, and the damage a hull that stays hot takes.
func _update_heat(step: float) -> void:
	var planet: Planet = nearest_planet()
	air_density = planet.air_density_at(global_position) if planet != null else 0.0

	if air_density > 0.0:
		var speed_ratio: float = linear_velocity.length() / HEAT_REFERENCE_SPEED
		hull_heat += air_density * speed_ratio * speed_ratio * HEAT_RATE * step
	# One bar, two sources. The air heats what it brakes; the star heats
	# whatever is in front of it, moving or not, which is what makes
	# hanging around near it a decision rather than an accident.
	var star: Star = Star.of(get_tree())
	star_flux = star.irradiance_at(global_position) if star != null else 0.0
	hull_heat += star_flux * STAR_HEAT_RATE * step
	hull_heat = clampf(hull_heat - HEAT_COOLING * step, 0.0, 1.0)

	if hull_heat > BURN_HEAT:
		var over: float = (hull_heat - BURN_HEAT) / (1.0 - BURN_HEAT)
		take_damage(over * BURN_RATE * step, "heat")


## True if any command in `command_set` would translate the ship rather than
## turn it. Lift-off asks this: a landed ship may aim freely, but the moment it
## is told to move it has to be handed back to the solver.
func _wants_translation(command_set: Dictionary) -> bool:
	for command: ShipControl.Command in ShipControl.LINEAR_COMMANDS:
		if float(command_set.get(command, 0.0)) > 0.001:
			return true
	return false


## Resolves every hull point that is inside rock.
##
## Each contact gets its own impulse applied at its own offset from the centre
## of mass, which is what makes the ship pivot: touch down on one rear corner
## and the impulse there spins the ship about that corner, exactly as it should.
## An aggregated central response cannot do that no matter how it is tuned.
##
## Runs after the engine forces because it has the last word: it edits the
## velocity, the spin and the transform directly.
func _resolve_terrain(state: PhysicsDirectBodyState2D) -> void:
	_terrain_contacts = 0

	var planet: Planet = nearest_planet()
	if planet == null:
		return

	var body_transform: Transform2D = state.transform
	var points: Array[Vector2] = []
	var normals: Array[Vector2] = []
	var deepest: float = 0.0
	var deepest_normal: Vector2 = Vector2.ZERO
	## Where the worst of it landed, in the ship's own frame. Kept so the
	## damage can fall on the engines that were actually there.
	var deepest_local: Vector2 = Vector2.ZERO

	# Before the impulses, while the approach speed and attitude are still the
	# ones the pilot flew rather than ones the first bounce produced.
	if _try_land(state, planet):
		return

	var local_points: Array[Vector2] = contact_points()
	for i: int in range(local_points.size()):
		var world_point: Vector2 = body_transform * local_points[i]
		if not planet.is_solid_at(world_point):
			continue
		var point_normal: Vector2 = planet.surface_normal_at(world_point)
		if point_normal.is_zero_approx():
			continue
		points.append(world_point)
		normals.append(point_normal)
		var depth: float = planet.penetration_at(world_point, point_normal, penetration_limit())
		if depth > deepest:
			deepest = depth
			deepest_normal = point_normal
			deepest_local = local_points[i]

	_terrain_contacts = points.size()
	if _terrain_contacts == 0:
		return

	# Torque comes from the lever arm to the centre of mass, not to the origin.
	# On this hull they are ~3 px apart, which is enough to matter.
	var centre_of_mass: Vector2 = body_transform.origin + state.center_of_mass
	var impact_speed: float = _apply_contact_impulses(state, planet, centre_of_mass, points, normals)

	# Positional correction is deliberately partial and leaves a sliver of
	# overlap. Pushing the hull fully clear every tick adds height that gravity
	# then gives back, and the ship hops along the ground forever.
	if deepest > PENETRATION_SLOP:
		body_transform.origin += deepest_normal * ((deepest - PENETRATION_SLOP) * PENETRATION_CORRECTION)
		state.transform = body_transform

	# Whether the legs took it decides what it costs, and it is charged
	# once. The overspeed landing used to be billed twice for one arrival --
	# by the gear check for refusing the landing, and by this line for the
	# contact that followed in the same tick -- which is most of how a
	# touchdown a shade too fast came to cost more than a crash.
	var on_legs: bool = gear != null and gear.contact_points().has(deepest_local)
	var damage: float = impact_damage(impact_speed, on_legs)
	if damage > 0.0:
		hull_impact.emit(impact_speed, damage)
		take_damage(damage, "gear" if on_legs else "impact")
		# The engines nearest where it struck take it. Landing on a jet is
		# supposed to be a different mistake from landing on the nose.
		damage_engines_near(deepest_local, damage)


## Solves the contacts with sequential impulses and returns the hardest
## approach speed seen, for the damage model.
##
## Several passes because the contacts are coupled: an impulse at the nose
## changes the closing speed at the tail. Four is plenty for six points.
func _apply_contact_impulses(
	state: PhysicsDirectBodyState2D,
	planet: Planet,
	centre_of_mass: Vector2,
	points: Array[Vector2],
	normals: Array[Vector2],
) -> float:
	var inverse_mass: float = state.inverse_mass
	var inverse_inertia: float = state.inverse_inertia
	var hardest: float = 0.0

	for iteration: int in range(contact_iterations()):
		for i: int in range(points.size()):
			var arm: Vector2 = points[i] - centre_of_mass
			var normal: Vector2 = normals[i]
			# Everything here is measured against the GROUND, not the world.
			# The rock at this point is moving if the planet turns, and a
			# solver that does not know it drives the hull to a standstill in
			# world space instead -- which is the planet sliding out from
			# under a ship that looks parked (IDEAS.md section 7).
			var ground: Vector2 = planet.surface_velocity_at(points[i])
			var relative: Vector2 = _velocity_at(state, arm) - ground

			var closing: float = relative.dot(normal)
			if closing >= 0.0:
				continue
			if iteration == 0:
				# Not the closing speed alone. Flying into a hillside is
				# mostly a scrape -- the normal takes a fraction of the
				# speed and the rest goes along the rock -- so reading only
				# the normal component called a two hundred px/s crash a
				# graze.
				var scrape: float = absf(relative.dot(Vector2(-normal.y, normal.x)))
				hardest = maxf(hardest, -closing + scrape_share * scrape)

			var normal_arm: float = arm.cross(normal)
			var normal_mass: float = inverse_mass + normal_arm * normal_arm * inverse_inertia
			if normal_mass <= 0.0:
				continue

			# Bounce only above a cutoff. Keeping restitution at a resting
			# contact is the other half of why the ship never stopped hopping.
			var restitution: float = terrain_bounce if -closing > RESTITUTION_CUTOFF else 0.0
			var normal_impulse: float = -(1.0 + restitution) * closing / normal_mass
			_apply_impulse_at(state, normal * normal_impulse, arm, inverse_mass, inverse_inertia)

			# Coulomb friction along the surface, capped by the normal impulse.
			var tangent: Vector2 = Vector2(-normal.y, normal.x)
			# Re-read after the normal impulse, and again against the ground.
			var sliding: float = (_velocity_at(state, arm) - ground).dot(tangent)
			var tangent_arm: float = arm.cross(tangent)
			var tangent_mass: float = inverse_mass + tangent_arm * tangent_arm * inverse_inertia
			if tangent_mass <= 0.0:
				continue
			var limit: float = terrain_friction * normal_impulse
			var friction_impulse: float = clampf(-sliding / tangent_mass, -limit, limit)
			_apply_impulse_at(state, tangent * friction_impulse, arm, inverse_mass, inverse_inertia)

	return hardest


## Velocity of the hull at an offset from the centre of mass.
func _velocity_at(state: PhysicsDirectBodyState2D, arm: Vector2) -> Vector2:
	return state.linear_velocity + state.angular_velocity * Vector2(-arm.y, arm.x)


func _apply_impulse_at(
	state: PhysicsDirectBodyState2D,
	impulse: Vector2,
	arm: Vector2,
	inverse_mass: float,
	inverse_inertia: float,
) -> void:
	state.linear_velocity += impulse * inverse_mass
	state.angular_velocity += arm.cross(impulse) * inverse_inertia


## Points tested against the terrain: the hull always, the legs once they are
## fully out. The legs are appended last so the contact loop can tell which
## contacts were made on them.
func contact_points() -> Array[Vector2]:
	var points: Array[Vector2] = _outline_contacts.duplicate()
	if gear != null:
		points.append_array(gear.contact_points())
	return points


## Vertices of the outline plus a point every CONTACT_STEP along each edge,
## worked out once rather than per tick.
func _build_contact_points() -> void:
	_outline_contacts.clear()
	var outline: PackedVector2Array = hull_outline
	if outline.size() < 3:
		return
	for i: int in range(outline.size()):
		var from: Vector2 = outline[i]
		var to: Vector2 = outline[(i + 1) % outline.size()]
		_outline_contacts.append(from)
		# Ceil, not floor: the spacing has to come out at or under the step,
		# and rounding down would leave the longest edges under-sampled --
		# which is exactly where a spike would slip through.
		var segments: int = maxi(1, ceili(from.distance_to(to) / CONTACT_STEP))
		for step: int in range(1, segments):
			_outline_contacts.append(from.lerp(to, float(step) / float(segments)))


## The convex shape projectiles hit, built from the same outline the terrain
## sampling uses. One source, so what a bullet hits and what touches the
## ground can never drift apart.
func _build_collision_shape() -> void:
	var shape_node: CollisionShape2D = get_node_or_null("HullShape") as CollisionShape2D
	if shape_node == null or hull_outline.size() < 3:
		return
	var convex: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
	convex.points = Geometry2D.convex_hull(hull_outline)
	shape_node.shape = convex


## How many solver passes this hull needs. More contacts couple more tightly,
## so a bigger outline gets more work rather than a softer landing.
func contact_iterations() -> int:
	var points: int = maxi(_outline_contacts.size(), 1)
	return clampi(
		ceili(float(CONTACT_ITERATIONS) * float(points) / float(ITERATION_REFERENCE_POINTS)),
		CONTACT_ITERATIONS,
		CONTACT_ITERATIONS_MAX,
	)


## How deep the terrain probe should look for this hull. A larger, faster
## ship buries itself further in one tick, and a fixed ceiling would saturate
## and leave the correction quietly under-doing it.
func penetration_limit() -> float:
	return maxf(PlanetTerrain.MAX_PENETRATION, hull_extent() * 2.0)


## Half the longest span of the outline: the ship's own idea of how big it is.
func hull_extent() -> float:
	var extent: float = 0.0
	for point: Vector2 in hull_outline:
		extent = maxf(extent, point.length())
	return extent


## Decides whether a touchdown is a landing, and does it.
##
## Nothing here is scripted difficulty: every threshold is a gear stat, and the
## ship either meets them or does not. Returns true when the ship has landed,
## in which case the caller must not also apply contact impulses.
func _try_land(state: PhysicsDirectBodyState2D, planet: Planet) -> bool:
	if gear == null or not gear.is_deployed():
		return false
	# Not while burning. Without this a ship that has just lifted off is still
	# sitting on its legs at zero descent, meets every condition, and lands
	# again on the same tick, so it can never leave.
	if _wants_translation(active_commands) or brake_command:
		return false

	var legs_down: int = 0
	for clearance: float in ground_under_legs(planet, state.transform):
		if clearance <= LEG_CONTACT_REACH:
			legs_down += 1
	# Nothing is touching yet, so there is nothing to judge.
	if legs_down == 0:
		return false

	var up: Vector2 = (state.transform.origin - planet.global_position).normalized()
	var slope: float = slope_under_legs(planet, state.transform)
	# Derived from the height field rather than probed out of the bitmap. The
	# probe ring needs to straddle a surface, and a leg resting a few pixels
	# into the rock has most of its ring inside: it reported a level shelf as a
	# 55 degree wall and refused every landing. Taking the normal from the same
	# slope the check already measures cannot disagree with it either.
	var normal: Vector2 = up.rotated(-slope)
	# Measured against the ground, which is moving on a spinning planet: what
	# matters is the speed relative to the rock, not to the planet's centre.
	var relative: Vector2 = state.linear_velocity - planet.surface_velocity_at(state.transform.origin)
	var descent: float = -relative.dot(up)
	var lateral: float = absf(relative.dot(up.orthogonal()))

	var over_descent: float = descent - gear.vertical_limit()
	var over_lateral: float = lateral - gear.lateral_limit()
	if over_descent > 0.0 or over_lateral > 0.0:
		# Refused, and nothing more. Not binary either: the ship is still in
		# the air's hands and the legs are about to hit the rock, which is
		# where the damage is worked out -- once, by whatever actually
		# touched. Charging here as well made one arrival two accidents.
		_reject_landing("speed")
		return false

	# Attitude is judged on the first leg to touch, not once they all have.
	# They never all would: at an 18 px track and 3 px of travel, two legs can
	# only be down together if the ship is within about ten degrees of level,
	# so waiting for both made a fifteen degree tolerance unreachable and the
	# check dead code. Refusing early also gives the pilot a reason instead of
	# an unexplained tumble.
	var ship_up: Vector2 = FORWARD.rotated(state.transform.get_rotation())
	if absf(ship_up.angle_to(normal)) > gear.tilt_limit():
		_reject_landing("tilt")
		return false

	# Standing on one leg is not standing.
	if legs_down < MIN_LEGS_DOWN:
		return false

	# Measured across the legs, which is the ground they actually have to stand
	# on. A shorter span is no good here: over 12 px on a 1.5 px texel grid a
	# single step between texels reads as a cliff.
	if absf(slope) > gear.slope_limit():
		_reject_landing("slope")
		return false

	_settle_on(planet, state)
	return true


## Clearance between each leg and the ground directly beneath it, in pixels.
## Negative means the leg is already in the rock.
##
## Sampled per leg rather than through the ship's centre. A two point slope
## taken across the hull can read as perfectly level while the ship sits astride
## a ridge, because both samples land on the flanks and neither sees the crest
## between them. Asking each leg about its own patch cannot be fooled that way,
## and it is what IDEAS.md section 7 specifies anyway.
func ground_under_legs(planet: Planet, from: Transform2D) -> Array[float]:
	var clearances: Array[float] = []
	if gear == null:
		return clearances
	for leg: Vector2 in gear.legs:
		var leg_point: Vector2 = from * leg
		clearances.append(planet.height_above_terrain(leg_point))
	return clearances


## Ground slope across the outermost legs, in radians, signed along the line
## from the first leg to the last.
func slope_under_legs(planet: Planet, from: Transform2D) -> float:
	if gear == null or gear.legs.size() < 2:
		return 0.0
	var first_leg: Vector2 = gear.legs[0]
	var last_leg: Vector2 = gear.legs[gear.legs.size() - 1]
	var first: Vector2 = from * first_leg
	var last: Vector2 = from * last_leg
	var run: float = first.distance_to(last)
	if run < 0.001:
		return 0.0
	var rise: float = planet.surface_radius_at(last) - planet.surface_radius_at(first)
	return atan2(rise, run) * signf(last_leg.x - first_leg.x)


func _reject_landing(reason: String) -> void:
	if last_landing_rejection == reason:
		return
	last_landing_rejection = reason
	landing_rejected.emit(reason)


## Pins the ship to the ground in the planet's polar frame.
##
## Stored as (angle, radius, heading relative to the planet) rather than as a
## world transform, so a turning planet carries the ship with it. The ship is
## deliberately NOT reparented to the planet: IDEAS.md section 9 requires the
## player to stay a direct child of the world, because systems are streamed in
## and out underneath it.
func _settle_on(planet: Planet, state: PhysicsDirectBodyState2D) -> void:
	var offset: Vector2 = state.transform.origin - planet.global_position
	_landed_planet = planet
	_landed_angle = offset.angle() - planet.global_rotation
	_landed_radius = offset.length()
	_landed_heading = state.transform.get_rotation() - planet.global_rotation

	state.linear_velocity = Vector2.ZERO
	state.angular_velocity = 0.0
	# Deferred, because this runs inside _integrate_forces and freezing is a
	# change to the body's state in the physics server, which refuses it while
	# it is flushing queries. The same trap as spawning a projectile from here.
	# One tick passes before it takes hold, which costs nothing: flight_mode is
	# already LANDED, so _integrate_forces bails out and applies no gravity, and
	# the velocity has just been zeroed.
	set_deferred("freeze", true)

	last_landing_rejection = ""
	flight_mode = FlightMode.LANDED
	flight_mode_changed.emit(flight_mode)
	landed.emit(planet)


## Keeps a landed ship glued to its patch of ground as the planet turns.
func _hold_landed_pose() -> void:
	if _landed_planet == null or not is_instance_valid(_landed_planet):
		flight_mode = FlightMode.PHYSICAL
		freeze = false
		return
	# The angle stays in the planet's own frame: polar_to_world runs it through
	# to_global(), which already applies the planet's rotation. Adding the
	# rotation here as well turned a parked ship into one sliding across the
	# ground at twice the surface speed.
	global_position = _landed_planet.polar_to_world(_landed_angle, _landed_radius)
	global_rotation = _landed_heading + _landed_planet.global_rotation


## Releases the ship from the ground, carrying the surface velocity with it so
## lift-off from a spinning planet does not start with a jolt.
func take_off(state: PhysicsDirectBodyState2D = null) -> void:
	if flight_mode != FlightMode.LANDED:
		return
	var surface_velocity: Vector2 = Vector2.ZERO
	if _landed_planet != null and is_instance_valid(_landed_planet):
		surface_velocity = _landed_planet.surface_velocity_at(global_position)

	freeze = false
	flight_mode = FlightMode.PHYSICAL
	_landed_planet = null
	if state != null:
		state.linear_velocity = surface_velocity
	else:
		linear_velocity = surface_velocity
	flight_mode_changed.emit(flight_mode)


## How far from an impact an engine still feels it, in the ship's own frame.
## About the width of the hull: a hit is local, but not to the pixel.
const ENGINE_DAMAGE_RADIUS: float = 16.0

## Engine health lost per point of hull damage, at the point of impact.
##
## Was 1.6, on the argument that machinery is more fragile than structure.
## True, and too much: a 120 px/s arrival took the nearest engine to 62%
## health, and one mistake should not cost half an engine. At 0.5 the same
## arrival leaves it at 88% and the penalty is felt without ending the
## flight.
const ENGINE_DAMAGE_SHARE: float = 0.5


## Hurts the engines around `point` (in the ship's frame) in proportion to
## how close they are to it.
##
## Nothing here rebuilds the control groups. That is the whole design: the
## groups are built from nominal thrust, so a half-dead engine is not
## compensated for and the ship flies crooked until the pilot finds a flight
## computer that will do the compensating (IDEAS.md section 3).
func damage_engines_near(point: Vector2, severity: float) -> void:
	if severity <= 0.0:
		return
	for engine: EngineInstance in engines:
		var reach: float = engine.mount.position.distance_to(point) / ENGINE_DAMAGE_RADIUS
		if reach >= 1.0:
			continue
		engine.health = clampf(
			engine.health - severity * ENGINE_DAMAGE_SHARE * (1.0 - reach), 0.0, 1.0
		)


## Where the legs meet the ground, in the ship's frame -- the gear node if
## the hull has one, the bottom of the hull otherwise.
func _gear_point() -> Vector2:
	if gear != null:
		return gear.position
	return Vector2(0.0, 10.0)


## Puts every engine back into new condition. The repair key for now; a bench
## at a station later.
## Puts the hull back together: integrity, heat and the damage tally.
##
## Separate from `respawn`, which also moves the ship and empties the
## hold. The sandbox wants the one without the other -- carry on from
## where you are, undamaged -- and so will a repair bay at a station.
func repair_hull() -> void:
	hull_integrity = 1.0
	hull_heat = 0.0
	accumulated_damage = 0.0
	last_landing_rejection = ""


func repair_engines() -> void:
	for engine: EngineInstance in engines:
		engine.health = 1.0


## The worst-off engine, for the HUD and the configuration report.
func worst_engine_health() -> float:
	var worst: float = 1.0
	for engine: EngineInstance in engines:
		worst = minf(worst, engine.health)
	return worst


## What an impact at this speed costs, as a fraction of the hull.
##
## Two tolerances and two curves, because the legs exist to change the
## answer. Below the tolerance it is free; above it the cost is the square
## of how far over, so the difference between a heavy landing and a crash is
## a difference in kind and not just in degree.
##
## Public because the shape of this curve is a design decision and belongs
## in a test that can read it, not in a number someone has to re-derive from
## a crash.
func impact_damage(speed: float, on_legs: bool) -> float:
	var tolerance: float = damage_speed_threshold
	var writeoff: float = hull_writeoff_excess
	if on_legs and gear != null:
		# Never below the bare hull's. Legs rated for 45 px/s under a hull
		# that shrugs off 60 would otherwise make touching down on the feet
		# worse than belly-flopping, and legs that make things worse are not
		# legs. Their rating decides whether the landing is *accepted*; here
		# it can only raise the bar, never lower it.
		tolerance = maxf(damage_speed_threshold, gear.vertical_limit())
		writeoff = gear_writeoff_excess
	var excess: float = speed - tolerance
	if excess <= 0.0 or writeoff <= 0.0:
		return 0.0
	var over: float = excess / writeoff
	return minf(over * over, 1.0)


## Takes damage from any source. The single door in, so that every way of
## hurting the ship shares the death path rather than each inventing its own.
## `cause` is not used yet. It is here because M2 wants damage to fall on the
## part that took it, and the call sites that know the answer are these.
func take_damage(amount: float, cause: String = "") -> void:
	if amount <= 0.0 or hull_integrity <= 0.0:
		return
	var _taken_by: String = cause
	accumulated_damage += amount
	hull_integrity = maxf(hull_integrity - amount, 0.0)
	hull_changed.emit(hull_integrity)
	if hull_integrity <= 0.0:
		_destroy()


func is_destroyed() -> bool:
	return hull_integrity <= 0.0


func _destroy() -> void:
	# The ship is not freed. Everything points at it, the camera, the HUD, the
	# contrails, the debug layer, and re-instantiating would mean rewiring all
	# of it on every death in a game whose whole point is dying often. The world
	# puts it back together in place instead.
	if flight_mode == FlightMode.LANDED:
		set_deferred("freeze", false)
		flight_mode = FlightMode.PHYSICAL
		_landed_planet = null
	destroyed.emit(global_position, linear_velocity)


## Puts a wrecked ship back in the air, intact and empty-handed.
##
## Resets everything a death should clear rather than only the obvious parts:
## leaving the heat, the gear or a stale landing rejection behind would have the
## new ship inherit the old one's problems.
func respawn(at: Vector2, velocity: Vector2) -> void:
	hull_integrity = 1.0
	accumulated_damage = 0.0
	hull_heat = 0.0
	last_landing_rejection = ""
	commands.clear()
	active_commands.clear()
	kill_rotation_command = false
	docked_at = null
	last_dock_rejection = ""
	_just_left = null
	boost_command = false
	boost_active = false
	_boost_spent = false
	heading_command = ControlChords.Chord.NONE
	brake_command = false
	fire_command = false
	energy = energy_capacity()
	_since_spend = energy_recharge_delay()
	repair_engines()
	for engine: EngineInstance in engines:
		engine.throttle = 0.0
		engine.target_throttle = 0.0
		engine.mount.set_exhaust(0.0)
	if gear != null:
		gear.stow_instantly()

	flight_mode = FlightMode.PHYSICAL
	_landed_planet = null
	freeze = false
	global_position = at
	global_rotation = velocity.angle() - PI * 0.5 if not velocity.is_zero_approx() else 0.0
	linear_velocity = velocity
	angular_velocity = 0.0
	# Without this the interpolator draws a streak from where the wreck died to
	# where the new ship appeared.
	reset_physics_interpolation()
	snap_drawn()

	hull_changed.emit(hull_integrity)
	flight_mode_changed.emit(flight_mode)
	respawned.emit()


## Where this hull is actually being drawn this frame, and facing.
##
## The interpolated transform, blended the way the renderer blends it.
## Everything in the presentation layer that puts something **into the
## world** at the ship -- a beam leaving the muzzle, sparks coming off
## the plating, dust under the nozzles -- has to use this rather than
## `global_transform`, or it lands where the ship will be rather than
## where the ship is seen to be.
##
## Not used by anything that simulates. A gun aims and hits in physics
## time and should; this is only about where the picture goes.
func drawn_transform() -> Transform2D:
	if _was_at == Vector2.INF:
		return global_transform
	var along: float = Engine.get_physics_interpolation_fraction()
	return Transform2D(
		lerp_angle(_was_facing, _now_facing, along),
		_was_at.lerp(_now_at, along),
	)


## Forgets where the ship was, for a move that is not a movement.
##
## A respawn or a jump puts the hull somewhere else entirely, and
## without this the picture spends one tick sliding there from the old
## system -- the same streak `reset_physics_interpolation()` exists to
## stop, which is why it is called in the same places.
func snap_drawn() -> void:
	_was_at = global_position
	_now_at = global_position
	_was_facing = global_rotation
	_now_facing = global_rotation


func drawn_position() -> Vector2:
	return drawn_transform().origin


## Where a point bolted to this hull is being drawn.
##
## For muzzles and nozzles: take where the thing is in physics terms,
## carry it into the hull's frame, and put it back out through the
## transform the renderer is actually using. A beam leaving a gun has
## to start at the gun as drawn, not at the gun as simulated.
func drawn_point(on_hull: Vector2) -> Vector2:
	return drawn_transform() * (global_transform.affine_inverse() * on_hull)


## How many hull points were inside rock last tick.
func get_terrain_contacts() -> int:
	return _terrain_contacts


## Closest planet, or null if there is none in the scene.
func nearest_planet() -> Planet:
	return Planet.nearest(get_tree(), global_position)


## Whether a planet is close enough to be pulling on the ship.
##
## The sphere of influence, not the air and not the ground. A star does not
## count: `nearest_planet` only looks at planets, and the question being
## asked is whether there is a world under the ship, not whether anything
## at all is pulling -- in a star system something always is.
func in_planetary_gravity() -> bool:
	var planet: Planet = nearest_planet()
	if planet == null:
		return false
	return (
		planet.global_position.distance_to(global_position) < planet.influence_radius
	)


## Gravitational acceleration the ship felt last tick. Not get_gravity(),
## which is already taken by PhysicsBody2D.
func get_applied_gravity() -> Vector2:
	return _gravity


## The pull of whatever owns `point`: see GravityWell.pull_at, which is
## patched rather than summed because our planets do not move.
func gravity_acceleration_at(point: Vector2) -> Vector2:
	return GravityWell.pull_at(get_tree(), point)


## How far from the cursor a seeker will still take a lock, in world pixels.
##
## Converted from screen pixels through the camera, so pointing is exactly
## as forgiving at every framing. A fixed world radius would be at its most
## generous zoomed right in -- which is where the pilot has the most
## precision and needs the help least.
func lock_reach() -> float:
	var scale: float = 1.0
	if is_inside_tree():
		scale = get_viewport().get_canvas_transform().get_scale().x
	return LOCK_RADIUS / maxf(scale, 0.001)


## Total force applied by the engines last tick, in global coordinates.
func get_applied_force() -> Vector2:
	return _applied_force


## Total torque applied by the engines last tick.
func get_applied_torque() -> float:
	return _applied_torque


## Ship speed along its own nose direction. Negative means flying backwards.
func get_forward_speed() -> float:
	return linear_velocity.dot(FORWARD.rotated(global_rotation))


## Fills the command set from the input actions. Only action names here, never
## keycodes. Called from _physics_process, see the note there.
func read_player_input(delta: float) -> void:
	commands.clear()

	# Chords first: a key taken over by one must not also be read as the
	# command it usually means.
	var chord: ControlChords.Chord = chords.update(ControlChords.poll(), delta)
	var taken: Array[StringName] = chords.consumed()

	_set_command(ShipControl.Command.FORWARD, _strength(&"thrust_forward", taken))
	_set_command(ShipControl.Command.BACK, _strength(&"thrust_reverse", taken))
	_set_command(ShipControl.Command.CCW, _strength(&"rotate_left", taken))
	_set_command(ShipControl.Command.CW, _strength(&"rotate_right", taken))
	_set_command(ShipControl.Command.STRAFE_LEFT, _strength(&"strafe_left", taken))
	_set_command(ShipControl.Command.STRAFE_RIGHT, _strength(&"strafe_right", taken))

	# A chord and a key for the same thing, and both are worth having. The
	# chords exist because the keyboard is nearly full, and they are what a
	# pilot's hands can reach without leaving the movement keys; the keys
	# exist because a chord has to be learned, and the three things here
	# are the ones a pilot reaches for when something has gone wrong. The
	# key wins when both are held, because the key is unambiguous.
	kill_rotation_command = chord == ControlChords.Chord.KILL_ROTATION
	auto_orbit_command = chord == ControlChords.Chord.AUTO_ORBIT
	auto_level_command = chord == ControlChords.Chord.AUTO_LEVEL
	altitude_hold_command = chord == ControlChords.Chord.ALTITUDE_HOLD
	deorbit_command = chord == ControlChords.Chord.DEORBIT
	# Only the two pointing chords drive the heading assist; the rest mean
	# something else entirely and would have it chasing the velocity while
	# another assist steered.
	heading_command = ControlChords.Chord.NONE
	if chord == ControlChords.Chord.PROGRADE or chord == ControlChords.Chord.RETROGRADE:
		heading_command = chord

	if Input.is_action_pressed("kill_rotation"):
		kill_rotation_command = true
	if Input.is_action_pressed("hold_prograde"):
		heading_command = ControlChords.Chord.PROGRADE
	elif Input.is_action_pressed("hold_retrograde"):
		heading_command = ControlChords.Chord.RETROGRADE
	# Pointing and spinning are different jobs, so a pilot holding both
	# gets the one that wins arguments: stop.
	if kill_rotation_command:
		heading_command = ControlChords.Chord.NONE

	brake_command = Input.is_action_pressed("brake")
	boost_command = Input.is_action_pressed("boost")


func _strength(action: StringName, taken: Array[StringName]) -> float:
	return 0.0 if taken.has(action) else Input.get_action_strength(action)


func _set_command(command: ShipControl.Command, amount: float) -> void:
	if amount > 0.0:
		commands[command] = amount


## Adds whatever the two assists are asking for on top of the pilot's commands.
func _resolve_commands(state: PhysicsDirectBodyState2D) -> void:
	active_commands = commands.duplicate()
	if kill_rotation_command:
		_apply_kill_rotation(state)
	if heading_command != ControlChords.Chord.NONE:
		_apply_heading_hold(state)
	if auto_orbit_command:
		_apply_auto_orbit(state)
	if auto_level_command:
		_apply_auto_level(state)
	if altitude_hold_command:
		_apply_altitude_hold(state)
	else:
		_held_altitude = -1.0
	if deorbit_command:
		_apply_deorbit(state)
	if brake_command:
		_apply_brake(state)


## Cancels spin by asking for the opposite rotation, proportionally.
##
## Below the epsilon the spin is zeroed outright: impulse engines are all or
## nothing, so chasing the last hundredth of a radian with them oscillates
## forever instead of converging.
func _apply_kill_rotation(state: PhysicsDirectBodyState2D) -> void:
	var spin: float = state.angular_velocity
	var opposing: ShipControl.Command = (
		ShipControl.Command.CCW if spin > 0.0 else ShipControl.Command.CW
	)

	# Derived rather than fixed, so retuning the torque jets cannot silently
	# reintroduce the chatter this guards against.
	var per_pulse: float = control.authority_of(opposing) / maxf(inertia, 0.0001) * state.step
	var epsilon: float = maxf(KILL_ROTATION_EPS, per_pulse * KILL_ROTATION_PULSE_MARGIN)
	if absf(spin) <= epsilon:
		state.angular_velocity = 0.0
		return
	var amount: float = clampf(absf(spin) / KILL_ROTATION_GAIN, 0.0, 1.0)
	active_commands[opposing] = maxf(float(active_commands.get(opposing, 0.0)), amount)


## Swings the nose onto the direction of travel, or onto its opposite.
##
## Velocity is measured against the ground, the same frame the landing check
## and the contact solver use, so a ship parked on a turning planet reads as
## stopped rather than as drifting east at eight pixels a second. In orbit
## that differs from the true orbital prograde by the surface speed, a few
## degrees at most; when M2's auto-orbit needs better it will work from the
## orbital elements rather than from this.
##
## Bang-bang rather than a pair of tuned gains: aim for the fastest spin that
## can still be stopped by the time the nose arrives, which is the same
## time-to-kill shape the brake uses and needs no constants that would go
## stale the next time the torque jets change.
func _apply_heading_hold(state: PhysicsDirectBodyState2D) -> void:
	var travel: Vector2 = state.linear_velocity
	var planet: Planet = nearest_planet()
	if planet != null:
		travel -= planet.surface_velocity_at(global_position)
	if travel.length() < HEADING_MIN_SPEED:
		return
	if heading_command == ControlChords.Chord.RETROGRADE:
		travel = -travel

	point_nose_along(state, travel)


## Swings the nose onto `direction`, arriving without spin left over.
##
## Bang-bang rather than a pair of tuned gains: aim for the fastest turn that
## can still be stopped in the angle that remains, which is the same
## time-to-kill shape the brake uses and needs no constants that would go
## stale the next time the torque jets change.
func point_nose_along(state: PhysicsDirectBodyState2D, direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	var wanted: float = angle_difference(
		state.transform.get_rotation(), direction.angle() - FORWARD.angle()
	)
	var spin: float = state.angular_velocity

	var toward: ShipControl.Command = (
		ShipControl.Command.CW if wanted > 0.0 else ShipControl.Command.CCW
	)
	var alpha: float = control.authority_of(toward) / maxf(inertia, 0.0001)
	if alpha <= 0.0:
		return

	var cruise: float = signf(wanted) * minf(sqrt(2.0 * alpha * absf(wanted)), HEADING_MAX_SPIN)
	var change: float = cruise - spin
	if absf(wanted) <= HEADING_EPS and absf(spin) <= HEADING_EPS:
		state.angular_velocity = 0.0
		return

	var command: ShipControl.Command = (
		ShipControl.Command.CW if change > 0.0 else ShipControl.Command.CCW
	)
	var reach: float = control.authority_of(command) / maxf(inertia, 0.0001) * state.step
	var amount: float = clampf(absf(change) / maxf(reach, 0.0001), 0.0, 1.0)
	active_commands[command] = maxf(float(active_commands.get(command, 0.0)), amount)


## Asks for thrust along `world_push`, whatever combination of linear
## commands that takes on this hull. The commands are in the ship's frame, so
## the direction is turned into it first.
func push_along(state: PhysicsDirectBodyState2D, world_push: Vector2) -> void:
	if world_push.is_zero_approx():
		return
	var local: Vector2 = world_push.rotated(-state.transform.get_rotation())
	_push_axis(local.y, ShipControl.Command.FORWARD, ShipControl.Command.BACK)
	_push_axis(local.x, ShipControl.Command.STRAFE_RIGHT, ShipControl.Command.STRAFE_LEFT)


## One axis of a wanted push. Forward is -Y, so a negative component wants
## FORWARD; +X is to the right and wants STRAFE_RIGHT.
func _push_axis(
	component: float, wants_negative: ShipControl.Command, wants_positive: ShipControl.Command
) -> void:
	if is_zero_approx(component):
		return
	var command: ShipControl.Command = wants_negative if component < 0.0 else wants_positive
	var authority: float = control.authority_of(command)
	if authority <= 0.0:
		return
	var amount: float = clampf(absf(component) * mass / authority, 0.0, 1.0)
	active_commands[command] = maxf(float(active_commands.get(command, 0.0)), amount)


## Flies the ship onto a circular orbit at whatever height it is already at.
##
## Only inside a gravity well and only above the air, because the manoeuvre
## means nothing in deep space and cannot be held where there is drag. Refused
## outright when the fitted computer does not have the function -- some do and
## some do not, and finding one that does is a real upgrade rather than a
## number going up (IDEAS.md section 8).
func _apply_auto_orbit(state: PhysicsDirectBodyState2D) -> void:
	var box: FlightComputerData = computer()
	if box == null or not box.has_auto_orbit:
		return
	var planet: Planet = nearest_planet()
	if planet == null:
		return

	var arm: Vector2 = state.transform.origin - planet.global_position
	var radius: float = arm.length()
	if radius >= planet.influence_radius or radius <= planet.atmosphere_radius():
		return

	# The circular velocity here, in whichever direction the ship is already
	# going round. Turning an orbit round is a different manoeuvre and not
	# one an autopilot should do on its own.
	var tangent: Vector2 = Vector2(-arm.y, arm.x).normalized()
	if tangent.dot(state.linear_velocity) < 0.0:
		tangent = -tangent
	var wanted: Vector2 = tangent * sqrt(planet.mu() / radius)

	var change: Vector2 = wanted - state.linear_velocity
	if change.length() <= AUTO_ORBIT_EPS:
		return

	# Turn to the burn, then burn. A hull's thrust is wildly lopsided -- 900 N
	# out of the nose against 290 N sideways on the stock ship -- so an assist
	# that only pushed with whatever happened to be pointing the right way
	# would barely move the orbit at all. Pointing first is what real
	# autopilots do and what makes this converge.
	point_nose_along(state, change)
	var nose: Vector2 = FORWARD.rotated(state.transform.get_rotation())
	if nose.dot(change.normalized()) > AUTO_ORBIT_ALIGNMENT:
		push_along(state, change)


## Runs the orbit assist once against the ship's present state, for a test
## that needs to see whether it asks for anything at all. Not used in flight:
## _integrate_forces owns the real call and owns the physics state.
func _apply_auto_orbit_probe() -> void:
	var box: FlightComputerData = computer()
	if box == null or not box.has_auto_orbit:
		return
	var planet: Planet = nearest_planet()
	if planet == null:
		return
	var arm: Vector2 = global_position - planet.global_position
	var radius: float = arm.length()
	if radius >= planet.influence_radius or radius <= planet.atmosphere_radius():
		return
	var tangent: Vector2 = Vector2(-arm.y, arm.x).normalized()
	if tangent.dot(linear_velocity) < 0.0:
		tangent = -tangent
	var change: Vector2 = tangent * sqrt(planet.mu() / radius) - linear_velocity
	if change.length() > AUTO_ORBIT_EPS:
		active_commands[ShipControl.Command.FORWARD] = 1.0


## Holds the height it was engaged at, pushing radially against gravity.
##
## Thrust against weight, damped by the climb rate, or the ship porpoises:
## height alone is a spring, and a spring with no damping oscillates for
## ever. This is the assist a pilot wants while reading the ground for
## somewhere to put down.
func _apply_altitude_hold(state: PhysicsDirectBodyState2D) -> void:
	var box: FlightComputerData = computer()
	if box == null or not box.has_altitude_hold:
		return
	var planet: Planet = nearest_planet()
	if planet == null:
		return

	var up: Vector2 = (state.transform.origin - planet.global_position).normalized()
	var height: float = planet.altitude_at(state.transform.origin)
	if _held_altitude < 0.0:
		_held_altitude = height

	var climb: float = state.linear_velocity.dot(up)
	var wanted: float = (_held_altitude - height) * ALTITUDE_HOLD_GAIN - climb * ALTITUDE_HOLD_DAMP
	# Hold against gravity as well as correcting, or the assist spends its
	# whole effort discovering that the ship is falling.
	var hold: float = -_gravity.dot(up)
	push_along(state, up * (wanted + hold) * mass / maxf(mass, 0.0001))


## Lowers the low point of the orbit until it touches the air, and stops.
##
## Retrograde at apoapsis is the cheap way down, and the sum that says how
## much is dull enough to be worth automating and easy enough to get wrong by
## hand. Stops as soon as the periapsis is inside the atmosphere: dropping it
## further only turns a descent into an impact.
func _apply_deorbit(state: PhysicsDirectBodyState2D) -> void:
	var box: FlightComputerData = computer()
	if box == null or not box.has_deorbit:
		return
	var planet: Planet = nearest_planet()
	if planet == null:
		return

	var extremes: Vector2 = planet.orbit_extremes(state.transform.origin, state.linear_velocity)
	if extremes.x <= planet.atmosphere_radius():
		return

	var travel: Vector2 = state.linear_velocity
	if travel.length() < DEORBIT_MIN_SPEED:
		return
	# Straight against the direction of travel: the burn that lowers the far
	# side of the orbit and nothing else.
	point_nose_along(state, -travel)
	var nose: Vector2 = FORWARD.rotated(state.transform.get_rotation())
	if nose.dot(-travel.normalized()) > AUTO_ORBIT_ALIGNMENT:
		push_along(state, -travel.normalized() * travel.length())


## Holds the nose level with the horizon, so a descent is flown feet-first.
func _apply_auto_level(state: PhysicsDirectBodyState2D) -> void:
	var box: FlightComputerData = computer()
	if box == null or not box.has_auto_level:
		return
	var planet: Planet = nearest_planet()
	if planet == null:
		return
	point_nose_along(state, state.transform.origin - planet.global_position)


## Points every steerable nozzle so its thrust helps the turn being asked
## for.
##
## Deflection is proportional to the rotation demand and always the way that
## adds torque about the centre of mass, which depends on which side of it
## the engine sits -- a tail engine and a nose engine steer opposite ways for
## the same turn. Worked out from the arm rather than declared per mount, so
## moving an engine cannot leave the sign behind.
func _aim_gimbals() -> void:
	var turn: float = (
		float(active_commands.get(ShipControl.Command.CW, 0.0))
		- float(active_commands.get(ShipControl.Command.CCW, 0.0))
	)
	# Positive is to the ship's right, matching the +X of its own frame.
	var side: float = (
		float(active_commands.get(ShipControl.Command.STRAFE_RIGHT, 0.0))
		- float(active_commands.get(ShipControl.Command.STRAFE_LEFT, 0.0))
	)
	for engine: EngineInstance in engines:
		if engine.data.gimbal_range <= 0.0:
			continue
		var reach: float = engine.data.gimbal_range
		var wanted: float = 0.0

		if not is_zero_approx(turn):
			var arm: Vector2 = engine.mount.position - center_of_mass
			# Which way to steer, derived rather than declared per mount so
			# that moving an engine cannot leave a stale sign behind.
			#
			# Godot's rotated(a) is v - a * v.orthogonal() for small a, so a
			# deflection of g adds a torque of -T * g * arm.cross(
			# d.orthogonal()). Written as the cross the other way round,
			# because the version with a leading minus is the one I got
			# backwards first time and the test caught it.
			var sense: float = signf(
				engine.mount.force_direction().orthogonal().cross(arm)
			)
			if is_zero_approx(sense):
				sense = 1.0
			wanted += clampf(turn, -1.0, 1.0) * reach * sense

		# And the other use of the same hinge. A couple deflected the same
		# way turns the ship; deflected opposite ways it shoves it sideways,
		# because then the torques cancel and the side forces add. Only a
		# nozzle with a partner is asked, for the reason recorded on
		# ShipControl.gimbal_partner: on its own it would mostly fly
		# forward.
		if not is_zero_approx(side) and control.gimbal_partner.has(engine):
			var slip: Vector2 = (
				engine.mount.force_direction().rotated(reach)
				- engine.mount.force_direction()
			)
			if not is_zero_approx(slip.x):
				wanted += clampf(side, -1.0, 1.0) * reach * signf(slip.x)

		# Asking for both at once gets both, up to what the hinge has. A
		# full turn and a full strafe cannot both be had from two nozzles,
		# and the clamp is where that shows rather than somewhere surprising.
		engine.target_gimbal = clampf(wanted, -reach, reach)


## Whether holding the brake turns the ship around before it pushes.
##
## Out in the open it does, and the reason is the shape of the hull: 900 N
## out of the nose against 500 N of reverse and 262 N sideways. Braking
## with whatever happens to be pointing the right way throws away two
## thirds of the ship, which at the speeds between planets is the
## difference between stopping and not.
##
## Inside a planet's pull it does not, and that is not a simplification.
## Down there the nose has another job -- holding an attitude over terrain,
## lining a landing up, keeping the heat shield into the airflow -- and a
## brake that spun the ship out of it would be a hazard. Low and slow is
## also where the weak engines are enough.
##
## A hull with nothing to turn with keeps the old brake, because for that
## hull the alternative is not braking at all.
func brakes_by_turning() -> bool:
	if in_planetary_gravity():
		return false
	return (
		control.authority_of(ShipControl.Command.CW) > 0.0
		and control.authority_of(ShipControl.Command.CCW) > 0.0
	)


## Kills linear velocity, one of two ways.
##
## Turning round and burning out in the open, pushing against the velocity
## one axis at a time under a planet: see `brakes_by_turning` for why they
## are not the same manoeuvre. Under a planet rotation is left alone
## entirely -- brake is for stopping, aiming stays the pilot's job -- and a
## direction with no engines behind it simply is not braked, so a ship with
## no reverse thruster cannot stop itself going forward. That is the
## intended consequence of building the groups from geometry, not a gap.
func _apply_brake(state: PhysicsDirectBodyState2D) -> void:
	# A drift too small to be worth turning for goes the old way too.
	# Swinging the whole hull round to shed three pixels a second is a lot
	# of ship for very little speed, and the strafe jets can have it. The
	# threshold is the heading hold's, for the heading hold's reason:
	# below it the direction of travel stops being a direction.
	if brakes_by_turning() and state.linear_velocity.length() >= HEADING_MIN_SPEED:
		_apply_retro_burn(state)
		return

	var local_velocity: Vector2 = state.linear_velocity.rotated(-state.transform.get_rotation())
	if local_velocity.length() < BRAKE_EPS:
		state.linear_velocity = Vector2.ZERO
		return

	# Each pair is (what fights a negative component, what fights a positive
	# one). Forward is -Y, so drifting forward is negative and wants BACK;
	# drifting right is +X and wants STRAFE_LEFT. Getting the second pair the
	# wrong way round made the brake push the ship harder in the direction it
	# was already sliding.
	_brake_axis(
		local_velocity.y,
		ShipControl.Command.BACK,
		ShipControl.Command.FORWARD,
	)
	_brake_axis(
		local_velocity.x,
		ShipControl.Command.STRAFE_RIGHT,
		ShipControl.Command.STRAFE_LEFT,
	)


## One velocity component against the group that opposes it.
##
## `opposes_negative` is the command that pushes against a negative component,
## `opposes_positive` against a positive one. Named for what they fight rather
## than for their own direction, because the two read the same at a glance and
## the pair for the sideways axis was written backwards. The throttle
## is the time the group would need to kill this component, clamped to one
## second, so it holds full thrust while there is real speed to shed and eases
## off over the last stretch instead of overshooting into a wobble.
func _brake_axis(
	component: float, opposes_negative: ShipControl.Command, opposes_positive: ShipControl.Command
) -> void:
	if is_zero_approx(component):
		return
	var command: ShipControl.Command = opposes_negative if component < 0.0 else opposes_positive
	var authority: float = control.authority_of(command)
	if authority <= 0.0:
		return
	var amount: float = clampf(absf(component) * mass / authority, 0.0, 1.0)
	active_commands[command] = maxf(float(active_commands.get(command, 0.0)), amount)


## Swings the nose onto retrograde, and once it is there, burns.
##
## The order is the whole manoeuvre and the gate is what enforces it:
## pushing while still coming round puts thrust somewhere the ship is not
## going, and the turn is the quick part -- it is the burn that takes the
## time. This is the same shape as the orbit assist, which found the same
## answer for the same reason, and it is what a real pilot does.
##
## The push goes through `push_along` rather than straight at the drive, so
## whatever is left over sideways gets the strafe engines. Once the nose is
## round there is almost nothing left over, which is the point of putting
## it round first.
##
## **Boost needs nothing here.** Holding the key multiplies whatever the
## throttles are already asking for, and by the time this is burning, what
## they are asking for is the main drive.
func _apply_retro_burn(state: PhysicsDirectBodyState2D) -> void:
	var back: Vector2 = -state.linear_velocity
	point_nose_along(state, back)
	var nose: Vector2 = FORWARD.rotated(state.transform.get_rotation())
	if nose.dot(back.normalized()) > RETRO_BURN_ALIGNMENT:
		push_along(state, back)
