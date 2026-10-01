class_name Star
extends GravityWell
## The star at the middle of a system: a pull that reaches everywhere and a
## heat that reaches a little way.
##
## Not a Planet, and deliberately not built out of one. It has no crust, no
## air, no shelves and nothing to land on; what it shares with a planet is
## exactly the gravity well, which is why that lives one class up.
##
## There is no collision shape either, and that is not an omission. A ship
## that keeps flying at the star dies of heat several thousand pixels
## before it could touch anything, so a hull to bounce off would be a hull
## nothing ever reaches.

## Palette, coolest first. A star's colour is the one thing about it the
## pilot can read from across the system, so it is not rolled separately:
## it is read off the mass. A blue star really is the heavy one, and the
## colour on the scanner marker is then a reading rather than a decoration
## -- how hard this system is going to pull on a transfer, visible from
## anywhere in it.
const COLOURS: Array[Color] = [
	Color(1.00, 0.44, 0.28),  ## Red dwarf.
	Color(1.00, 0.66, 0.33),  ## Orange.
	Color(1.00, 0.89, 0.60),  ## Yellow.
	Color(0.95, 0.97, 1.00),  ## White.
	Color(0.68, 0.82, 1.00),  ## Blue giant.
]

## How far the corona quad reaches, as a multiple of the star's radius.
## The glow itself falls off inside it; this is only where the quad stops.
const CORONA_REACH: float = 2.2

## How wide a convection cell should be, in world pixels.
##
## Fixed in pixels and turned into a cell count per star, rather than a
## fixed count across the disc: a count would make every star look the
## same size on screen however big it is, and the only thing the pilot
## ever sees is a screen's worth of surface.
const CELL_PIXELS: float = 85.0

var colour: Color = COLOURS[2]

@onready var _corona: ColorRect = $Corona
@onready var _surface: ColorRect = $Surface


## Builds this star as the body the system says it is.
func adopt(descriptor: SystemBody) -> void:
	body = descriptor
	surface_radius = descriptor.radius
	surface_gravity = descriptor.surface_gravity
	influence_radius = descriptor.well_radius
	colour = colour_for(descriptor.surface_gravity)
	# The star does not move: it is the origin everything else is measured
	# from (IDEAS.md, "Planety nie okrazaja gwiazdy").
	global_position = Vector2.ZERO
	_build_quads()


## Sizes the two quads and hands them their colours.
func _build_quads() -> void:
	if _surface == null:
		# Adopted before entering the tree, which is the normal path: the
		# @onready members are not there yet, and `_ready` calls back.
		return
	_fit(_surface, surface_radius)
	_fit(_corona, surface_radius * CORONA_REACH)

	var surface_material: ShaderMaterial = _own_material(_surface)
	surface_material.set_shader_parameter("core_color", colour)
	surface_material.set_shader_parameter(
		"cells", maxf(8.0, 2.0 * surface_radius / CELL_PIXELS)
	)

	var corona_material: ShaderMaterial = _own_material(_corona)
	# Warmer than the star by a touch: the outer atmosphere of a star is
	# cooler than its face, and the difference is what stops the halo from
	# reading as a blur of the disc.
	corona_material.set_shader_parameter("glow_color", colour.lerp(COLOURS[1], 0.3))
	corona_material.set_shader_parameter("disc", 1.0 / CORONA_REACH)


func _fit(quad: ColorRect, radius: float) -> void:
	quad.size = Vector2.ONE * radius * 2.0
	quad.position = -Vector2.ONE * radius


## The shader material this node may write into, duplicated off the scene's
## shared one the first time. Without this every star in a session would be
## the colour of the last one built.
func _own_material(quad: ColorRect) -> ShaderMaterial:
	var mine: ShaderMaterial = quad.material as ShaderMaterial
	if mine.resource_local_to_scene:
		return mine
	mine = mine.duplicate() as ShaderMaterial
	mine.resource_local_to_scene = true
	quad.material = mine
	return mine


func _ready() -> void:
	_build_quads()


## Radiant flux at `point`, as a fraction of what the surface gets.
##
## Inverse square from the centre, held at 1.0 inside the surface so that
## the one place the formula would blow up is the one place it does not
## need to be exact: anything there is already cooking.
##
## How far the heat reaches is deliberately not answered here. The star
## emits; what that does to a hull is a question about the hull, and the
## radius where lingering starts to cost you is derived from the ship's own
## heating and cooling rates in `Ship.burn_radius`. Two constants, one in
## each file, would be two answers waiting to disagree.
func irradiance_at(point: Vector2) -> float:
	var distance: float = global_position.distance_to(point)
	if distance <= surface_radius:
		return 1.0
	var ratio: float = surface_radius / distance
	return ratio * ratio


## The star of the system currently in the world, or null.
##
## A system has exactly one, so there is nothing to choose between and no
## "nearest" to compute -- unlike Planet.nearest, which has to.
static func of(tree: SceneTree) -> Star:
	for source: Node in tree.get_nodes_in_group(GROUP):
		var star: Star = source as Star
		if star != null:
			return star
	return null


## Which of those a star of this surface gravity is.
static func colour_for(gravity: float) -> Color:
	var across: float = inverse_lerp(
		StarSystem.STAR_GRAVITY.x, StarSystem.STAR_GRAVITY.y, gravity
	)
	var step: int = floori(clampf(across, 0.0, 0.999) * float(COLOURS.size()))
	return COLOURS[step]


func marker_color() -> Color:
	return colour
