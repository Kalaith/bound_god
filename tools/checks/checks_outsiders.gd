extends RefCounted
## M22 Other sects and outsiders: travel between regions, branches abroad,
## guests seeking sanctuary and the master's judgement, outlaws who decide
## for themselves, trade, relations between sects and schisms.
const Sim = preload("res://scripts/sim/sim.gd")
const Campaign = preload("res://scripts/sim/campaign.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Regions = preload("res://scripts/sim/regions.gd")
const Text = preload("res://scripts/core/text.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")
const Branches = preload("res://scripts/sim/branches.gd")
const Guests = preload("res://scripts/sim/guests.gd")
const Outlaws = preload("res://scripts/sim/outlaws.gd")
const Trade = preload("res://scripts/sim/trade.gd")
const Travel = preload("res://scripts/sim/travel.gd")
const Stores = preload("res://tools/checks/stores.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const DeliberationOutlaw = preload("res://scripts/agents/deliberation_outlaw.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const BranchChecks = preload("res://tools/checks/checks_branches.gd")


## Runs a campaign's clock `days` days on, frozen regions in step.
static func _days(campaign: RefCounted, days: float) -> void:
	campaign.run_ticks(campaign.active_sim().calendar.ticks_for_days(days))


## Puts everyone who set out on the road and brings them in at once (the
## road's length is a number; what happens on arrival is what is checked).
static func _arrive_now(campaign: RefCounted) -> void:
	Travel.drain(campaign)
	for trip in campaign.travellers:
		trip.arrive = 0
	Travel.arrive(campaign)


func check_a_leaver_arrives_in_another_region():
	var campaign: RefCounted = Campaign.create(11, {"neighbours": 1})
	var home: RefCounted = campaign.active_sim()
	var leaver: RefCounted = home.agents[0]
	var name: String = leaver.full_name()
	EffectsApply._leave(home, leaver)
	_arrive_now(campaign)
	for region in campaign.regions.slice(1):
		for agent in region.sim.agents:
			if agent.full_name() == name and agent.is_present():
				if agent.settlement_id < 0 or agent.partner >= 0 or not agent.parents.is_empty():
					return "the newcomer kept ties to the old world"
				if not region.sim.chronicle.entries.any(func(e: Dictionary) -> bool: return e.kind == "arrived_from_region"):
					return "the arrival was not chronicled"
				return ""
	return "%s arrived nowhere" % name


## A campaign whose valley holds a sect of ten, its grounds all taken.
static func _crowded_valley() -> Dictionary:
	var valley: Dictionary = BranchChecks._sect(12)
	var campaign = load("res://scripts/sim/campaign.gd").new()
	campaign.world_seed = valley.sim.world_seed
	campaign.regions.append({"id": 0, "archetype": "", "name": "region_home_valley", "sim": valley.sim})
	campaign.add_neighbours()
	var sim: RefCounted = valley.sim
	for index in range(sim.features.grounds.size()):
		var id: int = sim.settlements.create("x", sim.features.grounds[index].center, sim.features.grounds[index].center, sim.calendar.tick)
		sim.settlements.entries[id]["ground"] = index
	sim.settlements.join(sim.agents[0], sim.settlements.on_ground(0))
	for index in range(1, sim.features.grounds.size()):
		var settler: RefCounted = sim.agents[valley.members[valley.members.size() - index]]
		sim.settlements.join(settler, sim.settlements.on_ground(index))
		valley.sect.members.erase(settler.id)
	campaign.sync()
	valley["campaign"] = campaign
	return valley


func check_an_elder_founds_a_branch_abroad():
	var valley: Dictionary = _crowded_valley()
	var campaign: RefCounted = valley.campaign
	var sim: RefCounted = valley.sim
	var elder: RefCounted = sim.agents[int(valley.elders[0])]
	sim.calendar.tick = (sim.calendar.tick / sim.calendar.ticks_per_day) * sim.calendar.ticks_per_day + sim.calendar.ticks_per_hour() * 10
	for region in campaign.regions.slice(1):
		region.sim.calendar.tick = sim.calendar.tick
	var want: Dictionary = Branches.founding(sim, elder)
	if want.is_empty() or not Branches.is_abroad(int(want.ground)):
		return "an elder with no ground at home does not look abroad (%s, abroad %d)" % [str(want), sim.abroad.size()]
	var name: String = elder.full_name()
	Branches.emigrate(sim, elder, int(want.ground), int(want.cause))
	if elder.is_present():
		return "the emigrant stayed"
	_arrive_now(campaign)
	var region: RefCounted = campaign.sim_of(int(want.ground) / Branches.ABROAD)
	var settlement: int = region.settlements.on_ground(int(want.ground) % Branches.ABROAD)
	var branch: Dictionary = region.sects.in_settlement(settlement) if settlement >= 0 else {}
	if branch.is_empty() or branch.get("parent_abroad", {}).is_empty() or Branches.cutting_of(region, settlement).is_empty():
		return "no branch with its cutting abroad (settlement %d, sect %s)" % [settlement, str(branch.keys())]
	if region.agents[int(branch.master)].full_name() != name:
		return "the branch's master is not the elder"
	if valley.sect.get("abroad", []).is_empty():
		return "the parent sect does not know its branch abroad"
	return ""


## A guest from the marsh waits in the valley; the valley's sect is open or closed.
static func _guest(open: bool) -> Dictionary:
	var valley: Dictionary = BranchChecks._sect(10)
	var sim: RefCounted = valley.sim
	var guest: RefCounted = sim.agents[int(valley.members[5])]
	valley.sect.members.erase(guest.id)
	guest.cultivation.sect_id = -1
	guest.cultivation.progress = CultivationState.needed(guest.cultivation)
	guest.cultivation.peak_tick = sim.calendar.tick - sim.calendar.ticks_per_day * 5
	Guests.welcome(sim, guest, {"from": 1, "agent": 3, "sect": {"id": 1, "name": "sect_name|sect_adj_misty|sect_noun_lotus", "faction": "lotus_hall"}, "relation": 20.0})
	var d: Dictionary = valley.sect.doctrine
	d.openness = 0.9 if open else 0.1
	d.mercy = 0.8 if open else 0.2
	d.secrecy = 0.1 if open else 0.95
	valley["guest"] = guest
	return valley


func check_the_master_judges_a_guest_both_ways():
	for open in [true, false]:
		var valley: Dictionary = _guest(open)
		var sim: RefCounted = valley.sim
		var guest: RefCounted = valley.guest
		var master: RefCounted = sim.agents[int(valley.sect.master)]
		sim.calendar.tick = (sim.calendar.tick / sim.calendar.ticks_per_day) * sim.calendar.ticks_per_day + sim.calendar.ticks_per_hour() * 10
		var options: Array = []
		DeliberationCultivation.add(sim, guest, options)
		if options.any(func(c: Dictionary) -> bool: return int(c.goal.kind) == Goals.Kind.BREAKTHROUGH):
			return "a guest not yet admitted weighs facing Heaven"
		options = []
		DeliberationCultivation.add(sim, master, options)
		if not options.any(func(c: Dictionary) -> bool: return int(c.goal.kind) == Goals.Kind.ADMIT_GUEST):
			return "the master does not think to receive the guest"
		Guests.receive(sim, master, guest)
		var admitted: int = int(guest.backstory.guest.admitted)
		if admitted != (1 if open else 0):
			return "an %s sect %s the guest" % ["open" if open else "closed", "refused" if admitted == 0 else "admitted"]
		var entry: Dictionary = sim.chronicle.entries.back()
		if not str(entry.cause).begins_with("cause_guest_") or (open and entry.kind != "guest_admitted") or (not open and entry.kind != "guest_refused"):
			return "the judgement was chronicled as %s (%s)" % [entry.kind, entry.cause]
		if sim.outbound.is_empty() or str(sim.outbound.back().kind) != "relation":
			return "the judgement did not reach the guest's sect"
	return ""


func check_an_outlaw_raids_and_falls_back():
	var sim: RefCounted = Sim.create(11)
	Stores.fill(sim, 2, {"berries": 30, "wood": 25})
	var band: Dictionary = {"id": 1, "name": "x", "settlement_id": 2, "members": [], "loot": {}, "desecrated": false, "defenders": 0, "state": "raiding"}
	sim.raids.bands[1] = band
	var edge: Vector3i = sim.nav.nearest_walkable(sim.settlements.entries[2].camp + Vector3i(12, 0, 0), 6)
	band.members.append(Outlaws.spawn(sim, band, edge, false))
	var outlaw: RefCounted = sim.agents.back()
	if not DeliberationOutlaw.fall_back(sim, outlaw).is_empty():
		return "a fresh outlaw falls back (%s)" % DeliberationOutlaw.fall_back(sim, outlaw)
	if int(DeliberationOutlaw.candidates(sim, outlaw)[0].goal.kind) != Goals.Kind.RAID:
		return "a fresh outlaw does not raid"
	outlaw.health.hp = 30.0
	if DeliberationOutlaw.fall_back(sim, outlaw) != "cause_outlaw_hurt":
		return "a wounded outlaw does not fall back"
	outlaw.health.hp = 100.0
	for i in range(2):
		var defender: RefCounted = sim.agents[sim.settlements.entries[2].residents[i]]
		defender.cell = outlaw.cell + Vector3i(1, 0, i)
		defender.activity = "fighting"
	sim._refresh_agent_buckets()
	if not DeliberationOutlaw.fall_back(sim, outlaw).begins_with("cause_defenders"):
		return "an outnumbered outlaw stands (%s)" % DeliberationOutlaw.fall_back(sim, outlaw)
	for agent in sim.agents:
		if agent.activity == "fighting":
			agent.activity = "idle"
	# At the stores, they take what they can carry.
	outlaw.cell = sim.settlements.store_access(sim, 2, outlaw.cell)
	Outlaws.loot(sim, outlaw)
	if outlaw.carrying.is_empty() or DeliberationOutlaw.fall_back(sim, outlaw) != "cause_raid_done":
		return "a looting outlaw took nothing or stays on"
	if outlaw.carrying.is_empty():
		pass
	sim.threats.hit(sim, int(outlaw.backstory.outlaw.proxy), 1000.0, sim.agents[0])
	if outlaw.is_present() or sim.threats.exists(int(outlaw.backstory.outlaw.proxy)):
		return "an outlaw struck down still stands"
	return ""


func check_a_trade_pays_with_what_is_spare():
	var sim: RefCounted = Sim.create(11)
	Stores.fill(sim, 2, {"wood": 40, "berries": 10})
	var deal: Dictionary = Trade.exchange(sim, 2, {"herb": 6, "ore": 4})
	if int(deal.got.get("herb", 0)) <= 0 or int(deal.gave.get("wood", 0)) <= 0:
		return "nothing was traded for spare wood (%s)" % str(deal)
	var values: Dictionary = Regions.config().trade.values
	var given: float = 0.0
	for resource in deal.gave:
		given += float(values[resource]) * int(deal.gave[resource])
	var got: float = 0.0
	for resource in deal.got:
		got += float(values[resource]) * int(deal.got[resource])
	if given + 0.01 < got:
		return "the settlement paid %.1f for %.1f" % [given, got]
	var poor: RefCounted = Sim.create(11)
	if not Trade.exchange(poor, 1, {"herb": 6}).got.is_empty():
		return "a settlement with nothing spare bought goods"
	return ""


func check_relations_cross_lines_and_are_chronicled():
	var campaign: RefCounted = Campaign.create(11)
	var marsh: RefCounted = campaign.sim_of(1)
	var pass_sim: RefCounted = campaign.sim_of(2)
	var a: int = int(marsh.sects.in_settlement(1).id)
	var b: int = int(pass_sim.sects.in_settlement(1).id)
	var start: float = campaign.relations.score(campaign, 1, a, 2, b)
	campaign.relations.change(campaign, 1, a, 2, b, 100.0 - start, "cause_trader")
	if campaign.relations.standing_of(campaign.relations.score(campaign, 1, a, 2, b)) != "friendly":
		return "the sects are not friendly after a deep change"
	for sim in [marsh, pass_sim]:
		if not sim.chronicle.entries.any(func(e: Dictionary) -> bool: return e.kind == "relation_friendly"):
			return "the friendship was not chronicled in both regions"
	campaign.relations.change(campaign, 1, a, 2, b, -200.0, "cause_guest_refuse_secret")
	if campaign.relations.standing_of(campaign.relations.score(campaign, 1, a, 2, b)) != "hostile":
		return "the sects are not hostile after a deep change"
	return ""


func check_a_feud_splits_the_sect():
	var valley: Dictionary = BranchChecks._sect(10)
	var sim: RefCounted = valley.sim
	var elder: RefCounted = sim.agents[int(valley.elders[0])]
	var master: RefCounted = sim.agents[int(valley.sect.master)]
	elder.personality.leadership = -0.5
	elder.cultivation.drive = 0.1
	for id in valley.members.slice(9):
		valley.sect.members.erase(id)
	sim.calendar.tick = (sim.calendar.tick / sim.calendar.ticks_per_day) * sim.calendar.ticks_per_day + sim.calendar.ticks_per_hour() * 10
	if not Branches.founding(sim, elder).is_empty():
		return "a content elder at peace wants to leave"
	elder.beliefs.relation(master.id).opinion = -50.0
	master.beliefs.relation(elder.id).opinion = -50.0
	var want: Dictionary = Branches.founding(sim, elder)
	if want.is_empty() or int(want.cause) != Branches.Cause.SCHISM:
		return "an elder at odds with the master does not leave (%s)" % str(want)
	elder.carrying = {"resource": "wood", "amount": 1.0}
	elder.cell = sim.nav.nearest_walkable(sim.features.grounds[int(want.ground)].center, 4)
	EffectsApply._settle(sim, elder, int(want.ground), Branches.Cause.SCHISM)
	var place: int = sim.settlements.on_ground(int(want.ground))
	var rival: Dictionary = sim.sects.in_settlement(place)
	if rival.is_empty() or int(rival.get("broke_from", -1)) != int(valley.sect.id) or int(rival.get("parent", -1)) >= 0 or rival.has("branch"):
		return "the schism made %s" % str(rival)
	if not sim.chronicle.entries.any(func(e: Dictionary) -> bool: return e.kind == "sect_split"):
		return "the split was not chronicled"
	return ""


## Exit (plan M22): on seed 11 with a sect at the tree whose people know the
## god (its grounds at home taken), within 40 days headless a guest comes
## seeking sanctuary and the master or the tree's openness decides, an
## outlaw band raids by its own deliberation, a trader trades, an elder
## carries a cutting to another region, and the god steps through to the
## cutting there once it wakes, and comes home after the cooldown.
func long_check_the_lands_beyond_the_valley():
	var valley: Dictionary = _crowded_valley()
	var campaign: RefCounted = valley.campaign
	var sim: RefCounted = valley.sim
	for agent in sim.agents:
		if agent.is_present():
			agent.faith.knows = true
			agent.faith.devotion = 75.0
	var seen: Dictionary = {}
	var crossed: bool = false
	var home_again: bool = false
	for day in range(40):
		_days(campaign, 1.0)
		for region in campaign.regions:
			for entry in region.sim.chronicle.entries:
				if entry.kind in ["guest_arrived", "guest_admitted", "guest_refused", "guest_admitted_unasked", "raid_begins", "raid_over", "raid_over_desecrated",
						"raid_turned_back", "traded", "branch_founded_abroad", "guest_came_home"] and not seen.has(entry.kind):
					seen[entry.kind] = day
					print("      day %d (%s): %s %s" % [day, region.name, entry.kind, str(entry.cause)])
		if not crossed and seen.has("branch_founded_abroad"):
			for entry in campaign.shrines():
				if int(entry.region) > 0 and str(entry.shrine.kind) == "cutting" and str(entry.shrine.state) == "active":
					sim.faith.current(sim).favour = 60.0
					var result: Dictionary = campaign.transfer(int(entry.region), int(entry.shrine.id))
					if not result.ok:
						return "the god could not step through to the cutting abroad (%s)" % str(result)
					crossed = true
					print("      day %d: the god stepped through to %s" % [day, entry.shrine.name])
					break
		elif crossed and not home_again and campaign.transfer_refusal(0, 1) == "":
			campaign.active_sim().faith.current(campaign.active_sim()).favour = 40.0
			home_again = campaign.transfer(0, 1).ok
		var guest_done: bool = seen.has("guest_admitted") or seen.has("guest_refused") or seen.has("guest_admitted_unasked")
		if crossed and home_again and guest_done and seen.has("raid_begins") and seen.has("traded"):
			return ""
	return "after 40 days: %s, crossed %s, home %s" % [str(seen), crossed, home_again]


## Exit, second half (plan M22): fifty meditated years keep every region
## populated within the caps, each change chronicled with a cause.
func long_check_fifty_years_of_the_lands():
	var Meditation = load("res://tools/checks/meditation.gd")
	var AbstractWorld = load("res://scripts/sim/abstract/abstract_world.gd")
	var valley: Dictionary = Meditation.valley(11)
	var campaign = load("res://scripts/sim/campaign.gd").new()
	campaign.world_seed = valley.sim.world_seed
	campaign.regions.append({"id": 0, "archetype": "", "name": "region_home_valley", "sim": valley.sim})
	campaign.add_neighbours()
	var home: RefCounted = valley.sim
	var start: int = home.calendar.tick
	var days: float = 50.0 * home.calendar.days_per_season * 4
	var end: int = home.calendar.tick + home.calendar.ticks_for_days(days)
	var began: int = Time.get_ticks_msec()
	var model: RefCounted = AbstractWorld.begin(home)
	model.step = AbstractWorld.step_for(days, float(home.calendar.days_per_season * 4))
	home.meditating = true
	while home.calendar.tick < end:
		model.step_hour(home)
		campaign.sync()
	model.finish(home)
	home.meditating = false
	var counts: Dictionary = {}
	var total: int = 0
	for region in campaign.regions:
		var people: int = region.sim.present_count()
		total += people
		var cap: int = region.sim.birth_cap() + int(Regions.number("region_cap"))
		var kinds: Dictionary = {}
		for entry in region.sim.chronicle.since(start):
			if entry.kind in ["guest_arrived", "guest_admitted", "guest_refused", "traded", "raid_begins", "branch_founded_abroad", "arrived_from_region",
					"sect_split", "relation_friendly", "relation_hostile", "school_taken", "schism"]:
				kinds[entry.kind] = int(kinds.get(entry.kind, 0)) + 1
		counts[region.name] = {"people": people, "events": kinds}
		# Nobody lives in the hidden realm; visitors come and go (M23).
		if people == 0 and int(region.id) != int(campaign.realm):
			return "%s emptied in fifty years" % region.name
		if people > cap:
			return "%s holds %d people, past its cap" % [region.name, people]
	print("      %s; %d people in all; %.1f s" % [str(counts), total, (Time.get_ticks_msec() - began) / 1000.0])
	if total > int(Regions.number("world_cap")):
		return "the world holds %d, past its cap" % total
	# M23's exit rides on the same fifty years: ages, deeds, epilogue, export.
	var SagaText = load("res://scripts/presentation/ui/saga_text.gd")
	var ChronicleExport = load("res://scripts/presentation/ui/chronicle_export.gd")
	var ages: Array = campaign.ages.map(func(a: Dictionary) -> String: return "%s(%s) day %d" % [a.name, a.arg, a.day])
	print("      ages %s; deeds %s" % [str(ages), str(campaign.deeds)])
	if campaign.ages.size() < 3 or campaign.deeds.size() < 3:
		return "fifty years made %d ages and %d deeds" % [campaign.ages.size(), campaign.deeds.size()]
	var stats: Dictionary = load("res://scripts/sim/statistics.gd").of(campaign)
	var epilogue: String = "
".join(SagaText.epilogue(campaign, false))
	if not epilogue.contains(Text.format("saga_stat", {"name": Text.label("stat_births"), "value": int(stats.births)})):
		return "the epilogue's numbers do not agree with the statistics"
	var written: String = ChronicleExport.markdown(campaign)
	for age in campaign.ages:
		if not written.contains(SagaText._sentence(SagaText.age_name(age))):
			return "the export lacks %s" % SagaText.age_name(age)
	return ""
