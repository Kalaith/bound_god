extends RefCounted
## Owns all world state. No nodes, no physics, no global RNG, no clock:
## `Sim.create(seed).run_ticks(n)` runs headless. Randomness comes only from
## `rng`; player commands go through `apply_command` between ticks.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const VoxelWorld = preload("res://scripts/world/voxel_world.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")
const NavGrid = preload("res://scripts/world/nav_grid.gd")
const Calendar = preload("res://scripts/sim/calendar.gd")
const ResourceSites = preload("res://scripts/sim/resource_sites.gd")
const GodState = preload("res://scripts/sim/god_state.gd")
const Commands = preload("res://scripts/sim/commands.gd")
const Structures = preload("res://scripts/world/structures.gd")
const Spatial = preload("res://scripts/sim/spatial.gd")
const Effects = preload("res://scripts/sim/effects.gd")
const Settlements = preload("res://scripts/sim/settlements.gd")
const Chronicle = preload("res://scripts/sim/chronicle.gd")
const Population = preload("res://scripts/sim/population.gd")
const AgentTick = preload("res://scripts/sim/agent_tick.gd")
const Daily = preload("res://scripts/sim/daily.gd")
const Places = preload("res://scripts/sim/places.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Data = preload("res://scripts/core/data.gd")
const Construction = preload("res://scripts/sim/construction.gd")
const SettlementLife = preload("res://scripts/sim/settlement_life.gd")
const Director = preload("res://scripts/sim/director.gd")
const CommandsWorld = preload("res://scripts/sim/commands_world.gd")
const Template = preload("res://scripts/building/template.gd")
const Faith = preload("res://scripts/sim/faith.gd")
const Requests = preload("res://scripts/sim/requests.gd")

var world_seed: int = 1
var rng := RandomNumberGenerator.new()
var calendar: RefCounted
var voxels: RefCounted
var nav: RefCounted
var sites: RefCounted
var god: RefCounted
var structures: RefCounted
var spatial: RefCounted
var effects: RefCounted
var settlements: RefCounted
var chronicle: RefCounted
## Array of Agent, index == id (the dead and departed stay, never present).
var agents: Array = []
## item id -> {id, cell, resource, amount}
var items: Dictionary = {}
var next_item_id: int = 1
## Fixed places from generation: sacred_tree, ruin, hamlet.
var features: Dictionary = {}
var command_log: Array = []
## Who changed each cell last this tick, for structures and the chronicle.
var edit_sources: Dictionary = {}
## Cells people stand in (feet and head) this tick: Vector3i -> agent id.
var occupied: Dictionary = {}
## Systems that arrive in later milestones; null until they exist.
var faith: RefCounted = null
var requests: RefCounted = null
var director: RefCounted = null
var threats: RefCounted = null
var settlement_life: RefCounted = null
var construction: RefCounted = null
## Kindled cells (miracle): Array of {cell, radius, until}.
var kindled: Array = []
## Veils of fog (miracle): Array of {cell, radius, until}.
var veils: Array = []
## Template id -> Template, built on demand from offered copies or starters.
var _templates: Dictionary = {}
var _sites_version: int = -1
var _events_seen: int = 0


static func create(seed: int, options: Dictionary = {}) -> RefCounted:
	var sim = load("res://scripts/sim/sim.gd").new()
	sim.setup(seed, options)
	return sim


func setup(seed: int, options: Dictionary) -> void:
	Registry.build()
	world_seed = maxi(seed, 1)
	rng.seed = world_seed
	calendar = Calendar.new()
	# The first morning: the travellers arrive soon after dawn.
	calendar.tick = calendar.ticks_per_day * 7 / 24
	god = GodState.new()
	sites = ResourceSites.new()
	var size: Vector3i
	if options.has("size"):
		size = options.size
	else:
		var raw: Array = Balance.list("world.size")
		size = Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))
	voxels = VoxelWorld.new(size)
	var gen := WorldGen.new(voxels, rng)
	var result: Dictionary = gen.flat(int(options.get("ground", 4))) if options.get("world", "valley") == "flat" else gen.valley()
	features = result.features
	sites.load_generated(result.sites)
	structures = Structures.new()
	structures.initialize(voxels)
	nav = NavGrid.new(voxels)
	nav.path_cap = Balance.integer("agents.paths_per_tick")
	nav.build()
	spatial = Spatial.new()
	effects = Effects.new()
	settlements = Settlements.new()
	chronicle = Chronicle.new()
	construction = Construction.new()
	settlement_life = SettlementLife.new()
	director = Director.new()
	_events_seen = structures.events.size()
	god.grace_until_tick = calendar.tick + calendar.ticks_for_days(Balance.number("shrines.grace_days"))
	Population.found(self, options)
	faith = Faith.new()
	faith.setup(self)
	requests = Requests.new()
	_refresh_site_buckets()
	settlement_life.refresh_jobs(self)


