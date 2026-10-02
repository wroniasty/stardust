class_name Planet
extends GravityWell
## A planet: a destructible crust with its own gravity well and a layered
## atmosphere.
##
## Every parameter is rolled from `planet_seed`, so a planet is reproducible
## from one number and nothing about it is hand-placed.
##
## The pull, the well and its edge live in GravityWell, which the star shares.
## What is a planet and not a star begins here: ground, air and weather.
##
## The crust lives in PlanetTerrain as a polar bitmap. This node only owns it,
## keeps the shader pointed at it, and converts between world and local space
## for callers (see IDEAS.md section 6).

## Emitted when rock is actually removed, so anything resting on the ground
## can hear that it moved instead of asking every frame whether it did.
## Terrain is carved a few times a minute and read sixty times a second;
## the difference is the whole reason this is a signal.
signal carved(point: Vector2, radius: float)

## Concentric drag shells, from the top of the atmosphere down. Each entry is
## (fraction of the atmosphere height, fraction of the full drag). The top
## shell barely bites, which is what makes aerobraking a slow burn rather than
## a wall (M1.5).
const SHELL_PROFILE: Array[Vector2] = [
	Vector2(1.00, 0.15),
	Vector2(0.66, 0.50),
	Vector2(0.33, 1.00),
]

## Kinds of sky a planet can roll.
##
## One shader draws all of them; what differs is where the deck sits, how
## broken it is, how far it is warped and how hard the altitudes are sheared
## against each other. Rolling a type first and then jittering inside it keeps
## planets recognisable: independent rolls on eight parameters would average
## every world into the same middling haze.
enum CloudType {
	STRATUS,  ## Flat overcast lid, few gaps.
	CUMULUS,  ## Broken heaps with clear sky between them.
	CIRRUS,  ## Thin, fast, wispy veil high up.
	BANDED,  ## Sheared latitude bands, the gas giant look.
}

## Weather is part of what makes a planet recognisable, so none of it is a
## global constant beyond how often a planet has any.
const CLOUD_CHANCE: float = 0.75

## Sub-layers a deck is split into. Each turns at its own rate, which is what
## gives the sky depth when the ship flies through it; one layer reads as a
## sheet of stickers however good the individual clouds are.
const CLOUD_LAYERS: int = 3
const CLOUD_SPEED_RANGE: Vector2 = Vector2(0.008, 0.05)

## Clearance the cloud base keeps above the highest rock the generator can
## produce, in pixels. Mountains reach well past the nominal surface, so a deck
## placed purely as a fraction of the atmosphere would hang inside them.
const CLOUD_CLEARANCE: float = 20.0

## Fastest a planet may turn, in radians per second.
const MAX_SPIN_RATE: float = 0.02

## Roughly one landing shelf per this many pixels of circumference, never fewer
## than MIN_PLATEAUS.
const PLATEAU_SPACING: float = 900.0
const MIN_PLATEAUS: int = 4

## Drag of the densest shell at full atmospheric density, as Area2D linear_damp.
##
## This number is not a feel knob, it is a speed limit. Linear damping gives a
## terminal velocity of g / damp, so the drag near the ground decides whether a
## ship can still crash. At the original 2.0 the limit came out at 31 px/s
## against a 60 px/s damage threshold: the air made it physically impossible to
## hit hard enough to take damage, and landing stopped being a skill. At 0.4 the
## same planet allows 154 px/s, so the pilot has to do the braking.
##
## The profile was steepened to match, from 3/25/100 to 15/50/100, which leaves
## the top shell at exactly the drag it had before. Aerobraking is unchanged;
## only the lower air let go.
const MAX_ATMOSPHERE_DAMP: float = 0.4


## Terminal velocity a falling ship approaches at `point`, or INF in vacuum.
##
## Exposed because it is the number that decides whether landing is a skill,
## and a test guards it (see MAX_ATMOSPHERE_DAMP).
func terminal_velocity_at(point: Vector2) -> float:
	var density: float = air_density_at(point)
	if density <= 0.0:
		return INF
	return surface_gravity / (MAX_ATMOSPHERE_DAMP * density)

## Angular drag as a fraction of the linear drag on the same shell. Air resists
## a spin as well as a push, but deliberately less: low over a planet is exactly
## where the pilot needs to point the ship precisely, and the stock rotational
## engines only make 60 units of thrust each.
const ANGULAR_DAMP_RATIO: float = 0.5

