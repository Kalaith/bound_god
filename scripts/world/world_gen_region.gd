extends RefCounted
## A neighbouring region's world (M22): the valley's terrain rules with the
## archetype's numbers (height, rim, river, ridge, forest), but no sacred
## tree, ruin or hamlet. The region's people live in a clearing at the
## centre, round a spirit spring whose qi lets their sect cultivate; their
## buildings are raised there once the world exists (sim/region_seed.gd).
## Draws randomness only from the generator's stream.

const NONE := Vector3i(-1, -1, -1)


static func generate(gen: RefCounted, archetype: Dictionary) -> Dictionary:
	for key in archetype.terrain:
		gen._b[key] = archetype.terrain[key]
	# No ruin or hamlet: their places lie far off the map, where nothing is drawn.
	gen._b["ridge_ruin"] = [-500, -500]
	gen._b["ridge_hamlet"] = [-500, -500]
	gen._height_noise.seed = gen.rng.randi()
	gen._height_noise.frequency = 0.018
	gen._detail_noise.seed = gen.rng.randi()
	gen._detail_noise.frequency = 0.07
	gen._forest_noise.seed = gen.rng.randi()
	gen._forest_noise.frequency = 0.035
	gen._rock_noise.seed = gen.rng.randi()
	gen._rock_noise.frequency = 0.12
	gen._heights()
	# Only the clearing is levelled (the valley also levels its ruin and hamlet).
	var center := Vector2i(int(gen._b.sacred_tree[0]), int(gen._b.sacred_tree[1]))
	gen._flatten(center, int(gen._b.meadow_radius), maxi(gen._top(center.x, center.y), int(gen._b.water_level) + 2), 6)
	gen._columns()
	_clearing(gen, archetype)
	gen._vegetation()
	gen._founding_grounds()
	return {"sites": gen.sites, "features": gen.features}


## The settlement's clearing at the map's middle (where the valley's tree
## would stand), kept open, with the spirit spring at its heart.
static func _clearing(gen: RefCounted, archetype: Dictionary) -> void:
	var cx: int = int(gen._b.sacred_tree[0])
	var cz: int = int(gen._b.sacred_tree[1])
	var top: int = gen._top(cx, cz)
	var clear: float = float(gen._b.meadow_radius) + 0.5
	for z in range(cz - 12, cz + 14):
		for x in range(cx - 12, cx + 14):
			if Vector2(x - cx - 0.5, z - cz - 0.5).length() <= clear:
				gen.reserved[Vector2i(x, z)] = true
	gen.features["home"] = {"center": Vector3i(cx, top + 1, cz), "name": str(archetype.settlement)}
	gen.features["wells"] = [{"cell": Vector3i(cx + 2, top + 1, cz - 2), "qi": float(archetype.well_qi)}]
