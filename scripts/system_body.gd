class_name SystemBody
extends RefCounted
## One thing in a star system: the star, a planet, a moon, a station.
##
## Pure data. No nodes, no scene tree, nothing that has to be freed. A body
## exists whether or not anything is instantiated for it, which is the whole
## point of the split in IDEAS.md section 9: the model is the universe, the
## scene is only the part of it the player is near.
##
## The split of ownership with `Planet` is deliberate. **The system decides
## how big and how heavy; the seed decides what it looks like.** Radius and
## gravity are here because laying out a system needs them -- an orbit has
## to clear a surface, a moon has to stay inside its parent's well -- and
## because two places rolling the same number is two places that drift. The
## terrain, weather, colours and shelves all come from `seed` when the body
## is built, and nothing here duplicates them.

enum Kind {
	STAR, ## The one body at the origin. Everything else goes round it.
	PLANET, ## Landable, generated from its seed by Planet.
	MOON, ## The same, but orbiting a planet rather than the star.
	STATION, ## Dockable, no terrain, no gravity worth the name.
}

var kind: Kind = Kind.PLANET

## What this body's own generator is seeded with. Derived from the parent's
## seed and its index, so the whole universe still unrolls from one number.
var seed: int = 0

var display_name: String = "body"

## Surface radius in pixels, and surface gravity in px/s^2. A station's
## gravity is zero and its radius is the size of the thing you dock with.
var radius: float = 1000.0
var surface_gravity: float = 0.0

## How far this body's pull reaches, in pixels. Zero means "whatever the
## body rolls for itself", which is what a planet built from a bare seed
## and no system does.
##
## Here rather than rolled by the planet because it is not a free choice:
## a well only reaches as far as the body still out-pulls the star, and
## how far that is depends on where the layout put it. The layout is the
## only thing that knows, so the layout decides -- same reason radius and
## gravity live here (IDEAS.md "Gwiazda: ciagnie wszedzie").
var well_radius: float = 0.0

## What it goes round, or null for the star.
##
## Held weakly, and that is the whole reason it is behind a method. Bodies
## form a tree with links both ways, RefCounted counts references and has
## no cycle collector, so a parent holding its children while the children
## hold their parent is a system that is never freed -- three hundred of
## them in one test run, and Godot says so at exit. The owning reference is
## the system's `bodies` list; walking up from a child never needs to keep
## anything alive.
var _parent: WeakRef = null
var children: Array[SystemBody] = []


func parent_body() -> SystemBody:
	return null if _parent == null else _parent.get_ref() as SystemBody


func set_parent_body(body: SystemBody) -> void:
	_parent = null if body == null else weakref(body)

## The orbit, as a circle. Radius in pixels from the parent's centre, phase
## in radians at time zero, period in seconds.
##
## Circles rather than ellipses, and that is a choice rather than an
## oversight. An ellipse wants Kepler's equation solved per query to keep
## the time dependence honest; parameterising one by mean anomaly instead
## would draw the right shape while lying about the speed, which is the
## worst of both. A circle is exactly periodic, exact at any time, and
## costs a sine. When a system wants ellipses it can have real ones.
var orbit_radius: float = 0.0
var orbit_phase: float = 0.0
var orbit_period: float = 0.0


## Gravitational parameter, mu = g * r^2. What a satellite's period is
## worked out from, and the same expression the ship's orbit solver uses.
func mu() -> float:
	return surface_gravity * radius * radius


## Where this body is at `time`, in the system's own frame with the star at
## the origin.
##
## Analytic and recursive, with no state of any kind. A body streamed out
## and back comes back where it should be because nothing was integrating
## it in the first place -- there is no drift to accumulate and no update
## to miss. Depth is two at most: a moon asks its planet, which asks the
## star, which is the origin.
func position_at(time: float) -> Vector2:
	var above: SystemBody = parent_body()
	var centre: Vector2 = Vector2.ZERO if above == null else above.position_at(time)
	if orbit_period <= 0.0:
		return centre
	return centre + Vector2.from_angle(orbit_phase + TAU * time / orbit_period) * orbit_radius


## How far out this body and everything under it reach from the parent.
func extent() -> float:
	var out: float = orbit_radius + radius
	for child: SystemBody in children:
		out = maxf(out, orbit_radius + child.extent())
	return out


## The period of a circular orbit of `orbit` pixels around this body.
func period_for(orbit: float) -> float:
	var gravitational: float = mu()
	if gravitational <= 0.0 or orbit <= 0.0:
		return 0.0
	return TAU * sqrt(orbit * orbit * orbit / gravitational)


func kind_name() -> String:
	return Kind.keys()[int(kind)].to_lower()
