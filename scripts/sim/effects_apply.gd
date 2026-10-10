extends RefCounted
## Applies the tick's Effects once, after every agent has acted: world
## actions in push order (lowest id first when two want the same thing),
## then conversations, then message delivery to inboxes.
const Balance = preload("res://scripts/core/balance.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Beliefs = preload("res://scripts/agents/beliefs.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Social = preload("res://scripts/sim/social.gd")
const EffectsBuild = preload("res://scripts/sim/effects_build.gd")
const Text = preload("res://scripts/core/text.gd")

const Need = Personality.Need


static func apply(sim: RefCounted) -> void:
	var effects: RefCounted = sim.effects
	for action in effects.actions:
		var agent: RefCounted = sim.agents[int(action.agent)] if int(action.agent) >= 0 else null
		match str(action.type):
			"drop":
				sim.drop_item(action.cell, action.resource, float(action.amount))
			"take_stock":
				_take_stock(sim, agent, action)
			"deposit":
				_deposit(sim, agent, action)
			"forage":
				_forage(sim, agent, action)
			"harvest":
				_harvest(sim, agent, action)
			"pick_up":
				_pick_up(sim, agent, action)
			"claim_bed":
				_claim_bed(sim, agent, int(action.structure))
			"gift":
				_gift(sim, agent, action)
			"treat":
				_treat(sim, agent, action)
			"join":
				_join(sim, agent, int(action.settlement))
			"attack_threat":
				if sim.threats != null:
					sim.threats.hit(sim, int(action.threat), float(action.damage), agent)
			"prayer":
				sim.faith.record_prayer(sim, agent, int(action.shrine), action.intent)
			"tend":
				var shrine: Dictionary = sim.faith.get_shrine(int(action.shrine))
				if not shrine.is_empty():
					shrine.condition = minf(float(shrine.condition) + float(action.amount), 100.0)
			"leave":
				_leave(sim, agent)
			"plant":
				_plant(sim, agent, action.cell)
			"settle":
				_settle(sim, agent, int(action.ground))
			_:
				EffectsBuild.apply(sim, agent, action)
	for entry in effects.interactions:
		Social.resolve(sim, entry)
	for message in effects.messages:
		var to: int = int(message.to)
		if to >= 0 and to < sim.agents.size() and sim.agents[to].is_present():
			sim.agents[to].inbox.append(message)
	effects.clear()


static func _take_stock(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	var resource: String = action.resource
	if not agent.carrying.is_empty() and agent.carrying.resource != resource:
		agent.step_result = {"took": 0}
		return
	var taken: int = sim.settlements.take(sim, int(action.settlement), resource, int(action.amount), agent.cell)
	if taken > 0:
		agent.carrying = {"resource": resource, "amount": agent.carried(resource) + taken}
	agent.step_result = {"took": taken}
	# Whoever uses the stores sees what is left in them.
	agent.beliefs.stock = sim.settlements.stock_of(int(action.settlement)).duplicate()


static func _deposit(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	if agent.carrying.is_empty():
		agent.step_result = {"stored": 0}
		return
	var resource: String = agent.carrying.resource
	var whole: int = int(floor(float(agent.carrying.amount)))
	var stored: int = sim.settlements.add(sim, int(action.settlement), resource, whole, agent.cell)
	var left: float = float(agent.carrying.amount) - stored
	if left > 0.05:
		agent.carrying.amount = left
		if stored == 0:
			# No chest here has room: set it down loose for later.
			sim.drop_item(agent.cell, resource, left)
			agent.carrying = {}
	else:
		agent.carrying = {}
	agent.step_result = {"stored": stored if stored > 0 else (1 if agent.carrying.is_empty() else 0)}
	agent.beliefs.stock = sim.settlements.stock_of(int(action.settlement)).duplicate()
	sim.note_delivery(agent, resource, stored)


static func _forage(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	var cell: Vector3i = action.cell
	var berries: int = sim.voxels.block_meta(cell)
	var count: int = int(agent.step_result.get("count", 0))
	if sim.voxels.get_block(cell) != Registry.id("berry_bush") or berries <= 0:
		agent.step_result = {"ate": 0, "count": count}
		return
	sim.set_block(cell, Registry.id("berry_bush"), berries - 1, "npc:%d" % agent.id)
	agent.change_need(Need.FOOD, Balance.number("needs.forage_restore"))
	Mind.add(agent, "ate_foraged", sim.calendar.ticks_per_day)
	Mind.remove(agent, "went_hungry")
	agent.step_result = {"ate": 1, "count": count}


## Take one block's yield from a site: trees are felled from the top, and a
## felled tree's leaves fall with its last log.
static func _harvest(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	var id: int = int(action.site)
	var site: Dictionary = sim.sites.get_site(id)
	if site.is_empty() or site.cells.is_empty():
		agent.step_result = {"got": 0}
		return
	var resource: String = sim.sites.resource_of(id)
	if not agent.carrying.is_empty() and agent.carrying.resource != resource:
		agent.step_result = {"got": 0}
		return
	# Trees are felled and boulders broken from the top down, and nobody's
	# floor is taken from under them.
	var cell: Vector3i = Vector3i(-1, -1, -1)
	for candidate in site.cells:
		if Registry.solid[sim.voxels.get_block(candidate)] == 1 and sim.occupied.has(candidate + Vector3i.UP):
			continue
		if cell.x < 0 or (site.kind in ["tree", "rock"] and candidate.y > cell.y):
			cell = candidate
	if cell.x < 0:
		agent.step_result = {"got": 0}
		return
	var block: int = sim.voxels.get_block(cell)
	var gained: int = Registry.yields[block]
	var leaves: Array = site.get("leaves", [])
	var source: String = "npc:%d" % agent.id
	if site.kind == "bush":
		sim.set_block(cell, block, maxi(sim.voxels.block_meta(cell) - 1, 0), source)
		gained = 1
	else:
		sim.set_block(cell, 0, 0, source)
	if site.kind == "tree" and sim.sites.get_site(id).is_empty():
		for leaf in leaves:
			if sim.voxels.get_block(leaf) == Registry.id("leaves"):
				sim.set_block(leaf, 0, 0, source)
	agent.carrying = {"resource": resource, "amount": agent.carried(resource) + gained}
	agent.step_result = {"got": gained}


## A berry pressed into an empty planter becomes a bare bush that ripens.
static func _plant(sim: RefCounted, agent: RefCounted, cell: Vector3i) -> void:
	var open: bool = sim.voxels.get_block(cell) == 0 and Registry.component(sim.voxels.get_block(cell + Vector3i.DOWN)) == "planter"
	if not open or agent.carried("berries") < 1.0 or sim.is_occupied(cell):
		agent.step_result = {"planted": 0}
		return
	agent.carrying.amount = float(agent.carrying.amount) - 1.0
	if float(agent.carrying.amount) < 0.05:
		agent.carrying = {}
	sim.set_block(cell, Registry.id("berry_bush"), 0, "npc:%d" % agent.id)
	agent.step_result = {"planted": 1}


static func _pick_up(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	var item: Dictionary = sim.items.get(int(action.item), {})
	if item.is_empty() or (not agent.carrying.is_empty() and agent.carrying.resource != item.resource):
		agent.step_result = {"picked": 0}
		return
	var room: float = Balance.number("agents.carry_capacity") - agent.carried(item.resource)
	var taken: float = minf(room, float(item.amount))
	item.amount = float(item.amount) - taken
	if item.amount <= 0.05:
		sim.items.erase(int(action.item))
	agent.carrying = {"resource": item.resource, "amount": agent.carried(item.resource) + taken}
	agent.step_result = {"picked": 1 if taken > 0.0 else 0}


## A bed in a dwelling becomes this person's home if one is free.
static func _claim_bed(sim: RefCounted, agent: RefCounted, id: int) -> void:
	var entry: Dictionary = sim.structures.entries.get(id, {})
	if entry.is_empty() or entry.residents.has(agent.id):
		return
	if int(entry.capacity.get("beds", 0)) - entry.residents.size() <= 0:
		return
	sim.set_home(agent, id)


static func _gift(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	var receiver: RefCounted = sim.agents[int(action.to)]
	if not receiver.is_present():
		sim.drop_item(agent.cell, action.resource, float(action.amount))
		return
	if not receiver.carrying.is_empty():
		sim.drop_item(receiver.cell, receiver.carrying.resource, float(receiver.carrying.amount))
	receiver.carrying = {"resource": action.resource, "amount": float(action.amount)}
	Beliefs.change_opinion(receiver.beliefs.relation(agent.id), 6.0)
	Mind.add(agent, "helped_friend", sim.calendar.ticks_per_day, receiver.id)


static func _treat(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	var patient: RefCounted = sim.agents[int(action.to)]
	if not patient.is_present():
		return
	patient.health.treated = bool(patient.health.ill)
	patient.health.hp = minf(float(patient.health.hp) + 8.0, 100.0)
	Mind.add(patient, "cared_for", sim.calendar.ticks_per_day, agent.id)
	Beliefs.change_opinion(patient.beliefs.relation(agent.id), 5.0)


## Moving in: a new settlement, its stock believed, its designs half known.
static func _join(sim: RefCounted, agent: RefCounted, settlement_id: int) -> void:
	var settlement: Dictionary = sim.settlements.get_settlement(settlement_id)
	if settlement.is_empty() or agent.settlement_id == settlement_id:
		return
	var from: String = sim.settlements.get_settlement(agent.settlement_id).get("name", "")
	sim.set_home(agent, -1)
	sim.settlements.join(agent, settlement_id)
	agent.beliefs.stock = sim.settlements.stock_of(settlement_id).duplicate()
	for id in agent.beliefs.known_templates:
		if not settlement.known_templates.has(id):
			settlement.known_templates.append(id)
	agent.low_mood_ticks = 0
	agent.joined_day = sim.calendar.day()
	Mind.add(agent, "arrived", sim.calendar.ticks_per_day)
	sim.chronicle_event("migrated", settlement_id, {"name": agent.full_name(), "from": from}, "cause_unhappy", [agent.id])


static func _leave(sim: RefCounted, agent: RefCounted) -> void:
	agent.life = "departed"
	agent.life_day = sim.calendar.day()
	agent.intention = {}
	agent.path.clear()
	sim.set_home(agent, -1)
	if sim.settlements.entries.has(agent.settlement_id):
		sim.settlements.entries[agent.settlement_id].residents.erase(agent.id)
	if agent.partner >= 0 and sim.agents[agent.partner].partner == agent.id:
		sim.agents[agent.partner].partner = -1
	sim.chronicle_event("departed", agent.settlement_id, {"name": agent.full_name()}, "cause_unhappy", [agent.id])


## A founder arrives at open land: the first sets down a chest from the wood
## they carried and names the new settlement after the place; whoever comes
## later joins it. Either way they live there now and put down their load.
static func _settle(sim: RefCounted, agent: RefCounted, index: int) -> void:
	var ground: Dictionary = sim.features.grounds[index]
	var id: int = sim.settlements.on_ground(index)
	var from: String = sim.settlements.get_settlement(agent.settlement_id).get("name", "")
	if id < 0:
		if agent.carried("wood") < 1.0:
			agent.step_result = {"settled": 0}
			return
		var camp: Vector3i = sim.nav.nearest_walkable(ground.center, 4)
		var chest: Vector3i = _chest_spot(sim, camp)
		if camp.x < 0 or chest.x < 0:
			agent.step_result = {"settled": 0}
			return
		id = sim.settlements.create(Text.label(ground.name), ground.center, camp, sim.calendar.tick)
		sim.settlements.entries[id]["ground"] = index
		agent.carrying.amount = float(agent.carrying.amount) - 1.0
		sim.set_block(chest, Registry.id("storage_chest"), 0, "npc:%d" % agent.id)
		sim.chronicle_event("settlement_founded", id, {"name": agent.full_name(), "place": Text.label(ground.name), "from": from}, "cause_devotion", [agent.id])
	sim.set_home(agent, -1)
	sim.settlements.join(agent, id)
	var settlement: Dictionary = sim.settlements.entries[id]
	# Anyone setting out to live on open land knows how to raise a lean-to.
	if not agent.beliefs.known_templates.has("lean_to"):
		agent.beliefs.known_templates.append("lean_to")
	for design in agent.beliefs.known_templates:
		if not settlement.known_templates.has(design):
			settlement.known_templates.append(design)
	if not agent.carrying.is_empty() and float(agent.carrying.amount) >= 1.0:
		var stored: int = sim.settlements.add(sim, id, agent.carrying.resource, int(agent.carrying.amount), agent.cell)
		agent.carrying.amount = float(agent.carrying.amount) - stored
	if agent.carrying.is_empty() or float(agent.carrying.amount) < 0.05:
		agent.carrying = {}
	agent.beliefs.stock = sim.settlements.stock_of(id).duplicate()
	agent.low_mood_ticks = 0
	agent.joined_day = sim.calendar.day()
	Mind.add(agent, "arrived", sim.calendar.ticks_per_day)
	agent.step_result = {"settled": 1}


## Open ground beside the camp for the first chest.
static func _chest_spot(sim: RefCounted, camp: Vector3i) -> Vector3i:
	if camp.x < 0:
		return camp
	for side in [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)]:
		var cell: Vector3i = sim.nav.surface(camp.x + side.x * 2, camp.z + side.z * 2)
		if cell.x >= 0 and sim.voxels.get_block(cell) == 0 and not sim.is_occupied(cell) and not sim.is_reserved_cell(cell):
			return cell
	return Vector3i(-1, -1, -1)
