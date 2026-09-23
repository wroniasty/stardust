class_name ShipControl
extends RefCounted
## Turns a ship's engine geometry into control groups, and pilot commands into
## per-engine throttles.
##
## The idea replacing the old fixed roles: an engine has a position and a
## direction, and what it is good for is computed, not declared. Each engine
## gets a contribution vector
##
##     c = (Fx/mass, Fy/mass, tau/inertia * gyration_radius)
##
## and every command is a direction in that same space. An engine joins a
## command's group if it pushes usefully along that direction, weighted by how
## cleanly it does so. Move an engine and its job changes with it.
##
## The gyration radius on the third component is not decoration. Without it the
## vector mixes px/s^2 with rad/s^2 and the two are not comparable: a torque
## engine's own linear side effect (a few px/s^2) would swamp its angular
## contribution (a fraction of a rad/s^2), the side penalty would reject it,
## and no engine would ever qualify for a rotation group. Multiplying the
## angular term by sqrt(inertia/mass) expresses all three as the acceleration
## seen at the ship's radius of gyration, which is the comparison the heuristic
## is actually trying to make.

## Six things a pilot can ask for, in the ship's frame. Forward is -Y and a
## positive rotation is clockwise on screen, matching Godot's 2D convention.
enum Command { FORWARD, BACK, STRAFE_LEFT, STRAFE_RIGHT, CCW, CW }

const COMMAND_AXES: Dictionary = {
	Command.FORWARD: Vector3(0.0, -1.0, 0.0),
	Command.BACK: Vector3(0.0, 1.0, 0.0),
	Command.STRAFE_LEFT: Vector3(-1.0, 0.0, 0.0),
	Command.STRAFE_RIGHT: Vector3(1.0, 0.0, 0.0),
	Command.CCW: Vector3(0.0, 0.0, -1.0),
	Command.CW: Vector3(0.0, 0.0, 1.0),
}

## Commands that move the ship rather than turn it. Braking only uses these.
const LINEAR_COMMANDS: Array[Command] = [
	Command.FORWARD, Command.BACK, Command.STRAFE_LEFT, Command.STRAFE_RIGHT,
]

## How hard an engine is punished for pushing across the command as well as
## along it. Zero would accept any engine with a positive projection.
var side_penalty: float = 0.5

## Minimum normalised weight for an engine to join a group at all.
var weight_threshold: float = 0.05

## command -> Array of { "engine": EngineInstance, "weight": float }.
var groups: Dictionary = {}

## command -> total contribution along the command axis at full throttle, in
## native units: force for the linear commands, torque for the rotational ones.
## Braking divides by this, so it has to be a real force, not a score.
var max_authority: Dictionary = {}


## Recomputes every group from the current geometry.
##
## `engines` must already be paired with their mounts; `centre_of_mass`,
## `mass` and `inertia` are the ship's, after the modules have been counted in.
func rebuild(
	engines: Array[EngineInstance], centre_of_mass: Vector2, mass: float, inertia: float
) -> void:
	groups.clear()
	max_authority.clear()

	var gyration: float = sqrt(maxf(inertia, 0.0001) / maxf(mass, 0.0001))

	var contributions: Array[Vector3] = []
	var torques: PackedFloat32Array = PackedFloat32Array()
	var forces: Array[Vector2] = []
	for engine: EngineInstance in engines:
		var force: Vector2 = engine.nominal_force()
		var arm: Vector2 = engine.mount.position - centre_of_mass
		var torque: float = arm.cross(force)
		forces.append(force)
		torques.append(torque)
		contributions.append(
			Vector3(force.x / mass, force.y / mass, (torque / inertia) * gyration)
		)

	for command: Command in COMMAND_AXES:
		var axis: Vector3 = COMMAND_AXES[command]
		var members: Array = []
		var best: float = 0.0

		for i: int in range(engines.size()):
			var contribution: Vector3 = contributions[i]
			var along: float = contribution.dot(axis)
			if along <= 0.0:
				continue
			var sideways: float = (contribution - axis * along).length()
			var weight: float = along - side_penalty * sideways
			if weight <= 0.0:
				continue
			members.append({"engine": engines[i], "weight": weight, "index": i})
			best = maxf(best, weight)

		var kept: Array = []
		var authority: float = 0.0
		for member: Dictionary in members:
			var normalised: float = member["weight"] / best
			if normalised < weight_threshold:
				continue
			kept.append({"engine": member["engine"], "weight": normalised})
			var index: int = member["index"]
			# Authority in native units, scaled by the weight the engine will
			# actually be run at when the command is held at 1.
			if command == Command.CW or command == Command.CCW:
				authority += absf(torques[index]) * normalised
			else:
				var axis_2d: Vector2 = Vector2(axis.x, axis.y)
				authority += forces[index].dot(axis_2d) * normalised

		groups[command] = kept
		max_authority[command] = authority


## Sets every engine's target throttle from a set of command values.
##
## An engine in several groups sums its shares, which is what lets a bow
## thruster serve both a strafe and a turn at once.
func apply_commands(engines: Array[EngineInstance], commands: Dictionary) -> void:
	for engine: EngineInstance in engines:
		engine.target_throttle = 0.0

	for command: Command in commands:
		var amount: float = commands[command]
		if amount <= 0.0 or not groups.has(command):
			continue
		for member: Dictionary in groups[command]:
			var engine: EngineInstance = member["engine"]
			engine.target_throttle += amount * float(member["weight"])

	for engine: EngineInstance in engines:
		engine.target_throttle = clampf(engine.target_throttle, 0.0, 1.0)


func authority_of(command: Command) -> float:
	return float(max_authority.get(command, 0.0))


func has_authority(command: Command) -> bool:
	return authority_of(command) > 0.0


func command_name(command: Command) -> String:
	return Command.keys()[int(command)]


## One line per group plus a warning for each empty one, printed after a
## rebuild. A ship that cannot turn one way is a configuration bug, and it
## should be obvious at startup rather than in flight.
func describe() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for command: Command in COMMAND_AXES:
		var members: Array = groups.get(command, [])
		if members.is_empty():
			lines.append("WARN: no %s authority" % command_name(command))
			continue
		var parts: PackedStringArray = PackedStringArray()
		for member: Dictionary in members:
			var engine: EngineInstance = member["engine"]
			parts.append("%s %.2f" % [engine.mount.name, member["weight"]])
		lines.append(
			"%-13s authority %8.1f  [%s]"
			% [command_name(command), authority_of(command), ", ".join(parts)]
		)
	return lines
