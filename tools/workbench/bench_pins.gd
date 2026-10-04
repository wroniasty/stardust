class_name BenchPins
extends Node
## Holds a few ship fields at a value the bench chose.
##
## The ship overwrites some of its own state every tick -- `air_density` and
## `star_flux` from a planet and a star the bench does not have, `hull_heat`
## from both -- so writing them once does nothing for longer than a frame.
## A pin writes the value again before anything reads it, which is what lets
## a form say "the air is this thick" in a scene with no air.
##
## Runs ahead of the ship and of the presentation nodes, in both callbacks:
## the ship's physics step runs after every `_physics_process` and zeroes
## what it owns, and the sound and the sprites read in `_process`, after that
## step. A pin applied only in the first would be overwritten before the
## second ever looked.
##
## Pins hold what the ship would otherwise recompute. State the ship keeps
## by itself -- hull integrity, engine health -- is written directly by the
## forms and is not pinned: pinning it would make damage impossible.

## Fields the ship recomputes, which are therefore worth pinning.
const PINNABLE: Array[StringName] = [&"hull_heat", &"air_density", &"star_flux"]

var ship: Ship = null

## Fuel and energy, kept full when asked. A refill rather than a pin: the
## ship does change these itself, and "never runs dry" is the request.
var endless_fuel: bool = false
var endless_energy: bool = false

var _pinned: Dictionary = {}


func _ready() -> void:
	process_priority = -10
	process_physics_priority = -10


func pin(key: StringName, value: float) -> void:
	assert(PINNABLE.has(key), "%s is not something the ship recomputes" % key)
	_pinned[key] = value


func unpin(key: StringName) -> void:
	_pinned.erase(key)


func is_pinned(key: StringName) -> bool:
	return _pinned.has(key)


func pinned_value(key: StringName) -> float:
	return float(_pinned.get(key, 0.0))


## Lets go of everything, for the "reset" button.
func clear() -> void:
	_pinned.clear()
	endless_fuel = false
	endless_energy = false


func _physics_process(_delta: float) -> void:
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	if ship == null:
		return
	for key: StringName in _pinned:
		ship.set(key, _pinned[key])
	if endless_fuel:
		ship.fuel = ship.fuel_capacity()
	if endless_energy:
		ship.energy = ship.energy_capacity()
