extends RefCounted
## The long soak (plan M25), shared by `tools/soak.gd` and the release check:
## a campaign meditates `years` years in spans of `span` years (the abstract
## model in every region, in lockstep), plays one detailed day after each
## span, and saves and reloads once midway. Script errors are found by the
## caller grepping the output; this returns the invariants it checked.
const Campaign = preload("res://scripts/sim/campaign.gd")
const CampaignState = preload("res://scripts/sim/campaign_state.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const Meditation = preload("res://tools/checks/meditation.gd")

const QUIET: Array[String] = ["sleeping", "cultivating", "recovering", "facing_heaven", "praying"]


## {problem: "" or why, report: {...}}.
static func run(seed: int, years: int, span: int) -> Dictionary:
	var valley: Dictionary = Meditation.valley(seed)
	var campaign = load("res://scripts/sim/campaign.gd").new()
	campaign.world_seed = valley.sim.world_seed
	campaign.regions.append({"id": 0, "archetype": "", "name": "region_home_valley", "sim": valley.sim})
	campaign.add_neighbours()
	var report: Dictionary = {"spans": [], "reloaded": false}
	var began: int = Time.get_ticks_msec()
	for done in range(0, years, span):
		var home: RefCounted = campaign.active_sim()
		var t: int = Time.get_ticks_msec()
		_meditate(campaign, float(span) * home.calendar.days_per_season * 4)
		var abstract_ms: int = Time.get_ticks_msec() - t
		t = Time.get_ticks_msec()
		var stuck: int = _detailed_day(campaign)
		var problem: String = _whole(campaign)
		report.spans.append({"years": done + span, "abstract_s": abstract_ms / 1000.0, "day_s": (Time.get_ticks_msec() - t) / 1000.0,
			"people": _people(campaign), "stuck": stuck, "ages": campaign.ages.size(), "deeds": campaign.deeds.size()})
		print("SOAK span %s" % str(report.spans.back()))
		if not problem.is_empty():
			return {"problem": "after %d years: %s" % [done + span, problem], "report": report}
		if stuck > 0:
			return {"problem": "after %d years %d people stood stuck all day" % [done + span, stuck], "report": report}
		if not report.reloaded and done + span >= years / 2:
			var saved: Dictionary = CampaignState.capture(campaign)
			campaign = CampaignState.restore(bytes_to_var(var_to_bytes(saved.sim)), bytes_to_var(var_to_bytes(saved.chunks)), bytes_to_var(var_to_bytes(saved.regions)))
			report.reloaded = true
	report["total_s"] = (Time.get_ticks_msec() - began) / 1000.0
	if campaign.ages.size() < 3:
		return {"problem": "%d years made only %d ages" % [years, campaign.ages.size()], "report": report}
	return {"problem": "", "report": report}


static func _meditate(campaign: RefCounted, days: float) -> void:
	var home: RefCounted = campaign.active_sim()
	var end: int = home.calendar.tick + home.calendar.ticks_for_days(days)
	var model: RefCounted = AbstractWorld.begin(home)
	model.step = AbstractWorld.step_for(days, float(home.calendar.days_per_season * 4))
	home.meditating = true
	while home.calendar.tick < end:
		model.step_hour(home)
		campaign.sync()
	model.finish(home)
	home.meditating = false


## One detailed day; returns how many stood in one place on one errand all
## day doing nothing a person might rightly do all day.
static func _detailed_day(campaign: RefCounted) -> int:
	var home: RefCounted = campaign.active_sim()
	var before: Dictionary = {}
	for agent in home.agents:
		if agent.is_present():
			before[agent.id] = [agent.cell, str(agent.intention.get("goal", {}))]
	campaign.run_ticks(home.calendar.ticks_per_day)
	var stuck: int = 0
	for agent in home.agents:
		if not agent.is_present() or not before.has(agent.id) or agent.activity in QUIET:
			continue
		if before[agent.id] == [agent.cell, str(agent.intention.get("goal", {}))] and not agent.intention.is_empty():
			stuck += 1
	return stuck


## The world is whole: people in every land but the realm, no negative stock.
static func _whole(campaign: RefCounted) -> String:
	for region in campaign.regions:
		var sim: RefCounted = region.sim
		if sim.present_count() == 0 and int(region.id) != int(campaign.realm):
			return "%s is empty" % region.name
		for chest in sim.settlements.chests:
			for resource in sim.settlements.chests[chest]:
				if int(sim.settlements.chests[chest][resource]) < 0:
					return "a chest in %s holds %d %s" % [region.name, int(sim.settlements.chests[chest][resource]), resource]
	return ""


static func _people(campaign: RefCounted) -> Array:
	var counts: Array = []
	for region in campaign.regions:
		counts.append(region.sim.present_count())
	return counts
