extends RefCounted
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const Capture = preload("res://scripts/building/template_capture.gd")
const Library = preload("res://scripts/building/template_library.gd")
const World = preload("res://scripts/world/voxel_world.gd")
const Structures = preload("res://scripts/world/structures.gd")
const Registry = preload("res://scripts/world/block_registry.gd")


func check_cottage_capture_and_roof_loss() -> String:
	var cottage: RefCounted = Template.from_starter(Data.starter("miner_hut"))
	var world := World.new(Vector3i(20, 12, 20))
	var origin := Vector3i(4, 1, 4)
	for z in range(20):
		for x in range(20):
			world.fill(Vector3i(x, 0, z), Registry.id("stone"))
	for block in cottage.placement(0):
		world.set_block(origin + block[0], block[1], block[2])
	var structures := Structures.new()
	structures.initialize(world)
	var home: Dictionary = structures.at(origin + Vector3i(2, 0, 2))
	if home.is_empty() or not home.functions.has("dwelling") or home.capacity.beds != 2:
		return "A hand-built cottage was not recognised with two beds"
	if home.capacity.get("sleepers") != 9:
		return "Shelter floor counted furniture tops: %s" % str(home.capacity)
	var result: Array = Capture.capture(world, origin - Vector3i(1, 0, 1), origin + Vector3i(5, 4, 5), "Cottage")
	if result[0] == null or result[0].size != cottage.size or result[0].capacity.get("beds") != 2:
		return "Capture did not trim and recognise the cottage: " + str(result[1])
	var roof: Vector3i = origin + Vector3i(2, 2, 2)
	world.set_block(roof, 0)
	structures.on_edit(world, roof, 10, "god")
	for entry in structures.built():
		if entry.functions.has("dwelling"):
			return "A bed exposed to the sky still counts as a dwelling"
	if structures.events.back().cause != "god":
		return "Roof damage lost its cause"
	return ""


func check_template_roundtrip_and_untrusted_fields() -> String:
	var cottage: RefCounted = Template.from_starter(Data.starter("miner_hut"))
	var raw: Dictionary = cottage.to_dict()
	raw.functions = ["shrine"]
	raw.capacity = {"beds": 999}
	raw.bill = {}
	var parsed: Array = Template.from_dict(JSON.parse_string(JSON.stringify(raw)))
	if parsed[0] == null or parsed[0].to_dict() != cottage.to_dict():
		return "Derived claims were trusted, or the valid format changed"
	for corruption in ["size", "palette", "blocks", "meta", "entrance", "id", "schema_version"]:
		var bad: Dictionary = raw.duplicate(true)
		match corruption:
			"size": bad.size = [5.5, 3, 5]
			"palette": bad.palette.append("sacred_tree")
			"blocks": bad.blocks = "!!!!"
			"meta": bad.meta = {"99999": 1}
			"entrance": bad.entrance = [0, {}, 0]
			"id": bad.id = "../escape"
			"schema_version": bad.schema_version = 1.5
		var rejected: Array = Template.from_dict(bad)
		if rejected[0] != null or str(rejected[1]).is_empty():
			return "Invalid " + corruption + " was accepted"
	return ""


func check_template_files_and_backup_recovery() -> String:
	var library := Library.new()
	library.root = "user://verification_m3"
	var design: RefCounted = Template.from_starter(Data.starter("miner_hut"))
	var problem: String = library.save(design)
	if not problem.is_empty():
		return problem
	problem = library.save(design)
	var path: String = library.root.path_join(design.id + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	library.scan()
	if library.designs.size() != 1 or library.designs[0].to_dict() != design.to_dict() or not library.errors.has("template_recovered"):
		return "Library backup recovery failed"
	var exported: String = library.root.path_join("export.json")
	problem = Library.write_file(exported, design)
	var imported: Array = library.import_file(exported)
	if not problem.is_empty() or imported[0] == null or imported[0].to_dict() != design.to_dict():
		return "Export/import changed the design"
	for name in DirAccess.get_files_at(library.root):
		DirAccess.remove_absolute(library.root.path_join(name))
	DirAccess.remove_absolute(library.root)
	return ""
