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

## One Vector3 per engine: the acceleration it delivers at full power, in the
## same space the commands live in. Kept from the rebuild so the allocator
## does not have to work them out again every tick.
var columns: Array[Vector3] = []

## Whether to allocate by bounded least squares rather than by the weights.
## Set from the fitted flight computer; false is the built-in behaviour.
var solve_allocation: bool = false

## command -> total contribution along the command axis at full throttle, in
## native units: force for the linear commands, torque for the rotational ones.
## Braking divides by this, so it has to be a real force, not a score.
var max_authority: Dictionary = {}

## Gimballed engines that form a couple, as engine -> engine.
##
## Two nozzles whose thrusts oppose and whose arms oppose. Deflect such a
## pair **the same way** and the side forces cancel while the torques add,
## which is the turn the ship already knew how to do. Deflect them
## **opposite ways** and the torques cancel while the side forces add,
## which is a strafe -- and two nozzles are then the whole ship.
##
## Why a pair and not any gimbal: one nozzle swung sideways shoves the
## ship along its own thrust just as hard as before, so a lone gimballed
## main drive asked to strafe mostly flies forward. The preset built to
## show that is called "gimbal pojedynczy (dryfuje)" and it is right to.
## Only a partner cancels the shove, so only a partner earns the group.
var gimbal_partner: Dictionary = {}

## How closely two nozzles have to oppose to count as a couple. Dot
## products, so 0.95 is about eighteen degrees of slop in each of thrust
## and arm -- loose enough for a hull nobody measured with a protractor,
## tight enough that two jets at right angles are not a pair.
const COUPLE_ALIGNMENT: float = -0.95

## And how closely matched in size. A big nozzle opposite a small one does
## not cancel; it mostly wins.
const COUPLE_BALANCE: float = 0.25


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

	columns.clear()
	var contributions: Array[Vector3] = []
	var torques: PackedFloat32Array = PackedFloat32Array()
	var forces: Array[Vector2] = []
	# What a nozzle hard over adds, on top of what it makes pointing
	# straight. For a main drive on the centreline that is the whole of its
	# torque: the arm is parallel to the thrust, so the cross product is
	# nothing until the nozzle swings.
	#
	# Kept apart from the contribution instead of folded into it, because a
	# gimbal swings **both ways**: one engine serves CW and CCW, and a
	# single contribution vector can only point one way. Which way it goes
	# is decided per command, below.
	var swing: PackedFloat32Array = PackedFloat32Array()
	# And what it adds sideways, which is the same deflection seen as a
	# force rather than as a torque. Only useful to a nozzle with a partner
	# -- see `gimbal_partner`.
	var slip: Array[Vector2] = []
	var arms: Array[Vector2] = []
	for engine: EngineInstance in engines:
		var force: Vector2 = engine.nominal_force()
		var arm: Vector2 = engine.mount.position - centre_of_mass
		var torque: float = arm.cross(force)
		forces.append(force)
		arms.append(arm)
		torques.append(torque)
		var reach: float = engine.data.gimbal_range if engine.data != null else 0.0
		swing.append(
			0.0 if reach <= 0.0 else absf(arm.cross(force.rotated(reach)) - torque)
		)
		slip.append(Vector2.ZERO if reach <= 0.0 else force.rotated(reach) - force)
		contributions.append(
			Vector3(force.x / mass, force.y / mass, (torque / inertia) * gyration)
		)
		# The same vector, kept for the allocator. Nominal here as well: what
		# an engine can still manage is read at solve time, because condition
		# changes between rebuilds and the groups deliberately do not.
		columns.append(contributions[contributions.size() - 1])

	_engine_order.clear()
	for i: int in range(engines.size()):
		_engine_order[engines[i]] = i
	_find_couples(engines, forces, arms, swing)

	for command: Command in COMMAND_AXES:
		var axis: Vector3 = COMMAND_AXES[command]
		var members: Array = []
		var best: float = 0.0

		var turning: bool = command == Command.CW or command == Command.CCW
		var strafing: bool = (
			command == Command.STRAFE_LEFT or command == Command.STRAFE_RIGHT
		)
		var axis_flat: Vector2 = Vector2(axis.x, axis.y)
		for i: int in range(engines.size()):
			var contribution: Vector3 = contributions[i]
			if strafing and gimbal_partner.has(engines[i]):
				# A couple, so the partner cancels this nozzle's own thrust
				# and the torque its deflection makes. What is left is the
				# side force alone, which is already exactly on the axis --
				# hence a contribution of nothing else, and no penalty to
				# charge it for being off one.
				contribution = axis * (absf(slip[i].dot(axis_flat)) / mass)
			if turning and swing[i] > 0.0:
				# The nozzle will be swung the way that helps, so the torque
				# it can bring to this command is always the full swing in
				# the command's own direction.
				contribution.z += signf(axis.z) * (swing[i] / inertia) * gyration
			var along: float = contribution.dot(axis)
			if along <= 0.0:
				continue
			var sideways: float = (contribution - axis * along).length()
			# A gimballed engine turning the ship also shoves it forward
			# hard, and the side penalty rejected it for exactly that --
			# which left a ship whose only steering is a gimbal unable to
			# steer at all. The shove is not evidence that this is the
			# wrong tool; it is the known price of the tool. The relative
			# threshold below still drops it when real torque jets are
			# bolted on, because theirs is an order of magnitude better.
			var weight: float = along
			if not (turning and swing[i] > 0.0) and not (
				strafing and gimbal_partner.has(engines[i])
			):
				weight -= side_penalty * sideways
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
			if turning:
				authority += (absf(torques[index]) + swing[index]) * normalised
			elif strafing and gimbal_partner.has(member["engine"]):
				# The deflection, not the thrust: the thrust is what the
				# partner is busy cancelling.
				authority += absf(slip[index].dot(axis_flat)) * normalised
			else:
				authority += forces[index].dot(axis_flat) * normalised

		groups[command] = kept
		max_authority[command] = authority


