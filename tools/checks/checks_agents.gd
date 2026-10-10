extends RefCounted
## M4 acceptance: situated, robust, proactive and deterministic people who
## survive their first days.
const Stores = preload("res://tools/checks/stores.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Cognition = preload("res://scripts/sim/cognition.gd")
const Text = preload("res://scripts/core/text.gd")

const Need = Personality.Need
const Kind = Goals.Kind


func _flat(people: bool = true) -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(48, 16, 48), "ground": 4, "people": people})


func _candidate(kind: int, utility: float) -> Dictionary:
	return {"goal": Goals.make(kind), "utility": utility, "reason": "", "value": NAN}


func check_people_only_know_what_they_have_perceived():
	var sim: RefCounted = Sim.create(7)
	sim.run_ticks(6)
	var sight: float = 12.0 + 6.0
	for agent in sim.agents:
		for id in agent.beliefs.sites:
			var cell: Vector3i = agent.beliefs.sites[id].cell
			if Vector2(cell.x - agent.cell.x, cell.z - agent.cell.z).length() > sight + 2.0:
				return "%s believes in a site they never saw at %s" % [agent.given_name, cell]
	if sim.agents[0].beliefs.sites.size() >= sim.sites.sites.size():
		return "a traveller knows every site in the valley"
	if sim.agents[0].beliefs.sites.is_empty():
		return "a traveller saw nothing around the tree"
	return ""


func check_committed_goals_resist_small_temptations_but_yield_to_breaks():
	var build: Dictionary = Goals.make(Kind.BUILD, 1)
	var eat: Dictionary = Goals.make(Kind.EAT)
	if Cognition.should_switch(build, 0.5, _candidate(Kind.RELAX, 0.55)):
		return "a small temptation broke a commitment"
	if not Cognition.should_switch(build, 0.5, _candidate(Kind.RELAX, 0.9)):
		return "a much better goal did not win"
	if not Cognition.should_switch(build, 0.5, _candidate(Kind.RELAX, 0.8)):
		return "relax 0.8 should displace work at 0.5"
	if Cognition.should_switch(eat, 0.5, _candidate(Kind.RELAX, 0.8)):
		return "leisure displaced a survival goal without a large margin"
	if not Cognition.should_switch(build, 5.0, _candidate(Kind.BREAK, 0.1)):
		return "a mental break must always win"
	return ""


func check_a_failed_plan_corrects_beliefs_and_tries_another_way():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	var friend: RefCounted = sim.agents[1]
	agent.needs[Need.FOOD] = 5.0
	agent.beliefs.stock = {}
	agent.carrying = {}
	agent.beliefs.relation(friend.id).opinion = 60.0
	# A bush remembered beside them that is no longer there.
	agent.beliefs.note_site(9999, "bush", agent.cell + Vector3i(2, 0, 0), 3, sim.calendar.tick)
	agent.intention = {}
	agent.next_deliberation = sim.calendar.tick
	sim.run_ticks(20)
	var failed_at: int = -1
	var replanned: bool = false
	for i in range(agent.decisions.size() - 1, -1, -1):
		var entry: Dictionary = agent.decisions[i]
		if entry.kind == "failed" and entry.plan == "forage":
			failed_at = i
		elif failed_at >= 0 and i < failed_at and entry.kind == "plan" and entry.plan != "forage":
			replanned = true
	if failed_at < 0:
		return "the vanished bush was never tried: %s" % str(agent.decisions)
	if agent.beliefs.sites.has(9999):
		return "the vanished bush is still believed"
	if not replanned:
		return "no other plan followed the failure: %s" % str(agent.decisions)
	return ""


