extends RefCounted
## Applies the tick's Effects once, after every agent has acted: world
## actions in push order (lowest id first when two want the same thing),
## then conversations, then message delivery to inboxes.
const Balance = preload("res://scripts/core/balance.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Social = preload("res://scripts/sim/social.gd")
const EffectsBuild = preload("res://scripts/sim/effects_build.gd")

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
	var taken: int = sim.settlements.take(int(action.settlement), resource, int(action.amount))
	if taken > 0:
		agent.carrying = {"resource": resource, "amount": agent.carried(resource) + taken}
	agent.step_result = {"took": taken}


static func _deposit(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	if agent.carrying.is_empty():
		agent.step_result = {"stored": 0}
		return
	var resource: String = agent.carrying.resource
	var whole: int = int(floor(float(agent.carrying.amount)))
	var stored: int = sim.settlements.add(sim, int(action.settlement), resource, whole)
	var left: float = float(agent.carrying.amount) - stored
	if left > 0.05:
		agent.carrying.amount = left
		if stored == 0:
			# The stores are full: set it down beside them for later.
			sim.drop_item(agent.cell, resource, left)
			agent.carrying = {}
	else:
		agent.carrying = {}
	agent.step_result = {"stored": stored if stored > 0 else (1 if agent.carrying.is_empty() else 0)}
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
	var cell: Vector3i = site.cells.back() if site.kind == "tree" else site.cells[0]
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
