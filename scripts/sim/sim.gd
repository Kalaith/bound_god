extends RefCounted
## Owns all world state. No nodes, no physics, no global RNG, no clock:
## `Sim.create(seed).run_ticks(n)` runs headless. Randomness comes only from
## `rng`; player commands go through `apply_command` between ticks.
const SectHalls = preload("res://scripts/sim/sect_halls.gd")
const Renovations = preload("res://scripts/sim/renovations.gd")
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
const Threats = preload("res://scripts/sim/threats.gd")
const Raids = preload("res://scripts/sim/raids.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const Kitchens = preload("res://scripts/sim/kitchens.gd")
const Woods = preload("res://scripts/sim/woods.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Qi = preload("res://scripts/sim/qi.gd")
const Sects = preload("res://scripts/sim/sects.gd")
const Tribulations = preload("res://scripts/sim/tribulations.gd")
const TreeGrowth = preload("res://scripts/sim/tree_growth.gd")
const Paths = preload("res://scripts/sim/paths.gd")
const Weather = preload("res://scripts/sim/weather.gd")
const Herbs = preload("res://scripts/sim/herbs.gd")
const Alchemy = preload("res://scripts/sim/alchemy.gd")
const TreeAbilities = preload("res://scripts/sim/tree_abilities.gd")
const Routes = preload("res://scripts/sim/routes.gd")
const Regions = preload("res://scripts/sim/regions.gd")
const RegionSeed = preload("res://scripts/sim/region_seed.gd")

var world_seed: int = 1
## Which region of the campaign this world is (0: the home valley, M22).
var region_id: int = 0
## How this world was made (world kind, size); saved so a load regenerates it.
var options: Dictionary = {}
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
## item id -> {id, cell, resource, amount, day dropped}
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
var raids: RefCounted = null
var settlement_life: RefCounted = null
var construction: RefCounted = null
var crops: RefCounted = null
var kitchens: RefCounted = null
var woods: RefCounted = null
var qi: RefCounted = null
var sects: RefCounted = null
var tribulations: RefCounted = null
var tree_growth: RefCounted = null
var paths: RefCounted = null
## Traffic between linked settlements wearing their routes (M21).
var routes: RefCounted = null
## People setting out for another region since the campaign last looked
## (sim/travel.gd drains it): Array of Dictionary records (M22).
var outbound: Array = []
## Free founding grounds in the other regions, as the campaign last saw
## them: Array of {region, ground, name, region_name} (M22).
var abroad: Array = []
## Whether this region knows of the tree's sanctuary and may seek it
## ({open: bool}), kept by the campaign (M22).
var sanctuary: Dictionary = {}
## Which regions send traders here, as the campaign last saw them:
## Array of {region, region_name, goods, technique, sect, friendly} (M22).
var traders: Array = []
var weather: RefCounted = null
var herbs: RefCounted = null
## Smithy anvils, worked like kitchens (M20).
var forges: RefCounted = null
## Alchemy benches, what to refine and refining (M20b).
var alchemy: RefCounted = null
## Kindled cells (miracle): Array of {cell, radius, until}.
var kindled: Array = []
## Veils of fog (miracle): Array of {cell, radius, until}.
var veils: Array = []
## Vector3i -> true for every lantern standing in the world.
var lanterns: Dictionary = {}
## True while the god meditates (the abstract model runs): prayers then
## bring half the Favour, so skipping years is never free.
var meditating: bool = false
## Template id -> Template, built on demand from offered copies or starters.
var _templates: Dictionary = {}
var _sites_version: int = -1
## Bumped whenever anyone's intention changes; the pursuit index follows it.
var goal_version: int = 0
var _pursuit_version: int = -1
## Goal key -> Array of the ids of present people pursuing it, in id order.
var _pursuit: Dictionary = {}
var _events_seen: int = 0


static func create(seed: int, setup_options: Dictionary = {}) -> RefCounted:
	var sim = load("res://scripts/sim/sim.gd").new()
	sim.setup(seed, setup_options)
	return sim


func setup(seed: int, setup_options: Dictionary) -> void:
	var restoring: bool = setup_options.get("restoring", false)
	Registry.build()
	options = setup_options.duplicate(true)
	options.erase("restoring")
	world_seed = maxi(seed, 1)
	region_id = int(setup_options.get("region", 0))
	# A neighbouring region draws from its own stream (plan §3.1, M22).
	rng.seed = world_seed if region_id == 0 else hash([world_seed, region_id, "region"])
	calendar = Calendar.new()
	# The first morning: the travellers arrive soon after dawn.
	calendar.tick = calendar.ticks_per_day * 7 / 24
	god = GodState.new()
	god.hotbar.resize(Balance.integer("avatar.hotbar_slots"))
	god.hotbar.fill(0)
	sites = ResourceSites.new()
	var size: Vector3i
	if setup_options.has("size"):
		size = setup_options.size
	else:
		var raw: Array = Balance.list("world.size")
		size = Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))
	voxels = VoxelWorld.new(size)
	var gen := WorldGen.new(voxels, rng)
	var result: Dictionary
	if setup_options.get("world", "valley") == "flat":
		result = gen.flat(int(setup_options.get("ground", 4)))
	elif region_id > 0:
		result = gen.region(Regions.archetype(str(setup_options.archetype)))
	else:
		result = gen.valley()
	features = result.features
	for well in features.get("wells", []):
		voxels.qi_wells[well.cell] = float(well.qi)
	sites.load_generated(result.sites)
	structures = Structures.new()
	structures.initialize(voxels)
	nav = NavGrid.new(voxels)
	nav.path_cap = Balance.integer("agents.paths_per_tick")
	if not restoring:
		nav.build()
	spatial = Spatial.new()
	effects = Effects.new()
	settlements = Settlements.new()
	settlements.today = calendar.day()
	chronicle = Chronicle.new()
	construction = Construction.new()
	crops = Crops.new()
	kitchens = Kitchens.new()
	woods = Woods.new()
	qi = Qi.new()
	sects = Sects.new()
	tribulations = Tribulations.new()
	tree_growth = TreeGrowth.new()
	paths = Paths.new()
	routes = Routes.new()
	weather = Weather.new()
	herbs = Herbs.new()
	forges = Kitchens.new("smithy")
	alchemy = Alchemy.new()
	weather.setup(self)
	settlement_life = SettlementLife.new()
	director = Director.new()
	_events_seen = structures.events.size()
	faith = Faith.new()
	requests = Requests.new()
	threats = Threats.new()
	raids = Raids.new()
	director.raid_hooks = raids
	if restoring:
		return
	for chest in features.get("hamlet", {}).get("chests", []):
		settlements.chests[chest] = {}
	if region_id > 0 and str(Regions.archetype(str(setup_options.archetype)).get("kind", "")) == "realm":
		RegionSeed.found_realm(self, Regions.archetype(str(setup_options.archetype)))
	elif region_id > 0:
		RegionSeed.found(self, Regions.archetype(str(setup_options.archetype)))
	else:
		Population.found(self, setup_options)
	faith.setup(self)
	if setup_options.get("threats", setup_options.get("world", "valley") == "valley"):
		threats.setup_wolves(self)
	_refresh_site_buckets()
	settlement_life.refresh_jobs(self)


