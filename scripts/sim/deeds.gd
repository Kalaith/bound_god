extends RefCounted
## Deeds of the saga (M23): milestones of the long game, a closed list in
## `saga.json` `deeds`, each with a detector over the campaign's state and
## chronicles. A deed is done once, kept with its day and chronicled in the
## valley; none grants anything. Detectors (closed): sect_at_tree, chronicle
## (a kind seen anywhere), chronicle_count (a kind in the valley, n times),
## realm (someone of the valley reached it), relics (kept at once), years, phase.
const Data = preload("res://scripts/core/data.gd")
const Relics = preload("res://scripts/sim/relics.gd")

const CHECKS: Array[String] = ["sect_at_tree", "chronicle", "chronicle_count", "realm", "relics", "years", "phase"]


static func catalog() -> Array:
	return Data.file("saga").deeds


static func daily(campaign: RefCounted) -> void:
	var home: RefCounted = campaign.sim_of(0)
	for deed in catalog():
		if campaign.deeds.has(str(deed.id)) or not done(campaign, deed):
			continue
		campaign.deeds[str(deed.id)] = home.calendar.day()
		home.chronicle_event("deed_done", -1, {"deed": "deed_" + str(deed.id)}, "cause_deed|deed_help_" + str(deed.id))


## Whether a deed's detector holds now.
static func done(campaign: RefCounted, deed: Dictionary) -> bool:
	var home: RefCounted = campaign.sim_of(0)
	match str(deed.check):
		"sect_at_tree":
			var hollow: int = home.settlements.at_cell(home.features.get("sacred_tree", Vector3i.ZERO))
			return home.sects != null and not home.sects.in_settlement(hollow).is_empty()
		"chronicle":
			return int(campaign.kinds_seen.get(str(deed.kind), 0)) > 0
		"chronicle_count":
			return int(campaign.kinds_seen.get("valley:" + str(deed.kind), 0)) >= int(deed.count)
		"realm":
			# Someone of the valley's own (a faction's old masters do not count).
			for agent in home.agents:
				if not agent.cultivation.is_empty() and int(agent.cultivation.get("realm", 0)) >= int(deed.realm):
					return true
			return false
		"relics":
			return home.tree_growth != null and Relics.at(home, Relics.tree_shrine(home)).size() >= int(deed.count)
		"years":
			var start: int = int(campaign.ages[0].tick) if not campaign.ages.is_empty() else 0
			return float(home.calendar.tick - start) / (home.calendar.ticks_per_day * home.calendar.days_per_season * 4) >= float(deed.years)
		"phase":
			return home.tree_growth != null and home.tree_growth.phase_id() == str(deed.phase)
	return false
