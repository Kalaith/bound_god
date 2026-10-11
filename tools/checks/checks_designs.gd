extends RefCounted
## Designs without the god: people work out what their settlement lacks
## (the sect's halls only by its master and elders), someone sets out and
## comes back with plans, wayfarers pass through and share theirs, and the
## abstract model does the same while the god meditates.
const Sim = preload("res://scripts/sim/sim.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Deliberation = preload("res://scripts/agents/deliberation.gd")
const Lore = preload("res://scripts/sim/designs_lore.gd")
const Wayfarers = preload("res://scripts/sim/wayfarers.gd")
const AbstractBuild = preload("res://scripts/sim/abstract/abstract_build.gd")
const Abstract = preload("res://tools/checks/checks_abstract.gd")


static func _village(people: int = 10) -> RefCounted:
	var sim: RefCounted = Sim.create(11)
	Abstract._settle(sim, people)
	sim.run_ticks(12)
	return sim


## A grown person living in the test village (the ridge hamlet's miners live apart).
static func _villager(sim: RefCounted, skip: int = 0) -> RefCounted:
	for agent in sim.agents:
		if agent.is_present() and not agent.is_child and agent.settlement_id == 1:
			if skip == 0:
				return agent
			skip -= 1
	return null


static func _knows(sim: RefCounted, function: String) -> bool:
	for template_id in Lore.known_in(sim, 1):
		if sim.template(template_id) != null and sim.template(template_id).functions.has(function):
			return true
	return false


static func _lacks(sim: RefCounted, function: String) -> bool:
	return Lore.lacking(sim, 1).any(func(want: Array) -> bool: return str(want[0]) == function)


## A settlement big enough for a hall and knowing no hall's design has
## people who would work one out; their hours add up to the design, learned
## by everyone living there and chronicled with its cause.
func check_people_work_out_a_design_their_settlement_lacks():
	var sim: RefCounted = _village()
	if _knows(sim, "hall") or not _lacks(sim, "hall"):
		return "the test village should lack a hall's design (knows: %s)" % str(Lore.known_in(sim, 1).keys())
	var studying: bool = false
	for agent in sim.agents:
		if agent.is_present() and not agent.is_child and agent.settlement_id == 1:
			for option in Deliberation.candidates(sim, agent):
				studying = studying or int(option.goal.kind) == Goals.Kind.STUDY
	if not studying:
		return "nobody weighed working out a design the settlement lacks"
	var scholar: RefCounted = _villager(sim)
	var worked: String = ""
	for i in range(200):
		worked = Lore.study(sim, scholar, "hall", false, 1.0)
		if not worked.is_empty():
			break
	if worked.is_empty() or not _knows(sim, "hall"):
		return "200 hours of study worked out no hall"
	for agent in sim.agents:
		if agent.is_present() and agent.settlement_id == 1 and not agent.beliefs.known_templates.has(worked):
			return "%s living there does not know the worked-out %s" % [agent.full_name(), worked]
	if not sim.chronicle.entries.any(func(entry: Dictionary) -> bool: return entry.kind == "design_worked_out"):
		return "working out a design was not chronicled"
	return ""


## Only a sect's master and elders work out its halls; anyone grown works
## out the village's buildings.
func check_only_sect_leaders_work_out_grand_halls():
	var sim: RefCounted = _village()
	var member: RefCounted = _villager(sim, 1)
	if not Lore.may_study(sim, member, false) or Lore.may_study(sim, member, true):
		return "an ordinary grown person may study village %s, sect halls %s" % [Lore.may_study(sim, member, false), Lore.may_study(sim, member, true)]
	if Lore.starter_for(sim, "meditation_hall", Lore.authors(true)).is_empty() or not Lore.starter_for(sim, "meditation_hall", Lore.authors(false)).is_empty():
		return "the grand halls are not the wandering cultivators' alone"
	return ""


## Someone sets out: away, they are not present (and stay away through a
## save); on their day they come back with plans everyone there learns.
func check_a_traveller_sets_out_and_returns_with_plans():
	var sim: RefCounted = _village()
	var traveller: RefCounted = _villager(sim, 2)
	traveller.health.hp = 100.0
	traveller.joined_day = sim.calendar.day() - 10
	var index: int = traveller.id
	if not Lore.may_travel(sim, traveller):
		return "a healthy grown person of a settlement of ten may not travel"
	var before: int = Lore.known_in(sim, 1).size()
	Lore.set_out(sim, traveller)
	if traveller.is_present() or traveller.life != "away" or not Lore.away(sim, 1):
		return "the traveller did not leave (%s)" % traveller.life
	var saved: Dictionary = SimState.capture(sim)
	sim = SimState.restore(bytes_to_var(var_to_bytes(saved.sim)), bytes_to_var(var_to_bytes(saved.chunks)))
	traveller = sim.agents[index]
	if traveller.life != "away" or not Lore.away(sim, 1):
		return "a save forgot the traveller was away"
	sim.calendar.tick += sim.calendar.ticks_per_day * 8
	Lore.daily(sim)
	if not traveller.is_present():
		return "the traveller had not come back after eight days (%s)" % traveller.life
	if Lore.known_in(sim, 1).size() <= before:
		return "the traveller brought no plans back"
	if not sim.chronicle.entries.any(func(entry: Dictionary) -> bool: return entry.kind == "returned_with_plans"):
		return "the return was not chronicled"
	return ""


## A wayfarer stops, shares plans everyone there learns, builds no home
## (the settlement does not count them homeless) and goes on their way.
func check_wayfarers_pass_through_and_share_plans():
	var sim: RefCounted = _village()
	sim.calendar.tick = sim.calendar.ticks_per_day * 5 + 300
	var settlement: Dictionary = sim.settlements.entries[1]
	settlement["next_wayfarer"] = sim.calendar.tick
	var people: int = sim.agents.size()
	var before: int = Lore.known_in(sim, 1).size()
	Wayfarers.daily(sim)
	if sim.agents.size() != people + 1:
		return "no wayfarer came"
	var wayfarer: RefCounted = sim.agents.back()
	if not Wayfarers.passing(wayfarer) or not wayfarer.is_present():
		return "the newcomer is not a wayfarer staying here"
	if Lore.known_in(sim, 1).size() <= before:
		return "the wayfarer shared no plans"
	for want in AbstractBuild.wants(sim, 1):
		if str(want[0]) == "dwelling" and int(want[2]) == wayfarer.id:
			return "the wayfarer is counted as someone to house"
	sim.calendar.tick += sim.calendar.ticks_per_day * 3
	Wayfarers.daily(sim)
	if wayfarer.is_present() or settlement.residents.has(wayfarer.id):
		return "the wayfarer never went on their way"
	if int(settlement.next_wayfarer) <= sim.calendar.tick:
		return "no next wayfarer is expected"
	return ""


## While the god meditates the settlement still works out what it lacks.
func check_meditation_works_out_lacking_designs():
	var sim: RefCounted = _village()
	if not _lacks(sim, "hall"):
		return "the test village should lack a hall's design"
	for day in range(30):
		Lore.abstract_day(sim, 1)
		sim.calendar.tick += sim.calendar.ticks_per_day
	if not _knows(sim, "hall"):
		return "thirty abstract days worked out no hall (study %s)" % str(sim.settlements.entries[1].get("study", {}))
	return ""
