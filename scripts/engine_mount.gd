class_name EngineMount
extends Node2D
## A hardpoint on the hull that an engine can be bolted into: where it sits,
## which way it pushes, and what fits.
##
## The mount carries the geometry, the EngineData carries the machine. Keeping
## them apart is what lets M2 swap engines between mounts as loot without any
## of the control code noticing.

## Direction of the FORCE on the ship, in the ship's local frame, unit length.
## The exhaust plume points the opposite way. Stated as force rather than as
## nozzle direction because force is what every calculation downstream wants,
## and flipping the convention halfway is a classic source of sign bugs.
@export var thrust_direction: Vector2 = Vector2.UP

## Engine types this mount accepts. Left wide open on the stock ship: what an
## engine is good for comes out of the mount geometry, not out of its type, so
## a MAIN engine in a nose slot is a strange choice rather than an illegal one.
## The flags are here for hulls that genuinely cannot take a type at all.
@export_flags("Main", "Torque", "Thruster") var allowed_types: int = 7

## How much engine the slot has room for. Compared against EngineData.bulk,
## and nothing else: the slot itself is a hole in the hull and contributes no
## mass of its own.
@export var size: float = 1.0

## The engine currently fitted, or null for an empty mount.
@export var installed: EngineData = null

## The particle trail behind the flame.
##
## Scaled small in the scene on purpose: `particles/dot.png` is 24 texels
## across and a puff of exhaust wants to be two to five design pixels, so
## `scale_min` and `scale_max` are a tenth of what they would be for art
## drawn at the particle's own size. Before that texture existed this
## emitter had none at all, which in Godot means literal quads -- the
## exhaust was a grid of squares.
##
## It is the trail, not the flame. The flame is `ShipSkin`'s plume sprite,
## sitting at the nozzle exit; these are what it leaves behind, which is why
## they keep 85% of the emitter's velocity rather than all of it.
@onready var exhaust: GPUParticles2D = get_node_or_null("Exhaust") as GPUParticles2D


## Thrust direction in the ship's frame, unit length, with the node's own
## rotation folded in so a mount can be aimed in the editor.
func force_direction() -> Vector2:
	var direction: Vector2 = transform.basis_xform(thrust_direction)
	if direction.is_zero_approx():
		return Vector2.ZERO
	return direction.normalized()


## Mass this mount contributes: the fitted engine's own bulk, or nothing when
## the slot is empty.
func module_mass() -> float:
	return installed.bulk if installed != null else 0.0


## What a nozzle at full flow throws, measured against REFERENCE_THRUST.
##
## Scaled by the engine, which it was not at first and which is what made
## the manoeuvring thrusters as bright as the main drive -- eight equal
## lamps on one hull, which is a halo rather than a ship with engines.
## A flame is its thrust: a 180 N pod has no business lighting the same
## ground a 900 N drive does.
##
## Reach goes with the square root and strength goes linearly, so a small
## engine makes a small bright spot rather than a wide faint one. A wide
## faint one is exactly the look being avoided.
const REFERENCE_THRUST: float = 900.0
const GLOW_REACH: float = 110.0
const GLOW_STRENGTH: float = 0.5
const GLOW_COLOUR: Color = Color(1.00, 0.72, 0.42)


## How much of the reference this engine is, 0..1.
func _glow_share() -> float:
	if installed == null or REFERENCE_THRUST <= 0.0:
		return 0.0
	return clampf(installed.max_thrust / REFERENCE_THRUST, 0.0, 1.0)

var _glow: GlowLight = null


## Points the exhaust plume at `amount` of full flow, 0..1.
##
## The plume itself is configured in the scene, and one setting there matters
## more than the rest: `inherit_velocity_ratio`. Particles are emitted in world
## space at 70..110 px/s, which at a standstill is a flame and at 300 px/s is a
## puff the ship immediately leaves behind, drifting at a speed with no visible
## relation to anything. Carrying 85% of the emitter's velocity keeps the plume
## attached to the nozzle and lets the remaining 15% do the trailing, so it
## looks the same at every speed.
func set_exhaust(amount: float) -> void:
	if exhaust == null:
		return
	exhaust.emitting = amount > 0.02
	exhaust.amount_ratio = clampf(amount, 0.0, 1.0)

	# And the light the flame throws. Scaled with the flow rather than
	# switched on, because an engine at a tenth of throttle is a glow and
	# an engine at full is a landing light -- and because a light that
	# snapped on would turn a gentle correction burn into a strobe.
	var share: float = _glow_share()
	if share <= 0.0:
		return
	if _glow == null:
		_glow = GlowLight.make(GLOW_COLOUR, GLOW_REACH * sqrt(share), 0.0)
		add_child(_glow)
	_glow.energy = GLOW_STRENGTH * share * clampf(amount, 0.0, 1.0)
	_glow.visible = amount > 0.02


## True if this engine will physically go in: right kind, and small enough.
func fits(data: EngineData) -> bool:
	if data == null:
		return false
	return accepts(data.type) and data.bulk <= size


## True if the slot takes this kind of engine at all, ignoring how big it is.
## Split out from fits() so the loadout screen can tell "wrong kind" from
## "too big", which are different problems with different answers.
func accepts(type: EngineData.Type) -> bool:
	return (allowed_types & (1 << int(type))) != 0
