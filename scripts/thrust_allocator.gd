class_name ThrustAllocator
extends RefCounted
## Works out what each engine should be doing, given what the pilot asked the
## ship as a whole to do.
##
## The heuristic it replaces sorts engines into groups by how cleanly each one
## pushes along a command, and that is a good answer for a symmetric ship in
## good repair. It is a poor one otherwise: the groups are built from nominal
## thrust and fixed weights, so a half-dead jet still gets its full share of
## the demand, delivers less than its partner, and the ship turns while
## sliding sideways. The pilot has to fly against it.
##
## This asks the real question instead. Each engine contributes a known
## acceleration; find the throttles that come closest to the acceleration
## wanted, given that a throttle is between nothing and everything. In
## symbols: minimise |A t - b| with t in [0, 1], which is bounded least
## squares -- non-negative because an engine cannot suck (IDEAS.md section 3).
##
## Projected gradient rather than Lawson-Hanson: with a handful of engines it
## converges in a fixed, small number of passes, every pass is the same
## arithmetic, and there is no active set to go wrong. A fixed cost per tick
## matters more here than the last decimal place of optimality.

## Passes per solve. Twenty is comfortably past the point where the answer
## stops moving on eight engines; the cost is eight multiply-adds a pass.
const ITERATIONS: int = 20

## Below this the demand is nothing worth spending fuel on.
const DEMAND_EPS: float = 0.0001


## Throttles for `columns`, each a Vector3 of the acceleration one engine
## delivers at full power, against the wanted acceleration `target`.
##
## Static and free of ship state: everything it needs is in the arguments,
## which is what lets the comparison against the heuristic be measured rather
## than argued about.
static func solve(columns: Array[Vector3], target: Vector3) -> PackedFloat32Array:
	var throttles: PackedFloat32Array = PackedFloat32Array()
	throttles.resize(columns.size())
	if columns.is_empty() or target.length_squared() < DEMAND_EPS:
		return throttles

	# Step size from the Lipschitz constant of the gradient. Bounded by the
	# largest eigenvalue of A^T A, and its trace is an easy upper bound on
	# that -- loose, which only means the steps are conservative.
	var trace: float = 0.0
	for column: Vector3 in columns:
		trace += column.length_squared()
	if trace <= 0.0:
		return throttles
	var step: float = 1.0 / trace

	for pass_index: int in range(ITERATIONS):
		# Where the ship is actually going with the current throttles.
		var made: Vector3 = Vector3.ZERO
		for i: int in range(columns.size()):
			made += columns[i] * throttles[i]
		var error: Vector3 = made - target

		for i: int in range(columns.size()):
			# d/dt |A t - b|^2 for one engine, halved -- the factor is
			# absorbed into the step.
			throttles[i] = clampf(throttles[i] - step * columns[i].dot(error), 0.0, 1.0)

	return throttles


## The acceleration `throttles` actually produce, for checking the answer.
static func produced(columns: Array[Vector3], throttles: PackedFloat32Array) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	for i: int in range(mini(columns.size(), throttles.size())):
		total += columns[i] * throttles[i]
	return total