## Caches and counters that follow from restored state.
func after_restore() -> void:
	_events_seen = structures.events.size()
	_sites_version = -1
	_templates.clear()
	goal_version += 1
	director.raid_hooks = raids
	faith.sync_sources(self)
	_refresh_site_buckets()
	_refresh_agent_buckets()


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
	if old != block:
		settlements.on_block(self, cell, old, block)
		crops.on_block(cell, block)
		herbs.on_block(cell, block)
		woods.on_block(self, cell, old, block)
		if Registry.component(block) == "lantern":
			lanterns[cell] = true
		elif lanterns.has(cell):
			lanterns.erase(cell)
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


## Many block changes at once (a building finished while the valley passes
## abstractly): the same hooks as set_block, but rooms are re-probed and the
## navigation graph relinked once for all of them. `entries` are [cell, block, meta].
func set_blocks(entries: Array, source: String) -> void:
	var changed: Array = []
	var walk: Array = []
	var olds: Array = []
	for entry in entries:
		var cell: Vector3i = entry[0]
		var block: int = int(entry[1])
		var old: int = voxels.get_block(cell)
		if not voxels.set_block(cell, block, int(entry[2])):
			continue
		sites.on_block_changed(cell, old, block, voxels)
		edit_sources[cell] = source
		if old == block:
			continue
		settlements.on_block(self, cell, old, block)
		crops.on_block(cell, block)
		herbs.on_block(cell, block)
		woods.on_block(self, cell, old, block)
		if Registry.component(block) == "lantern":
			lanterns[cell] = true
		elif lanterns.has(cell):
			lanterns.erase(cell)
		changed.append(cell)
		olds.append([old, block])
		if Registry.passable[old] != Registry.passable[block] or Registry.solid[old] != Registry.solid[block] \
				or Registry.opaque[old] != Registry.opaque[block]:
			walk.append(cell)
	if changed.is_empty():
		return
	structures.on_edits(voxels, changed, calendar.tick, source)
	if faith != null:
		for i in range(changed.size()):
			faith.on_block(self, changed[i], int(olds[i][0]), int(olds[i][1]), source)
	nav.update_cells(walk)


# --- Presence -----------------------------------------------------------------

func zone_center() -> Vector3:
	if faith != null:
		return faith.zone_center(self)
	var tree: Vector3i = features.get("sacred_tree", features.get("home", {}).get("center", Vector3i.ZERO))
	return Vector3(tree.x + 1.0, tree.y, tree.z + 1.0)


