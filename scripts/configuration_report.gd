class_name ConfigurationReport
extends RefCounted
## What a ship can do once the modules on it have been counted up, and what is
## wrong with the result.
##
## Fitting a module changes the mass, the centre of mass and every control
## group at once, and the interesting failures are not "it got worse" but "it
## is now crooked": a rotation that shoves the ship sideways, a strafe that is
## stronger one way than the other, a direction with nothing behind it at all.
## Those stay invisible until the pilot is already fighting them.
##
## Written after breaking exactly that while tuning engine bulk: the centre of
## mass moved 0.8 px, the torque pair went to weights 1.00 and 0.82, and every
## turn left a sideways push. A test caught it because one existed; a pilot
## swapping engines has no test.
##
## That case is one this report deliberately stays quiet about. 0.046 N on
## 13.9 kg is 0.003 px/s^2, three hundred times under the warning threshold.
## The test guards a design invariant and is right to demand zero, because an
## asymmetry nobody feels today grows with the next module fitted. The report
## tells a pilot what they will feel, and printing a drift a thousand times
## weaker than the air would only teach them to ignore it. Two jobs, two
## thresholds.
##
## A snapshot rather than a view: it keeps the numbers it was built from, so a
## report taken before a swap can still be compared with one taken after.

enum Severity { OK, WARN, FAULT }

## Unwanted sideways acceleration from a rotation command, in px/s^2, at which
## the report starts complaining. Worth comparing against surface gravity,
## about 30 px/s^2 on the test planet: a whole turn at 1 px/s^2 is a nudge you
## could blame on the air, 5 is a drift you have to fly against.
const WARN_DRIFT: float = 1.0
const FAULT_DRIFT: float = 5.0

## How lopsided a mirrored pair of commands may be, weaker over stronger,
## before it is worth saying.
const WARN_BALANCE: float = 0.8
const FAULT_BALANCE: float = 0.5

## Mirrored pairs. Only mirrored ones: a ship with a big main drive and a
## small retro is normal rather than broken, so FORWARD and BACK are never
## measured against each other. Listing a pair in one order only, or the same
## fault would be reported twice.
const MIRRORS: Array[Array] = [
	[ShipControl.Command.STRAFE_LEFT, ShipControl.Command.STRAFE_RIGHT],
	[ShipControl.Command.CCW, ShipControl.Command.CW],
]

## Relative authority change below this is not worth reporting after a swap.
const NOTABLE_CHANGE: float = 0.05

var mass: float = 0.0
var centre: Vector2 = Vector2.ZERO
var inertia: float = 0.0

## command -> authority in native units (force for the linear commands, torque
## for the rotational ones), and -> the engines behind it as "name weight".
var authority: Dictionary = {}
var members: Dictionary = {}

## command -> leftover force the group applies to the hull, in newtons. A
## rotation group is meant to be a couple: equal and opposite forces whose
## torques add and whose forces cancel. Whatever fails to cancel is a shove.
var residual: Dictionary = {}

## { "severity": Severity, "text": String }, worst first.
var findings: Array[Dictionary] = []


static func of(ship: Ship) -> ConfigurationReport:
	var report: ConfigurationReport = ConfigurationReport.new()
	if ship == null or ship.control == null:
		return report
	report.mass = ship.mass
	report.centre = ship.center_of_mass
	report.inertia = ship.inertia

	for command: ShipControl.Command in ShipControl.COMMAND_AXES:
		var group: Array = ship.control.groups.get(command, [])
		report.authority[command] = ship.control.authority_of(command)

		var names: PackedStringArray = PackedStringArray()
		var leftover: Vector2 = Vector2.ZERO
		for member: Dictionary in group:
			var engine: EngineInstance = member["engine"]
			var weight: float = member["weight"]
			names.append("%s %.2f" % [engine.mount.name, weight])
			leftover += engine.nominal_force() * weight
		report.members[command] = names
		report.residual[command] = leftover.length()

	report._find_faults()
	return report