@export var planet_seed: int = 0

# --- Rolled from the seed in generate(). ---
# `surface_radius`, `surface_gravity` and `influence_radius` are rolled here
# too, but declared in GravityWell: they are what makes a thing a source.

## Thickness of the atmosphere above the surface. Zero means an airless rock.
var atmosphere_height: float = 90.0

## 0..1, scales the drag of every shell.
var atmosphere_density: float = 1.0

## Radians per second the planet turns. Day and night, and something a landed
## ship has to be carried along by.
var spin_rate: float = 0.0

## Flat landing shelves levelled into the relief.
var plateau_count: int = 0

var surface_color: Color = Color(0.45, 0.38, 0.32)
var atmosphere_color: Color = Color(0.45, 0.62, 0.95)

# --- Weather, rolled from the same seed. ---

var has_clouds: bool = false
var cloud_color: Color = Color(1.0, 0.97, 0.95)

## Base and thickness of the deck, as fractions of the atmosphere height.
var cloud_base: float = 0.4
var cloud_depth: float = 0.15

var cloud_type: CloudType = CloudType.CUMULUS
## Fraction of the circumference standing under cloud. 1.0 means the clouds
## laid end to end would just circle the planet; above that they overlap into a
## continuous sheet.
var cloud_coverage: float = 0.6
var cloud_opacity: float = 0.6

## Size of one cloud, both measured in deck thicknesses so that they mean the
## same thing on a moon and on a gas giant. Height is given directly rather
## than as an aspect ratio: derived from the width it silently produced clouds
## several times taller than the deck they live in.
var cloud_puff_size: float = 2.0
var cloud_puff_height: float = 0.8

## Radians per second the deck turns, signed.
var cloud_speed: float = 0.02
var cloud_softness: float = 0.12
var cloud_warp: float = 0.3
var cloud_height_variation: float = 0.5
var cloud_shear: float = 0.0
var cloud_shading: float = 0.35
var cloud_octaves: int = 4

## How level the undersides are cut. Cumulus bases are famously flat, because
## they all condense at the same altitude; cirrus has no base at all.
var cloud_flat_base: float = 0.7

const CLOUD_SHADER: Shader = preload("res://shaders/cloud.gdshader")

var terrain: PlanetTerrain = PlanetTerrain.new()

@onready var _terrain_quad: ColorRect = $Terrain
@onready var _atmosphere: ColorRect = $Atmosphere
@onready var _clouds: Node2D = $Clouds
@onready var _shells: Node2D = $AtmosphereShells

var _terrain_material: ShaderMaterial = null
var _atmosphere_material: ShaderMaterial = null
var _cloud_material: ShaderMaterial = null


## The moment on the galaxy clock this planet is placed at. Handed in
## rather than fetched, which is the whole point: a planet that reaches for
## an autoload by path is a planet that behaves differently depending on
## who is running it, and the first version of this did exactly that --
## under `--script`, where the autoload does not exist, it still came back
## with something that was not zero and put the planet a radian and a half
## off its orbit.
var placed_at: float = 0.0


## Set by `prepare()`: the crust is already computed and must not be
## thrown away and rebuilt when the node enters the tree.
var _prebuilt: bool = false


func _ready() -> void:
	if _prebuilt:
		_raise()
	elif body != null:
		adopt(body, placed_at)
	else:
		generate(planet_seed)


## The first half of being born, for a planet whose crust is going to be
## computed on a worker thread: roll the parameters, and nothing else.
##
## Rolling is arithmetic and costs nothing; the crust is thirty-five
## milliseconds. Splitting them is what lets the expensive half run off the
## frame, and it can only run off the frame while the node is still out of
## the tree -- a node in the tree is a node something can ask about.
func prepare(descriptor: SystemBody, at_time: float) -> void:
	body = descriptor
	placed_at = at_time
	roll_parameters(
		descriptor.seed,
		descriptor.radius,
		descriptor.surface_gravity,
		descriptor.well_radius,
		descriptor.atmosphere_height,
	)
	_prebuilt = true


## The work the worker thread does. Handed out as a Callable so the caller
## decides which thread it runs on and this class does not have to know.
##
## `remembered` is a crust this world was left with. Put back here rather
## than after the node is in the tree, because doing it on the main thread
## cost fifteen milliseconds -- a returning planet hitched harder than a
## new one, which is precisely backwards.
func crust_task(remembered: PackedByteArray = PackedByteArray()) -> Callable:
	return func() -> void:
		terrain.build(planet_seed, surface_radius, plateau_count)
		if not remembered.is_empty():
			terrain.restore_crust(remembered)


