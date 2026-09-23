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

## Engine types this mount accepts. M2 checks it when fitting loot; nothing
## enforces it yet.
@export_flags("Main", "Torque", "Thruster") var allowed_types: int = 7

## Structural size of the slot. Doubles as the mass the fitted module adds to
## the ship, which is how modules move the centre of mass.
@export var size: float = 1.0

## The engine currently fitted, or null for an empty mount.
@export var installed: EngineData = null

@onready var exhaust: GPUParticles2D = get_node_or_null("Exhaust") as GPUParticles2D


## Thrust direction in the ship's frame, unit length, with the node's own
## rotation folded in so a mount can be aimed in the editor.
func force_direction() -> Vector2:
	var direction: Vector2 = transform.basis_xform(thrust_direction)
	if direction.is_zero_approx():
		return Vector2.ZERO
	return direction.normalized()


## Mass this mount contributes when occupied.
func module_mass() -> float:
	return size if installed != null else 0.0


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


func accepts(type: EngineData.Type) -> bool:
	return (allowed_types & (1 << int(type))) != 0