func check_exhausted_goals_back_off_and_frustrate():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	Stores.fill(sim, agent.settlement_id, {})
	agent.beliefs.stock = {}
	agent.beliefs.sites.clear()
	agent.carrying = {}
	agent.intention = {"goal": Goals.make(Kind.EAT), "utility": 1.0, "reason": "", "value": 0.0, "plan": {}, "tried": [], "started_tick": sim.calendar.tick}
	Cognition.ensure_plan(sim, agent)
	if not agent.is_backed_off(Goals.key_of(Kind.EAT), sim.calendar.tick):
		return "an Eat goal with no plan left was not backed off"
	if not Mind.has(agent, "frustrated") or agent.decisions.front().kind != "gave_up":
		return "giving up must log and frustrate"
	return ""


func check_travellers_live_through_five_days():
	var sim: RefCounted = Sim.create(11)
	var seen: Dictionary = {}
	var started: int = Time.get_ticks_msec()
	for _i in range(sim.calendar.ticks_per_day * 5):
		sim.step()
		for agent in sim.agents:
			if agent.settlement_id == 1:
				seen["%d:%s" % [agent.id, agent.activity]] = true
				if agent.activity in ["sleeping", "sheltering"] and not sim.calendar.is_daylight() and sim.is_under_canopy(agent.cell):
					seen["%d:covered" % agent.id] = true
	var elapsed: float = (Time.get_ticks_msec() - started) / 1000.0
	print("      5 days, %d people: %.1fs (%.2f ms/tick)" % [sim.agents.size(), elapsed, elapsed * 1000.0 / (sim.calendar.ticks_per_day * 5)])
	for agent in sim.agents:
		# The two travellers of the first morning; migrants come later.
		if agent.settlement_id != 1 or agent.joined_day != 1:
			continue
		if not agent.is_present():
			return "%s died of %s" % [agent.given_name, agent.life_cause]
		for activity in ["eating", "sleeping"]:
			if not seen.has("%d:%s" % [agent.id, activity]):
				return "%s never spent time %s" % [agent.given_name, activity]
		if not seen.has("%d:covered" % agent.id):
			return "%s never sought cover at night" % agent.given_name
		if float(agent.health.hp) < 50.0 or agent.need(Need.FOOD) < 5.0:
			return "%s is failing: hp %.0f food %.0f" % [agent.given_name, agent.health.hp, agent.need(Need.FOOD)]
	for agent in sim.agents:
		if not agent.is_present():
			return "a miner died of %s" % agent.life_cause
	return ""


func check_the_same_seed_plays_out_identically():
	var a: RefCounted = Sim.create(21)
	var b: RefCounted = Sim.create(21)
	var ticks: int = a.calendar.ticks_per_day * 2
	a.run_ticks(ticks)
	b.run_ticks(ticks)
	if a.state_hash() != b.state_hash():
		return "two runs of seed 21 diverged"
	return ""


func check_every_label_resolves():
	var missing: Array = []
	for name in Goals.NAMES:
		if not Text.has("goal_" + name):
			missing.append("goal_" + name)
	for name in Plans.FAIL_NAMES:
		if not Text.has("fail_" + name):
			missing.append("fail_" + name)
	var pattern := RegEx.new()
	pattern.compile("option\\(\"([a-z_]+)\"")
	var activity := RegEx.new()
	activity.compile("activity = \"([a-z_]+)\"")
	var reason := RegEx.new()
	reason.compile("\"(reason_[a-z_]+|interrupt_[a-z_]+|cause_[a-z_]+)\"")
	for folder in ["res://scripts/agents", "res://scripts/sim"]:
		for file in DirAccess.get_files_at(folder):
			var source: String = FileAccess.get_file_as_string(folder.path_join(file))
			for found in pattern.search_all(source):
				if not Text.has("plan_" + found.get_string(1)):
					missing.append("plan_" + found.get_string(1))
			for found in activity.search_all(source):
				if not Text.has("activity_" + found.get_string(1)):
					missing.append("activity_" + found.get_string(1))
			for found in reason.search_all(source):
				if not Text.has(found.get_string(1)):
					missing.append(found.get_string(1))
	return "" if missing.is_empty() else "missing labels: " + ", ".join(missing)
