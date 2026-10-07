class_name Damage
extends RefCounted
## Who can be hurt, asked in one place.
##
## Three things in this game deal damage -- a round on contact, the
## blast around it, and a beam's ray -- and all three used to ask the
## same wrong question: `collider as Ship`. Wrong because what every
## one of them means is "can this be hurt", and the answer stopped
## being "it is the player's hull" the moment anything else could be
## shot at.
##
## **Duck-typed rather than a list of classes, deliberately.** A `Foe`
## and a `Ship` share nothing but this: one is a rigid body with a
## fitout, a tank and a control solver, the other is a light node with
## a number on it. Giving them a common base class would be inventing a
## relationship to satisfy a cast. The day a station, a crate or a
## carrier's hangar becomes shootable, it needs the method and nothing
## else -- no new branch here, and no third place that forgot to add
## one.

## Hurts it, if it can be hurt. Returns whether anything happened, so a
## caller that has to decide between "the round stops here" and "the
## round carries on" has an answer.
static func deal(what: Object, amount: float, cause: String = "") -> bool:
	if not can_be_hurt(what):
		return false
	what.call("take_damage", amount, cause)
	return true


static func can_be_hurt(what: Object) -> bool:
	return (
		what != null
		and is_instance_valid(what)
		and what.has_method("take_damage")
	)
