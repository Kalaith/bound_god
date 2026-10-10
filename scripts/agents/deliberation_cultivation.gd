extends RefCounted
## Cultivation candidates: sitting in the tree's qi, asking a teacher for a
## technique, teaching someone who asked, and founding a sect once a teacher
## has students of their own. All compete in the ordinary utility contest,
## so a sect that only meditates goes hungry.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")

const Kind = Goals.Kind
const Need = Personality.Need
const NONE := Vector3i(-1, -1, -1)


static func _candidate(kind: int, utility: float, reason: String, target: int = -1, value: float = NAN) -> Dictionary:
	return {"goal": Goals.make(kind, target), "utility": utility, "reason": reason, "value": value}


static func add(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if agent.is_child or agent.cultivation.is_empty() or sim.qi == null:
		return
	_cultivate(sim, agent, out)
	_learn(sim, agent, out)
	_teach(sim, agent, out)
	_found_sect(sim, agent, out)


## The densest spot round the tree this person can sit in that nobody else
## is sitting in: their own place on the ring, or one of a few others.
static func spot(sim: RefCounted, agent: RefCounted) -> Vector3i:
	var tree: Vector3i = sim.features.get("sacred_tree", NONE)
	if tree.x < 0:
		return NONE
	var center := Vector3(tree.x + 1.0, tree.y, tree.z + 1.0)
	var best: Vector3i = NONE
	var best_qi: float = -1.0
	for k in range(4):
		var cell: Vector3i = H.ring_cell(sim, center, agent.id + k * 97, Balance.number("cultivation.spot_inner"), Balance.number("cultivation.spot_outer"))
		if cell.x < 0 or _taken(sim, agent, cell):
			continue
		var qi: float = sim.qi.density(sim, cell)
		if qi > best_qi:
			best = cell
			best_qi = qi
	return best


static func _taken(sim: RefCounted, agent: RefCounted, cell: Vector3i) -> bool:
	var other: int = int(sim.occupied.get(cell, -1))
	return other >= 0 and other != agent.id and sim.agents[other].activity == "cultivating"


static func _cultivate(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	var cultivation: Dictionary = agent.cultivation
	var realm: int = int(cultivation.realm)
	var drive: float = float(cultivation.drive)
	if drive < 0.05 and realm == 0:
		return
	var cell: Vector3i = spot(sim, agent)
	if cell.x < 0:
		return
	var qi: float = sim.qi.density(sim, cell)
	var utility: float = (Balance.number("cultivation.utility_base") + Balance.number("cultivation.utility_drive") * drive) \
		* (0.4 + 0.6 * qi) * (1.0 + Balance.number("cultivation.realm_bonus") * realm) * agent.capacity()
	# A long walk to the tree weighs against it.
	utility *= clampf(1.2 - H.distance(cell, agent.cell) / 60.0, 0.2, 1.0)
	if agent.need(Need.FOOD) < 40.0 or agent.need(Need.REST) < 30.0:
		utility *= 0.5
	if CultivationState.at_peak(cultivation) and realm >= 1:
		utility *= 0.3
	var hour: float = sim.calendar.hour()
	if absf(hour - Balance.number("time.dawn_hour")) < 1.0 or absf(hour - Balance.number("time.dusk_hour")) < 1.0:
		utility += Balance.number("cultivation.dawn_dusk_bonus") * drive
	if Schedule.is_sleep_time(sim, agent):
		utility *= 0.3
	out.append(_candidate(Kind.CULTIVATE, utility, "reason_cultivate", -1, qi * 100.0))


## Someone in the same place who knows a technique this person lacks.
static func teacher_for(sim: RefCounted, agent: RefCounted) -> int:
	var best: int = -1
	var best_distance: float = INF
	var window: int = Balance.integer("agents.failure_memory_ticks")
	for other in sim.agents:
		if other.id == agent.id or not other.is_present() or other.is_child or other.cultivation.is_empty():
			continue
		if not CultivationState.is_cultivator(other.cultivation) or other.settlement_id != agent.settlement_id:
			continue
		if lacking(agent, other).is_empty() or agent.beliefs.opinion_of(other.id) < -10.0:
			continue
		if agent.beliefs.recently_failed("teacher:%d" % other.id, sim.calendar.tick, window):
			continue
		var d: float = H.distance(other.cell, agent.cell)
		if d < best_distance:
			best = other.id
			best_distance = d
	return best


## Techniques `teacher` knows and `student` does not.
static func lacking(student: RefCounted, teacher: RefCounted) -> Array:
	var result: Array = []
	for id in teacher.cultivation.techniques:
		if not student.cultivation.techniques.has(id):
			result.append(id)
	return result


static func _learn(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	var drive: float = float(agent.cultivation.drive)
	if drive < 0.3 and not CultivationState.is_cultivator(agent.cultivation):
		return
	if Schedule.is_sleep_time(sim, agent):
		return
	var teacher: int = teacher_for(sim, agent)
	if teacher < 0:
		return
	var utility: float = (Balance.number("cultivation.learn_base") + Balance.number("cultivation.learn_drive") * drive) * agent.capacity()
	out.append(_candidate(Kind.LEARN, utility, "reason_learn", teacher))


static func _teach(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if agent.help_task.is_empty() or int(agent.help_task.need) != Goals.HelpNeed.TEACHING:
		return
	var student: int = int(agent.help_task.requester)
	if not sim.agents[student].is_present() or lacking(sim.agents[student], agent).is_empty():
		agent.help_task = {}
		return
	var utility: float = Balance.number("cultivation.teach_utility") * (0.8 + 0.4 * maxf(agent.personality.kindness, 0.0))
	out.append(_candidate(Kind.TEACH, utility, "reason_teach", student))


## Present students this person taught who live in their settlement.
static func students_here(sim: RefCounted, agent: RefCounted) -> Array:
	var result: Array = []
	for id in agent.cultivation.students:
		var student: RefCounted = sim.agents[id]
		if student.is_present() and student.settlement_id == agent.settlement_id:
			result.append(id)
	return result


static func _found_sect(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if sim.sects == null or int(agent.cultivation.sect_id) >= 0 or not CultivationState.is_cultivator(agent.cultivation):
		return
	if students_here(sim, agent).size() < Balance.integer("cultivation.sect_students"):
		return
	if not sim.sects.can_found_in(sim, agent.settlement_id):
		return
	var utility: float = Balance.number("cultivation.found_sect_base") + 0.3 * maxf(agent.personality.leadership, 0.0) + 0.2 * float(agent.cultivation.drive)
	out.append(_candidate(Kind.FOUND_SECT, utility, "reason_found_sect"))