## The second half: the texture, the visuals and the place it stands.
func _raise() -> void:
	terrain.finish()
	_build_terrain_quad()
	_build_atmosphere()
	_build_clouds()
	global_position = body.position_at(placed_at)


## Builds this planet as the body the system says it is.
##
## The join between the two halves of the split: **the system decides how
## big and how heavy, the seed decides what it looks like.** Size and
## gravity are handed over, everything else -- terrain, weather, colour,
## shelves -- is rolled from the body's own seed, and the roll is the same
## one it would have made on its own.
func adopt(descriptor: SystemBody, at_time: float = 0.0) -> void:
	body = descriptor
	placed_at = at_time
	roll_parameters(
		descriptor.seed,
		descriptor.radius,
		descriptor.surface_gravity,
		descriptor.well_radius,
		descriptor.atmosphere_height,
	)
	rebuild()
	global_position = descriptor.position_at(at_time)


func marker_color() -> Color:
	return surface_color


## Planet whose centre is closest to `point`, or null if there is none.
##
## Ships, projectiles and the debug HUD all need this; keeping one copy means
## the day planets stop being a flat group (M3 streaming) there is one place to
## change. A Planet and not a GravityWell on purpose: every caller wants
## ground, air or terrain, and the star has none of those.
static func nearest(tree: SceneTree, point: Vector2) -> Planet:
	var best: Planet = null
	var best_distance: float = INF
	for source: Node in tree.get_nodes_in_group(GROUP):
		var planet: Planet = source as Planet
		if planet == null:
			continue
		var distance: float = planet.global_position.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = planet
	return best


func has_ground() -> bool:
	return true


## Radius at the top of the atmosphere. Equals surface_radius when airless.
func atmosphere_radius() -> float:
	return surface_radius + atmosphere_height


## Radius above which no terrain can exist. Safe altitude for spawning.
func terrain_ceiling() -> float:
	return terrain.outer_radius


## Height above the nominal surface at a point, negative below it.
func altitude_at(point: Vector2) -> float:
	return global_position.distance_to(point) - surface_radius


## Height above the ground actually under a point, negative inside rock.
##
## Different from altitude_at(), and the difference is which question is
## being asked. Against the nominal radius is the orbital answer, where the
## mountains are noise on a number in the thousands. Against the terrain is
## the close-in answer, where the mountains are the entire subject: the
## landing readout, the approach camera, a shell that has to know whether it
## went off in the dirt. Three places spelled this out by hand before it had
## a name, which is three chances to measure the wrong one.
func height_above_terrain(point: Vector2) -> float:
	return global_position.distance_to(point) - surface_radius_at(point)


## True if a world point is inside rock.
func is_solid_at(point: Vector2) -> bool:
	return terrain.is_solid_local(to_local(point))


## Outward terrain normal at a world point, in world space.
func surface_normal_at(point: Vector2) -> Vector2:
	# The planet is not scaled, so a local direction is already a world one
	# apart from the node's rotation.
	return terrain.normal_local(to_local(point)).rotated(global_rotation)


## How far a world point sits inside rock, measured along `normal`.
func penetration_at(point: Vector2, normal: Vector2, limit: float = -1.0) -> float:
	var ceiling: float = limit if limit > 0.0 else PlanetTerrain.MAX_PENETRATION
	return terrain.penetration_local(to_local(point), normal.rotated(-global_rotation), ceiling)


## Blows a hole in the crust. Returns true if any rock was removed.
func carve(point: Vector2, radius: float) -> bool:
	if not terrain.carve_local(to_local(point), radius):
		return false
	carved.emit(point, radius)
	return true


func _physics_process(delta: float) -> void:
	if not is_zero_approx(spin_rate):
		rotation = wrapf(rotation + spin_rate * delta, -PI, PI)
	_follow_the_star()


