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

## Corona shells beyond the surface: (radius as a multiple of the surface,
## alpha). Drawn outward from the disc so the star has an edge that glows
## rather than a cut-out circle against the starfield.
const CORONA: Array[Vector2] = [
	Vector2(1.06, 0.55),
	Vector2(1.14, 0.30),
	Vector2(1.28, 0.14),
	Vector2(1.50, 0.05),
]

var colour: Color = COLOURS[2]


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
	queue_redraw()


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


func _draw() -> void:
	# Outermost first: each shell is translucent and the next one paints
	# over it, so going the other way would hide the whole corona under
	# its own widest ring.
	for i: int in range(CORONA.size() - 1, -1, -1):
		var shell: Vector2 = CORONA[i]
		draw_circle(Vector2.ZERO, surface_radius * shell.x, Color(colour, shell.y))
	draw_circle(Vector2.ZERO, surface_radius, colour)