func apply_command(command: Dictionary) -> Dictionary:
	var result: Dictionary = Commands.apply(self, command)
	_reconcile_homes("god")
	return result


## Every block change in the simulation goes through here.
func set_block(cell: Vector3i, block: int, meta: int = 0, source: String = "") -> bool:
	var old: int = voxels.get_block(cell)
	if not voxels.set_block(cell, block, meta):
		return false
	sites.on_block_changed(cell, old, block, voxels)
	if not source.is_empty():
		edit_sources[cell] = source
	if old != block:
		structures.on_edit(voxels, cell, calendar.tick, source)
		if faith != null:
			faith.on_block(self, cell, old, block, source)
		if Registry.passable[old] != Registry.passable[block] or Registry.solid[old] != Registry.solid[block] \
				or Registry.opaque[old] != Registry.opaque[block]:
			nav.update_cells([cell])
	return true


# --- Presence -----------------------------------------------------------------

func zone_center() -> Vector3:
	if faith != null:
		return faith.zone_center(self)
	var tree: Vector3i = features.sacred_tree
	return Vector3(tree.x + 1.0, tree.y, tree.z + 1.0)


func zone_radius() -> float:
	if faith != null:
		return faith.zone_radius(self)
	return Balance.number("shrines.radius_base")


func in_zone(point: Vector3) -> bool:
	var center: Vector3 = zone_center()
	return Vector2(point.x - center.x, point.z - center.z).length() <= zone_radius()


func is_occupied(cell: Vector3i) -> bool:
	return occupied.has(cell)


func is_reserved_cell(cell: Vector3i) -> bool:
	return construction != null and construction.is_reserved(cell)


# --- Places (thin wrappers so agent code has one world contract) -------------

func structure_access(id: int, from: Vector3i) -> Vector3i:
	return Places.structure_access(self, id, from)


func site_access(id: int) -> Vector3i:
	return Places.site_access(self, id)


func construction_access(id: int, from: Vector3i) -> Vector3i:
	return construction.access(self, id, from) if construction != null else Vector3i(-1, -1, -1)


func structure_id_at(cell: Vector3i) -> int:
	return Places.structure_id_at(self, cell)


func is_under_canopy(cell: Vector3i) -> bool:
	return Places.is_under_canopy(self, cell)


func is_kindled(cell: Vector3i) -> bool:
	for entry in kindled:
		if int(entry.until) > calendar.tick and Vector3(cell).distance_to(Vector3(entry.cell)) <= float(entry.radius):
			return true
	return false


## True when a veil of fog hides `cell` from a watcher outside it.
func is_veiled(cell: Vector3i, _watcher: Vector3i) -> bool:
	for entry in veils:
		if int(entry.until) > calendar.tick and Vector2(cell.x - entry.cell.x, cell.z - entry.cell.z).length() <= float(entry.radius):
			return true
	return false


func threats_list() -> Array:
	return threats.list() if threats != null else []


func threat_exists(id: int) -> bool:
	return threats != null and threats.exists(id)


func drop_item(cell: Vector3i, resource: String, amount: float) -> void:
	if amount <= 0.05 or resource.is_empty():
		return
	for id in items:
		var item: Dictionary = items[id]
		if item.cell == cell and item.resource == resource:
			item.amount = float(item.amount) + amount
			return
	items[next_item_id] = {"id": next_item_id, "cell": cell, "resource": resource, "amount": amount}
	next_item_id += 1


## A delivery reached the stores (requests listen for this).
func note_delivery(agent: RefCounted, resource: String, amount: int) -> void:
	if requests != null and amount > 0:
		requests.on_delivery(self, agent, resource, amount)


