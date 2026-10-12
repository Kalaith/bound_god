extends RefCounted
## Travel between regions (M22). Each world records who sets out for another
## region (`sim.outbound`): people leaving for good, and elders and their
## followers carrying a cutting to a ground abroad. The campaign drains those
## records as it keeps the regions in step and, `regions.travel_days` later,
## the traveller arrives in the other region as a person of that world (a new
## id there; their own record kept, ties to the old world let go). Leavers
## go to the neighbouring region with the most room; emigrants to the ground
## they set out for, where they found or join a branch. Every arrival is
## chronicled in the region it reaches. Order: regions by id, then records
## in the order they were made.
const Agent = preload("res://scripts/agents/agent.gd")
const Beliefs = preload("res://scripts/agents/beliefs.gd")
const Population = preload("res://scripts/sim/population.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const Branches = preload("res://scripts/sim/branches.gd")
const Regions = preload("res://scripts/sim/regions.gd")
const Guests = preload("res://scripts/sim/guests.gd")
const Expeditions = preload("res://scripts/sim/expeditions.gd")


## Takes what every world has sent out and puts it on the road.
static func drain(campaign: RefCounted) -> void:
	for region in campaign.regions:
		var sim: RefCounted = region.sim
		for record in sim.outbound:
			var to: int = int(record.get("region", -1))
			if str(record.kind) == "relation":
				# Word of a guest admitted or refused reaches the other sect at once.
				campaign.relations.change(campaign, int(region.id), int(record.sect), int(record.other_region), int(record.other_sect), float(record.amount), str(record.cause))
				continue
			if str(record.kind) == "leaver":
				to = _roomiest(campaign, int(region.id))
			if to == -2:
				to = int(campaign.realm)
			if to < 0 or to >= campaign.regions.size() or to == int(region.id):
				continue
			var trip: Dictionary = record.duplicate(true)
			if str(record.kind) == "guest":
				trip["relation"] = campaign.relations.score(campaign, int(region.id), int(record.sect.id), 0, valley_sect(campaign))
			trip["from"] = int(region.id)
			trip["region"] = to
			# The realm in the roots lies a step away, not a road (M23).
			var road: bool = not str(record.kind) in ["expedition", "expedition_home"]
			trip["arrive"] = sim.calendar.tick + (sim.calendar.ticks_for_days(Regions.number("travel_days")) if road else 0)
			campaign.travellers.append(trip)
		sim.outbound.clear()


## The neighbouring region with the most room under the cap, or -1.
static func _roomiest(campaign: RefCounted, from: int) -> int:
	var best: int = -1
	var room: int = 0
	for region in campaign.regions:
		var id: int = int(region.id)
		# Nobody settles in the hidden realm (M23).
		if id == from or id == int(campaign.realm):
			continue
		var left: int = int(Regions.number("region_cap")) - region.sim.present_count()
		if left > room:
			best = id
			room = left
	return best


## Travellers whose road has reached its end arrive.
static func arrive(campaign: RefCounted) -> void:
	var keep: Array = []
	for trip in campaign.travellers:
		var sim: RefCounted = campaign.sim_of(int(trip.region))
		if sim == null or int(trip.arrive) > sim.calendar.tick:
			keep.append(trip)
			continue
		if str(trip.kind) == "returning":
			Guests.come_home(sim, trip)
			continue
		if str(trip.kind) == "expedition_home":
			Expeditions.come_home(sim, trip)
			continue
		var agent: RefCounted = _person(sim, trip.record)
		if str(trip.kind) == "emigrant":
			_settle_abroad(campaign, sim, agent, trip)
		elif str(trip.kind) == "guest":
			_guest(sim, agent, trip)
		elif str(trip.kind) == "expedition":
			var camp: Vector3i = sim.settlements.entries[1].camp
			Population.arrive(sim, agent, sim.nav.nearest_walkable(camp, 5), 1, "")
			Expeditions.arrive(sim, agent, trip)
		else:
			_newcomer(campaign, sim, agent, trip)
		if campaign.is_frozen(int(trip.region)) and agent.is_present():
			AbstractWorld.freeze(agent)
	campaign.travellers = keep


## The traveller as a person of the world they reach: their nature, skills,
## cultivation and faith kept; their home, ties and what they knew of the
## old world's places let go.
static func _person(sim: RefCounted, record: Dictionary) -> RefCounted:
	var agent: RefCounted = Agent.from_dict(record)
	agent.id = sim.agents.size()
	agent.beliefs = Beliefs.new()
	agent.beliefs.known_templates = record.get("beliefs", {}).get("known_templates", []).duplicate()
	agent.partner = -1
	agent.home = -1
	agent.parents = []
	agent.settlement_id = -1
	agent.intention = {}
	agent.path.clear()
	agent.inbox.clear()
	agent.help_task = {}
	agent.mental_break = {}
	agent.carrying = {}
	agent.life = "present"
	agent.low_mood_ticks = 0
	if not agent.cultivation.is_empty():
		agent.cultivation.teacher = -1
		agent.cultivation.students = []
		agent.cultivation.sect_id = -1
	if agent.faith.has("shrine_id"):
		agent.faith.shrine_id = -1
	return agent


## The valley's sect (at the tree's settlement), or -1.
static func valley_sect(campaign: RefCounted) -> int:
	var home: RefCounted = campaign.sim_of(0)
	var hollow: int = home.settlements.at_cell(home.features.get("sacred_tree", Vector3i.ZERO))
	return int(home.sects.in_settlement(hollow).get("id", -1)) if home.sects != null else -1


## A guest reaches the tree's settlement and waits to be received.
static func _guest(sim: RefCounted, agent: RefCounted, trip: Dictionary) -> void:
	var hollow: int = sim.settlements.at_cell(sim.features.get("sacred_tree", Vector3i.ZERO))
	if hollow < 0:
		return
	var camp: Vector3i = sim.settlements.entries[hollow].camp
	var cell: Vector3i = sim.nav.nearest_walkable(camp + Vector3i(-2, 0, 2), 6)
	Population.arrive(sim, agent, cell if cell.x >= 0 else camp, hollow, "")
	Guests.welcome(sim, agent, trip)


## Whether each region knows of the tree's sanctuary (someone there knows the
## god, or the god's renown has spread) and its sect is not hostile to the
## valley's (`sim.sanctuary`).
static func share_sanctuary(campaign: RefCounted) -> void:
	var renown: int = int(campaign.sim_of(0).god.renown)
	var valley: int = valley_sect(campaign)
	for region in campaign.regions.slice(1):
		if int(region.id) == int(campaign.realm):
			continue
		var sim: RefCounted = region.sim
		var known: bool = renown >= int(Guests.config().renown_known)
		for agent in sim.agents:
			if known:
				break
			known = agent.is_present() and agent.faith.get("knows", false)
		var sect: Dictionary = sim.sects.in_settlement(1) if sim.sects != null else {}
		var hostile: bool = not sect.is_empty() and valley >= 0 			and campaign.relations.standing_of(campaign.relations.score(campaign, int(region.id), int(sect.id), 0, valley)) == "hostile"
		sim.sanctuary = {"open": known and not hostile}


## Which regions send traders to each region: every other region with people,
## a trader's goods (its archetype's, or the valley's), its sect's manual and
## whether its sect is friendly with the visited region's (`sim.traders`).
static func share_traders(campaign: RefCounted) -> void:
	for region in campaign.regions:
		var sim: RefCounted = region.sim
		if int(region.id) == int(campaign.realm):
			sim.traders = []
			continue
		var here: Dictionary = sim.sects.in_settlement(1) if sim.sects != null else {}
		if int(region.id) == 0:
			here = sim.sects.get_sect(valley_sect(campaign))
		var list: Array = []
		for other in campaign.regions:
			if int(other.id) == int(region.id) or int(other.id) == int(campaign.realm) or other.sim.present_count() == 0:
				continue
			var sect: Dictionary = other.sim.sects.get_sect(valley_sect(campaign)) if int(other.id) == 0 else other.sim.sects.in_settlement(1)
			var score: float = 0.0
			if not here.is_empty() and not sect.is_empty():
				score = campaign.relations.score(campaign, int(region.id), int(here.id), int(other.id), int(sect.id))
			if campaign.relations.standing_of(score) == "hostile":
				continue
			var archetype: Dictionary = Regions.archetype(str(other.archetype))
			var technique: String = ""
			if not sect.is_empty() and not sect.get("manuals", []).is_empty():
				technique = str(sect.manuals[0])
			list.append({"region": int(other.id), "region_name": str(other.name), "goods": archetype.get("goods", Regions.config().home_goods),
				"technique": technique, "sect": int(sect.get("id", -1)), "friendly": campaign.relations.standing_of(score) == "friendly"})
		sim.traders = list


static func _newcomer(campaign: RefCounted, sim: RefCounted, agent: RefCounted, trip: Dictionary) -> void:
	var home: int = 1 if sim.settlements.entries.has(1) else (sim.settlements.ids()[0] if not sim.settlements.ids().is_empty() else -1)
	if home < 0:
		return
	var camp: Vector3i = sim.settlements.entries[home].camp
	var cell: Vector3i = sim.nav.nearest_walkable(camp + Vector3i(2, 0, -2), 6)
	Population.arrive(sim, agent, cell if cell.x >= 0 else camp, home, "arrival")
	sim.chronicle_event("arrived_from_region", home, {"name": agent.full_name(), "region": str(campaign.regions[int(trip.from)].name)},
		"cause_left_home|" + str(campaign.regions[int(trip.from)].name), [agent.id])


## An emigrant reaches the ground they set out for: the first plants the
## cutting and founds a branch of the sect they came from; later ones join.
static func _settle_abroad(campaign: RefCounted, sim: RefCounted, agent: RefCounted, trip: Dictionary) -> void:
	var ground: int = int(trip.ground)
	var camp: Vector3i = sim.nav.nearest_walkable(sim.features.grounds[ground].center, 4)
	agent.cell = camp
	agent.position = Movement.center(camp)
	agent.previous_position = agent.position
	agent.next_deliberation = sim.calendar.tick + agent.id % 3
	sim.agents.append(agent)
	agent.carrying = {"resource": "wood", "amount": 1.0}
	EffectsApply._settle(sim, agent, ground, 0)
	agent.step_result = {}
	var settlement: int = sim.settlements.on_ground(ground)
	if settlement < 0:
		return
	var id: int = Branches.settle_abroad(sim, agent, settlement, int(trip.cause), trip.parent)
	sim.chronicle_event("arrived_from_region", settlement, {"name": agent.full_name(), "region": str(campaign.regions[int(trip.from)].name)},
		"cause_carried_cutting|" + str(campaign.regions[int(trip.from)].name), [agent.id])
	# The sect they came from learns where its branch abroad stands.
	var parent_sim: RefCounted = campaign.sim_of(int(trip.from))
	var parent: Dictionary = parent_sim.sects.get_sect(int(trip.parent.sect))
	if not parent.is_empty() and id > 0:
		var abroad: Array = parent.get("abroad", [])
		abroad.append({"region": int(trip.region), "ground": ground, "sect": id, "founder": int(trip.parent.founder)})
		parent["abroad"] = abroad


## Every free founding ground in the other regions, for a world to know of
## (`sim.abroad`): Array of {region, ground, name, region_name}.
static func share_grounds(campaign: RefCounted) -> void:
	var free: Array = []
	for region in campaign.regions:
		var sim: RefCounted = region.sim
		for index in range(sim.features.get("grounds", []).size()):
			if Branches.ground_free(sim, index) and not _bound_for(campaign, int(region.id), index):
				free.append({"region": int(region.id), "ground": index, "name": str(sim.features.grounds[index].name), "region_name": str(region.name)})
	for region in campaign.regions:
		region.sim.abroad = free.filter(func(entry: Dictionary) -> bool: return int(entry.region) != int(region.id))


## Whether someone is already on the road to found on that ground.
static func _bound_for(campaign: RefCounted, region: int, ground: int) -> bool:
	for trip in campaign.travellers:
		if str(trip.kind) == "emigrant" and int(trip.region) == region and int(trip.ground) == ground and int(trip.cause) > 0:
			return true
	return false
