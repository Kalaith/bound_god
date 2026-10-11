extends RefCounted
## Construction effects: marking a site, delivering materials, placing and
## repairing blocks, and finishing a building with the reason it was built.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const JobBoard = preload("res://scripts/sim/job_board.gd")
const Construction = preload("res://scripts/sim/construction.gd")
const Blueprints = preload("res://scripts/sim/blueprints.gd")
const Renovations = preload("res://scripts/sim/renovations.gd")

## Why a sect raised each of its halls (M19b), by purpose.
const SECT_HALL_CAUSES: Dictionary = {
	"library": "cause_sect_needs_library", "meditation_room": "cause_sect_needs_meditation_room",
	"tribulation_chamber": "cause_sect_needs_tribulation_chamber", "infirmary": "cause_sect_needs_infirmary",
	"spirit_array": "cause_sect_needs_spirit_array", "sect_gate": "cause_sect_needs_sect_gate",
	"ancestral_hall": "cause_sect_needs_ancestral_hall", "precept_stele": "cause_sect_needs_precept_stele",
	"bell_tower": "cause_sect_needs_bell_tower", "lecture_hall": "cause_sect_needs_lecture_hall",
}


static func apply(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	match str(action.type):
		"mark_site":
			_mark(sim, agent, action)
		"deliver":
			_deliver(sim, agent, action)
		"place_block":
			_place(sim, agent, action)
		"repair_block":
			_repair(sim, agent, action)
		_:
			push_error("Unknown effect " + str(action.type))


## Two founders may pick overlapping ground in one tick: the first wins.
static func _mark(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	for entry in action.order:
		if sim.construction.is_reserved(entry[0]):
			agent.step_result = {"site": 0}
			return
	var order: Array = action.order.duplicate(true)
	var made_do: Array = []
	for resource in ["stone", "thatch"]:
		if not Construction.knows_near(sim, agent, resource) and Construction.in_planks(order, 0, resource) > 0:
			made_do.append(resource)
	var timber: bool = not made_do.is_empty()
	var id: int = sim.construction.create(action.template_id, action.origin, int(action.rotation), agent.settlement_id,
		agent.id, action.purpose, order, sim.calendar.tick)
	agent.step_result = {"site": id}
	if action.has("blueprint"):
		Blueprints.taken(sim, int(action.blueprint), agent)
	if timber:
		sim.construction.sites[id]["made_do"] = true
	var cause: String = _cause(sim, agent, str(action.purpose))
	sim.construction.sites[id]["cause"] = cause
	sim.chronicle_event("site_marked", agent.settlement_id, {"name": agent.full_name(), "design": sim.template_name(action.template_id)}, cause, [agent.id])
	for resource in made_do:
		sim.chronicle_event("site_made_do", agent.settlement_id, {"design": sim.template_name(action.template_id)}, Construction.MAKE_DO_CAUSE[resource], [agent.id])


## Why a site was started, in words the chronicle can keep.
static func _cause(sim: RefCounted, agent: RefCounted, purpose: String) -> String:
	var settlement: Dictionary = sim.settlements.get_settlement(agent.settlement_id)
	var beds: int = 0
	for entry in sim.structures.built():
		if Vector2(entry.anchor.x - settlement.center.x, entry.anchor.z - settlement.center.z).length() <= float(settlement.radius):
			beds += int(entry.capacity.get("beds", 0))
	match purpose:
		"home":
			return "cause_housing|%d|%d" % [settlement.residents.size(), beds]
		"storehouse":
			return "cause_stores_full"
		"shelter":
			return "cause_many_homeless"
		"shrine":
			return "cause_no_shrine"
		"hall":
			return "cause_no_hall"
		"garden":
			return "cause_food_low"
		"meditation_hall":
			return "cause_sect_needs_hall"
		"tribulation_ground":
			return "cause_sect_needs_ground"
	# The sect's halls (M19b), each with its own reason.
	return str(SECT_HALL_CAUSES.get(purpose, "cause_npc"))


static func _deliver(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	var id: int = int(action.site)
	var site: Dictionary = sim.construction.get_site(id)
	if site.is_empty() or agent.carrying.is_empty():
		agent.step_result = {"delivered": 0}
		return
	var resource: String = agent.carrying.resource
	var wanted: int = int(sim.construction.missing(id).get(resource, 0))
	var given: int = mini(wanted, int(floor(float(agent.carrying.amount))))
	if given <= 0:
		agent.step_result = {"delivered": 0}
		return
	site.delivered[resource] = int(site.delivered.get(resource, 0)) + given
	var left: float = float(agent.carrying.amount) - given
	agent.carrying = {"resource": resource, "amount": left} if left > 0.05 else {}
	site.last_progress_tick = sim.calendar.tick
	agent.step_result = {"delivered": given}


static func _place(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	var id: int = int(action.site)
	var site: Dictionary = sim.construction.get_site(id)
	var work: int = int(agent.step_result.get("waits", 0))
	if site.is_empty() or int(site.cursor) != int(action.index):
		agent.step_result = {"placed": 0, "waits": work}
		return
	var entry: Array = site.order[site.cursor]
	var cell: Vector3i = entry[0]
	var block: int = entry[1]
	if Registry.solid[block] == 1 and sim.is_occupied(cell):
		# Someone is standing there; wait for them to move.
		agent.step_result = {"placed": 0, "blocked": true, "waits": work}
		return
	var current: int = sim.voxels.get_block(cell)
	var resource: String = Registry.build_resource(block) if block != 0 else ""
	var clearable: bool = current == 0 or current == Registry.id("tall_grass") or current == block
	if not clearable:
		# Something else took the cell; skip it and say so.
		agent.record(sim.calendar.tick, "message", {"text": "log_block_skipped", "args": {"block": Registry.block_name(current)}})
		sim.construction.advance(id, sim.calendar.tick)
	else:
		if not resource.is_empty():
			if int(site.delivered.get(resource, 0)) <= 0:
				agent.step_result = {"placed": 0, "waits": work}
				return
			site.delivered[resource] = int(site.delivered[resource]) - 1
		sim.set_block(cell, block, int(entry[2]), "npc:%d" % agent.id)
		sim.construction.advance(id, sim.calendar.tick)
		agent.stats.blocks_placed += 1
	agent.step_result = {"placed": 1}
	if int(site.cursor) >= site.order.size():
		_complete(sim, site)
		agent.step_result = {"placed": 1, "completed": true}


static func _complete(sim: RefCounted, site: Dictionary) -> void:
	if Renovations.is_renovation(str(site.template_id)):
		sim.construction.release(int(site.id))
		Renovations.complete(sim, site)
		return
	var template: RefCounted = sim.template(site.template_id)
	var layout: Array = []
	for entry in template.placement(int(site.rotation)):
		layout.append([site.origin + entry[0], entry[1], entry[2]])
	var structure_id: int = -1
	for entry in sim.structures.built():
		for part in layout:
			if entry.cells.has(part[0]):
				structure_id = entry.id
				break
		if structure_id >= 0:
			break
	sim.construction.release(int(site.id))
	var founder: RefCounted = sim.agents[int(site.founder)] if int(site.founder) >= 0 else null
	var people: Array = []
	if structure_id >= 0:
		var structure: Dictionary = sim.structures.entries[structure_id]
		structure.template_id = site.template_id
		sim.settlement_life.remember(sim, structure_id, site, layout)
		if founder != null and founder.is_present() and structure.functions.has("dwelling") and site.purpose == "home":
			sim.set_home(founder, structure_id)
			people.append(founder.id)
			Mind.add(founder, "home_built", sim.calendar.ticks_per_day)
			if founder.partner >= 0 and sim.agents[founder.partner].is_present():
				sim.set_home(sim.agents[founder.partner], structure_id)
				people.append(founder.partner)
	var settlement: Dictionary = sim.settlements.get_settlement(int(site.settlement_id))
	if not settlement.is_empty() and not settlement.known_templates.has(site.template_id):
		settlement.known_templates.append(site.template_id)
	sim.chronicle_event("built", int(site.settlement_id), {"name": founder.full_name() if founder != null else "", "design": sim.template_name(site.template_id)},
		str(site.get("cause", "cause_npc")), people)


static func _repair(sim: RefCounted, agent: RefCounted, action: Dictionary) -> void:
	var cell: Vector3i = action.cell
	var block: int = int(action.block)
	var resource: String = Registry.build_resource(block)
	var current: int = sim.voxels.get_block(cell)
	var clear: bool = current == 0 or (bool(action.get("rubble", false)) and (current == Registry.id("cobble") or current == Registry.id("tall_grass")))
	if not clear or (not resource.is_empty() and agent.carried(resource) < 1.0) or sim.is_occupied(cell):
		agent.step_result = {"repaired": 0}
		return
	sim.set_block(cell, block, int(action.meta), "npc:%d" % agent.id)
	if not resource.is_empty():
		var left: float = float(agent.carrying.amount) - 1.0
		agent.carrying = {"resource": resource, "amount": left} if left > 0.05 else {}
	agent.stats.blocks_placed += 1
	Personality.practise(agent, Personality.Skill.CONSTRUCTION, 4.0)
	agent.step_result = {"repaired": 1}
