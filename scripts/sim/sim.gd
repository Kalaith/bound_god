extends RefCounted
## Owns all world state. No nodes, no physics, no global RNG, no clock:
## `Sim.create(seed).run_ticks(n)` runs headless. Randomness comes only from
## `rng`; player commands go through `apply_command` between ticks.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const VoxelWorld = preload("res://scripts/world/voxel_world.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")
const Calendar = preload("res://scripts/sim/calendar.gd")
const ResourceSites = preload("res://scripts/sim/resource_sites.gd")
const GodState = preload("res://scripts/sim/god_state.gd")
const Commands = preload("res://scripts/sim/commands.gd")

var world_seed: int = 1
var rng := RandomNumberGenerator.new()
var calendar: RefCounted
var voxels: RefCounted
var sites: RefCounted
var god: RefCounted
## Fixed places from generation: sacred_tree, ruin, hamlet.
var features: Dictionary = {}
var command_log: Array = []
## Who changed each cell last this tick, for structures and the chronicle.
var edit_sources: Dictionary = {}


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
	god.grace_until_tick = calendar.tick + calendar.ticks_for_days(Balance.number("shrines.grace_days"))


func apply_command(command: Dictionary) -> Dictionary:
	return Commands.apply(self, command)


## Every block change in the simulation goes through here.
func set_block(cell: Vector3i, block: int, meta: int = 0, source: String = "") -> bool:
	var old: int = voxels.get_block(cell)
	if not voxels.set_block(cell, block, meta):
		return false
	sites.on_block_changed(cell, old, block, voxels)
	if not source.is_empty():
		edit_sources[cell] = source
	return true


# --- Presence -----------------------------------------------------------------

func zone_center() -> Vector3:
	var tree: Vector3i = features.sacred_tree
	return Vector3(tree.x + 1.0, tree.y, tree.z + 1.0)


func zone_radius() -> float:
	return Balance.number("shrines.radius_base")


func in_zone(point: Vector3) -> bool:
	var center: Vector3 = zone_center()
	return Vector2(point.x - center.x, point.z - center.z).length() <= zone_radius()


func is_occupied(_cell: Vector3i) -> bool:
	return false


func is_reserved_cell(_cell: Vector3i) -> bool:
	return false


# --- Time ---------------------------------------------------------------------

func step() -> void:
	calendar.tick += 1


func run_ticks(count: int) -> void:
	for _i in range(count):
		step()
