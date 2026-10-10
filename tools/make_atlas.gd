extends SceneTree
## Paints assets/blocks_atlas.png: 16 px procedural tiles in an 8 x 7 grid,
## laid out as data/blocks.json expects (8 x 7 since fields and granaries). Run once after changing a tile:
## Godot --headless --path . --script res://tools/make_atlas.gd

const TILE: int = 16
var rng := RandomNumberGenerator.new()
var image: Image


func _init() -> void:
	rng.seed = 1717
	image = Image.create(TILE * 8, TILE * 7, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_noise(Vector2i(0, 0), Color("5a9138"), Color("4a7f2e"), Color("6ea648"))
	_grass_side(Vector2i(1, 0))
	_noise(Vector2i(2, 0), Color("7a5236"), Color("634129"), Color("8d6443"))
	_noise(Vector2i(3, 0), Color("8a8c8e"), Color("767879"), Color("a0a2a4"))
	_noise(Vector2i(4, 0), Color("d9c98f"), Color("cdb978"), Color("e6d9a6"))
	_pebbles(Vector2i(5, 0), Color("8b8172"), Color("6e665a"), Color("a69b8a"))
	_ore(Vector2i(6, 0))
	_water(Vector2i(7, 0))
	_noise(Vector2i(0, 1), Color("3a3a3e"), Color("2a2a2d"), Color("4b4b50"))
	_bark(Vector2i(1, 1), Color("8a6440"), Color("6b4a2e"))
	_rings(Vector2i(2, 1))
	_planks(Vector2i(3, 1), Color("b48a55"), Color("8d6a3e"))
	_thatch(Vector2i(4, 1))
	_bricks(Vector2i(5, 1), Color("b9b5aa"), Color("8e8a80"))
	_cobble(Vector2i(6, 1))
	_glass(Vector2i(7, 1))
	_fence(Vector2i(0, 2))
	_bed_top(Vector2i(1, 2))
	_bed_side(Vector2i(2, 2))
	_door(Vector2i(3, 2))
	_chest_side(Vector2i(4, 2))
	_planks(Vector2i(5, 2), Color("9a6e3e"), Color("6e4c28"))
	_workbench_top(Vector2i(6, 2))
	_workbench_side(Vector2i(7, 2))
	_hearth_side(Vector2i(0, 3))
	_embers(Vector2i(1, 3))
	_altar(Vector2i(2, 3), false)
	_altar(Vector2i(3, 3), true)
	_leaves(Vector2i(4, 3), Color("3f7a33"), Color("2f6427"), true)
	_bark(Vector2i(5, 3), Color("d8d2c0"), Color("b7ae96"))
	_glow_lines(Vector2i(5, 3))
	_leaves(Vector2i(6, 3), Color("467f35"), Color("356b28"), false)
	_tall_grass(Vector2i(7, 3))
	_leaves(Vector2i(0, 4), Color("7fd6b0"), Color("4fae8c"), false)
	_leaves(Vector2i(1, 4), Color("3f7a33"), Color("2f6427"), false)
	_table_top(Vector2i(0, 5))
	_table_side(Vector2i(1, 5))
	_bench(Vector2i(2, 5))
	_tilled(Vector2i(3, 5))
	_planter_side(Vector2i(4, 5))
	_lantern(Vector2i(5, 5))
	_furrows(Vector2i(6, 5))
	_bin_side(Vector2i(7, 5))
	_bin_top(Vector2i(0, 6))
	for stage in range(4):
		_crop(Vector2i(1 + stage, 6), stage)
	var error: int = image.save_png("res://assets/blocks_atlas.png")
	print("atlas saved: ", error == OK)
	quit(0 if error == OK else 1)


func _px(tile: Vector2i, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < TILE and y < TILE:
		image.set_pixel(tile.x * TILE + x, tile.y * TILE + y, color)


func _noise(tile: Vector2i, base: Color, dark: Color, light: Color) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var roll: float = rng.randf()
			_px(tile, x, y, dark if roll < 0.18 else light if roll > 0.86 else base)


func _grass_side(tile: Vector2i) -> void:
	_noise(tile, Color("7a5236"), Color("634129"), Color("8d6443"))
	for x in range(TILE):
		var depth: int = 3 + rng.randi_range(0, 2)
		for y in range(depth):
			_px(tile, x, y, Color("5f9e3c") if rng.randf() > 0.2 else Color("4d8a31"))


func _pebbles(tile: Vector2i, base: Color, dark: Color, light: Color) -> void:
	_noise(tile, base, dark, base)
	for _i in range(14):
		var x: int = rng.randi_range(0, 14)
		var y: int = rng.randi_range(0, 14)
		_px(tile, x, y, light)
		_px(tile, x + 1, y, light)
		_px(tile, x, y + 1, dark)


func _ore(tile: Vector2i) -> void:
	_noise(tile, Color("8a8c8e"), Color("767879"), Color("a0a2a4"))
	for _i in range(6):
		var x: int = rng.randi_range(1, 13)
		var y: int = rng.randi_range(1, 13)
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			_px(tile, x + d.x, y + d.y, Color("d9823b") if rng.randf() > 0.3 else Color("f2b35e"))


func _water(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var wave: float = sin((x + y * 0.5) * 0.8) * 0.5 + 0.5
			_px(tile, x, y, Color("3b6fa8").lerp(Color("5d92c9"), wave * 0.5 + rng.randf() * 0.15))


func _bark(tile: Vector2i, base: Color, dark: Color) -> void:
	for x in range(TILE):
		var stripe: bool = x % 4 == 0 or rng.randf() < 0.1
		for y in range(TILE):
			_px(tile, x, y, dark if stripe or rng.randf() < 0.08 else base)


func _rings(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var d: float = Vector2(x - 7.5, y - 7.5).length()
			var ring: bool = int(d) % 3 == 0
			_px(tile, x, y, Color("6b4a2e") if d > 7.0 else (Color("a37b4c") if ring else Color("c19a63")))


func _planks(tile: Vector2i, base: Color, seam: Color) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var color: Color = base.darkened(rng.randf() * 0.08)
			if y % 4 == 3 or (x == (y / 4 * 5 + 3) % TILE):
				color = seam
			_px(tile, x, y, color)


func _thatch(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var stroke: bool = (x + y * 2) % 5 == 0
			_px(tile, x, y, Color("a8863a") if stroke else Color("d8b65a").darkened(rng.randf() * 0.12))


func _bricks(tile: Vector2i, base: Color, mortar: Color) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var offset: int = 4 if (y / 4) % 2 == 1 else 0
			var edge: bool = y % 4 == 3 or (x + offset) % 8 == 7
			_px(tile, x, y, mortar if edge else base.darkened(rng.randf() * 0.07))


func _cobble(tile: Vector2i) -> void:
	_noise(tile, Color("6f6f6f"), Color("595959"), Color("6f6f6f"))
	for _i in range(9):
		var cx: int = rng.randi_range(1, 14)
		var cy: int = rng.randi_range(1, 14)
		var r: int = rng.randi_range(2, 3)
		var shade: Color = Color("8f8f8f").darkened(rng.randf() * 0.2)
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if x * x + y * y <= r * r:
					_px(tile, cx + x, cy + y, shade)


func _glass(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var frame: bool = x == 0 or y == 0 or x == 15 or y == 15
			_px(tile, x, y, Color("cfe8f0") if frame else Color(0.75, 0.9, 1.0, 0.22 if (x + y) % 7 else 0.5))


func _fence(tile: Vector2i) -> void:
	_bark(tile, Color("9c7447"), Color("7a5832"))


func _bed_top(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var color: Color = Color("b23b3b").darkened(rng.randf() * 0.08)
			if y < 5:
				color = Color("eeeadf")
			if x == 0 or x == 15:
				color = Color("8d6a3e")
			_px(tile, x, y, color)


func _bed_side(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			_px(tile, x, y, Color("b23b3b") if y < 9 else Color("8d6a3e").darkened(rng.randf() * 0.1))


func _door(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var color: Color = Color("8a5f33").darkened(rng.randf() * 0.08)
			if x % 5 == 0 or y == 0 or y == 15:
				color = Color("5c3d1f")
			_px(tile, x, y, color)
	_px(tile, 12, 8, Color("e6c27a"))
	_px(tile, 12, 9, Color("e6c27a"))


func _chest_side(tile: Vector2i) -> void:
	_planks(tile, Color("9a6e3e"), Color("6e4c28"))
	for x in range(TILE):
		_px(tile, x, 5, Color("3d3024"))
	for y in range(4, 9):
		_px(tile, 7, y, Color("e6c27a"))
		_px(tile, 8, y, Color("e6c27a"))


func _workbench_top(tile: Vector2i) -> void:
	_planks(tile, Color("c09460"), Color("8d6a3e"))
	for i in range(TILE):
		_px(tile, i, 7, Color("5c3d1f"))
		_px(tile, 7, i, Color("5c3d1f"))


func _workbench_side(tile: Vector2i) -> void:
	_planks(tile, Color("9a6e3e"), Color("6e4c28"))
	for y in range(3, 12):
		_px(tile, 4, y, Color("b0b4b8"))
	for x in range(9, 14):
		_px(tile, x, 5, Color("b0b4b8"))


func _hearth_side(tile: Vector2i) -> void:
	_bricks(tile, Color("7e7a74"), Color("5a5650"))
	for y in range(8, 15):
		for x in range(4, 12):
			_px(tile, x, y, Color("f08a2c") if rng.randf() > 0.4 else Color("ffd060"))


func _embers(tile: Vector2i) -> void:
	_noise(tile, Color("3a2a22"), Color("2a1d17"), Color("4a362b"))
	for _i in range(20):
		_px(tile, rng.randi_range(2, 13), rng.randi_range(2, 13), Color("ff9a3c"))


func _altar(tile: Vector2i, top: bool) -> void:
	_bricks(tile, Color("e1dccd"), Color("c4bda8"))
	var gold := Color("e6c27a")
	if top:
		for angle in range(32):
			var at: Vector2 = Vector2(7.5, 7.5) + Vector2.from_angle(angle * TAU / 32.0) * 5.0
			_px(tile, int(at.x), int(at.y), gold)
		_px(tile, 7, 7, gold)
		_px(tile, 8, 8, gold)
	else:
		for y in range(4, 12):
			_px(tile, 7, y, gold)
			_px(tile, 8, y, gold)
		for x in range(5, 11):
			_px(tile, x, 6, gold)


func _leaves(tile: Vector2i, base: Color, dark: Color, berries: bool) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var roll: float = rng.randf()
			if roll < 0.12:
				continue
			_px(tile, x, y, dark if roll < 0.4 else base)
	if berries:
		for _i in range(8):
			var x: int = rng.randi_range(1, 14)
			var y: int = rng.randi_range(1, 14)
			_px(tile, x, y, Color("c0283a"))
			_px(tile, x + 1, y, Color("e04a5a"))


func _glow_lines(tile: Vector2i) -> void:
	for y in range(TILE):
		if y % 5 == 2:
			for x in range(3, 13):
				_px(tile, x, y + (x % 3) / 2, Color("bdf5ff"))


func _tall_grass(tile: Vector2i) -> void:
	for blade in range(7):
		var x: int = 1 + blade * 2
		var height: int = rng.randi_range(8, 15)
		for y in range(TILE - height, TILE):
			_px(tile, x + (1 if y < 6 and blade % 2 == 0 else 0), y, Color("7fb04a").darkened(rng.randf() * 0.2))


func _table_top(tile: Vector2i) -> void:
	_planks(tile, Color("c49a64"), Color("9a7446"))
	for i in range(TILE):
		_px(tile, i, 0, Color("6e4c28"))
		_px(tile, i, 15, Color("6e4c28"))


func _table_side(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var leg: bool = (x < 3 or x > 12) and y > 3
			if y <= 3 or leg:
				_px(tile, x, y, Color("9a7446").darkened(rng.randf() * 0.12))


func _bench(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var seat: bool = y >= 6 and y <= 9
			var leg: bool = (x < 2 or x > 13) and y > 9
			if seat or leg:
				_px(tile, x, y, Color("8d6a3e").darkened(rng.randf() * 0.12))


func _tilled(tile: Vector2i) -> void:
	_noise(tile, Color("5e3f27"), Color("4a301d"), Color("70503a"))
	for y in range(TILE):
		if y % 4 == 1:
			for x in range(1, 15):
				_px(tile, x, y, Color("3d2818"))
	for i in range(TILE):
		_px(tile, i, 0, Color("8d6a3e"))
		_px(tile, i, 15, Color("8d6a3e"))
		_px(tile, 0, i, Color("8d6a3e"))
		_px(tile, 15, i, Color("8d6a3e"))


func _planter_side(tile: Vector2i) -> void:
	_planks(tile, Color("9a7446"), Color("6e4c28"))
	for x in range(TILE):
		_px(tile, x, 0, Color("5e3f27"))
		_px(tile, x, 1, Color("5e3f27"))


func _lantern(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var frame: bool = y < 2 or y > 13 or x < 2 or x > 13
			var glow: Color = Color("ffd27a").lerp(Color("fff1c4"), rng.randf() * 0.5)
			_px(tile, x, y, Color("3a3a3e") if frame else glow)


## Farmland: dark, damp soil in ridges.
func _furrows(tile: Vector2i) -> void:
	_noise(tile, Color("5a3a22"), Color("442b18"), Color("6b4a30"))
	for y in range(TILE):
		if y % 4 == 2:
			for x in range(TILE):
				_px(tile, x, y, Color("3a2414"))
		elif y % 4 == 0:
			for x in range(TILE):
				if rng.randf() > 0.4:
					_px(tile, x, y, Color("7a5638"))


func _bin_side(tile: Vector2i) -> void:
	_planks(tile, Color("b8945c"), Color("8a6a3c"))
	for y in range(TILE):
		_px(tile, 0, y, Color("5e4226"))
		_px(tile, 15, y, Color("5e4226"))
	for x in range(TILE):
		_px(tile, x, 4, Color("5e4226"))
		_px(tile, x, 11, Color("5e4226"))


func _bin_top(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var rim: bool = x < 2 or x > 13 or y < 2 or y > 13
			_px(tile, x, y, Color("8a6a3c") if rim else Color("d8b45a").darkened(rng.randf() * 0.25))


## A crop by stage: a sprout, a young green tuft, tall green stalks, ripe gold ears.
func _crop(tile: Vector2i, stage: int) -> void:
	var heights: Array = [4, 8, 12, 14]
	var green: Color = Color("6fae3e") if stage < 3 else Color("c9a640")
	for stalk in range(5 if stage > 0 else 3):
		var x: int = 2 + stalk * 3 if stage > 0 else 5 + stalk * 2
		var height: int = heights[stage] - rng.randi_range(0, 2)
		for y in range(TILE - height, TILE):
			_px(tile, x, y, green.darkened(rng.randf() * 0.2))
		if stage == 3:
			for y in range(TILE - height, TILE - height + 4):
				_px(tile, x + 1, y, Color("e6c65c"))