func zone_radius() -> float:
	if faith != null:
		return faith.zone_radius(self)
	return Balance.number("shrines.radius_base")


## Within the presence zone: the shrine's circle, and, manifested at the
## tree once its roots run along the paths, wherever they reach.
func in_zone(point: Vector3) -> bool:
	var center: Vector3 = zone_center()
	if Vector2(point.x - center.x, point.z - center.z).length() <= zone_radius():
		return true
	return faith != null and not god.dormant and str(faith.current(self).get("kind", "")) == "tree" and TreeAbilities.rooted(self, point)


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


## Whether a lantern's light reaches a cell.
func is_lit(cell: Vector3i) -> bool:
	var reach: float = Balance.number("world.lantern_reach")
	for lantern in lanterns:
		if absi(lantern.y - cell.y) <= 4 and Vector2(cell.x - lantern.x, cell.z - lantern.z).length() <= reach:
			return true
	return false


func threats_list() -> Array:
	return threats.list() if threats != null else []


func threat_exists(id: int) -> bool:
	if id <= -1000:
		return tribulations != null and tribulations.storm_active(id)
	return threats != null and threats.exists(id)


func drop_item(cell: Vector3i, resource: String, amount: float) -> void:
	if amount <= 0.05 or resource.is_empty():
		return
	for id in items:
		var item: Dictionary = items[id]
		if item.cell == cell and item.resource == resource:
			item.amount = float(item.amount) + amount
			# A pile is as old as the oldest food in it.
			item.day = mini(int(item.day), settlements.today)
			return
	items[next_item_id] = {"id": next_item_id, "cell": cell, "resource": resource, "amount": amount, "day": settlements.today}
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
	goal_version += 1
	nav.paths_this_tick = 0
	if calendar.is_new_day():
		Daily.new_day(self)
	if calendar.is_new_hour():
		Daily.new_hour(self)
	if settlement_life != null and calendar.tick % 10 == 0:
		settlement_life.refresh_jobs(self)
	if threats != null:
		threats.step(self)
		SectHalls.ring(self)
	if tribulations != null:
		tribulations.step(self)
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
	var state: Array = [calendar.tick, rng.state, people, settlements.to_dict(), sites.to_dict(), items, crops.to_dict(), kitchens.to_dict(), woods.to_dict(),
		god.to_dict(), chronicle.to_dict(), command_log, voxels.hash_state(), sects.to_dict(), tribulations.to_dict(), tree_growth.to_dict(), weather.to_dict(), herbs.to_dict(), alchemy.to_dict(), forges.to_dict(), routes.to_dict()]
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
	elif settlements.designs.has(id):
		result = Template.from_dict(settlements.designs[id])[0]
	elif not Data.starter(id).is_empty():
		result = Template.from_starter(Data.starter(id))
	_templates[id] = result
	return result


func forget_template_cache(id: String) -> void:
	_templates.erase(id)


## A design's display name: offered copies first, then the starters.
func template_name(id: String) -> String:
	if Renovations.is_renovation(id):
		return Renovations.name_of(id)
	if god.offered.has(id):
		return str(god.offered[id].get("name", id))
	if settlements.designs.has(id):
		return str(settlements.designs[id].get("name", id))
	return str(Data.starter(id).get("name", id))


## The pots of a station's structures by its function: kitchen or smithy
## (alchemy has benches of its own, `alchemy`).
func station(function: String) -> RefCounted:
	return forges if function == "smithy" else kitchens


## Ids of present people whose current goal has this key, in id order.
## Rebuilt only after an intention changes, so deliberation never scans
## everyone once per candidate.
func pursuers(goal_key: int) -> Array:
	if _pursuit_version != goal_version:
		_pursuit_version = goal_version
		_pursuit.clear()
		for agent in agents:
			if agent.is_present() and not agent.intention.is_empty():
				var key: int = Goals.key(agent.intention.goal)
				if not _pursuit.has(key):
					_pursuit[key] = []
				_pursuit[key].append(agent.id)
	return _pursuit.get(goal_key, [])


## How many may live here before migrants stop coming: the valley's cap, or
## a neighbouring region's (M22).
func migrant_cap() -> int:
	if is_realm():
		return 0
	return Balance.integer("population.cap") if region_id == 0 else int(Regions.number("region_cap"))


## Whether this world is the hidden realm, where nobody settles (M23).
func is_realm() -> bool:
	return str(Regions.archetype(str(options.get("archetype", ""))).get("kind", "")) == "realm"


## How many may live here before no more children are born.
func birth_cap() -> int:
	if is_realm():
		return 0
	return Balance.integer("population.birth_cap") if region_id == 0 else int(Regions.number("region_cap")) + int(Regions.number("region_birth_margin"))


## The world's pace of hunger and cold, chosen at a new world (M23).
func pace() -> float:
	return float(options.get("pace", 1.0))


func present_count() -> int:
	var count: int = 0
	for agent in agents:
		if agent.is_present():
			count += 1
	return count
