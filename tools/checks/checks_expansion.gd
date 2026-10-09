extends RefCounted
## M9 acceptance: the god's name travels with its followers, the ridge folk
## restore their altar, the ridge shrine wakes and the god can step through.
const Sim = preload("res://scripts/sim/sim.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const Social = preload("res://scripts/sim/social.gd")
const Cognition = preload("res://scripts/sim/cognition.gd")
const Deliberation = preload("res://scripts/agents/deliberation.gd")


func check_the_name_reaches_the_ridge_and_the_god_follows():
	var sim: RefCounted = Sim.create(11)
	sim.run_ticks(12)
	for agent in sim.agents:
		if agent.settlement_id == 1:
			agent.faith.knows = true
			agent.faith.devotion = 72.0
	sim.faith.shrines[1].favour = 60.0
	var ridge: int = 2
	var restored: bool = false
	for day in range(15):
		var open: bool = false
		for id in sim.requests.ids():
			open = open or sim.requests.requests[id].state == "open"
		if not open:
			sim.apply_command({"type": "post_request", "kind": "carry_name", "target": 2, "boon": 10})
		sim.run_ticks(sim.calendar.ticks_per_day)
		restored = restored or sim.faith.shrines[ridge].state != "fallen"
		if sim.faith.shrines[ridge].state == "active":
			break
	var miners: int = 0
	for agent in sim.agents:
		if agent.settlement_id == 2 and agent.faith.knows:
			miners += 1
	print("      day %d: %d of the ridge folk know the god, ridge altar %s" % [sim.calendar.day(), miners, sim.faith.shrines[ridge].state])
	if miners < 3:
		return "the name did not reach the ridge folk"
	if not restored:
		return "nobody restored the ridge altar"
	if sim.faith.shrines[ridge].state != "active":
		return "the restored ridge altar never became active"
	if sim.god.dormant:
		sim.faith.daily(sim)
	var result: Dictionary = sim.apply_command({"type": "transfer_shrine", "shrine": ridge})
	if not result.ok and sim.god.active_shrine_id != ridge:
		return "the god could not transfer to the ridge: " + str(result.reason)
	if Vector2(sim.zone_center().x - sim.features.ruin.altar.x, sim.zone_center().z - sim.features.ruin.altar.z).length() > 2.0:
		return "after transferring, the presence zone is not at the ridge altar"
	return ""


func check_a_story_makes_a_stranger_aware():
	var sim: RefCounted = Sim.create(21, {"world": "flat", "size": Vector3i(48, 16, 48), "ground": 4})
	var teller: RefCounted = sim.agents[0]
	var stranger: RefCounted = sim.agents[1]
	teller.faith.knows = true
	teller.faith.devotion = 70.0
	stranger.faith = preload("res://scripts/agents/generation.gd").new_faith()
	Social.resolve(sim, {"from": teller.id, "to": stranger.id, "topic": Plans.Topic.STORY})
	if not stranger.faith.knows or FaithState.stage(stranger.faith) < 1:
		return "a story did not make the stranger aware"
	var first: float = float(stranger.faith.devotion)
	Social.resolve(sim, {"from": teller.id, "to": stranger.id, "topic": Plans.Topic.STORY})
	if float(stranger.faith.devotion) <= first:
		return "a second story from a devout teller added no devotion"
	return ""


func check_a_whisper_never_forces_a_goal_below_commitment():
	var sim: RefCounted = Sim.create(21, {"world": "flat", "size": Vector3i(48, 16, 48), "ground": 4})
	var agent: RefCounted = sim.agents[0]
	agent.faith.knows = true
	agent.faith.devotion = 50.0
	# A small urge toward relaxing, against a committed survival goal.
	agent.whispers = [{"kind": Goals.Kind.RELAX, "target": -1, "bonus": 0.2, "until": sim.calendar.tick + 100}]
	agent.needs[4] = 60.0
	var options: Array = Deliberation.candidates(sim, agent)
	var relax: Dictionary = {}
	for entry in options:
		if int(entry.goal.kind) == Goals.Kind.RELAX:
			relax = entry
	if relax.is_empty() or not relax.get("urged", false):
		return "the whisper did not raise the urged goal"
	if Cognition.should_switch(Goals.make(Goals.Kind.EAT), 0.5, relax):
		return "an urged goal displaced a committed survival goal below the margin (%.2f)" % relax.utility
	return ""
