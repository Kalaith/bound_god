extends RefCounted
## M13 village growth: new buildings with real uses, settlement standing,
## more people, and founding a second settlement.
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const World = preload("res://scripts/world/voxel_world.gd")
const Structures = preload("res://scripts/world/structures.gd")
const Registry = preload("res://scripts/world/block_registry.gd")


## Each valley design is recognised for the function it was made for, both as
## a template and once raised in the world.
func check_valley_designs_have_their_functions():
	var expected: Dictionary = {"timber_cottage": "dwelling", "store_shed": "storehouse", "village_hall": "hall", "garden_patch": "garden"}
	var ids: Array = expected.keys()
	ids.sort()
	for id in ids:
		var design: RefCounted = Template.from_starter(Data.starter(id))
		if not design.functions.has(expected[id]):
			return "%s is not a %s as a design: %s" % [id, expected[id], str(design.functions)]
		var world := World.new(Vector3i(20, 12, 20))
		for z in range(20):
			for x in range(20):
				world.fill(Vector3i(x, 0, z), Registry.id("grass"))
		for block in design.placement(0):
			world.set_block(Vector3i(4, 1, 4) + block[0], block[1], block[2])
		var structures := Structures.new()
		structures.initialize(world)
		var found: Array = []
		for entry in structures.built():
			found.append_array(entry.functions)
		if not found.has(expected[id]):
			return "%s raised in the world is not a %s: %s" % [id, expected[id], str(found)]
		if id == "garden_patch" and found.count("garden") != 1:
			return "one patch of planters was counted as %d gardens" % found.count("garden")
	return ""