## Tells the surface, the air and every cloud deck which way the star is.
##
## Every frame, because this is what a day is: the planet turns and the
## terminator walks round it. There is nothing to store and nothing to keep
## in step -- the direction is read off the star's position, so a planet
## woken up at any clock reading has the time of day it should have.
##
## With no star in the scene the strength goes to zero and the shaders skip
## the whole term, which leaves M1's single planet and the tests lit all
## the way round instead of half dark for no reason anyone could see.
func _follow_the_star() -> void:
	var star: Star = Star.of(get_tree())
	var lit: float = 0.0
	var towards: Vector2 = Vector2.UP
	if star != null:
		var arm: Vector2 = to_local(star.global_position)
		if not arm.is_zero_approx():
			towards = arm.normalized()
			lit = 1.0
	for shader: ShaderMaterial in [_terrain_material, _atmosphere_material]:
		if shader != null:
			shader.set_shader_parameter("sun_dir", towards)
			shader.set_shader_parameter("sunlight", lit)
			shader.set_shader_parameter("terminator", GravityWell.TERMINATOR)
	for child: Node in _clouds.get_children():
		var field: CloudField = child as CloudField
		if field != null:
			field.face_the_star(
				star.global_position if star != null else Vector2.ZERO, star != null
			)

	# And whatever is standing on the ground, which is the crates. Done
	# from here rather than by the crate itself because a settled crate
	# switches its own processing off -- that is what makes a shelf full
	# of them free -- and waking them up sixty times a second to ask what
	# time of day it is would undo exactly the saving that bought.
	for child: Node in get_children():
		var crate: LootCrate = child as LootCrate
		if crate != null:
			var lit_here: float = GravityWell.daylight_at(
				get_tree(), crate.global_position
			)
			crate.self_modulate = Color(lit_here, lit_here, lit_here)


## Radius of the ground below a world point, in the planet's local frame.
func surface_radius_at(point: Vector2) -> float:
	return terrain.surface_radius_at(to_local(point).angle())


## Slope of the ground under a world point, in radians.
##
## Measured in the polar frame the terrain is stored in: two height samples an
## arc apart, and the rise over the run between them. Zero is level ground,
## positive means the surface climbs anticlockwise. This is what the landing
## legs are checked against (IDEAS.md section 7).
func slope_at(point: Vector2, span: float = 12.0) -> float:
	var local: Vector2 = to_local(point)
	var radius: float = maxf(local.length(), 1.0)
	var angle: float = local.angle()
	# A fixed arc length rather than a fixed angle, so the measurement covers
	# the same patch of ground on a moon and on a gas giant.
	var half_angle: float = (span * 0.5) / radius

	var behind: float = terrain.surface_radius_at(angle - half_angle)
	var ahead: float = terrain.surface_radius_at(angle + half_angle)
	return atan2(ahead - behind, span)


## World position of a point given in the planet's polar frame. Used to keep a
## landed ship glued to the ground while the planet turns underneath it.
func polar_to_world(angle: float, radius: float) -> Vector2:
	return to_global(Vector2.from_angle(angle) * radius)


## Surface speed at a world point, from the planet's own rotation.
func surface_velocity_at(point: Vector2) -> Vector2:
	var arm: Vector2 = point - global_position
	return Vector2(-arm.y, arm.x) * spin_rate


## Air density at a world point, 0..1.
##
## Derived from the same SHELL_PROFILE the drag areas are built from, so the
## heating model and the braking cannot disagree about how thick the air is.
func air_density_at(point: Vector2) -> float:
	if atmosphere_height <= 0.0 or atmosphere_density <= 0.0:
		return 0.0
	var altitude: float = global_position.distance_to(point) - surface_radius
	if altitude >= atmosphere_height:
		return 0.0
	# The profile runs outermost first, so the last shell that still contains
	# the point is the innermost one, which is the one the physics server picks.
	var fraction: float = 0.0
	for profile: Vector2 in SHELL_PROFILE:
		if altitude <= atmosphere_height * profile.x:
			fraction = profile.y
	return atmosphere_density * fraction


## What a rolled world can be, as ranges rather than literals in the roll.
##
## Named because the system model rolls the same two numbers when it lays
## out a system, and a moon has to orbit inside its parent's well whatever
## that well happened to roll: `INFLUENCE_RATIO.x` is the floor the layout
## has to stay under. Two places rolling the same quantity from two sets of
## literals is two places that drift apart.
##
## Gravity is kept well under the ship's 80 px/s^2 of main thrust so a stock
## ship can always lift off.
const RADIUS_RANGE: Vector2 = Vector2(900.0, 1800.0)
const GRAVITY_RANGE: Vector2 = Vector2(25.0, 60.0)
const INFLUENCE_RATIO: Vector2 = Vector2(3.5, 6.0)