func set_home(agent: RefCounted, id: int) -> void:
	var old: Dictionary = structures.entries.get(agent.home, {})
	if not old.is_empty():
		old.residents.erase(agent.id)
	agent.home = id
	var entry: Dictionary = structures.entries.get(id, {})
	if not entry.is_empty() and not entry.residents.has(agent.id):
		entry.residents.append(agent.id)
		var place: int = settlements.at_cell(entry.anchor)
		if place >= 0:
			settlements.join(agent, place)


func chronicle_event(kind: String, settlement_id: int, args: Dictionary, cause: String = "", people: Array = [], known: bool = true) -> void:
	var place: String = settlements.get_settlement(settlement_id).get("name", "")
	chronicle.add(calendar.tick, calendar.day(), kind, place, args, cause, people, known)


## People whose home stopped being a dwelling lose it, and remember why.
func _reconcile_homes(cause: String) -> void:
	if structures.events.size() == _events_seen:
		return
	_events_seen = structures.events.size()
	for agent in agents:
		if agent.home < 0:
			continue
		var entry: Dictionary = structures.entries.get(agent.home, {})
		if entry.is_empty() or not entry.functions.has("dwelling") or not entry.residents.has(agent.id):
			if not entry.is_empty():
				entry.residents.erase(agent.id)
			agent.home = -1
			if agent.is_present():
				Mind.add(agent, "lost_home", calendar.ticks_per_day)
				chronicle_event("home_lost", agent.settlement_id, {"name": agent.full_name()}, cause, [agent.id])


func _refresh_site_buckets() -> void:
	if sites.version == _sites_version:
		return
	_sites_version = sites.version
	spatial.clear_layer("sites")
	for id in sites.ids_sorted():
		var site: Dictionary = sites.get_site(id)
		if not site.cells.is_empty():
			spatial.insert("sites", id, site.cells[0])


func _refresh_agent_buckets() -> void:
	spatial.clear_layer("agents")
	occupied.clear()
	for agent in agents:
		if agent.is_present():
			spatial.insert("agents", agent.id, agent.cell)
			occupied[agent.cell] = agent.id
			occupied[agent.cell + Vector3i.UP] = agent.id


# --- Time ---------------------------------------------------------------------

func step() -> void:
	calendar.tick += 1
	nav.paths_this_tick = 0
	if calendar.is_new_day():
		Daily.new_day(self)
	if calendar.is_new_hour():
		Daily.new_hour(self)
	if settlement_life != null and calendar.tick % 10 == 0:
		settlement_life.refresh_jobs(self)
	if threats != null:
		threats.step(self)
	_refresh_site_buckets()
	_refresh_agent_buckets()
	AgentTick.update_agents(self)
	AgentTick.after_agents(self)
	_reconcile_homes("npc")


func run_ticks(count: int) -> void:
	for _i in range(count):
		step()


## A fingerprint of everything that simulates; same seed and commands, same hash.
func state_hash() -> int:
	var people: Array = []
	for agent in agents:
		people.append(agent.to_dict())
	var state: Array = [calendar.tick, rng.state, people, settlements.to_dict(), sites.to_dict(), items,
		god.to_dict(), chronicle.to_dict(), command_log, voxels.hash_state()]
	return hash(var_to_bytes(state))


## Commands beyond block edits (offers, transfers, and later faith).
func apply_extended_command(command: Dictionary) -> Dictionary:
	return CommandsWorld.apply(self, command)


## A design by id: offered copies first, then the starters; null if unknown.
func template(id: String) -> RefCounted:
	if _templates.has(id):
		return _templates[id]
	var result: RefCounted = null
	if god.offered.has(id):
		result = Template.from_dict(god.offered[id])[0]
	elif not Data.starter(id).is_empty():
		result = Template.from_starter(Data.starter(id))
	_templates[id] = result
	return result


func forget_template_cache(id: String) -> void:
	_templates.erase(id)


## A design's display name: offered copies first, then the starters.
func template_name(id: String) -> String:
	if god.offered.has(id):
		return str(god.offered[id].get("name", id))
	return str(Data.starter(id).get("name", id))


func present_count() -> int:
	var count: int = 0
	for agent in agents:
		if agent.is_present():
			count += 1
	return count
