extends RefCounted
## Voxel world generation and meshing.
const VoxelWorld = preload("res://scripts/world/voxel_world.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")
const Mesher = preload("res://scripts/world/chunk_mesher.gd")
const Balance = preload("res://scripts/core/balance.gd")


func _valley(seed: int) -> Array:
	var size: Array = Balance.list("world.size")
	var world = VoxelWorld.new(Vector3i(int(size[0]), int(size[1]), int(size[2])))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var result: Dictionary = WorldGen.new(world, rng).valley()
	return [world, result]


func check_same_seed_same_valley():
	var a: Array = _valley(11)
	var b: Array = _valley(11)
	var c: Array = _valley(12)
	if a[0].hash_state() != b[0].hash_state():
		return "seed 11 produced two different valleys"
	if a[1].sites.size() != b[1].sites.size():
		return "seed 11 produced different resource sites"
	if a[0].hash_state() == c[0].hash_state():
		return "seeds 11 and 12 produced the same valley"
	return ""


func check_valley_has_its_features():
	var result: Dictionary = _valley(5)[1]
	var kinds: Dictionary = {}
	for site in result.sites:
		kinds[site.kind] = int(kinds.get(site.kind, 0)) + 1
	for kind in ["tree", "bush", "grass", "rock", "ore"]:
		if int(kinds.get(kind, 0)) < 3:
			return "too few %s sites: %s" % [kind, kinds]
	for key in ["sacred_tree", "ruin", "hamlet"]:
		if not result.features.has(key):
			return "missing feature " + key
	var tree: Vector3i = result.features.sacred_tree
	var ruin: Vector3i = result.features.ruin.altar
	var distance: float = Vector2(ruin.x - tree.x, ruin.z - tree.z).length()
	if distance < 60.0 or distance > 80.0:
		return "the ruin is %.0f blocks from the tree, not about 68" % distance
	var middle: Array = Balance.list("world.size")
	if absi(tree.x - int(middle[0]) / 2) > 2 or absi(tree.z - int(middle[2]) / 2) > 2:
		return "the sacred tree stands at %s, not in the middle of the valley" % tree
	return ""


func check_first_circle_holds_wood_stone_and_berries():
	for seed in [5, 11, 12, 31]:
		var result: Dictionary = _valley(seed)[1]
		var tree: Vector3i = result.features.sacred_tree
		var reach: float = Balance.number("shrines.tree_min_radius")
		var near: Dictionary = {"tree": 0, "rock": 0, "bush": 0}
		for site in result.sites:
			var cell: Vector3i = site.cells[0]
			if near.has(site.kind) and Vector2(cell.x - tree.x - 1, cell.z - tree.z - 1).length() <= reach:
				near[site.kind] += 1
		for kind in near:
			if int(near[kind]) < 2:
				return "seed %d: only %d %s sites inside the tree's first circle: %s" % [seed, near[kind], kind, near]
	return ""


func check_meshing_culls_hidden_faces():
	var world = VoxelWorld.new(Vector3i(16, 16, 16))
	for x in range(3):
		for y in range(3):
			for z in range(3):
				world.set_block(Vector3i(4 + x, 4 + y, 4 + z), 3)
	var data: Dictionary = Mesher.build(world, Vector3i.ZERO)
	var quads: int = data.surfaces[0].indices.size() / 6
	return "" if quads == 54 else "a 3x3x3 cube should show 54 faces, got %d" % quads