## How often a world comes out airless, and how deep the air is otherwise
## as a fraction of the surface radius.
##
## Named for the same reason as the three above: the system model rolls
## this one too, because how much air a world has is a question an orbit
## asks (it is what separates a decaying orbit from a lasting one) and the
## map wants to draw it for worlds that have not been built yet.
const AIRLESS_CHANCE: float = 0.2
const AIR_RATIO: Vector2 = Vector2(0.25, 0.45)


## Rolls every parameter from a seed and builds the planet from them.
##
## The two halves are separate on purpose. Rolling fills the fields; building
## reads them. That lets the planet configurator (F6) change a field by hand
## and rebuild without having to invent a seed that would have produced it,
## and it is the same split streaming will need in M3, where a planet's
## parameters are saved and restored rather than re-rolled.
func generate(new_seed: int) -> void:
	roll_parameters(new_seed)
	rebuild()


## Fills every parameter from the seed, touching nothing that is drawn.
## `forced_radius` and `forced_gravity` are how a system tells a planet how
## big and how heavy it is. Both rolls happen either way and the result is
## thrown away when overridden, so the random stream stays aligned: the
## same seed gives the same terrain, weather and colours whether the size
## came from the system or from the roll.
## How deep this world's air is, or zero for an airless rock. Static so
## that the system model can roll it for a planet nobody has built yet --
## the map draws the air of worlds that are still only descriptors.
static func roll_air(rng: RandomNumberGenerator, radius: float) -> float:
	if rng.randf() < AIRLESS_CHANCE:
		return 0.0
	return radius * rng.randf_range(AIR_RATIO.x, AIR_RATIO.y)


func roll_parameters(
	new_seed: int,
	forced_radius: float = 0.0,
	forced_gravity: float = 0.0,
	forced_well: float = 0.0,
	forced_air: float = -1.0,
) -> void:
	planet_seed = new_seed

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = planet_seed

	var rolled_radius: float = rng.randf_range(RADIUS_RANGE.x, RADIUS_RANGE.y)
	var rolled_gravity: float = rng.randf_range(GRAVITY_RANGE.x, GRAVITY_RANGE.y)
	surface_radius = rolled_radius if forced_radius <= 0.0 else forced_radius
	surface_gravity = rolled_gravity if forced_gravity <= 0.0 else forced_gravity
	# The well is drawn either way, like the two above it, so that forcing
	# one does not shift every later roll and give the same world a
	# different face depending on who built it.
	var rolled_well: float = surface_radius * rng.randf_range(
		INFLUENCE_RATIO.x, INFLUENCE_RATIO.y
	)
	influence_radius = rolled_well if forced_well <= 0.0 else forced_well

	var rolled_air: float = roll_air(rng, surface_radius)
	var thickness: float = rng.randf_range(0.4, 1.0)
	atmosphere_height = rolled_air if forced_air < 0.0 else forced_air
	# Airless is one fact, not two: a world with no air has no density
	# either, however the density roll came out.
	atmosphere_density = 0.0 if atmosphere_height <= 0.0 else thickness

	surface_color = Color.from_hsv(rng.randf(), rng.randf_range(0.15, 0.45), rng.randf_range(0.30, 0.55))
	atmosphere_color = Color.from_hsv(rng.randf(), rng.randf_range(0.30, 0.70), rng.randf_range(0.60, 0.95))

	# Slow enough that the surface speed stays well under the landing gear's
	# lateral tolerance: the ground has to move visibly without shearing a
	# parked ship off its legs.
	spin_rate = rng.randf_range(-MAX_SPIN_RATE, MAX_SPIN_RATE)

	# Scaled with circumference so a big world is not proportionally harder to
	# find a shelf on than a small one.
	plateau_count = maxi(
		MIN_PLATEAUS, int(TAU * surface_radius / PLATEAU_SPACING)
	)

	_roll_weather(rng)


## Rebuilds crust, atmosphere and weather from whatever the fields say now.
func rebuild() -> void:
	terrain.generate(planet_seed, surface_radius, plateau_count)

	_build_terrain_quad()
	_build_atmosphere()
	_build_clouds()


## The crust as it now stands, or nothing when this world is untouched.
##
## Empty for an unscarred planet on purpose: a world nobody shot at comes
## back identical from its seed, and keeping a copy of it would be keeping
## the seed twice.
func crust_delta() -> PackedByteArray:
	return terrain.crust() if terrain.scarred else PackedByteArray()


