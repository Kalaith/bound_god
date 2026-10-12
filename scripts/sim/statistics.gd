extends RefCounted
## The campaign's numbers (M23), worked out when asked from every region's
## chronicle and state: nothing is counted on the side, so the numbers can
## never disagree with the chronicle the player reads.

## Chronicle kinds counted, by the statistic they feed.
const COUNTED: Dictionary = {
	"births": ["birth"], "arrivals": ["arrival_migrants", "arrival_seekers", "arrived_from_region"], "departures": ["departed"],
	"trials_passed": ["trial_passed"], "trials_injured": ["trial_injured"], "trials_died": ["trial_died"], "trials_defied": ["trial_defied"],
	"sects": ["sect_founded"], "masters": ["sect_master"], "branches": ["branch_founded", "branch_founded_abroad"], "splits": ["sect_split", "schism"],
	"guests": ["guest_arrived"], "guests_admitted": ["guest_admitted", "guest_admitted_unasked"], "guests_refused": ["guest_refused"],
	"raids": ["raid_begins"], "raids_turned": ["raid_turned_back"], "shrines_fallen": ["shrine_fell"],
	"miracles": ["miracle"], "buildings": ["built"], "trades": ["traded"], "realms": ["realm_reached"],
}


static func of(campaign: RefCounted) -> Dictionary:
	var home: RefCounted = campaign.sim_of(0)
	var start: int = int(campaign.ages[0].tick) if not campaign.ages.is_empty() else 0
	var year_ticks: int = home.calendar.ticks_per_day * home.calendar.days_per_season * 4
	var result: Dictionary = {"years": float(home.calendar.tick - start) / year_ticks, "people": 0, "ever": 0, "deaths": 0, "deaths_by": {},
		"regions": campaign.regions.size(), "ages": campaign.ages.size(), "deeds": campaign.deeds.size()}
	for key in COUNTED:
		result[key] = 0
	var kinds: Dictionary = {}
	for key in COUNTED:
		for kind in COUNTED[key]:
			kinds[kind] = key
	for region in campaign.regions:
		var sim: RefCounted = region.sim
		result.people = int(result.people) + sim.present_count()
		result.ever = int(result.ever) + sim.agents.size()
		for entry in sim.chronicle.entries:
			if int(entry.tick) < start:
				continue
			var kind: String = str(entry.kind)
			if kinds.has(kind):
				result[kinds[kind]] = int(result[kinds[kind]]) + 1
			if kind == "death":
				result.deaths = int(result.deaths) + 1
				var cause: String = str(entry.cause).split("|")[0]
				result.deaths_by[cause] = int(result.deaths_by.get(cause, 0)) + 1
	result["relics"] = home.tree_growth.relics.size() if home.tree_growth != null else 0
	result["phase"] = home.tree_growth.phase_id() if home.tree_growth != null else ""
	return result
