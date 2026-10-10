extends RefCounted
## M18 Meditation: a pinned person's trial wakes the god (or a protect rule
## answers it), materialised sites are sound, and prayers bring half the
## Favour while the god meditates.
const Meditation = preload("res://tools/checks/meditation.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Registry = preload("res://scripts/world/block_registry.gd")


static func _at_peak(sim: RefCounted, id: int) -> RefCounted:
	var agent: RefCounted = sim.agents[id]
	agent.cultivation.progress = CultivationState.needed(agent.cultivation)
	agent.cultivation.peak_tick = sim.calendar.tick - sim.calendar.ticks_for_days(10.0)
	agent.personality.bravery = 0.8
	return agent


## A pinned disciple at their peak, with no word left for their trial,
## wakes the meditating god before Heaven answers.
func check_a_pinned_trial_wakes_the_god():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var disciple: RefCounted = _at_peak(sim, int(valley.members[1]))
	sim.apply_command({"type": "follow", "agent": disciple.id})
	var model: RefCounted = AbstractWorld.begin(sim)
	var reason: Dictionary = model.run_hours(sim, 24 * 3)
	model.finish(sim)
	if str(reason.get("kind", "")) != "trial" or int(reason.get("agent", -1)) != disciple.id:
		return "the god was not woken for the trial: %s" % str(reason)
	if not disciple.cultivation.trials.is_empty():
		return "Heaven answered before the god woke"
	return ""


## With a protect rule, the trial goes ahead while the god meditates and the
## rule spends Favour on a shield, which the chronicle explains.
func check_a_protect_rule_answers_the_trial():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var disciple: RefCounted = _at_peak(sim, int(valley.members[1]))
	sim.apply_command({"type": "follow", "agent": disciple.id})
	if not sim.apply_command({"type": "protect", "agent": disciple.id, "mode": "shield", "limit": 60.0}).ok:
		return "the rule was refused"
	sim.faith.get_shrine(1).favour = 100.0
	var model: RefCounted = AbstractWorld.begin(sim)
	var reason: Dictionary = model.run_hours(sim, 24 * 3)
	model.finish(sim)
	if str(reason.get("kind", "")) == "trial":
		return "the god was woken despite the rule"
	if disciple.cultivation.trials.is_empty():
		return "no trial happened in three days: %s" % str(reason)
	if float(disciple.cultivation.trials[0].shield) <= 0.0:
		return "the trial was not shielded"
	for entry in sim.chronicle.entries:
		if entry.kind == "miracle" and str(entry.cause).begins_with("cause_protect_rule"):
			return ""
	return "the shield was not chronicled with the rule as its cause"


## After days of abstract building, every site's placed blocks stand in the
## world as ordered, the rest of each site is still reserved, everyone
## stands on walkable ground, and the valley plays on.
func check_materialised_sites_are_sound():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var model: RefCounted = AbstractWorld.begin(sim)
	model.run_hours(sim, 24 * 8)
	model.finish(sim)
	var grass: int = Registry.id("tall_grass")
	for id in sim.construction.ids():
		var site: Dictionary = sim.construction.get_site(id)
		for index in range(site.order.size()):
			var entry: Array = site.order[index]
			if index < int(site.cursor):
				var block: int = sim.voxels.get_block(entry[0])
				if int(entry[1]) != 0 and block != int(entry[1]) and block != grass and Registry.passable[block] == 1:
					return "a placed block of %s is missing at %s" % [site.template_id, entry[0]]
			elif not sim.construction.is_reserved(entry[0]):
				return "an unbuilt cell of %s is not reserved" % site.template_id
	for agent in sim.agents:
		if agent.is_present() and not sim.nav.is_walkable(agent.cell):
			return "%s was thawed off the ground" % agent.full_name()
	var built: int = 0
	for entry in sim.chronicle.entries:
		built += 1 if entry.kind == "built" else 0
	if built == 0:
		return "nothing was built in eight abstract days"
	sim.run_ticks(sim.calendar.ticks_per_day / 2)
	return ""


## Prayers while the god meditates bring half the Favour they would.
func check_meditation_halves_favour():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var agent: RefCounted = sim.agents[int(valley.master)]
	agent.faith.devotion = 80.0
	var shrine: Dictionary = sim.faith.get_shrine(1)
	shrine.favour = 0.0
	sim.faith.record_prayer(sim, agent, 1, {"kind": "thanks"})
	var awake: float = float(shrine.favour)
	shrine.favour = 0.0
	sim.meditating = true
	sim.faith.record_prayer(sim, agent, 1, {"kind": "thanks"})
	sim.meditating = false
	if not is_equal_approx(float(shrine.favour) * 2.0, awake) or awake <= 0.0:
		return "favour %.2f awake, %.2f meditating" % [awake, float(shrine.favour)]
	return ""
