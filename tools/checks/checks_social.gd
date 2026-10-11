extends RefCounted
## M7 acceptance: bonds form, friends feed the hungry, breaks override,
## and clashing natures sour conversation.
const Stores = preload("res://tools/checks/stores.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Deliberation = preload("res://scripts/agents/deliberation.gd")
const Social = preload("res://scripts/sim/social.gd")
const Population = preload("res://scripts/sim/population.gd")
const Generation = preload("res://scripts/agents/generation.gd")

const Need = Personality.Need


func _flat() -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(48, 16, 48), "ground": 4})


func long_check_relationships_form_over_twenty_days():
	var sim: RefCounted = Sim.create(11)
	sim.run_ticks(sim.calendar.ticks_per_day * 20)
	var friends: int = 0
	for agent in sim.agents:
		for other in agent.beliefs.relations:
			if agent.beliefs.bond_with(other) in ["friend", "close_friend"]:
				friends += 1
	var noted: bool = false
	for entry in sim.chronicle.entries:
		noted = noted or str(entry.kind) in ["became_friends", "became_close_friends", "became_rivals"]
	print("      day 20: %d people, %d friendly bonds" % [sim.present_count(), friends])
	if friends < 2:
		return "only %d friendly bonds after 20 days" % friends
	if not noted:
		return "no bond change reached the chronicle"
	return ""


func check_a_hungry_person_with_empty_stores_is_fed_by_a_friend():
	var sim: RefCounted = _flat()
	# After the midday meal, so a well-fed friend keeps what they carry.
	sim.calendar.tick = sim.calendar.ticks_per_day * 13 / 24
	var hungry: RefCounted = sim.agents[0]
	var friend: RefCounted = sim.agents[1]
	Stores.fill(sim, 1, {})
	for agent in [hungry, friend]:
		agent.beliefs.stock = {}
		agent.beliefs.sites.clear()
		agent.intention = {}
	hungry.needs[Need.FOOD] = 12.0
	hungry.carrying = {}
	friend.needs[Need.FOOD] = 100.0
	friend.carrying = {"resource": "berries", "amount": 3.0}
	hungry.beliefs.relation(friend.id).opinion = 60.0
	friend.beliefs.relation(hungry.id).opinion = 60.0
	var start: float = hungry.need(Need.FOOD)
	var asked: bool = false
	for _i in range(300):
		sim.step()
		var plan: Dictionary = hungry.current_plan()
		asked = asked or plan.get("id", "") == "ask_friend_for_food"
	if not asked:
		return "the hungry person never asked a friend: %s" % str(hungry.decisions)
	if friend.stats.helped_others < 1 or hungry.need(Need.FOOD) <= start:
		return "the friend did not feed them (food %.0f, helped %d)" % [hungry.need(Need.FOOD), friend.stats.helped_others]
	return ""


func check_a_mental_break_overrides_every_other_goal():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	agent.mental_break = {"kind": Goals.BreakKind.SULK, "until": sim.calendar.tick + 100}
	var options: Array = Deliberation.candidates(sim, agent)
	if options.size() != 1 or int(options[0].goal.kind) != Goals.Kind.BREAK or options[0].utility != 10.0:
		return "a break did not become the only candidate: %s" % str(options)
	return ""


func check_clashing_natures_sour_small_talk():
	var sim: RefCounted = _flat()
	var a: RefCounted = Generation.adult(sim.rng, sim.agents.size())
	var b: RefCounted = Generation.adult(sim.rng, sim.agents.size() + 1)
	a.traits = ["abrasive"]
	b.traits = ["kind"]
	for agent in [a, b]:
		agent.personality = Personality.from_traits(agent.traits)
		Population.arrive(sim, agent, sim.agents[0].cell, 1, "")
	for _i in range(40):
		Social.resolve(sim, {"from": a.id, "to": b.id, "topic": Plans.Topic.SMALL_TALK})
	if b.beliefs.opinion_of(a.id) >= 0.0:
		return "a kind person still likes an abrasive one after 40 talks: %.1f" % b.beliefs.opinion_of(a.id)
	return ""