func worst() -> Severity:
	var level: int = int(Severity.OK)
	for finding: Dictionary in findings:
		level = maxi(level, int(finding["severity"]))
	return level as Severity


## The console form, printed after every rebuild.
func lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append("mass %.1f, com (%.2f, %.2f), inertia %.0f" % [
		mass, centre.x, centre.y, inertia,
	])
	for command: ShipControl.Command in ShipControl.COMMAND_AXES:
		var names: PackedStringArray = members.get(command, PackedStringArray())
		if names.is_empty():
			continue
		out.append("%-13s authority %8.1f  [%s]" % [
			_name(command), float(authority[command]), ", ".join(names),
		])
	for finding: Dictionary in findings:
		out.append("%s: %s" % [Severity.keys()[int(finding["severity"])], finding["text"]])
	return out


## What a swap actually did, written for the pilot rather than for the log:
## the directions whose authority moved, and any fault the new module brought
## with it.
##
## Differences only. A module that changes nothing worth naming produces no
## lines at all, and the screen says that rather than inventing reassurance.
func compare(before: ConfigurationReport) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if before == null:
		return out

	for command: ShipControl.Command in ShipControl.COMMAND_AXES:
		var was: float = float(before.authority.get(command, 0.0))
		var now: float = float(authority.get(command, 0.0))
		if was <= 0.0 and now <= 0.0:
			continue
		if was <= 0.0:
			out.append("+%s %.0f" % [_name(command), now])
			continue
		if now <= 0.0:
			out.append("LOST %s" % _name(command))
			continue
		var change: float = now / was - 1.0
		if absf(change) >= NOTABLE_CHANGE:
			out.append("%s %.0f -> %.0f (%+.0f%%)" % [_name(command), was, now, change * 100.0])

	# Only faults the old configuration did not already have. Repeating an old
	# one here would blame the wrong part.
	var known: Array[String] = []
	for finding: Dictionary in before.findings:
		known.append(finding["text"])
	for finding: Dictionary in findings:
		if not known.has(finding["text"]):
			out.append("%s: %s" % [Severity.keys()[int(finding["severity"])], finding["text"]])
	return out


func _find_faults() -> void:
	for command: ShipControl.Command in ShipControl.COMMAND_AXES:
		if (members.get(command, PackedStringArray()) as PackedStringArray).is_empty():
			_add(Severity.FAULT, "no %s authority at all" % _name(command))

	# A rotation group that fails to cancel its own forces turns and shoves at
	# the same time. Reported as the acceleration it causes rather than as
	# newtons: that is the part the pilot feels, and it stays comparable
	# across ships of different mass.
	for command: ShipControl.Command in [ShipControl.Command.CCW, ShipControl.Command.CW]:
		var drift: float = float(residual.get(command, 0.0)) / maxf(mass, 0.0001)
		if drift >= WARN_DRIFT:
			_add(
				Severity.FAULT if drift >= FAULT_DRIFT else Severity.WARN,
				"%s pushes the ship sideways at %.1f px/s2" % [_name(command), drift],
			)

	for pair: Array in MIRRORS:
		var first: float = float(authority.get(pair[0], 0.0))
		var second: float = float(authority.get(pair[1], 0.0))
		var stronger: float = maxf(first, second)
		if stronger <= 0.0:
			continue
		var ratio: float = minf(first, second) / stronger
		if ratio >= WARN_BALANCE:
			continue
		var weak: ShipControl.Command = pair[0] if first < second else pair[1]
		var strong: ShipControl.Command = pair[1] if first < second else pair[0]
		_add(
			Severity.FAULT if ratio < FAULT_BALANCE else Severity.WARN,
			"%s is only %.0f%% of %s" % [_name(weak), ratio * 100.0, _name(strong)],
		)

	findings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["severity"]) > int(b["severity"])
	)


func _add(severity: Severity, text: String) -> void:
	findings.append({"severity": severity, "text": text})


func _name(command: ShipControl.Command) -> String:
	return ShipControl.Command.keys()[int(command)]
