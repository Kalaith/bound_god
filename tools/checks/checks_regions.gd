extends RefCounted
## M22 Regions: the campaign of the valley and its neighbours, each a world
## of its own, frozen and stepped in lockstep while the god is elsewhere;
## the god stepping between regions; campaign saves.
const Campaign = preload("res://scripts/sim/campaign.gd")
const CampaignState = preload("res://scripts/sim/campaign_state.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Sects = preload("res://scripts/sim/sects.gd")
const FaithPeople = preload("res://scripts/sim/faith_people.gd")
const Regions = preload("res://scripts/sim/regions.gd")
const Miracles = preload("res://scripts/sim/miracles.gd")

## One campaign shared by the checks that only read it (three worlds take
## seconds to make); checks that change it make their own.
static var _shared: RefCounted = null


static func _campaign() -> RefCounted:
	if _shared == null:
		_shared = Campaign.create(11)
	return _shared


## An altar raised in region `id` by its people, who believe; active.
static func _altar(campaign: RefCounted, id: int) -> int:
	var sim: RefCounted = campaign.sim_of(id)
	var settlement: Dictionary = sim.settlements.entries[1]
	var cell: Vector3i = sim.nav.surface(settlement.camp.x - 3, settlement.camp.z + 2)
	sim.set_block(cell, Registry.id("altar"), 0, "npc:0")
	var shrine: Dictionary = sim.faith.get_shrine(int(sim.faith.by_cell[cell]))
	shrine.state = "active"
	shrine.support = 2.0
	return int(shrine.id)


func check_a_new_world_has_neighbouring_regions():
	var campaign: RefCounted = _campaign()
	if campaign.regions.size() != 1 + int(Regions.number("count")):
		return "%d regions" % campaign.regions.size()
	for region in campaign.regions.slice(1):
		var sim: RefCounted = region.sim
		if sim.features.has("sacred_tree") or sim.features.get("wells", []).is_empty():
			return "%s has a tree or no spring" % region.name
		var sect: Dictionary = sim.sects.in_settlement(1)
		if sect.is_empty() or str(sect.get("faction", "")).is_empty() or sim.present_count() < 6:
			return "%s: sect %s, %d people" % [region.name, Sects.name_of(sect), sim.present_count()]
		if sim.structures.built().size() < 4 or sim.settlements.total(1) <= 0:
			return "%s has %d buildings and %d in its stores" % [region.name, sim.structures.built().size(), sim.settlements.total(1)]
		if sim.god.active_shrine_id >= 0 or not sim.faith.shrines.is_empty():
			return "the god is in %s from the start" % region.name
		if not campaign.is_frozen(int(region.id)):
			return "%s runs in detail" % region.name
		for agent in sim.agents:
			if agent.faith.get("knows", false):
				return "someone in %s knows the god" % region.name
	if campaign.is_frozen(0):
		return "the valley is frozen"
	var Sim = load("res://scripts/sim/sim.gd")
	var again: RefCounted = Sim.create(11, {"region": 1, "archetype": str(campaign.regions[1].archetype)})
	again.calendar.tick = campaign.regions[1].sim.calendar.tick
	again.settlements.today = again.calendar.day()
	var fresh = load("res://scripts/sim/abstract/abstract_world.gd").begin(again)
	if again.state_hash() != campaign.regions[1].sim.state_hash():
		return "the marsh differs for the same seed"
	return ""


func check_frozen_regions_keep_step():
	var campaign: RefCounted = _campaign()
	var home: RefCounted = campaign.active_sim()
	var people: Array = []
	for region in campaign.regions:
		people.append(region.sim.present_count())
	campaign.run_ticks(home.calendar.ticks_per_day)
	var step: int = home.calendar.ticks_per_hour() * int(Regions.number("abstract_step"))
	for region in campaign.regions.slice(1):
		var behind: int = home.calendar.tick - region.sim.calendar.tick
		if behind < 0 or behind >= step:
			return "%s is %d ticks behind the valley" % [region.name, behind]
		if region.sim.present_count() == 0:
			return "%s emptied" % region.name
	return ""


func check_the_god_steps_into_another_region_and_back():
	var campaign: RefCounted = Campaign.create(11, {"neighbours": 1})
	var home: RefCounted = campaign.active_sim()
	var tree: Dictionary = home.faith.current(home)
	tree.favour = 60.0
	home.god.add_stock("wood", 7)
	var marsh: RefCounted = campaign.sim_of(1)
	var altar: int = _altar(campaign, 1)
	marsh.faith.shrines[altar].state = "dormant"
	if campaign.transfer_refusal(1, altar) != "transfer_inactive":
		return "a dormant shrine took the god (%s)" % campaign.transfer_refusal(1, altar)
	marsh.faith.shrines[altar].state = "active"
	var result: Dictionary = campaign.transfer(1, altar)
	if not result.ok or campaign.active != 1:
		return "the god did not step through (%s)" % str(result)
	if not campaign.is_frozen(0) or campaign.is_frozen(1):
		return "the valley did not freeze or the marsh did not wake"
	if float(tree.favour) > 60.0 - campaign.cost_to(1) + Regions.number("transfer_cost") + 0.01:
		return "the journey cost %.1f" % (60.0 - float(tree.favour))
	if marsh.god.stock("wood") != 7 or marsh.god.active_shrine_id != altar or home.god.active_shrine_id != -1:
		return "the god did not carry its stock or stand at the altar"
	for agent in marsh.agents:
		if agent.is_present() and not agent.intention.is_empty() and agent.next_deliberation > marsh.calendar.tick + 10:
			return "a thawed person does not deliberate"
	if campaign.transfer_refusal(0, int(tree.id)) != "transfer_cooldown":
		return "the god could go straight back (%s)" % campaign.transfer_refusal(0, int(tree.id))
	# The cooldown passes.
	marsh.god.last_transfer_tick -= Miracles.transfer_cooldown_ticks(marsh)
	marsh.faith.shrines[altar].favour = 40.0
	result = campaign.transfer(0, int(tree.id))
	if not result.ok or campaign.active != 0 or not campaign.is_frozen(1):
		return "the god could not come home (%s)" % str(result)
	return ""


func check_a_god_left_shrineless_goes_to_another_region():
	var campaign: RefCounted = Campaign.create(11, {"neighbours": 1})
	var home: RefCounted = campaign.active_sim()
	var altar: int = _altar(campaign, 1)
	home.god.dormant = true
	campaign.sync()
	if campaign.active != 1 or campaign.sim_of(1).god.active_shrine_id != altar:
		return "a dormant god did not go to the active shrine in another region (active %d)" % campaign.active
	return ""


func check_a_campaign_saves_and_loads():
	var campaign: RefCounted = _campaign()
	campaign.run_ticks(campaign.active_sim().calendar.ticks_per_hour() * 4)
	var saved: Dictionary = CampaignState.capture(campaign)
	var regions: Variant = bytes_to_var(var_to_bytes(saved.regions))
	if not CampaignState.problem(regions).is_empty():
		return "the region file is refused: %s" % CampaignState.problem(regions)
	var restored: RefCounted = CampaignState.restore(bytes_to_var(var_to_bytes(saved.sim)), bytes_to_var(var_to_bytes(saved.chunks)), regions)
	if restored.regions.size() != campaign.regions.size() or restored.active != campaign.active or restored.models.size() != campaign.models.size():
		return "the restored campaign differs in shape"
	for i in range(campaign.regions.size()):
		if restored.regions[i].sim.state_hash() != campaign.regions[i].sim.state_hash():
			return "region %d hashes differently after loading" % i
	campaign.run_ticks(campaign.active_sim().calendar.ticks_per_hour() * 4)
	restored.run_ticks(restored.active_sim().calendar.ticks_per_hour() * 4)
	if restored.state_hash() != campaign.state_hash():
		return "the restored campaign does not continue identically"
	# A valley saved before regions gaining its neighbours: checks_release.gd.
	return ""