## Finds the gimballed nozzles that oppose each other, and records them.
##
## O(n squared) over the gimballed engines only, which on any hull anyone
## would fly is two. Done at rebuild, because a couple is a fact about the
## geometry and the geometry only changes on a refit.
func _find_couples(
	engines: Array[EngineInstance],
	forces: Array[Vector2],
	arms: Array[Vector2],
	swing: PackedFloat32Array,
) -> void:
	gimbal_partner.clear()
	for i: int in range(engines.size()):
		if swing[i] <= 0.0:
			continue
		for j: int in range(engines.size()):
			if i == j or swing[j] <= 0.0:
				continue
			if not _opposes(forces[i], forces[j]):
				continue
			if not _opposes(arms[i], arms[j]):
				continue
			gimbal_partner[engines[i]] = engines[j]
			break


## Whether two vectors point opposite ways and are about the same length.
func _opposes(a: Vector2, b: Vector2) -> bool:
	if a.is_zero_approx() or b.is_zero_approx():
		return false
	if a.normalized().dot(b.normalized()) > COUPLE_ALIGNMENT:
		return false
	var longest: float = maxf(a.length(), b.length())
	return absf(a.length() - b.length()) / longest <= COUPLE_BALANCE


## Sets every engine's target throttle from a set of command values.
##
## An engine in several groups sums its shares, which is what lets a bow
## thruster serve both a strafe and a turn at once.
func apply_commands(engines: Array[EngineInstance], commands: Dictionary) -> void:
	for engine: EngineInstance in engines:
		engine.target_throttle = 0.0

	if solve_allocation:
		_allocate(engines, commands)
		return

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


## Allocates by bounded least squares against what the engines can actually
## deliver right now.
##
## The demand is the same axes the groups use, so a pilot pressing FORWARD
## and CW asks for the sum of those two directions. Scaled by the authority
## the heuristic would have found, so a full command still means full thrust
## rather than one unit of an abstract axis.
func _allocate(engines: Array[EngineInstance], commands: Dictionary) -> void:
	var demand: Vector3 = Vector3.ZERO
	for command: Command in commands:
		var amount: float = commands[command]
		if amount <= 0.0:
			continue
		demand += (COMMAND_AXES[command] as Vector3) * amount * _axis_scale(command)
	if demand.length_squared() <= 0.0:
		return

	# Condition folded in here and not at rebuild: a damaged engine must be
	# asked for less, which is the entire reason to run this instead of the
	# weights.
	var live: Array[Vector3] = []
	for i: int in range(engines.size()):
		live.append(columns[i] * engines[i].condition_factor())

	var throttles: PackedFloat32Array = ThrustAllocator.solve(live, demand)
	for i: int in range(engines.size()):
		engines[i].target_throttle = throttles[i]


## How much acceleration one unit of a command is worth, so the allocator is
## aiming at the same magnitude the weights would have produced.
func _axis_scale(command: Command) -> float:
	var best: float = 0.0
	for member: Dictionary in groups.get(command, []):
		var contribution: Vector3 = columns[_index_of(member["engine"])]
		best = maxf(best, absf(contribution.dot(COMMAND_AXES[command] as Vector3)))
	return best


func _index_of(engine: EngineInstance) -> int:
	return _engine_order.get(engine, 0)


## engine -> its column index, filled at rebuild so the lookup above is not a
## linear scan every tick.
var _engine_order: Dictionary = {}
