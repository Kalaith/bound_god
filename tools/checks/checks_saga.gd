extends RefCounted
## M23 Campaign shape: new-world options, named ages, deeds, statistics, the
## epilogue on fading, the chronicle export, the warding formation and
## expeditions into the hidden realm.
const Campaign = preload("res://scripts/sim/campaign.gd")
const CampaignState = preload("res://scripts/sim/campaign_state.gd")
const Ages = preload("res://scripts/sim/ages.gd")
const Deeds = preload("res://scripts/sim/deeds.gd")
const Statistics = preload("res://scripts/sim/statistics.gd")
const Expeditions = preload("res://scripts/sim/expeditions.gd")
const Travel = preload("res://scripts/sim/travel.gd")
const Outlaws = preload("res://scripts/sim/outlaws.gd")
const TreeAbilities = preload("res://scripts/sim/tree_abilities.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const DeliberationOutlaw = preload("res://scripts/agents/deliberation_outlaw.gd")
const ChronicleExport = preload("res://scripts/presentation/ui/chronicle_export.gd")
const Text = preload("res://scripts/core/text.gd")


## A campaign of the valley alone (fast to make).
static func _valley() -> RefCounted:
	return Campaign.create(11, {"neighbours": 0})


static func _note(sim: RefCounted, kind: String, args: Dictionary = {}, cause: String = "") -> void:
	sim.chronicle.add(sim.calendar.tick, sim.calendar.day(), kind, "Tree Hollow", args, cause)


func check_new_world_options_reach_the_campaign():
	var campaign: RefCounted = Campaign.create(11, {"neighbours": 0, "outlaws": false, "pace": 1.2})
	var home: RefCounted = campaign.active_sim()
	if campaign.regions.size() != 1 or home.options.get("outlaws", true) or absf(home.pace() - 1.2) > 0.001:
		return "the options did not reach the world (%d regions, %s)" % [campaign.regions.size(), str(home.options)]
	home.calendar.tick = home.calendar.ticks_per_day * 11
	for i in range(8):
		home.director.daily(home)
		home.calendar.tick += home.calendar.ticks_per_day
	if not home.raids.bands.is_empty():
		return "outlaws came to a world begun without them"
	var saved: Dictionary = CampaignState.capture(campaign)
	var back: RefCounted = CampaignState.restore(bytes_to_var(var_to_bytes(saved.sim)), bytes_to_var(var_to_bytes(saved.chunks)), bytes_to_var(var_to_bytes(saved.regions)))
	if back.options != campaign.options or back.regions.size() != 1:
		return "the options were not saved"
	return ""


func check_ages_turn_on_their_rules():
	var campaign: RefCounted = _valley()
	var home: RefCounted = campaign.active_sim()
	if campaign.ages.size() != 1 or str(campaign.ages[0].name) != "age_first":
		return "the campaign did not begin with its first age"
	_note(home, "sect_founded", {"sect": "sect_name|sect_adj_quiet|sect_noun_bark"})
	_note(home, "sect_founded", {"sect": "sect_name|sect_adj_iron|sect_noun_root"})
	_note(home, "sect_master", {"name": "Ree Cobb"})
	_note(home, "tree_grew", {"phase": "phase_spirit_root"})
	_note(home, "trader_came", {})
	Ages.daily(campaign)
	var names: Array = campaign.ages.map(func(a: Dictionary) -> String: return str(a.name))
	if names != ["age_first", "age_sect", "age_master", "age_phase"]:
		return "ages %s" % str(names)
	if str(campaign.ages[2].arg) != "Ree Cobb" or not home.chronicle.entries.any(func(e: Dictionary) -> bool: return e.kind == "age_began"):
		return "an age was not named from its turning or not chronicled"
	for i in range(4):
		_note(home, "death", {"name": "x"}, "cause_starvation")
	Ages.daily(campaign)
	if str(campaign.ages.back().name) != "age_famine":
		return "a famine did not begin the Long Hunger (%s)" % str(campaign.ages.back().name)
	return ""


func check_deeds_are_detected_and_chronicled():
	var campaign: RefCounted = _valley()
	var home: RefCounted = campaign.active_sim()
	for deed in Deeds.catalog():
		if not Deeds.CHECKS.has(str(deed.check)) or not Text.has("deed_" + str(deed.id)) or not Text.has("deed_help_" + str(deed.id)):
			return "deed %s has no detector or no words" % str(deed.id)
	Deeds.daily(campaign)
	if not campaign.deeds.is_empty():
		return "deeds done at the start: %s" % str(campaign.deeds)
	for i in range(3):
		_note(home, "sect_master", {"name": "x"})
	_note(home, "raid_turned_back", {"band": "x"})
	home.agents[0].cultivation.realm = 3
	Ages.daily(campaign)
	Deeds.daily(campaign)
	for id in ["three_masters", "raid_repelled", "core_formation"]:
		if not campaign.deeds.has(id):
			return "deed %s was not seen (%s)" % [id, str(campaign.deeds)]
	if not home.chronicle.entries.any(func(e: Dictionary) -> bool: return e.kind == "deed_done"):
		return "the deeds were not chronicled"
	return ""


func check_statistics_agree_with_the_chronicle():
	var campaign: RefCounted = _valley()
	var home: RefCounted = campaign.active_sim()
	var before: Dictionary = Statistics.of(campaign)
	_note(home, "birth", {})
	_note(home, "death", {}, "cause_wounds")
	_note(home, "death", {}, "cause_starvation")
	_note(home, "trial_passed", {})
	var after: Dictionary = Statistics.of(campaign)
	if int(after.births) - int(before.births) != 1 or int(after.deaths) - int(before.deaths) != 2 or int(after.trials_passed) - int(before.trials_passed) != 1:
		return "the numbers do not follow the chronicle (%s)" % str(after)
	if int(after.deaths_by.get("cause_starvation", 0)) < 1:
		return "deaths are not counted by cause"
	if int(after.people) != home.present_count():
		return "people now %d, the world holds %d" % [int(after.people), home.present_count()]
	return ""


func check_the_god_fades_when_nobody_believes():
	var campaign: RefCounted = _valley()
	var home: RefCounted = campaign.active_sim()
	if campaign.faded():
		return "a waking god has faded"
	home.god.dormant = true
	for agent in home.agents:
		agent.faith.knows = false
	if not campaign.faded():
		return "a dormant god nobody believes in has not faded"
	home.agents[0].faith.knows = true
	home.agents[0].faith.devotion = 60.0
	if campaign.faded():
		return "a god with a believer has faded"
	return ""


func check_the_chronicle_is_written_down_by_age():
	var campaign: RefCounted = _valley()
	var home: RefCounted = campaign.active_sim()
	_note(home, "sect_founded", {"sect": "sect_name|sect_adj_quiet|sect_noun_bark"})
	Ages.daily(campaign)
	var text: String = ChronicleExport.markdown(campaign)
	if not text.contains("## The Age of First Seeds") or not text.contains("## The Age of the Quiet Bark Sect") or not text.contains(Text.label("region_home_valley")):
		return "the export lacks its ages or regions:\n" + text.substr(0, 400)
	return ""


func check_the_ward_turns_back_outlaws_and_wolves():
	var campaign: RefCounted = _valley()
	var home: RefCounted = campaign.active_sim()
	var tree: Vector3i = home.features.sacred_tree
	var near: Vector3i = home.nav.nearest_walkable(tree + Vector3i(6, 0, 0), 4)
	if TreeAbilities.warded(home, near):
		return "the tree wards before it has the formation"
	home.tree_growth.unlocks.append("warding_formation")
	if not TreeAbilities.warded(home, near) or TreeAbilities.warded(home, home.nav.nearest_walkable(tree + Vector3i(40, 0, 0), 6)):
		return "the ward does not hold round the trunk alone"
	var band: Dictionary = {"id": 1, "name": "x", "settlement_id": 1, "members": [], "loot": {}, "desecrated": false, "defenders": 0, "state": "raiding"}
	home.raids.bands[1] = band
	band.members.append(Outlaws.spawn(home, band, near, false))
	if DeliberationOutlaw.fall_back(home, home.agents.back()) != "cause_formation":
		return "an outlaw inside the ward stands (%s)" % DeliberationOutlaw.fall_back(home, home.agents.back())
	return ""


func check_an_expedition_goes_into_the_realm_and_comes_out():
	var campaign: RefCounted = _valley()
	var home: RefCounted = campaign.active_sim()
	home.tree_growth.unlocks.append("root_realm")
	campaign.sync()
	if campaign.realm < 0 or campaign.sim_of(campaign.realm).faith.shrines.is_empty():
		return "the realm did not open, or has no root heart"
	var agent: RefCounted = home.agents[0]
	agent.cultivation = CultivationState.fresh(0.5, "none", 0.6)
	agent.cultivation.realm = 1
	Expeditions.set_out(home, agent)
	Travel.drain(campaign)
	Travel.arrive(campaign)
	var realm: RefCounted = campaign.sim_of(campaign.realm)
	var visitor: RefCounted = realm.agents.back()
	if not Expeditions.is_visitor(visitor) or not visitor.is_present():
		return "nobody arrived in the realm"
	visitor.cultivation.progress = 50.0
	visitor.backstory.expedition.until = realm.calendar.tick
	Expeditions.daily(realm)
	Travel.drain(campaign)
	Travel.arrive(campaign)
	if visitor.is_present() and agent.life == "away":
		return "the visitor did not come out"
	if agent.life == "present" and float(agent.cultivation.progress) < 50.0:
		return "the cultivation the realm gave did not come home"
	if not home.chronicle.entries.any(func(e: Dictionary) -> bool: return e.kind in ["realm_returned", "death"]):
		return "the return was not chronicled"
	return ""
