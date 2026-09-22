class_name Planet
extends Node2D
## A planet: a circle with its own gravity well and a layered atmosphere.
##
## Every parameter is rolled from `planet_seed`, so a planet is reproducible
## from one number and nothing about it is hand-placed. The surface is a flat
## disc for now; the pixel terrain that replaces it arrives in M1.3.
##
## Gravity is not a gravity_point Area2D: its falloff is fixed and cannot be
## faded out at the edge of the well. Planets publish themselves in the
## GRAVITY_GROUP instead and ships sum `gravity_at()` themselves
## (see IDEAS.md section 5).

## Planets register here so ships can find them without a scene path.
const GRAVITY_GROUP: StringName = &"gravity_sources"

## Concentric drag shells, from the top of the atmosphere down. Each entry is
## (fraction of the atmosphere height, fraction of the full drag). The top
## shell barely bites, which is what makes aerobraking a slow burn rather than
## a wall (M1.5).
const SHELL_PROFILE: Array[Vector2] = [
	Vector2(1.00, 0.03),
	Vector2(0.66, 0.25),
	Vector2(0.33, 1.00),
]

## Drag of the densest shell at full atmospheric density, as Area2D linear_damp.
const MAX_ATMOSPHERE_DAMP: float = 2.0

@export var planet_seed: int = 0

# --- Rolled from the seed in generate(). ---

## Radius of the solid body, in pixels.
var surface_radius: float = 600.0

## Gravitational acceleration at the surface, in pixels per second squared.
var surface_gravity: float = 40.0

## Beyond this radius the planet pulls nothing.
var influence_radius: float = 3000.0

## Thickness of the atmosphere above the surface. Zero means an airless rock.
var atmosphere_height: float = 90.0

## 0..1, scales the drag of every shell.
var atmosphere_density: float = 1.0

var surface_color: Color = Color(0.45, 0.38, 0.32)
var atmosphere_color: Color = Color(0.45, 0.62, 0.95)

@onready var _atmosphere: ColorRect = $Atmosphere
@onready var _shells: Node2D = $AtmosphereShells

var _atmosphere_material: ShaderMaterial = null


func _ready() -> void:
	add_to_group(GRAVITY_GROUP)
	generate(planet_seed)


## Radius at the top of the atmosphere. Equals surface_radius when airless.
func atmosphere_radius() -> float:
	return surface_radius + atmosphere_height


## Height above the surface at a point, negative underground.
func altitude_at(point: Vector2) -> float:
	return global_position.distance_to(point) - surface_radius


## Gravitational acceleration a body feels at `point`, in pixels per second
## squared. Inverse square above the surface, faded smoothly to nothing at the
## edge of the well so a ship does not get a kick when it crosses the boundary.
func gravity_at(point: Vector2) -> Vector2:
	var to_center: Vector2 = global_position - point
	var distance: float = to_center.length()
	if distance < 0.001 or distance >= influence_radius:
		return Vector2.ZERO

	# Underground the inverse square would blow up, so hold it at surface value.
	var effective: float = maxf(distance, surface_radius)
	var strength: float = surface_gravity * pow(surface_radius / effective, 2.0)
	strength *= _edge_falloff(distance)
	return (to_center / distance) * strength


## Rolls every parameter from a seed and rebuilds the atmosphere.
func generate(new_seed: int) -> void:
	planet_seed = new_seed

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = planet_seed

	surface_radius = rng.randf_range(400.0, 900.0)
	# Kept well under the ship's 80 px/s^2 of main thrust so a stock ship can
	# always lift off. Heavy worlds that fight the engines are an M2 problem.
	surface_gravity = rng.randf_range(25.0, 60.0)
	influence_radius = surface_radius * rng.randf_range(3.5, 6.0)

	if rng.randf() < 0.2:
		atmosphere_height = 0.0
		atmosphere_density = 0.0
	else:
		atmosphere_height = surface_radius * rng.randf_range(0.10, 0.22)
		atmosphere_density = rng.randf_range(0.4, 1.0)

	surface_color = Color.from_hsv(rng.randf(), rng.randf_range(0.15, 0.45), rng.randf_range(0.30, 0.55))
	atmosphere_color = Color.from_hsv(rng.randf(), rng.randf_range(0.30, 0.70), rng.randf_range(0.60, 0.95))

	_build_atmosphere()
	queue_redraw()


func _draw() -> void:
	# Placeholder body. M1.3 replaces this with the terrain bitmap.
	draw_circle(Vector2.ZERO, surface_radius, surface_color)


## Smoothly takes gravity to zero over the outer tenth of the well.
func _edge_falloff(distance: float) -> float:
	var fade_start: float = influence_radius * 0.9
	if distance <= fade_start:
		return 1.0
	return 1.0 - smoothstep(fade_start, influence_radius, distance)


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
	# Inner shells are listed last and must win: higher priority is processed
	# first, and COMBINE_REPLACE then ignores every thinner shell around it.
	shell.priority = index + 1
	shell.add_child(collision)
	return shell