## Puts a remembered crust back. Returns whether it fitted.
func apply_crust(bytes: PackedByteArray) -> bool:
	return terrain.restore_crust(bytes)


## Angles, in the planet's own frame, of the shelves the generator levelled.
##
## These are the places the planet was built to be landed on, so anything that
## wants to put something down -- the configurator's teleport, a base in M3 --
## should ask rather than hunt for a flat spot.
func landing_sites() -> PackedFloat32Array:
	return terrain.plateau_angles


## Rolls the cloud deck. Airless rocks get no weather.
func _roll_weather(rng: RandomNumberGenerator) -> void:
	has_clouds = atmosphere_height > 0.0 and atmosphere_density > 0.0 and rng.randf() < CLOUD_CHANCE
	if not has_clouds:
		return

	cloud_type = _roll_cloud_type(rng)
	var direction: float = signf(rng.randf() - 0.5)
	cloud_speed = rng.randf_range(CLOUD_SPEED_RANGE.x, CLOUD_SPEED_RANGE.y) * direction

	match cloud_type:
		CloudType.STRATUS:
			cloud_base = rng.randf_range(0.20, 0.40)
			cloud_depth = rng.randf_range(0.10, 0.18)
			cloud_coverage = rng.randf_range(1.2, 1.8)
			cloud_opacity = rng.randf_range(0.45, 0.70)
			cloud_puff_size = rng.randf_range(3.0, 6.0)
			cloud_puff_height = rng.randf_range(0.35, 0.55)
			cloud_softness = rng.randf_range(0.16, 0.30)
			cloud_warp = rng.randf_range(0.10, 0.25)
			cloud_height_variation = rng.randf_range(0.05, 0.20)
			cloud_shear = rng.randf_range(-0.2, 0.2)
			cloud_shading = rng.randf_range(0.15, 0.30)
			cloud_octaves = 3
			cloud_flat_base = rng.randf_range(0.40, 0.65)
		CloudType.CUMULUS:
			cloud_base = rng.randf_range(0.28, 0.50)
			cloud_depth = rng.randf_range(0.16, 0.30)
			cloud_coverage = rng.randf_range(0.50, 0.80)
			cloud_opacity = rng.randf_range(0.60, 0.85)
			cloud_puff_size = rng.randf_range(1.4, 2.6)
			cloud_puff_height = rng.randf_range(0.70, 1.00)
			cloud_softness = rng.randf_range(0.05, 0.11)
			cloud_warp = rng.randf_range(0.25, 0.45)
			cloud_height_variation = rng.randf_range(0.55, 0.80)
			cloud_shear = rng.randf_range(-0.3, 0.3)
			cloud_shading = rng.randf_range(0.35, 0.55)
			cloud_octaves = 5
			cloud_flat_base = rng.randf_range(0.70, 0.90)
		CloudType.CIRRUS:
			cloud_base = rng.randf_range(0.55, 0.80)
			cloud_depth = rng.randf_range(0.06, 0.12)
			cloud_coverage = rng.randf_range(0.40, 0.70)
			cloud_opacity = rng.randf_range(0.25, 0.45)
			cloud_puff_size = rng.randf_range(5.0, 9.0)
			cloud_puff_height = rng.randf_range(0.25, 0.45)
			cloud_softness = rng.randf_range(0.12, 0.24)
			cloud_warp = rng.randf_range(0.55, 0.90)
			cloud_height_variation = rng.randf_range(0.25, 0.45)
			cloud_shear = rng.randf_range(0.6, 1.4) * direction
			cloud_shading = rng.randf_range(0.10, 0.20)
			cloud_octaves = 4
			cloud_flat_base = rng.randf_range(0.05, 0.20)
		CloudType.BANDED:
			cloud_base = rng.randf_range(0.22, 0.45)
			cloud_depth = rng.randf_range(0.22, 0.38)
			cloud_coverage = rng.randf_range(1.0, 1.5)
			cloud_opacity = rng.randf_range(0.55, 0.80)
			cloud_puff_size = rng.randf_range(5.0, 10.0)
			cloud_puff_height = rng.randf_range(0.50, 0.80)
			cloud_softness = rng.randf_range(0.10, 0.20)
			cloud_warp = rng.randf_range(0.15, 0.30)
			cloud_height_variation = rng.randf_range(0.10, 0.25)
			cloud_shear = rng.randf_range(1.0, 1.8) * direction
			cloud_shading = rng.randf_range(0.20, 0.35)
			cloud_octaves = 4
			cloud_flat_base = rng.randf_range(0.25, 0.45)

	# Mostly white, tinted towards the air it floats in, so the weather looks
	# like it belongs to the planet instead of being pasted on top of it.
	cloud_color = Color.WHITE.lerp(atmosphere_color, rng.randf_range(0.05, 0.45))


