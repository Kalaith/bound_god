extends RefCounted
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Template = preload("res://scripts/building/template.gd")


static func capture(world: RefCounted, a: Vector3i, b: Vector3i, title: String) -> Array:
	var low: Vector3i = Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var high: Vector3i = Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	var span: Vector3i = high - low + Vector3i.ONE
	var limits: Array = Data.template_limits().max_size
	if not world.in_bounds(low) or not world.in_bounds(high):
		return [null, "template_bounds"]
	for axis in range(3):
		if span[axis] > int(limits[axis]):
			return [null, "template_size"]
	var trimmed_low: Vector3i = high
	var trimmed_high: Vector3i = low
	var found: bool = false
	for y in range(low.y, high.y + 1):
		for z in range(low.z, high.z + 1):
			for x in range(low.x, high.x + 1):
				var cell := Vector3i(x, y, z)
				var block: int = world.get_block(cell)
				if block == 0:
					continue
				if Registry.placeable[block] == 0:
					return [null, "template_palette"]
				found = true
				trimmed_low = Vector3i(mini(trimmed_low.x, cell.x), mini(trimmed_low.y, cell.y), mini(trimmed_low.z, cell.z))
				trimmed_high = Vector3i(maxi(trimmed_high.x, cell.x), maxi(trimmed_high.y, cell.y), maxi(trimmed_high.z, cell.z))
	if not found:
		return [null, "template_empty"]
	var design := Template.new()
	design.name = title.strip_edges()
	design.size = trimmed_high - trimmed_low + Vector3i.ONE
	design.cells.resize(design.size.x * design.size.y * design.size.z)
	for y in range(design.size.y):
		for z in range(design.size.z):
			for x in range(design.size.x):
				var local := Vector3i(x, y, z)
				var cell: Vector3i = trimmed_low + local
				var block_name: String = Registry.block_name(world.get_block(cell))
				if not design.palette.has(block_name):
					design.palette.append(block_name)
				var index: int = design.index_of(local)
				design.cells[index] = design.palette.find(block_name)
				# A design keeps which way its doors face, not whether they stand open.
				if block_name == "door" and world.block_meta(cell) & 1 != 0:
					design.meta[index] = 1
	design.id = "design_" + (str(design.size) + str(design.cells) + str(design.meta)).sha256_text().left(16)
	design.recompute()
	return Template.from_dict(design.to_dict())
