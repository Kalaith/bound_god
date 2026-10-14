extends RefCounted
## Cultivation effects, applied at the end of the tick: stepping into a new
## realm (and, for the first under the tree, comprehending its technique),
## a technique passed from teacher to student, and a sect founded.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const FruitChoice = preload("res://scripts/agents/fruit_choice.gd")
const TreeAbilities = preload("res://scripts/sim/tree_abilities.gd")


## Returns true when the action was a cultivation effect.
static func apply(sim: RefCounted, agent: RefCounted, action: Dictionary) -> bool:
	match str(action.type):
		"advance_realm":
			_advance(sim, agent, float(action.qi))
		"teach":
			_teach(sim, agent, int(action.to), str(action.technique))
		"announce_trial":
			agent.step_result = {"trial": sim.tribulations.announce(sim, agent, action.site)}
		"pick_fruit":
			_pick_fruit(sim, agent, int(action.get("for", agent.id)))
		"hand_fruit":
			_hand_fruit(sim, agent, int(action.to))
		"found_sect":
			var id: int = sim.sects.found(sim, agent)
			agent.step_result = {"sect": id}
		_:
			return false
	return true


## The threshold is crossed: a new realm, a foundation as sound as the qi
## it was laid in, and a longer life.
static func _advance(sim: RefCounted, agent: RefCounted, qi: float) -> void:
	var cultivation: Dictionary = agent.cultivation
	if not CultivationState.at_peak(cultivation) or int(cultivation.realm) + 1 >= Data.realms().size():
		agent.step_result = {"advanced": 0}
		return
	cultivation.realm = int(cultivation.realm) + 1
	cultivation.progress = 0.0
	var affinity: Dictionary = Data.affinity(str(cultivation.affinity))
	cultivation.foundation = clampf(Balance.number("cultivation.start_foundation") + Balance.number("cultivation.qi_foundation") * (qi - 0.5)
		+ float(affinity.get("foundation_bonus", 0.0)), 0.1, 1.0)
	agent.step_result = {"advanced": 1}
	Mind.add(agent, "advanced_realm", sim.calendar.ticks_per_day)
	var realm: String = "realm_" + str(Data.realm(int(cultivation.realm)).id)
	sim.chronicle_event("realm_reached", agent.settlement_id, {"name": agent.full_name(), "realm": realm}, "cause_qi_progress", [agent.id])
	_comprehend(sim, agent, qi)


## The tree's first gift: whoever first reaches Qi Refining in its densest
## qi, while nobody living knows the tree's technique, comprehends it.
static func _comprehend(sim: RefCounted, agent: RefCounted, qi: float) -> void:
	if qi < Balance.number("cultivation.comprehend_qi"):
		return
	for technique in Data.cultivation().techniques:
		if str(technique.source) != "tree" or agent.cultivation.techniques.has(technique.id):
			continue
		var known: bool = false
		for other in sim.agents:
			known = known or (other.is_present() and other.cultivation.get("techniques", []).has(technique.id))
		if known:
			continue
		agent.cultivation.techniques.append(technique.id)
		sim.chronicle_event("technique_comprehended", agent.settlement_id, {"name": agent.full_name(), "technique": "technique_" + str(technique.id)},
			"cause_qi_insight", [agent.id])
		return


static func _teach(sim: RefCounted, teacher: RefCounted, id: int, technique: String) -> void:
	var student: RefCounted = sim.agents[id]
	if not student.is_present() or student.cultivation.techniques.has(technique) or not teacher.cultivation.techniques.has(technique):
		teacher.step_result = {"taught": 0}
		return
	student.cultivation.techniques.append(technique)
	student.cultivation.teacher = teacher.id
	student.cultivation.progress = minf(float(student.cultivation.progress) + Balance.number("cultivation.teach_progress"), CultivationState.needed(student.cultivation))
	if not teacher.cultivation.students.has(id):
		teacher.cultivation.students.append(id)
	teacher.step_result = {"taught": 1}
	student.step_result = {"learned": 1}
	teacher.help_task = {}
	Mind.add(student, "learned_technique", sim.calendar.ticks_per_day, teacher.id)
	Mind.add(teacher, "taught_student", sim.calendar.ticks_per_day, id)
	sim.chronicle_event("taught", teacher.settlement_id, {"teacher": teacher.full_name(), "student": student.full_name(), "technique": "technique_" + technique},
		"cause_asked_to_learn|%s" % student.given_name, [teacher.id, id])
	if sim.sects != null:
		sim.sects.on_taught(sim, teacher, student)
	# The Way taught beneath the tree teaches the tree too.
	if sim.tree_growth != null and sim.tree_growth.in_shade(sim, teacher.cell, teacher.settlement_id):
		sim.tree_growth.lesson(sim, "teaching", teacher.full_name(), [teacher.id, id])


## A fruit from the tree: kept for the picker's own trial, or carried for the
## one their master chose (the choice and its reason go in the chronicle).
static func _pick_fruit(sim: RefCounted, agent: RefCounted, recipient: int) -> void:
	if sim.tree_growth == null or not sim.tree_growth.pick(sim):
		agent.step_result = {"picked": 0}
		return
	agent.step_result = {"picked": 1}
	var sect: Dictionary = sim.sects.in_settlement(agent.settlement_id)
	var choice: Array = FruitChoice.choose(sim, sect, agent) if not sect.is_empty() else [recipient, "cause_fruit_readiest"]
	var reason: String = str(choice[1]) if int(choice[0]) == recipient else "cause_fruit_readiest"
	if recipient == agent.id:
		agent.cultivation.fruit = true
		if sect.is_empty():
			sim.chronicle_event("fruit_taken", agent.settlement_id, {"name": agent.full_name()}, "cause_no_sect", [agent.id])
		else:
			sim.chronicle_event("fruit_kept", agent.settlement_id, {"name": agent.full_name()}, "%s|%s" % [reason, agent.given_name], [agent.id])
		return
	agent.carrying = {"resource": "spirit_fruit", "amount": 1.0}
	var other: RefCounted = sim.agents[recipient]
	sim.chronicle_event("fruit_given", agent.settlement_id, {"giver": agent.full_name(), "name": other.full_name()},
		"%s|%s" % [reason, agent.given_name], [agent.id, recipient])


static func _hand_fruit(sim: RefCounted, agent: RefCounted, recipient: int) -> void:
	var other: RefCounted = sim.agents[recipient]
	if not other.is_present():
		sim.tree_growth.fruit += 1
		return
	TreeAbilities.receive(sim, other, agent)
	Mind.add(other, "given_fruit", sim.calendar.ticks_per_day, agent.id)