## Heaps are the common case; a banded gas giant sky should stay a surprise.
func _roll_cloud_type(rng: RandomNumberGenerator) -> CloudType:
	var roll: float = rng.randf()
	if roll < 0.40:
		return CloudType.CUMULUS
	if roll < 0.70:
		return CloudType.STRATUS
	if roll < 0.90:
		return CloudType.CIRRUS
	return CloudType.BANDED


## Colour of the underside of the deck. Cloud tops catch the light and bottoms
## do not, which is most of what makes a puff read as having volume.
func cloud_shade_color() -> Color:
	return cloud_color.darkened(0.45).lerp(atmosphere_color, 0.35)


## Radius the cloud deck starts at, or the surface when there is none.
##
## The rolled fraction is only a wish: the deck is pushed up above the terrain
## ceiling, and kept below the top of the air, so clouds are always weather in
## the sky rather than a decal stuck on a mountainside.
func cloud_base_radius() -> float:
	if not has_clouds:
		return surface_radius
	var floor_radius: float = terrain.outer_radius + CLOUD_CLEARANCE
	var thickness: float = atmosphere_height * cloud_depth
	var ceiling_radius: float = atmosphere_radius() - thickness
	var wanted: float = surface_radius + atmosphere_height * cloud_base
	return clampf(wanted, floor_radius, maxf(floor_radius, ceiling_radius))


## Radius of the top of the cloud deck, or the surface when there is none.
func cloud_ceiling() -> float:
	if not has_clouds:
		return surface_radius
	return cloud_base_radius() + atmosphere_height * cloud_depth


func _build_terrain_quad() -> void:
	var radius: float = terrain.outer_radius
	_terrain_quad.size = Vector2.ONE * radius * 2.0
	_terrain_quad.position = -Vector2.ONE * radius

	if _terrain_material == null:
		_terrain_material = (_terrain_quad.material as ShaderMaterial).duplicate() as ShaderMaterial
		_terrain_quad.material = _terrain_material

	_terrain_material.set_shader_parameter("terrain", terrain.texture)
	_terrain_material.set_shader_parameter("inner_radius", terrain.inner_radius)
	_terrain_material.set_shader_parameter("outer_radius", terrain.outer_radius)
	# One hue, three depths: the strata read as one rock rather than three.
	_terrain_material.set_shader_parameter("crust_color", surface_color.lightened(0.25))
	_terrain_material.set_shader_parameter("rock_color", surface_color)
	_terrain_material.set_shader_parameter("core_color", surface_color.darkened(0.45))


func _build_atmosphere() -> void:
	for child: Node in _shells.get_children():
		child.queue_free()

	var has_air: bool = atmosphere_height > 0.0 and atmosphere_density > 0.0
	_atmosphere.visible = has_air
	if not has_air:
		return

	var radius: float = atmosphere_radius()
	_atmosphere.size = Vector2.ONE * radius * 2.0
	_atmosphere.position = -Vector2.ONE * radius

	# Each planet needs its own copy or they would all share one set of colours.
	if _atmosphere_material == null:
		_atmosphere_material = (_atmosphere.material as ShaderMaterial).duplicate() as ShaderMaterial
		_atmosphere.material = _atmosphere_material
	_atmosphere_material.set_shader_parameter("surface_ratio", surface_radius / radius)
	_atmosphere_material.set_shader_parameter("atmosphere_color", atmosphere_color)
	_atmosphere_material.set_shader_parameter("density", atmosphere_density)

	for i: int in range(SHELL_PROFILE.size()):
		_shells.add_child(_make_shell(i))


