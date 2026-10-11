extends RefCounted
## Cultivation candidates: sitting in the tree's qi, asking a teacher for a
## technique, teaching someone who asked, and founding a sect once a teacher
## has students of their own. All compete in the ordinary utility contest,
## so a sect that only meditates goes hungry.
const DeliberationCrafts = preload("res://scripts/agents/deliberation_crafts.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const FruitChoice = preload("res://scripts/agents/fruit_choice.gd")
const SectPlaces = preload("res://scripts/sim/sect_places.gd")
const SectHalls = preload("res://scripts/sim/sect_halls.gd")
const Elixirs = preload("res://scripts/sim/elixirs.gd")
const Branches = preload("res://scripts/sim/branches.gd")
const Guests = preload("res://scripts/sim/guests.gd")

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
	_branch(sim, agent, out)
	_receive_guest(sim, agent, out)
	_breakthrough(sim, agent, out)
	_witness(sim, agent, out)
	_share_fruit(sim, agent, out)
	_convalesce(sim, agent, out)
	var refine: Dictionary = DeliberationCrafts.refine(sim, agent)
	if not refine.is_empty():
		var candidate: Dictionary = _candidate(Kind.REFINE, float(refine.utility), "reason_refine", int(refine.room))
		candidate.goal = Goals.make(Kind.REFINE, int(refine.room), int(refine.seat))
		out.append(candidate)
	_medicate(sim, agent, out)


## The densest spot round the tree this person can sit in that nobody else
## is sitting in: their own place on the ring, one of a few others, or a
## free mat in their settlement's meditation hall (its qi counted with the
## hall's help).
static func spot(sim: RefCounted, agent: RefCounted) -> Vector3i:
	var tree: Vector3i = sim.features.get("sacred_tree", NONE)
	if tree.x < 0:
		return NONE
	var center := Vector3(tree.x + 1.0, tree.y, tree.z + 1.0)
	var best: Vector3i = NONE
	var best_qi: float = -1.0
	var cells: Array = []
	for k in range(4):
		cells.append(H.ring_cell(sim, center, agent.id + k * 97, Balance.number("cultivation.spot_inner"), Balance.number("cultivation.spot_outer")))
	# Spots the god has nurtured are cultivation places too.
	if sim.tree_growth != null:
		for nurtured in sim.tree_growth.nurtured:
			var at: Vector3i = nurtured.cell
			cells.append(H.ring_cell(sim, Vector3(at.x + 0.5, at.y, at.z + 0.5), agent.id, 0.5, float(nurtured.radius) * 0.7))
	# So are the sect's spirit-gathering arrays in their settlement.
	for entry in SectHalls.of(sim, agent.settlement_id, "spirit_array"):
		var jades: Array = entry.components.get("jade", [])
		var middle := Vector3.ZERO
		for jade in jades:
			middle += Vector3(jade) / jades.size()
		cells.append(H.ring_cell(sim, middle + Vector3(0.5, 0.0, 0.5), agent.id, 0.5, 2.0))
	cells.append(SectPlaces.hall_mat(sim, agent))
	cells.append(SectHalls.room_mat(sim, agent))
	# A branch sits round its own cutting of the tree.
	cells.append(Branches.ring_cell(sim, agent))
	for cell in cells:
		if cell.x < 0 or _taken(sim, agent, cell):
			continue
		var qi: float = sitting_qi(sim, cell, agent)
		if qi > best_qi:
			best = cell
			best_qi = qi
	return best


## The qi a sitting at a cell is worth: the field, helped by a hall (or, for
## one already on the Way, a meditation room).
static func sitting_qi(sim: RefCounted, cell: Vector3i, agent: RefCounted = null) -> float:
	var qi: float = sim.qi.density(sim, cell)
	if agent != null:
		return qi * SectHalls.sitting_factor(sim, agent, cell)
	return qi * Balance.number("cultivation.hall_factor") if SectPlaces.in_hall(sim, cell) else qi


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
	var qi: float = sitting_qi(sim, cell, agent)
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


## The master receives a guest who has come to the tree for sanctuary.
static func _receive_guest(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if sim.region_id != 0 or sim.sects == null or Schedule.is_sleep_time(sim, agent):
		return
	var sect: Dictionary = sim.sects.get_sect(int(agent.cultivation.get("sect_id", -1)))
	if sect.is_empty() or int(sect.master) != agent.id:
		return
	var waiting: Array = Guests.waiting(sim, agent.settlement_id)
	if not waiting.is_empty():
		out.append(_candidate(Kind.ADMIT_GUEST, float(Guests.config().receive_pull), "reason_receive_guest", waiting[0].id))


## An elder may carry a cutting to free land, and a member may follow a
## branch of their sect (branches.gd weighs both).
static func _branch(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	var want: Dictionary = Branches.founding(sim, agent)
	if not want.is_empty():
		var candidate: Dictionary = _candidate(Kind.FOUND_BRANCH, float(want.utility), "reason_found_branch", int(want.ground))
		candidate.goal = Goals.make(Kind.FOUND_BRANCH, int(want.ground), int(want.cause))
		out.append(candidate)
		return
	want = Branches.following(sim, agent)
	if not want.is_empty():
		out.append(_candidate(Kind.FOUND_BRANCH, float(want.utility), "reason_follow_branch", int(want.ground)))


## At a realm's peak a cultivator weighs facing Heaven: impatience grows
## the longer they wait, preparation (rest, food, help) makes it look less
## like folly, courage and ambition push, a cracked foundation holds back.
## Once announced there is no turning back.
static func _breakthrough(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	var c: Dictionary = agent.cultivation
	if sim.tribulations == null or int(c.realm) < 1 or not CultivationState.has_next(c) or not CultivationState.at_peak(c):
		return
	if not sim.tribulations.of(agent.id).is_empty():
		out.append(_candidate(Kind.BREAKTHROUGH, Balance.number("cultivation.trial_committed"), "reason_facing_heaven"))
		return
	# A guest faces Heaven here only once the sect has let them (M22).
	if not Guests.may_face(agent):
		return
	# Abroad, a cultivator may rather face Heaven beneath the sacred tree.
	if Guests.would_seek(sim, agent):
		out.append(_candidate(Kind.SEEK_SANCTUARY, Balance.number("cultivation.trial_committed") * 0.5, "reason_seek_sanctuary"))
		return
	if Schedule.is_sleep_time(sim, agent):
		return
	var days: float = float(sim.calendar.tick - int(c.peak_tick)) / sim.calendar.ticks_per_day if int(c.peak_tick) >= 0 else 0.0
	var impatience: float = clampf(days / Balance.number("cultivation.peak_days"), 0.0, 1.0)
	var prep: float = sim.tribulations.preparation(sim, agent)
	var courage: float = clampf(0.5 + 0.3 * float(agent.personality.bravery) + 0.3 * float(c.drive) - (0.3 if float(c.foundation) < 0.35 else 0.0), 0.1, 1.2)
	var utility: float = (Balance.number("cultivation.peak_base") + Balance.number("cultivation.peak_impatience") * impatience) * courage * (0.4 + 0.6 * prep)
	# Few call Heaven while a thunderstorm already rages; only the worn-out wait gives way.
	if sim.weather != null and sim.weather.is_storm() and impatience < 1.0:
		utility *= float(sim.weather.data().trial_wait)
	out.append(_candidate(Kind.BREAKTHROUGH, utility, "reason_at_peak", -1, prep * 100.0))


## Where to face Heaven: their settlement's tribulation chamber, then its
## ground, when it has one; otherwise the tree's sanctuary when it can be
## reached, unless a loner would rather be alone with it, near home.
static func trial_site(sim: RefCounted, agent: RefCounted) -> Vector3i:
	var chamber: Vector3i = SectHalls.chamber_cell(sim, agent)
	if chamber.x >= 0:
		return chamber
	var ground: Dictionary = SectPlaces.ground(sim, agent.settlement_id)
	if not ground.is_empty():
		var stand: Vector3i = SectPlaces.ground_cell(sim, ground)
		if stand.x >= 0:
			return stand
	var tree: Vector3i = sim.features.get("sacred_tree", NONE)
	var near_tree: bool = tree.x >= 0 and H.distance(tree, agent.cell) <= Balance.number("cultivation.sanctuary_reach")
	if near_tree and not agent.has_trait("loner"):
		var cell: Vector3i = spot(sim, agent)
		if cell.x >= 0:
			return cell
	if tree.x < 0 or not near_tree:
		# Far from the tree, a branch faces Heaven by its own cutting, where
		# its relics lie.
		var by_cutting: Vector3i = Branches.ring_cell(sim, agent)
		return by_cutting if by_cutting.x >= 0 else H.wander_cell(sim, agent)
	# A quiet place beyond the sanctuary, on their own side of the tree.
	var angle: float = float(agent.id) * 2.39996
	var reach: float = Balance.number("cultivation.sanctuary_radius") + 8.0
	var away := Vector3i(roundi(tree.x + cos(angle) * reach), tree.y, roundi(tree.z + sin(angle) * reach))
	var found: Vector3i = sim.nav.nearest_walkable(away, 4)
	return found if found.x >= 0 else H.wander_cell(sim, agent)


## A storm seen nearby moves believers to pray for the one inside it.
static func _witness(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if sim.tribulations == null or sim.tribulations.entries.is_empty() or not agent.faith.get("knows", false):
		return
	var sight: float = Balance.number("agents.sight_radius") * 1.5
	for id in sim.tribulations.entries:
		var trial: Dictionary = sim.tribulations.entries[id]
		if trial.state == "storm" and int(trial.agent) != agent.id and H.distance(trial.site, agent.cell) <= sight:
			out.append(_candidate(Kind.PRAY, Balance.number("cultivation.witness_prayer") * (0.5 + float(agent.faith.devotion) / 100.0), "reason_trial"))
			return


## Spirit fruit on the tree: a sect's master decides who should have it; where
## there is no sect, a cultivator near their peak takes one for themselves.
static func _share_fruit(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if sim.tree_growth == null:
		return
	# A fruit in hand is carried on to the one it was picked for.
	if not agent.carrying.is_empty() and str(agent.carrying.resource) == "spirit_fruit":
		var goal: Dictionary = agent.current_goal()
		var target: int = int(goal.target) if not goal.is_empty() and int(goal.kind) == Kind.SHARE_FRUIT else agent.id
		if target != agent.id and not sim.agents[target].is_present():
			target = agent.id
		out.append(_candidate(Kind.SHARE_FRUIT, 0.9, "reason_share_fruit", target))
		return
	if int(sim.tree_growth.fruit) <= 0 or Schedule.is_sleep_time(sim, agent):
		return
	var sect: Dictionary = sim.sects.in_settlement(agent.settlement_id) if sim.sects != null else {}
	if not sect.is_empty():
		if int(sect.master) != agent.id:
			return
		var choice: Array = FruitChoice.choose(sim, sect, agent)
		if int(choice[0]) < 0:
			return
		out.append(_candidate(Kind.SHARE_FRUIT, 0.6 + 0.2 * maxf(agent.personality.leadership, 0.0), "reason_share_fruit", int(choice[0])))
		return
	if FruitChoice.wants_fruit(sim, agent):
		out.append(_candidate(Kind.SHARE_FRUIT, 0.45 + 0.2 * float(agent.cultivation.drive), "reason_take_fruit", agent.id))


## A cultivator whose foundation a failed trial cracked goes to rest in their
## settlement's infirmary, where it mends.
static func _convalesce(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if not SectHalls.cracked(agent) or SectHalls.infirmary(sim, agent) < 0 or Schedule.is_sleep_time(sim, agent):
		return
	out.append(_candidate(Kind.SEEK_CARE, Balance.number("halls.convalesce_utility") * (0.6 + 0.4 * float(agent.cultivation.drive)), "reason_mend_foundation"))


## Someone hurt, cracked, poisoned by pills or near the end of their span
## goes to the stores for the preparation that would help, if they believe
## the stores hold one.
static func _medicate(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if agent.settlement_id < 0 or Schedule.is_sleep_time(sim, agent):
		return
	for need in Elixirs.needs(sim, agent):
		if agent.beliefs.believes_stock(str(need[0])):
			out.append(_candidate(Kind.MEDICATE, float(need[1]), "reason_medicate_%s" % need[0], Elixirs.index_of(str(need[0]))))
			return
