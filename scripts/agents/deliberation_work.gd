extends RefCounted
## Work candidates, read from the settlement's job board. Final Landing's
## player priority becomes the settlement's own culture weight, so labour is
## steered only by what people need and what their respected members do.
## FoundHome and ProposeProject are how construction begins.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const JobBoard = preload("res://scripts/sim/job_board.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const FunctionRules = preload("res://scripts/building/function_rules.gd")
const Construction = preload("res://scripts/sim/construction.gd")
const Standing = preload("res://scripts/sim/standing.gd")

const Kind = Goals.Kind
const Need = Personality.Need
const Skill = Personality.Skill
const FUNCTIONS: Array[String] = FunctionRules.FUNCTIONS


static func _candidate(kind: int, utility: float, reason: String, target: int = -1, value: float = NAN) -> Dictionary:
	return {"goal": Goals.make(kind, target), "utility": utility, "reason": reason, "value": value}


static func aptitude(agent: RefCounted, skill: int) -> float:
	var result: float = 0.6 + agent.skills.levels[skill] * 0.04
	if agent.skills.passions.has(skill):
		result += 0.3
	if agent.ambition.get("id", "") == "master_skill" and not agent.skills.passions.is_empty() and agent.skills.passions[0] == skill:
		result += 0.3
	return result