## Builds the deck as individual clouds rather than as a pattern in a ring.
##
## The ring this replaces could not work from inside the atmosphere: the camera
## flies through the middle of it, so every cloud was a slice of one continuous
## field bent along the horizon and the sky read as a doughnut. Clouds need
## edges and positions.
func _build_clouds() -> void:
	for child: Node in _clouds.get_children():
		child.queue_free()
	_clouds.visible = has_clouds
	if not has_clouds:
		return

	if _cloud_material == null:
		_cloud_material = ShaderMaterial.new()
		_cloud_material.shader = CLOUD_SHADER
	_cloud_material.set_shader_parameter("cloud_color", cloud_color)
	_cloud_material.set_shader_parameter("shade_color", cloud_shade_color())
	_cloud_material.set_shader_parameter("shading", cloud_shading)
	_cloud_material.set_shader_parameter("softness", cloud_softness)
	_cloud_material.set_shader_parameter("detail", cloud_warp)
	# How high the lobes pile up follows the same roll that decides how uneven
	# the deck is: a sky of towering heaps and a flat lid are the same fact
	# seen from two distances.
	_cloud_material.set_shader_parameter("pile", 0.45 + cloud_height_variation)
	_cloud_material.set_shader_parameter("flat_base", cloud_flat_base)

	var base: float = cloud_base_radius()
	var deck: float = maxf(cloud_ceiling() - base, 1.0)
	var mid: float = base + deck * 0.5

	# Size is relative to the deck, so a cloud means the same thing on a moon
	# and on a gas giant.
	var width: float = deck * cloud_puff_size
	var size: Vector2 = Vector2(width, deck * cloud_puff_height)

	# Coverage is what fraction of the circumference has cloud standing on it,
	# which is the only definition that survives changing the planet's size.
	var total: int = int(TAU * mid * cloud_coverage / maxf(width, 1.0))

	for layer: int in range(CLOUD_LAYERS):
		var field: CloudField = CloudField.new()
		field.name = "Layer%d" % layer
		# A copy each, because each layer turns at its own rate and so is
		# facing the star from a slightly different angle. Everything else
		# about them is identical; this one parameter is not.
		field.material = _cloud_material.duplicate() as ShaderMaterial
		# Layers are spread across the deck and stacked from the inside out, so
		# the highest one is thinnest and faintest, the way a real sky thins.
		var fraction: float = float(layer) / float(CLOUD_LAYERS)
		var fade: float = 1.0 - fraction * 0.35
		field.build(
			hash_seed(planet_seed, layer),
			int(total / CLOUD_LAYERS),
			base + deck * fraction,
			deck / float(CLOUD_LAYERS) * (1.0 + cloud_height_variation),
			size * fade,
			Vector2(cloud_opacity * 0.55, cloud_opacity) * fade,
		)
		# Shear turns the layers against each other. On a banded planet that is
		# the whole look; elsewhere it is just parallax.
		field.spin = cloud_speed * (1.0 + cloud_shear * (fraction - 0.5))
		_clouds.add_child(field)


## Clouds in the sky, across every layer.
func cloud_count() -> int:
	var total: int = 0
	for child: Node in _clouds.get_children():
		var field: CloudField = child as CloudField
		if field != null:
			total += field.cloud_count()
	return total


## A stable second seed from a first one, so layers of the same planet differ
## without either of them tracking the other.
static func hash_seed(base: int, salt: int) -> int:
	return hash(str(base, ":", salt))


func _make_shell(index: int) -> Area2D:
	var profile: Vector2 = SHELL_PROFILE[index]

	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = surface_radius + atmosphere_height * profile.x

	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.shape = shape

	var shell: Area2D = Area2D.new()
	shell.name = "Shell%d" % index
	shell.gravity_space_override = Area2D.SPACE_OVERRIDE_DISABLED
	shell.linear_damp_space_override = Area2D.SPACE_OVERRIDE_COMBINE_REPLACE
	shell.linear_damp = MAX_ATMOSPHERE_DAMP * atmosphere_density * profile.y
	# Both overrides are set explicitly. Area2D.angular_damp defaults to 1.0,
	# so leaving the override alone parks a very strong value on every shell
	# waiting to be switched on by accident.
	shell.angular_damp_space_override = Area2D.SPACE_OVERRIDE_COMBINE_REPLACE
	shell.angular_damp = shell.linear_damp * ANGULAR_DAMP_RATIO
	# Inner shells are listed last and must win: higher priority is processed
	# first, and COMBINE_REPLACE then ignores every thinner shell around it.
	shell.priority = index + 1
	shell.add_child(collision)
	return shell
