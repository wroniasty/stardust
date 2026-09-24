class_name Planet
extends Node2D
## A planet: a destructible crust with its own gravity well and a layered
## atmosphere.
##
## Every parameter is rolled from `planet_seed`, so a planet is reproducible
## from one number and nothing about it is hand-placed.
##
## Gravity is not a gravity_point Area2D: its falloff is fixed and cannot be
## faded out at the edge of the well. Planets publish themselves in the
## GRAVITY_GROUP instead and ships sum `gravity_at()` themselves
## (see IDEAS.md section 5).
##
## The crust lives in PlanetTerrain as a polar bitmap. This node only owns it,
## keeps the shader pointed at it, and converts between world and local space
## for callers (see IDEAS.md section 6).

## Planets register here so ships can find them without a scene path.
const GRAVITY_GROUP: StringName = &"gravity_sources"

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

## Radius of the nominal surface, in pixels. Mountains rise above it and
## valleys cut below it; see PlanetTerrain for the actual crust.
var surface_radius: float = 600.0

## Gravitational acceleration at the nominal surface, in pixels per second
## squared.
var surface_gravity: float = 40.0

## Beyond this radius the planet pulls nothing.
var influence_radius: float = 3000.0

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
var cloud_coverage: float = 0.45
var cloud_opacity: float = 0.6

## Width of one cloud in deck thicknesses, and how much flatter than round it
## is. Both are relative to the deck, so they mean the same thing on a moon and
## on a gas giant.
var cloud_puff_size: float = 1.2
var cloud_flatten: float = 1.0

## Radians per second the deck turns, signed.
var cloud_speed: float = 0.02
var cloud_softness: float = 0.12
var cloud_warp: float = 0.3
var cloud_height_variation: float = 0.5
var cloud_shear: float = 0.0
var cloud_shading: float = 0.35
var cloud_octaves: int = 4

var terrain: PlanetTerrain = PlanetTerrain.new()

@onready var _terrain_quad: ColorRect = $Terrain
@onready var _atmosphere: ColorRect = $Atmosphere
@onready var _clouds: ColorRect = $Clouds
@onready var _shells: Node2D = $AtmosphereShells

var _terrain_material: ShaderMaterial = null
var _atmosphere_material: ShaderMaterial = null
var _cloud_material: ShaderMaterial = null


func _ready() -> void:
	add_to_group(GRAVITY_GROUP)
	generate(planet_seed)


## Planet whose centre is closest to `point`, or null if there is none.
##
## Ships, projectiles and the debug HUD all need this; keeping one copy means
## the day planets stop being a flat group (M3 streaming) there is one place to
## change.
static func nearest(tree: SceneTree, point: Vector2) -> Planet:
	var best: Planet = null
	var best_distance: float = INF
	for source: Node in tree.get_nodes_in_group(GRAVITY_GROUP):
		var planet: Planet = source as Planet
		if planet == null:
			continue
		var distance: float = planet.global_position.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = planet
	return best


## Radius at the top of the atmosphere. Equals surface_radius when airless.
func atmosphere_radius() -> float:
	return surface_radius + atmosphere_height


## Radius above which no terrain can exist. Safe altitude for spawning.
func terrain_ceiling() -> float:
	return terrain.outer_radius


## Height above the nominal surface at a point, negative below it.
func altitude_at(point: Vector2) -> float:
	return global_position.distance_to(point) - surface_radius


## True if a world point is inside rock.
func is_solid_at(point: Vector2) -> bool:
	return terrain.is_solid_local(to_local(point))


## Outward terrain normal at a world point, in world space.
func surface_normal_at(point: Vector2) -> Vector2:
	# The planet is not scaled, so a local direction is already a world one
	# apart from the node's rotation.
	return terrain.normal_local(to_local(point)).rotated(global_rotation)


## How far a world point sits inside rock, measured along `normal`.
func penetration_at(point: Vector2, normal: Vector2) -> float:
	return terrain.penetration_local(to_local(point), normal.rotated(-global_rotation))


## Blows a hole in the crust. Returns true if any rock was removed.
func carve(point: Vector2, radius: float) -> bool:
	return terrain.carve_local(to_local(point), radius)


## Speed of a circular orbit at `radius`, in pixels per second.
##
## For an inverse square field measured at the surface this is
## sqrt(g * R^2 / r). Orbit lock, the tests and any autopilot must agree on it,
## so it lives here rather than being rederived at each call site.
func circular_orbit_speed(radius: float) -> float:
	if radius <= 0.001:
		return 0.0
	return sqrt(surface_gravity * surface_radius * surface_radius / radius)


func _physics_process(delta: float) -> void:
	if not is_zero_approx(spin_rate):
		rotation = wrapf(rotation + spin_rate * delta, -PI, PI)


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


## Gravitational acceleration a body feels at `point`, in pixels per second
## squared. Inverse square above the surface, faded smoothly to nothing at the
## edge of the well so a ship does not get a kick when it crosses the boundary.
func gravity_at(point: Vector2) -> Vector2:
	var to_centre: Vector2 = global_position - point
	var distance: float = to_centre.length()
	if distance < 0.001 or distance >= influence_radius:
		return Vector2.ZERO

	# Underground the inverse square would blow up, so hold it at surface value.
	var effective: float = maxf(distance, surface_radius)
	var strength: float = surface_gravity * pow(surface_radius / effective, 2.0)
	strength *= _edge_falloff(distance)
	return (to_centre / distance) * strength


