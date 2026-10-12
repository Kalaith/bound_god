extends RefCounted
## The hidden realm in the tree's roots (M23): one hand-built world, the same
## for every seed but for the scatter of its herbs. A round hollow of grass
## walled by stone and great roots (log columns), open to a pale sky, with a
## spring of dense qi at its heart, rare herbs about it (frost lotus by the
## water, thunder root on scorched earth, jade ginseng under the roots) and a
## clearing where visitors camp. Draws randomness only from the generator's
## stream; written with `fill` (generation, not edits).

const RADIUS: float = 24.0
const FLOOR: int = 12
const WALL: int = 30


static func generate(gen: RefCounted, archetype: Dictionary) -> Dictionary:
	var world: RefCounted = gen.world
	var size: Vector3i = world.size
	var centre := Vector2(size.x / 2.0, size.z / 2.0)
	gen.heights.resize(size.x * size.z)
	var ids: Dictionary = {}
	for name in ["bedrock", "stone", "dirt", "grass", "log", "water", "sand", "scorched_earth"]:
		ids[name] = gen._id(name)
	for z in range(size.z):
		for x in range(size.x):
			var d: float = Vector2(x + 0.5, z + 0.5).distance_to(centre)
			var top: int = FLOOR if d <= RADIUS else mini(WALL, FLOOR + 4 + int((d - RADIUS) * 3.0))
			gen.heights[x + z * size.x] = top
			world.fill(Vector3i(x, 0, z), ids.bedrock)
			for y in range(1, top + 1):
				world.fill(Vector3i(x, y, z), ids.stone if y < top - 2 or d > RADIUS else (ids.grass if y == top else ids.dirt))
			# Great roots stand round the hollow's edge.
			if d > RADIUS - 2.0 and d <= RADIUS and (int(atan2(z - centre.y, x - centre.x) * 12.0) % 3 == 0):
				for y in range(top + 1, WALL + 2):
					world.fill(Vector3i(x, y, z), ids.log)
	# The spring at the heart.
	var spring := Vector3i(int(centre.x), FLOOR, int(centre.y))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if Vector2(dx, dz).length() <= 2.2:
				world.fill(spring + Vector3i(dx, 0, dz), ids.water)
				world.fill(spring + Vector3i(dx, -1, dz), ids.sand)
	_herbs(gen, centre, ids)
	gen.features["home"] = {"center": Vector3i(int(centre.x) + 8, FLOOR + 1, int(centre.y) + 8), "name": str(archetype.settlement)}
	gen.features["wells"] = [{"cell": spring + Vector3i(0, 1, 0), "qi": float(archetype.well_qi)}]
	gen.features["heart"] = spring + Vector3i(3, 1, -3)
	gen.features["grounds"] = []
	return {"sites": gen.sites, "features": gen.features}


## Rare herbs, ripe, where each would grow: lotus by the water, thunder root
## on scorched patches, ginseng in the roots' shade. Decoration of the
## realm's riches (expeditions bring their share home, expeditions.gd).
static func _herbs(gen: RefCounted, centre: Vector2, ids: Dictionary) -> void:
	var world: RefCounted = gen.world
	var kinds: Array = [["frost_lotus", 4.0, 6], ["thunder_root", 12.0, 5], ["jade_ginseng", 20.0, 7]]
	for kind in kinds:
		var block: int = gen._id(str(kind[0]))
		for i in range(int(kind[2])):
			var angle: float = float(gen.rng.randf()) * TAU
			var at: Vector2 = Vector2(centre.x, centre.y) + Vector2.from_angle(angle) * (float(kind[1]) + gen.rng.randf() * 2.0)
			var cell := Vector3i(int(at.x), FLOOR + 1, int(at.y))
			if world.get_block(cell) != 0 or world.get_block(cell + Vector3i.DOWN) != ids.grass:
				continue
			if str(kind[0]) == "thunder_root":
				world.fill(cell + Vector3i.DOWN, ids.scorched_earth)
			world.fill(cell, block)
			world.meta[world.index_of(cell)] = 2
