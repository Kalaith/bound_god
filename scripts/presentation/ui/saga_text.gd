extends RefCounted
## The saga as words (M23): the ages, the deeds, the numbers, and the
## epilogue built from them, for the Saga screen, the epilogue screen and the
## exported chronicle. Nothing here is counted: it reads statistics.gd, the
## campaign's ages and deeds, and the chronicles.
const Text = preload("res://scripts/core/text.gd")
const ChronicleText = preload("res://scripts/presentation/ui/chronicle_text.gd")
const Statistics = preload("res://scripts/sim/statistics.gd")
const Deeds = preload("res://scripts/sim/deeds.gd")
const Sects = preload("res://scripts/sim/sects.gd")

## Statistics shown, in order.
const SHOWN: Array[String] = ["people", "ever", "births", "deaths", "arrivals", "departures", "sects", "masters", "branches", "splits",
	"trials_passed", "trials_injured", "trials_died", "trials_defied", "guests", "guests_admitted", "guests_refused", "raids", "raids_turned",
	"shrines_fallen", "miracles", "buildings", "trades", "relics"]


## An age's name, worded.
static func age_name(age: Dictionary) -> String:
	return Text.format(str(age.name), {"arg": ChronicleText.word(str(age.arg))})


static func ages(campaign: RefCounted) -> Array[String]:
	var lines: Array[String] = []
	for i in range(campaign.ages.size()):
		var age: Dictionary = campaign.ages[i]
		var until: String = Text.format("saga_age_until", {"day": int(campaign.ages[i + 1].day)}) if i + 1 < campaign.ages.size() else Text.label("saga_age_now")
		lines.append(Text.format("saga_age_line", {"age": _sentence(age_name(age)), "day": int(age.day), "until": until}))
	return lines


static func deeds(campaign: RefCounted) -> Array[String]:
	var lines: Array[String] = []
	for deed in Deeds.catalog():
		var id: String = str(deed.id)
		if campaign.deeds.has(id):
			lines.append(Text.format("saga_deed_done", {"deed": Text.label("deed_" + id), "day": int(campaign.deeds[id])}))
		else:
			lines.append(Text.format("saga_deed_open", {"deed": Text.label("deed_" + id), "help": Text.label("deed_help_" + id)}))
	return lines


static func numbers(stats: Dictionary) -> Array[String]:
	var lines: Array[String] = [Text.format("saga_years", {"years": "%.1f" % float(stats.years), "ages": int(stats.ages), "deeds": int(stats.deeds)})]
	for key in SHOWN:
		lines.append(Text.format("saga_stat", {"name": Text.label("stat_" + key), "value": int(stats.get(key, 0))}))
	var causes: Array = stats.deaths_by.keys()
	causes.sort()
	for cause in causes:
		lines.append("    " + Text.format("saga_stat", {"name": ChronicleText.cause(str(cause)), "value": int(stats.deaths_by[cause])}))
	return lines


## The epilogue: how long, how it ended, the ages, the deeds, the people
## the god followed, the last master and the tree.
static func epilogue(campaign: RefCounted, faded: bool) -> Array[String]:
	var stats: Dictionary = Statistics.of(campaign)
	var home: RefCounted = campaign.sim_of(0)
	var lines: Array[String] = []
	lines.append(Text.format("epilogue_faded" if faded else "epilogue_closed", {"years": "%.0f" % float(stats.years), "people": int(stats.ever)}))
	lines.append(Text.format("epilogue_tree", {"phase": Text.label("phase_" + str(stats.phase)), "relics": int(stats.relics)}))
	var hollow: int = home.settlements.at_cell(home.features.get("sacred_tree", Vector3i.ZERO))
	var sect: Dictionary = home.sects.in_settlement(hollow) if home.sects != null else {}
	if not sect.is_empty():
		lines.append(Text.format("epilogue_sect", {"sect": Sects.name_of(sect), "master": home.agents[int(sect.master)].full_name(), "members": sect.members.size()}))
	for id in home.god.followed:
		var agent: RefCounted = home.agents[int(id)]
		lines.append(Text.format("epilogue_followed_" + ("alive" if agent.is_present() else str(agent.life)), {"name": agent.full_name(),
			"cause": ChronicleText.cause(str(agent.life_cause)), "realm": Text.label("realm_" + str(_realm(agent)))}))
	lines.append("")
	lines.append_array(ages(campaign))
	lines.append("")
	for id in campaign.deeds:
		lines.append(Text.format("saga_deed_done", {"deed": Text.label("deed_" + str(id)), "day": int(campaign.deeds[id])}))
	lines.append("")
	lines.append_array(numbers(stats))
	return lines


static func _realm(agent: RefCounted) -> String:
	var Data = load("res://scripts/core/data.gd")
	return str(Data.realm(int(agent.cultivation.get("realm", 0))).get("id", "mortal"))


static func _sentence(phrase: String) -> String:
	return phrase.substr(0, 1).to_upper() + phrase.substr(1) if not phrase.is_empty() else phrase