## Rolls every parameter from a seed and rebuilds crust and atmosphere.
func generate(new_seed: int) -> void:
	planet_seed = new_seed

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = planet_seed

	surface_radius = rng.randf_range(900.0, 1800.0)
	# Kept well under the ship's 80 px/s^2 of main thrust so a stock ship can
	# always lift off. Heavy worlds that fight the engines are an M2 problem.
	surface_gravity = rng.randf_range(25.0, 60.0)
	influence_radius = surface_radius * rng.randf_range(3.5, 6.0)

	if rng.randf() < 0.2:
		atmosphere_height = 0.0
		atmosphere_density = 0.0
	else:
		atmosphere_height = surface_radius * rng.randf_range(0.25, 0.45)
		atmosphere_density = rng.randf_range(0.4, 1.0)

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

	terrain.generate(planet_seed, surface_radius, plateau_count)

	_build_terrain_quad()
	_build_atmosphere()
	_build_clouds()


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
			cloud_coverage = rng.randf_range(0.62, 0.85)
			cloud_opacity = rng.randf_range(0.45, 0.70)
			cloud_puff_size = rng.randf_range(2.5, 4.0)
			cloud_flatten = rng.randf_range(1.8, 3.0)
			cloud_softness = rng.randf_range(0.16, 0.30)
			cloud_warp = rng.randf_range(0.10, 0.25)
			cloud_height_variation = rng.randf_range(0.05, 0.20)
			cloud_shear = rng.randf_range(-0.2, 0.2)
			cloud_shading = rng.randf_range(0.15, 0.30)
			cloud_octaves = 3
		CloudType.CUMULUS:
			cloud_base = rng.randf_range(0.28, 0.50)
			cloud_depth = rng.randf_range(0.16, 0.30)
			cloud_coverage = rng.randf_range(0.42, 0.62)
			cloud_opacity = rng.randf_range(0.60, 0.85)
			cloud_puff_size = rng.randf_range(0.8, 1.5)
			cloud_flatten = rng.randf_range(0.7, 1.0)
			cloud_softness = rng.randf_range(0.05, 0.11)
			cloud_warp = rng.randf_range(0.25, 0.45)
			cloud_height_variation = rng.randf_range(0.55, 0.80)
			cloud_shear = rng.randf_range(-0.3, 0.3)
			cloud_shading = rng.randf_range(0.35, 0.55)
			cloud_octaves = 5
		CloudType.CIRRUS:
			cloud_base = rng.randf_range(0.55, 0.80)
			cloud_depth = rng.randf_range(0.06, 0.12)
			cloud_coverage = rng.randf_range(0.22, 0.40)
			cloud_opacity = rng.randf_range(0.25, 0.45)
			cloud_puff_size = rng.randf_range(3.0, 6.0)
			cloud_flatten = rng.randf_range(2.5, 4.0)
			cloud_softness = rng.randf_range(0.12, 0.24)
			cloud_warp = rng.randf_range(0.55, 0.90)
			cloud_height_variation = rng.randf_range(0.25, 0.45)
			cloud_shear = rng.randf_range(0.6, 1.4) * direction
			cloud_shading = rng.randf_range(0.10, 0.20)
			cloud_octaves = 4
		CloudType.BANDED:
			cloud_base = rng.randf_range(0.22, 0.45)
			cloud_depth = rng.randf_range(0.22, 0.38)
			cloud_coverage = rng.randf_range(0.45, 0.68)
			cloud_opacity = rng.randf_range(0.55, 0.80)
			cloud_puff_size = rng.randf_range(2.0, 4.0)
			cloud_flatten = rng.randf_range(3.0, 5.0)
			cloud_softness = rng.randf_range(0.10, 0.20)
			cloud_warp = rng.randf_range(0.15, 0.30)
			cloud_height_variation = rng.randf_range(0.10, 0.25)
			cloud_shear = rng.randf_range(1.0, 1.8) * direction
			cloud_shading = rng.randf_range(0.20, 0.35)
			cloud_octaves = 4

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


## Smoothly takes gravity to zero over the outer tenth of the well.
func _edge_falloff(distance: float) -> float:
	var fade_start: float = influence_radius * 0.9
	if distance <= fade_start:
		return 1.0
	return 1.0 - smoothstep(fade_start, influence_radius, distance)


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


## The cloud deck: one quad reaching to the top of the clouds, drawn over the
## terrain. It is told nothing about the surface, only where the deck sits.
func _build_clouds() -> void:
	_clouds.visible = has_clouds
	if not has_clouds:
		return

	var top: float = cloud_ceiling()
	_clouds.size = Vector2.ONE * top * 2.0
	_clouds.position = -Vector2.ONE * top

	if _cloud_material == null:
		_cloud_material = (_clouds.material as ShaderMaterial).duplicate() as ShaderMaterial
		_clouds.material = _cloud_material

	_cloud_material.set_shader_parameter("base_ratio", cloud_base_radius() / top)
	_cloud_material.set_shader_parameter("top_ratio", 1.0)
	_cloud_material.set_shader_parameter("cloud_color", cloud_color)
	_cloud_material.set_shader_parameter("coverage", cloud_coverage)
	_cloud_material.set_shader_parameter("opacity", cloud_opacity)
	_cloud_material.set_shader_parameter("puff_size", cloud_puff_size)
	_cloud_material.set_shader_parameter("flatten", cloud_flatten)
	_cloud_material.set_shader_parameter("scroll_speed", cloud_speed)
	_cloud_material.set_shader_parameter("edge_softness", cloud_softness)
	_cloud_material.set_shader_parameter("shade_color", cloud_shade_color())
	_cloud_material.set_shader_parameter("warp_strength", cloud_warp)
	_cloud_material.set_shader_parameter("height_variation", cloud_height_variation)
	_cloud_material.set_shader_parameter("shear", cloud_shear)
	_cloud_material.set_shader_parameter("shading", cloud_shading)
	_cloud_material.set_shader_parameter("octaves", cloud_octaves)


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
