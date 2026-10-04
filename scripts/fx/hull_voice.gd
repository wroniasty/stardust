class_name HullVoice
extends Node
## Co słychać od kadłuba: uderzenia, podwozie, odmowa, koniec.
##
## Everything the ship itself does, as opposed to what its engines do.
## Listens and never writes: every signal it hangs off was already being
## emitted for something else, and nothing in the simulation learns that
## this exists.
##
## **Conducted, nearly all of it.** You are inside this hull, so you
## hear it hit things whether or not there is any air to carry the
## sound. The one exception is the landing refusal, which is a cockpit
## annunciator rather than a thing happening in the world -- a warning
## that went quiet in vacuum would be a warning that had misunderstood
## which side of the glass it is on.

## Impact speed at which a strike is as loud as it gets. The same
## figure `CameraShake` and `DebrisField` reason about, restated rather
## than imported for the same reason they do not share it: three
## tunings on one number is three tunings nobody can move.
const REFERENCE_SPEED: float = 300.0

## Below this a contact is a contact, not a sound. A ship settling onto
## its feet touches the ground a dozen times in a second.
const FAINTEST_KNOCK: float = 0.06

## Above this share of the reference speed, metal starts dragging: the
## grind is layered over the thump rather than replacing it, because a
## bad landing is a thud **and** a scrape.
const GRINDS_ABOVE: float = 0.35

## How far the impact pitch falls between a tap and a crash. Falling
## pitch is most of what makes a hit read as mass rather than volume.
const KNOCK_PITCH: Vector2 = Vector2(1.45, 0.72)

## How often a hull resting on its legs complains, in seconds, and how
## loud. Irregular on purpose: a creak on a timer is a metronome.
const CREAK_GAP: Vector2 = Vector2(2.4, 7.0)
const CREAK_VOLUME: float = 0.35

@export var ship_path: NodePath

var _ship: Ship = null
var _gear: LandingGear = null

var _knock: AudioStream = null
var _grind: AudioStream = null
var _creak: AudioStream = null
var _servo: AudioStream = null
var _touch: AudioStream = null
var _deny: AudioStream = null
var _blast: AudioStream = null
var _revive: AudioStream = null

var _until_creak: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_knock = load("res://resources/audio/thump.tres") as AudioStream
	_grind = load("res://resources/audio/hull_grind.tres") as AudioStream
	_creak = load("res://resources/audio/hull_creak.tres") as AudioStream
	_servo = load("res://resources/audio/gear_servo.tres") as AudioStream
	_touch = load("res://resources/audio/gear_touch.tres") as AudioStream
	_deny = load("res://resources/audio/deny.tres") as AudioStream
	_blast = load("res://resources/audio/explode.tres") as AudioStream
	_revive = load("res://resources/audio/respawn.tres") as AudioStream

	_ship = get_node_or_null(ship_path) as Ship
	if _ship == null:
		return
	_ship.hull_impact.connect(_on_impact)
	_ship.landed.connect(_on_landed)
	_ship.landing_rejected.connect(_on_refused)
	_ship.destroyed.connect(_on_destroyed)
	_ship.respawned.connect(_on_respawned)
	_gear = _ship.gear
	if _gear != null:
		_gear.deployment_changed.connect(_on_gear_moving)
	_until_creak = _rng.randf_range(CREAK_GAP.x, CREAK_GAP.y)


func _physics_process(delta: float) -> void:
	settle(delta)


## The slow half: a hull standing on its legs, complaining now and then.
##
## Ungated and public like the rest of this layer. The gap is rolled
## fresh each time rather than ticking a fixed period, because a creak
## on a timer stops being a creak after the second one.
func settle(delta: float) -> float:
	if _ship == null or not is_instance_valid(_ship):
		return _until_creak
	if _ship.flight_mode != Ship.FlightMode.LANDED:
		# Reset rather than carry: a ship that takes off halfway to a
		# creak should not creak the moment it lands somewhere else.
		_until_creak = _rng.randf_range(CREAK_GAP.x, CREAK_GAP.y)
		return _until_creak
	_until_creak -= delta
	if _until_creak > 0.0:
		return _until_creak
	_until_creak = _rng.randf_range(CREAK_GAP.x, CREAK_GAP.y)
	_say(_creak, CREAK_VOLUME, _rng.randf_range(0.85, 1.2))
	return _until_creak


## A hit, from a tap to a grind.
##
## One event at different speeds rather than three samples: the signal
## carries the speed, so the pitch and the loudness do the work. The
## grind is **layered on** above a threshold instead of replacing the
## thump, because a bad landing is a thud and a scrape, not one or the
## other.
func _on_impact(impact_speed: float, _damage: float) -> void:
	var share: float = clampf(impact_speed / REFERENCE_SPEED, 0.0, 1.5)
	if share < FAINTEST_KNOCK:
		return
	_say(
		_knock,
		minf(share, 1.0),
		lerpf(KNOCK_PITCH.x, KNOCK_PITCH.y, minf(share, 1.0)),
	)
	if share >= GRINDS_ABOVE:
		var hard: float = (share - GRINDS_ABOVE) / maxf(1.0 - GRINDS_ABOVE, 0.001)
		_say(_grind, clampf(hard, 0.15, 1.0), _rng.randf_range(0.9, 1.1))


## The gear, in both directions: the same motor runs either way.
func _on_gear_moving(_deployed: bool) -> void:
	_say(_servo, 0.5, 1.0)


func _on_landed(_planet: Planet) -> void:
	_say(_touch, 0.8, _rng.randf_range(0.92, 1.08))


## Refused, and the reason is not thrown away: a HUD will want it, and
## a short blip that cannot say which rule was broken is a blip the
## pilot learns to ignore.
func _on_refused(_reason: String) -> void:
	_say(_deny, 0.6, 1.0, Soundscape.Path.INTERFACE)


func _on_destroyed(at: Vector2, _velocity: Vector2) -> void:
	var mixer: Soundscape = Soundscape.of()
	if mixer != null and _blast != null:
		mixer.play(_blast, at, Soundscape.Path.CONDUCTED, 1.0)


func _on_respawned() -> void:
	_say(_revive, 0.7, 1.0, Soundscape.Path.INTERFACE)


## Everything goes out through `Soundscape`, at the ship, conducted
## unless it is a thing in the cockpit rather than a thing in the world.
func _say(
	sample: AudioStream,
	volume: float,
	pitch: float,
	path: Soundscape.Path = Soundscape.Path.CONDUCTED,
) -> bool:
	var mixer: Soundscape = Soundscape.of()
	if mixer == null or sample == null or _ship == null or not is_instance_valid(_ship):
		return false
	return mixer.play(sample, _ship.global_position, path, volume, pitch)