## How a person feels about working beside whoever already pursues a goal.
static func company(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> float:
	var factor: float = 1.0
	var key: int = Goals.key(goal)
	for other in sim.agents:
		if other.id == agent.id or not other.is_present():
			continue
		var theirs: Dictionary = other.current_goal()
		if theirs.is_empty() or Goals.key(theirs) != key:
			continue
		match agent.beliefs.bond_with(other.id):
			"rival", "enemy":
				factor *= 0.55
			"friend", "close_friend":
				factor *= 1.15
			_:
				factor *= 0.8
	return factor


static func base_utility(sim: RefCounted, agent: RefCounted) -> float:
	var diligence: float = agent.personality.diligence
	var work_hours: bool = Schedule.is_work_hours(sim, agent)
	var base: float = 0.42 + diligence * 0.1 if work_hours else maxf(0.08 + diligence * 0.12, 0.02)
	if agent.need(Need.REST) < 25.0:
		base *= 0.5
	if agent.mood < 30.0:
		base *= 0.8
	return base * agent.capacity()


static func add(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if agent.is_child or agent.settlement_id < 0 or sim.settlement_life == null:
		return
	var board: Dictionary = sim.settlement_life.board(agent.settlement_id)
	if board.is_empty():
		return
	var settlement: Dictionary = sim.settlements.get_settlement(agent.settlement_id)
	var culture: Dictionary = settlement.culture
	var base: float = base_utility(sim, agent)
	var push := func(goal: Dictionary, factor: float, reason: String) -> void:
		var utility: float = base * factor * company(sim, agent, goal)
		if utility > 0.01:
			out.append({"goal": goal, "utility": utility, "reason": reason, "value": NAN})
	var build_bonus: float = 1.15 if agent.ambition.get("id", "") == "build_home" else 1.0
	var offered: int = 0
	for job in board.builds:
		if offered >= Balance.integer("construction.builds_offered"):
			break
		if not _actionable(sim, agent, job, board):
			continue
		offered += 1
		var founder: float = 1.3 if int(sim.construction.get_site(job.site).get("founder", -1)) == agent.id else 1.0
		push.call(Goals.make(Kind.BUILD, job.site), float(culture.build) * aptitude(agent, Skill.CONSTRUCTION) * build_bonus * founder, "reason_build")
	for i in range(mini(board.repairs.size(), 2)):
		push.call(Goals.make(Kind.REPAIR, board.repairs[i]), float(culture.build) * aptitude(agent, Skill.CONSTRUCTION) * 0.8, "reason_repair")
	# Food short in the chests makes food work matter more than any other.
	var hungry: float = Balance.number("work.hungry_food_pull") if Standing.food_days(sim, agent.settlement_id) < 1.0 else 1.0
	for index in range(JobBoard.RESOURCES.size()):
		var resource: String = JobBoard.RESOURCES[index]
		var demand: float = float(board.gather_demand.get(resource, 0.0)) * (hungry if resource == "berries" else 1.0)
		if demand < 0.05 or not agent.beliefs.has_site(JobBoard.SITE_KIND[resource]):
			continue
		push.call(Goals.make(Kind.GATHER, index), float(culture.gather) * aptitude(agent, Skill.GATHERING) * demand, "reason_gather")
	# Tend a garden: pick its ripe bushes into the stores, plant its empty planters.
	var ripe: Array = board.get("ripe", [])
	var plots: Array = board.get("plots", [])
	var can_plant: bool = not plots.is_empty() and (agent.carried("berries") >= 1.0 or agent.beliefs.believes_stock("berries") or agent.beliefs.has_site("bush"))
	if not ripe.is_empty() or can_plant:
		var garden: int = int(ripe[0][0]) if not ripe.is_empty() else int(plots[0][0])
		var pull: float = minf(0.45 + ripe.size() * 0.1 + (plots.size() * 0.06 if can_plant else 0.0), 1.1) * hungry
		push.call(Goals.make(Kind.GARDEN, garden), float(culture.gather) * aptitude(agent, Skill.GATHERING) * pull, "reason_garden")
	var unknown: int = 0
	for resource in board.gather_demand:
		if float(board.gather_demand[resource]) > 0.3 and not agent.beliefs.has_site(JobBoard.SITE_KIND[resource]):
			unknown += 1
	if unknown > 0 or agent.personality.curiosity > 0.3:
		push.call(Goals.make(Kind.SCOUT), float(culture.scout) * 0.45 * (1.0 + agent.personality.curiosity) * (1.0 + unknown * 0.3), "reason_scout")
	var loaded: bool = not agent.carrying.is_empty() and agent.carrying.resource != "berries"
	if not board.items.is_empty() or loaded:
		var load_factor: float = 1.0 if loaded else minf(board.items.size() / 3.0, 1.3)
		push.call(Goals.make(Kind.HAUL), float(culture.haul) * 0.75 * load_factor, "reason_haul")
	if agent.personality.bravery > 0.1 or agent.has_trait("leader"):
		for threat_id in board.threats:
			if not sim.threat_exists(threat_id):
				continue
			var threat_cell: Vector3i = sim.threats.entries[threat_id].cell
			var reach: float = Vector2(threat_cell.x - agent.cell.x, threat_cell.z - agent.cell.z).length()
			if reach < 16.0:
				out.append({"goal": Goals.make(Kind.DEFEND, threat_id), "utility": 0.8 * (0.4 + agent.personality.bravery) * float(agent.health.hp) / 100.0,
					"reason": "reason_defend", "value": reach})
	_found_home(sim, agent, out, base)
	_propose(sim, agent, out, base, board)


static func _actionable(sim: RefCounted, agent: RefCounted, job: Dictionary, board: Dictionary) -> bool:
	if job.ready:
		return true
	for resource in job.missing:
		if agent.beliefs.believes_stock(resource) or agent.carried(resource) >= 1.0:
			return true
		for item_id in board.get("loose", []):
			if sim.items.has(item_id) and sim.items[item_id].resource == resource:
				return true
	return false


## The best design this person knows for a function: enough capacity, cheapest.
static func known_design(sim: RefCounted, agent: RefCounted, function: String) -> RefCounted:
	var best: RefCounted = null
	for id in agent.beliefs.known_templates:
		var template: RefCounted = sim.template(id)
		if template == null or not template.functions.has(function):
			continue
		if best == null or template.block_count() < best.block_count() or (template.block_count() == best.block_count() and template.id < best.id):
			best = template
	return best


## Means believed available: every material in stock or known in the world.
static func means_believed(sim: RefCounted, agent: RefCounted, template: RefCounted) -> bool:
	for resource in template.bill:
		if agent.beliefs.believes_stock(resource):
			continue
		# Without stone, plain stone walls can go up in planks.
		if resource == "stone" and Construction.stone_is_walling(template) and (agent.beliefs.believes_stock("wood") or agent.beliefs.has_site("tree")):
			continue
		if not agent.beliefs.has_site(JobBoard.SITE_KIND.get(resource, "")):
			return false
	return true


static func _open_sites(sim: RefCounted, settlement_id: int) -> int:
	return sim.construction.in_settlement(settlement_id).size()


static func _founding(sim: RefCounted, agent: RefCounted) -> bool:
	for id in sim.construction.ids():
		if int(sim.construction.get_site(id).founder) == agent.id:
			return true
	return false


static func _found_home(sim: RefCounted, agent: RefCounted, out: Array, base: float) -> void:
	if agent.home >= 0 or agent.age_years < Balance.number("agents.adult_age_years") or _founding(sim, agent):
		return
	if agent.partner >= 0 and sim.agents[agent.partner].home >= 0:
		return
	if _open_sites(sim, agent.settlement_id) >= Balance.integer("construction.max_open_sites"):
		return
	var design: RefCounted = known_design(sim, agent, "dwelling")
	if design == null or not means_believed(sim, agent, design):
		return
	if int(sim.settlement_life.no_site_until.get("%d:%s" % [agent.settlement_id, design.id], -1)) > sim.calendar.tick:
		return
	var utility: float = Balance.number("construction.found_home_base") * base / 0.42
	utility *= 0.7 + (100.0 - agent.need(Need.SHELTER)) / 100.0
	if agent.partner >= 0:
		utility *= 1.2
	if agent.ambition.get("id", "") == "build_home":
		utility *= 1.3
	utility *= aptitude(agent, Skill.CONSTRUCTION) / 0.8
	out.append(_candidate(Kind.FOUND_HOME, utility, "reason_homeless"))


## How many standing structures in a settlement have each function.
static func _functions_in(sim: RefCounted, id: int) -> Dictionary:
	var counts: Dictionary = {}
	for entry in sim.structures.built():
		if sim.settlements.at_cell(entry.anchor) == id:
			for function in entry.functions:
				counts[function] = int(counts.get(function, 0)) + 1
	return counts


## Respected people notice what the whole settlement lacks.
static func _propose(sim: RefCounted, agent: RefCounted, out: Array, base: float, board: Dictionary) -> void:
	if agent.personality.leadership <= 0.2 and agent.personality.diligence <= 0.3:
		return
	if _founding(sim, agent) or _open_sites(sim, agent.settlement_id) >= Balance.integer("construction.max_open_sites"):
		return
	var id: int = agent.settlement_id
	var wants: Array = []
	var capacity: int = sim.settlements.capacity(sim, id)
	if capacity > 0 and sim.settlements.total(id) >= int(capacity * 0.85):
		wants.append(["storehouse", "reason_stores_full", 0.9])
	if int(board.get("housing_deficit", 0)) >= 3:
		wants.append(["shelter", "reason_many_homeless", 0.8])
	if sim.faith != null and sim.faith.wants_shrine(sim, agent):
		wants.append(["shrine", "reason_no_shrine", 0.85])
	var people: int = Standing.present(sim, id)
	var have: Dictionary = _functions_in(sim, id)
	if people >= Balance.integer("construction.hall_residents") and int(have.get("hall", 0)) == 0:
		wants.append(["hall", "reason_no_hall", 0.75])
	var gardens_wanted: int = ceili(float(people) / Balance.number("construction.people_per_garden"))
	if Standing.food_days(sim, id) < Balance.number("construction.garden_food_days") and int(have.get("garden", 0)) < gardens_wanted:
		wants.append(["garden", "reason_food_low", 0.8])
	for want in wants:
		var design: RefCounted = known_design(sim, agent, want[0])
		if design == null or not means_believed(sim, agent, design):
			continue
		var weight: float = 0.5 + maxf(agent.personality.leadership, 0.0)
		out.append(_candidate(Kind.PROPOSE_PROJECT, base * weight * float(want[2]) / 0.42 * 0.6, want[1], FUNCTIONS.find(want[0])))
