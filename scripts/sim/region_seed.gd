extends RefCounted
## The people of a neighbouring region (M22), set down once its world exists:
## a settlement in the clearing with its starting buildings (raised where
## its own people would choose to build them), chests with its stores, its
## people with the archetype's culture and a share of cultivators of their
## faction's path, and their sect, founded long before the god woke. They
## have never heard of the god. Randomness from the region's own stream.
const Balance = preload("res://scripts/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const Text = preload("res://scripts/core/text.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Template = preload("res://scripts/building/template.gd")
const SiteFinder = preload("res://scripts/building/site_finder.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Population = preload("res://scripts/sim/population.gd")
const Regions = preload("res://scripts/sim/regions.gd")


static func found(sim: RefCounted, archetype: Dictionary) -> void:
	var home: Dictionary = sim.features.home
	var camp: Vector3i = sim.nav.nearest_walkable(home.center + Vector3i(3, 0, 3), 5)
	var id: int = sim.settlements.create(Text.label(str(home.name)), home.center, camp, sim.calendar.tick)
	var settlement: Dictionary = sim.settlements.entries[id]
	for work in archetype.culture:
		settlement.culture[work] = float(archetype.culture[work])
	settlement.known_templates = archetype.designs.duplicate()
	_buildings(sim, id, archetype)
	_stores(sim, id, camp, archetype)
	var people: Array = _people(sim, id, home.center, archetype)
	_sect(sim, id, people, Regions.faction(str(archetype.faction)))


## The hidden realm (M23): nobody lives there; a camp for visitors, a chest
## for what they bring, and the root heart (a cutting of the tree, a shrine
## the god can step through to once visitors' prayers wake it).
static func found_realm(sim: RefCounted, archetype: Dictionary) -> void:
	var home: Dictionary = sim.features.home
	var camp: Vector3i = sim.nav.nearest_walkable(home.center, 4)
	var id: int = sim.settlements.create(Text.label(str(home.name)), home.center, camp, sim.calendar.tick)
	var chest: Vector3i = sim.nav.surface(camp.x + 2, camp.z)
	if chest.x >= 0 and sim.voxels.get_block(chest) == 0:
		sim.set_block(chest, Registry.id("storage_chest"), 0, "region")
	var heart: Vector3i = sim.features.heart
	if sim.voxels.get_block(heart) == 0:
		sim.set_block(heart, Registry.id("spirit_cutting"), 0, "region")
		var shrine: Dictionary = sim.faith.get_shrine(int(sim.faith.by_cell.get(heart, -1)))
		if not shrine.is_empty():
			shrine.name = Text.label("shrine_root_heart")
	sim.settlements.entries[id]["realm"] = true


## The starting buildings, each where the site finder would put it.
static func _buildings(sim: RefCounted, id: int, archetype: Dictionary) -> void:
	for design in archetype.buildings:
		var template: RefCounted = Template.from_starter(Data.starter(str(design)))
		var choice: Dictionary = SiteFinder.find(sim, template, sim.settlements.entries[id])
		if choice.is_empty():
			continue
		var entries: Array = []
		for entry in choice.order:
			entries.append([entry[0], entry[1], entry[2]])
		sim.set_blocks(entries, "region")
		for structure in sim.structures.built():
			if structure.template_id.is_empty() and structure.cells.has(choice.order[0][0]):
				structure.template_id = template.id


## Three chests by the camp holding the archetype's stores.
static func _stores(sim: RefCounted, id: int, camp: Vector3i, archetype: Dictionary) -> void:
	var chests: Array = []
	for side in [Vector3i(2, 0, 0), Vector3i(-2, 0, 0), Vector3i(0, 0, 2), Vector3i(0, 0, -2), Vector3i(2, 0, 2)]:
		if chests.size() >= 3:
			break
		var cell: Vector3i = sim.nav.surface(camp.x + side.x, camp.z + side.z)
		if cell.x >= 0 and sim.voxels.get_block(cell) == 0 and not sim.is_reserved_cell(cell):
			sim.set_block(cell, Registry.id("storage_chest"), 0, "region")
			chests.append(cell)
	var resources: Array = archetype.stock.keys()
	resources.sort()
	for resource in resources:
		var left: int = int(archetype.stock[resource])
		for chest in chests:
			left -= sim.settlements.chest_add(chest, resource, left)


static func _people(sim: RefCounted, id: int, center: Vector3i, archetype: Dictionary) -> Array:
	var faction: Dictionary = Regions.faction(str(archetype.faction))
	var people: Array = []
	for i in range(int(archetype.people)):
		var agent: RefCounted = Generation.adult(sim.rng, sim.agents.size())
		agent.beliefs.known_templates = archetype.designs.duplicate()
		if sim.rng.randf() < float(archetype.cultivators):
			var c: Dictionary = CultivationState.fresh(sim.rng.randf_range(0.3, 0.8), "none", sim.rng.randf_range(0.5, 0.9))
			c.realm = _realm(sim, faction.realms)
			c.techniques = [str(faction.technique)]
			c.progress = sim.rng.randf_range(0.0, 0.6) * CultivationState.needed(c)
			agent.cultivation = c
		var cell: Vector3i = sim.nav.nearest_walkable(center + Vector3i(i % 5 - 2, 0, 2 + i / 5), 6)
		Population.arrive(sim, agent, cell, id, "")
		# They have lived here for years.
		agent.joined_day = sim.calendar.day() - 30
		people.append(agent)
		for entry in sim.structures.built():
			if entry.functions.has("dwelling") and int(entry.capacity.get("beds", 0)) * 2 > entry.residents.size():
				sim.set_home(agent, entry.id)
				break
	# Neighbours of years.
	for agent in people:
		for other in people:
			if other.id != agent.id:
				var relation: Dictionary = agent.beliefs.relation(other.id)
				relation.familiarity = 40.0
				relation.opinion = float(sim.rng.randi_range(-5, 30))
	return people


## A realm by the faction's weights (one per realm order, mortal first).
static func _realm(sim: RefCounted, weights: Array) -> int:
	var total: float = 0.0
	for w in weights:
		total += float(w)
	var roll: float = sim.rng.randf() * total
	for order in range(weights.size()):
		roll -= float(weights[order])
		if roll < 0.0:
			return order
	return weights.size() - 1


## The region's sect: its cultivators, the highest realm as master, the
## faction's name and doctrine.
static func _sect(sim: RefCounted, id: int, people: Array, faction: Dictionary) -> void:
	var cultivators: Array = people.filter(func(a: RefCounted) -> bool: return CultivationState.is_cultivator(a.cultivation))
	if cultivators.is_empty():
		return
	cultivators.sort_custom(func(a: RefCounted, b: RefCounted) -> bool:
		return int(a.cultivation.realm) > int(b.cultivation.realm) or (int(a.cultivation.realm) == int(b.cultivation.realm) and a.id < b.id))
	var master: RefCounted = cultivators[0]
	sim.sects.found_faction(sim, master, cultivators, id, faction)
