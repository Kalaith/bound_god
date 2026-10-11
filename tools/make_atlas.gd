extends SceneTree
## Paints assets/blocks_atlas.png: 32 px procedural tiles in an 8 x 12 grid,
## laid out as data/blocks.json expects. The look is a soft painted wash:
## seamless low-frequency colour drift plus a few brush strokes per tile, in a
## muted palette of sage, cream, earth and faded blue (see docs/design/art_direction.md).
## Tiles are painted in order from one seed, so new tiles go at the end.
## Run once after changing a tile:
## Godot --headless --path . --script res://tools/make_atlas.gd

const TILE: int = 32
const AtlasSect = preload("res://tools/atlas_sect.gd")
const AtlasSeasons = preload("res://tools/atlas_seasons.gd")
const AtlasAlchemy = preload("res://tools/atlas_alchemy.gd")
const AtlasBranches = preload("res://tools/atlas_branches.gd")
var rng := RandomNumberGenerator.new()
var image: Image


func _init() -> void:
	rng.seed = 1717
	image = Image.create(TILE * 8, TILE * 12, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_meadow(Vector2i(0, 0))
	_grass_side(Vector2i(1, 0))
	_earth(Vector2i(2, 0), Color("8e6e50"))
	_stone(Vector2i(3, 0), Color("aaa69c"))
	_wash(Vector2i(4, 0), Color("dccfa8"), 0.05)
	_strokes(Vector2i(4, 0), Color("ebe0bd"), 10, 4, 0.35)
	_pebbles(Vector2i(5, 0))
	_ore(Vector2i(6, 0))
	_water(Vector2i(7, 0))
	_stone(Vector2i(0, 1), Color("58534e"))
	_bark(Vector2i(1, 1), Color("7d5d44"), Color("5c4232"))
	_rings(Vector2i(2, 1))
	_planks(Vector2i(3, 1), Color("bd986c"), Color("8c6c4c"))
	_thatch(Vector2i(4, 1))
	_bricks(Vector2i(5, 1), Color("c9c3b4"), Color("a39c8c"))
	_cobble(Vector2i(6, 1))
	_glass(Vector2i(7, 1))
	_bark(Vector2i(0, 2), Color("957252"), Color("74563c"))
	_bed_top(Vector2i(1, 2))
	_bed_side(Vector2i(2, 2))
	_door(Vector2i(3, 2))
	_chest_side(Vector2i(4, 2))
	_planks(Vector2i(5, 2), Color("a07650"), Color("75573a"))
	_workbench_top(Vector2i(6, 2))
	_workbench_side(Vector2i(7, 2))
	_hearth_side(Vector2i(0, 3))
	_embers(Vector2i(1, 3))
	_altar(Vector2i(2, 3), false)
	_altar(Vector2i(3, 3), true)
	_leaves(Vector2i(4, 3), Color("405a4a"), Color("2e4438"), Color("9cb596"), true)
	_bark(Vector2i(5, 3), Color("9d9282"), Color("756b5e"))
	_glow_lines(Vector2i(5, 3))
	_leaves(Vector2i(6, 3), Color("435e4b"), Color("304638"), Color("a0b898"), false)
	_tall_grass(Vector2i(7, 3))
	_leaves(Vector2i(0, 4), Color("5f9c92"), Color("427a74"), Color("c6ecdf"), false)
	_leaves(Vector2i(1, 4), Color("405a4a"), Color("2e4438"), Color("9cb596"), false)
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
	_sapling(Vector2i(5, 6))
	# Marks of heavenly lightning (M16): wood burnt black, earth scorched.
	_bark(Vector2i(6, 6), Color("3b302a"), Color("1f1915"))
	_strokes(Vector2i(6, 6), Color("8a4a2a"), 3, 3, 0.25)
	_earth(Vector2i(7, 6), Color("4b4038"))
	_strokes(Vector2i(7, 6), Color("2a2420"), 8, 5, 0.45)
	# Sect architecture (M19): a woven meditation mat, a carved formation
	# stone (side and top) and a worn path.
	_thatch(Vector2i(2, 4))
	_strokes(Vector2i(2, 4), Color("8c6c3c"), 6, 6, 0.3)
	_stone(Vector2i(3, 4), Color("8f9a92"))
	_glow_lines(Vector2i(3, 4))
	_stone(Vector2i(4, 4), Color("9aa59c"))
	_earth(Vector2i(5, 4), Color("a08a68"))
	_pebbles_on(Vector2i(5, 4))
	# The sect's halls (M19b): shelves, lecterns, incense, bells and the rest.
	AtlasSect.paint(self)
	# Herbs, alchemy and tools (M20).
	AtlasSeasons.paint(self)
	# The sect's alchemy (M20b).
	AtlasAlchemy.paint(self)
	# Branches and sacred sites (M21).
	AtlasBranches.paint(self)
	var error: int = image.save_png("res://assets/blocks_atlas.png")
	print("atlas saved: ", error == OK)
	quit(0 if error == OK else 1)


func _px(tile: Vector2i, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < TILE and y < TILE:
		image.set_pixel(tile.x * TILE + x, tile.y * TILE + y, color)


## Lays `color` over a pixel with some opacity; coordinates wrap so strokes
## stay seamless across neighbouring blocks.
func _blend(tile: Vector2i, x: int, y: int, color: Color, alpha: float) -> void:
	var px: int = tile.x * TILE + posmod(x, TILE)
	var py: int = tile.y * TILE + posmod(y, TILE)
	var under: Color = image.get_pixel(px, py)
	if under.a == 0.0:
		return
	var mixed: Color = under.lerp(color, clampf(alpha, 0.0, 1.0))
	mixed.a = under.a
	image.set_pixel(px, py, mixed)


## A seamless soft field in -1..1: a few sine waves with whole periods per tile.
func _field() -> Array:
	var waves: Array = []
	for _i in range(4):
		var fx: int = rng.randi_range(-2, 2)
		var fy: int = rng.randi_range(-2, 2)
		if fx == 0 and fy == 0:
			fx = 1
		waves.append([fx, fy, rng.randf() * TAU, rng.randf_range(0.5, 1.0)])
	return waves


func _sample(waves: Array, x: int, y: int) -> float:
	var total: float = 0.0
	var weight: float = 0.0
	for wave in waves:
		total += wave[3] * sin(TAU * (wave[0] * x + wave[1] * y) / float(TILE) + wave[2])
		weight += wave[3]
	return total / weight


## The base of every painted tile: one colour drifting gently lighter and darker.
func _wash(tile: Vector2i, base: Color, depth: float) -> void:
	var waves: Array = _field()
	for y in range(TILE):
		for x in range(TILE):
			var v: float = _sample(waves, x, y) * depth + (rng.randf() - 0.5) * depth * 0.25
			_px(tile, x, y, base.lightened(v) if v > 0.0 else base.darkened(-v))


## Short soft brush marks laid along `angle` (radians), wrapping at the edges.
func _strokes(tile: Vector2i, color: Color, count: int, length: int, alpha: float, angle: float = 0.0) -> void:
	for _i in range(count):
		var start := Vector2(rng.randf() * TILE, rng.randf() * TILE)
		var direction := Vector2.from_angle(angle + rng.randf_range(-0.35, 0.35))
		var reach: int = rng.randi_range(maxi(length / 2, 1), length)
		for step in range(reach):
			var at: Vector2 = start + direction * step
			var fade: float = sin(PI * (step + 0.5) / reach)
			_blend(tile, int(at.x), int(at.y), color, alpha * fade)
			_blend(tile, int(at.x), int(at.y) + 1, color, alpha * fade * 0.4)


func _meadow(tile: Vector2i) -> void:
	_wash(tile, Color("a3a76a"), 0.06)
	_strokes(tile, Color("bcbb86"), 14, 6, 0.4, -0.5)
	_strokes(tile, Color("889359"), 12, 5, 0.35, 0.4)


func _grass_side(tile: Vector2i) -> void:
	_earth(tile, Color("8e6e50"))
	var waves: Array = _field()
	for x in range(TILE):
		var depth: int = 6 + int(round(_sample(waves, x, 0) * 2.5))
		for y in range(depth):
			var color: Color = Color("a9a46c") if y < depth - 2 else Color("90925c")
			_px(tile, x, y, color.darkened(rng.randf() * 0.04))


func _earth(tile: Vector2i, base: Color) -> void:
	_wash(tile, base, 0.06)
	_strokes(tile, base.darkened(0.15), 8, 5, 0.35)
	_strokes(tile, base.lightened(0.12), 6, 4, 0.3)


func _stone(tile: Vector2i, base: Color) -> void:
	_wash(tile, base, 0.07)
	_strokes(tile, base.darkened(0.14), 6, 9, 0.35, 0.25)
	_strokes(tile, base.lightened(0.12), 6, 6, 0.3, -0.2)


func _pebbles(tile: Vector2i) -> void:
	_wash(tile, Color("a59c8c"), 0.05)
	for _i in range(16):
		var center := Vector2(rng.randf() * TILE, rng.randf() * TILE)
		var shade: Color = Color("bdb3a2") if rng.randf() > 0.5 else Color("8c8374")
		_dab(tile, center, rng.randf_range(1.2, 2.2), shade, 0.75)


## A soft round dab of paint.
func _dab(tile: Vector2i, center: Vector2, radius: float, color: Color, alpha: float) -> void:
	for y in range(int(center.y - radius) - 1, int(center.y + radius) + 2):
		for x in range(int(center.x - radius) - 1, int(center.x + radius) + 2):
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= radius:
				_blend(tile, x, y, color, alpha * (1.0 - smoothstep(radius * 0.6, radius, d)))


func _ore(tile: Vector2i) -> void:
	_stone(tile, Color("aaa69c"))
	for _i in range(6):
		_dab(tile, Vector2(rng.randf() * TILE, rng.randf() * TILE), rng.randf_range(1.5, 2.6), Color("c98c4f"), 0.9)


func _water(tile: Vector2i) -> void:
	_wash(tile, Color("86a3ad"), 0.05)
	for row in range(4):
		var y0: float = row * 8.0 + 3.0
		for x in range(TILE):
			var y: int = int(y0 + sin(TAU * x / float(TILE) * 2.0 + row) * 1.5)
			_blend(tile, x, y, Color("c8d6d0"), 0.35)


func _bark(tile: Vector2i, base: Color, dark: Color) -> void:
	_wash(tile, base, 0.05)
	_strokes(tile, dark, 12, 16, 0.6, PI * 0.5)
	_strokes(tile, base.lightened(0.12), 6, 10, 0.35, PI * 0.5)


func _rings(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var d: float = Vector2(x - 15.5, y - 15.5).length()
			var ring: float = 0.5 + 0.5 * cos(d * 1.1)
			var color: Color = Color("c2a27c").lerp(Color("a8865e"), ring * 0.6)
			_px(tile, x, y, Color("6a4e3a") if d > 14.5 else color)


func _planks(tile: Vector2i, base: Color, seam: Color) -> void:
	_wash(tile, base, 0.04)
	_strokes(tile, base.darkened(0.1), 10, 12, 0.35)
	for y in range(TILE):
		var board: int = y / 8
		for x in range(TILE):
			if y % 8 == 7 or (x == (board * 11 + 5) % TILE and y % 8 != 0):
				_blend(tile, x, y, seam, 0.8)


func _thatch(tile: Vector2i) -> void:
	_wash(tile, Color("d6b97c"), 0.05)
	_strokes(tile, Color("ae8f55"), 26, 10, 0.55, PI * 0.42)
	_strokes(tile, Color("ead39a"), 12, 8, 0.45, PI * 0.42)


func _bricks(tile: Vector2i, base: Color, mortar: Color) -> void:
	_wash(tile, base, 0.04)
	for y in range(TILE):
		for x in range(TILE):
			var offset: int = 8 if (y / 8) % 2 == 1 else 0
			if y % 8 == 7 or (x + offset) % 16 == 15:
				_blend(tile, x, y, mortar, 0.85)


func _cobble(tile: Vector2i) -> void:
	_wash(tile, Color("8f8c84"), 0.04)
	for _i in range(12):
		var center := Vector2(rng.randf() * TILE, rng.randf() * TILE)
		_dab(tile, center, rng.randf_range(3.5, 5.0), Color("aaa69c").darkened(rng.randf() * 0.12), 0.85)


func _glass(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var frame: bool = x < 2 or y < 2 or x > 29 or y > 29
			var streak: bool = (x + y) % 13 < 2
			_px(tile, x, y, Color("d8e2dc") if frame else Color(0.82, 0.9, 0.92, 0.45 if streak else 0.2))


func _bed_top(tile: Vector2i) -> void:
	_wash(tile, Color("b4574a"), 0.05)
	for y in range(TILE):
		for x in range(TILE):
			if y < 10:
				_px(tile, x, y, Color("ece4d2"))
			if x < 2 or x > 29:
				_px(tile, x, y, Color("8c6c4c"))


func _bed_side(tile: Vector2i) -> void:
	_wash(tile, Color("8c6c4c"), 0.05)
	for y in range(18):
		for x in range(TILE):
			_px(tile, x, y, Color("b4574a").darkened(rng.randf() * 0.04))


func _door(tile: Vector2i) -> void:
	_planks(tile, Color("93694a"), Color("6a4a32"))
	for y in range(TILE):
		for x in range(TILE):
			if x % 10 == 0 or y < 2 or y > 29:
				_px(tile, x, y, Color("5e4230"))
	_dab(tile, Vector2(24.5, 17.5), 1.6, Color("d9b878"), 1.0)


func _chest_side(tile: Vector2i) -> void:
	_planks(tile, Color("a07650"), Color("75573a"))
	for x in range(TILE):
		_px(tile, x, 10, Color("4a3a2c"))
		_px(tile, x, 11, Color("4a3a2c"))
	for y in range(8, 17):
		for x in range(14, 18):
			_px(tile, x, y, Color("d9b878"))


func _workbench_top(tile: Vector2i) -> void:
	_planks(tile, Color("c39e72"), Color("8c6c4c"))
	for i in range(TILE):
		_blend(tile, i, 15, Color("5e4230"), 0.9)
		_blend(tile, 15, i, Color("5e4230"), 0.9)


func _workbench_side(tile: Vector2i) -> void:
	_planks(tile, Color("a07650"), Color("75573a"))
	for y in range(6, 24):
		_px(tile, 8, y, Color("b7b8b2"))
		_px(tile, 9, y, Color("9c9d97"))
	for x in range(18, 28):
		_px(tile, x, 10, Color("b7b8b2"))
		_px(tile, x, 11, Color("9c9d97"))


func _hearth_side(tile: Vector2i) -> void:
	_bricks(tile, Color("8e8a82"), Color("6c6862"))
	for y in range(16, 30):
		for x in range(8, 24):
			_px(tile, x, y, Color("e08a4a").lerp(Color("f2c46e"), rng.randf() * 0.6))


func _embers(tile: Vector2i) -> void:
	_wash(tile, Color("463730"), 0.05)
	for _i in range(18):
		_dab(tile, Vector2(rng.randf_range(4, 28), rng.randf_range(4, 28)), 1.4, Color("ec9a55"), 0.9)


func _altar(tile: Vector2i, top: bool) -> void:
	_bricks(tile, Color("e6dfcd"), Color("cbc2ab"))
	var gold := Color("d4ac62")
	if top:
		for angle in range(64):
			var at: Vector2 = Vector2(15.5, 15.5) + Vector2.from_angle(angle * TAU / 64.0) * 10.0
			_dab(tile, at, 1.2, gold, 0.9)
		_dab(tile, Vector2(16, 16), 2.2, gold, 1.0)
	else:
		for y in range(8, 24):
			_px(tile, 15, y, gold)
			_px(tile, 16, y, gold)
		for x in range(10, 22):
			_px(tile, x, 12, gold)
			_px(tile, x, 13, gold)


## Foliage painted as overlapping leaf clumps with pale scalloped crests, the
## cloud motif of woodblock prints.
func _leaves(tile: Vector2i, base: Color, dark: Color, light: Color, berries: bool) -> void:
	_wash(tile, base, 0.05)
	for _i in range(18):
		_dab(tile, Vector2(rng.randf() * TILE, rng.randf() * TILE), rng.randf_range(2.0, 3.5), dark, 0.55)
	# Scallops scattered, not gridded, so a canopy never reads as wallpaper.
	for _i in range(7):
		var center := Vector2(rng.randf() * TILE, rng.randf_range(4.0, TILE))
		var radius: float = rng.randf_range(3.0, 4.5)
		for step in range(14):
			var angle: float = PI + PI * step / 13.0
			var at: Vector2 = center + Vector2.from_angle(angle) * radius
			_blend(tile, int(at.x), int(at.y), light, 0.6)
	if berries:
		for _i in range(9):
			_dab(tile, Vector2(rng.randf_range(3, 29), rng.randf_range(3, 29)), 1.6, Color("c4513f"), 1.0)


func _glow_lines(tile: Vector2i) -> void:
	for y in range(TILE):
		if y % 10 == 4:
			for x in range(6, 26):
				_px(tile, x, y + int(sin(x * 0.6) * 1.5), Color("a8ece6"))


func _tall_grass(tile: Vector2i) -> void:
	for blade in range(9):
		var x0: float = 2.0 + blade * 3.3
		var height: int = rng.randi_range(16, 30)
		var lean: float = rng.randf_range(-0.25, 0.25)
		var color: Color = Color("a5aa6c").darkened(rng.randf() * 0.18)
		for y in range(TILE - height, TILE):
			var t: float = float(TILE - y) / height
			var x: int = int(x0 + lean * t * t * 12.0)
			_px(tile, x, y, color)
			if t < 0.5:
				_px(tile, x + 1, y, color.darkened(0.08))


func _table_top(tile: Vector2i) -> void:
	_planks(tile, Color("c7a276"), Color("9c7a54"))
	for i in range(TILE):
		_px(tile, i, 0, Color("75573a"))
		_px(tile, i, TILE - 1, Color("75573a"))


func _table_side(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var leg: bool = (x < 6 or x > 25) and y > 7
			if y <= 7 or leg:
				_px(tile, x, y, Color("9c7a54").darkened(rng.randf() * 0.06))


func _bench(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var seat: bool = y >= 12 and y <= 19
			var leg: bool = (x < 4 or x > 27) and y > 19
			if seat or leg:
				_px(tile, x, y, Color("8c6c4c").darkened(rng.randf() * 0.06))


func _tilled(tile: Vector2i) -> void:
	_earth(tile, Color("6a4e38"))
	for y in range(TILE):
		if y % 8 == 3:
			for x in range(2, 30):
				_blend(tile, x, y, Color("4a3628"), 0.8)
	for i in range(TILE):
		for edge in [0, 1, TILE - 2, TILE - 1]:
			_px(tile, i, edge, Color("8c6c4c"))
			_px(tile, edge, i, Color("8c6c4c"))


func _planter_side(tile: Vector2i) -> void:
	_planks(tile, Color("9c7a54"), Color("75573a"))
	for x in range(TILE):
		for y in range(4):
			_px(tile, x, y, Color("6a4e38"))


func _lantern(tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var frame: bool = y < 4 or y > 27 or x < 4 or x > 27
			var glow: Color = Color("f4d08c").lerp(Color("fbeccb"), rng.randf() * 0.4)
			_px(tile, x, y, Color("4a4540") if frame else glow)


## Farmland: dark, damp soil in ridges.
func _furrows(tile: Vector2i) -> void:
	_earth(tile, Color("6e5038"))
	for y in range(TILE):
		if y % 8 == 4:
			for x in range(TILE):
				_blend(tile, x, y, Color("4a3628"), 0.85)
				_blend(tile, x, y + 1, Color("4a3628"), 0.4)
		elif y % 8 == 1:
			for x in range(TILE):
				_blend(tile, x, y, Color("94765a"), 0.5)


func _bin_side(tile: Vector2i) -> void:
	_planks(tile, Color("bd986c"), Color("8c6c4c"))
	for y in range(TILE):
		for x in [0, 1, TILE - 2, TILE - 1]:
			_px(tile, x, y, Color("6a4e38"))
	for x in range(TILE):
		_px(tile, x, 8, Color("6a4e38"))
		_px(tile, x, 23, Color("6a4e38"))


func _bin_top(tile: Vector2i) -> void:
	_wash(tile, Color("d9b871"), 0.08)
	for y in range(TILE):
		for x in range(TILE):
			if x < 3 or x > 28 or y < 3 or y > 28:
				_px(tile, x, y, Color("8c6c4c"))


## A crop by stage: a sprout, a young green tuft, tall green stalks, ripe gold ears.
func _crop(tile: Vector2i, stage: int) -> void:
	var heights: Array = [8, 16, 24, 28]
	var green: Color = Color("8fa462") if stage < 3 else Color("cfae5e")
	for stalk in range(5 if stage > 0 else 3):
		var x: int = 4 + stalk * 6 if stage > 0 else 10 + stalk * 5
		var height: int = heights[stage] - rng.randi_range(0, 3)
		for y in range(TILE - height, TILE):
			_px(tile, x, y, green.darkened(rng.randf() * 0.12))
			_px(tile, x + 1, y, green.darkened(0.1 + rng.randf() * 0.1))
		if stage == 3:
			for y in range(TILE - height, TILE - height + 8):
				_px(tile, x + 2, y, Color("e4c878"))
				_px(tile, x - 1, y + 1, Color("e4c878"))


## A sapling: a thin brown stem with a few small leaf tufts.
func _sapling(tile: Vector2i) -> void:
	for y in range(10, TILE):
		_px(tile, 15, y, Color("7d5d44"))
		_px(tile, 16, y, Color("8e6c50"))
	for tuft in [Vector2(15, 5), Vector2(10, 9), Vector2(21, 9), Vector2(12, 14), Vector2(20, 15)]:
		for y in range(int(tuft.y) - 3, int(tuft.y) + 4):
			for x in range(int(tuft.x) - 3, int(tuft.x) + 4):
				if Vector2(x, y).distance_to(tuft) < 3.2 and rng.randf() < 0.9:
					_px(tile, x, y, Color("6f8a5c").darkened(rng.randf() * 0.18))


## A few pale stones pressed into packed earth.
func _pebbles_on(tile: Vector2i) -> void:
	for _i in range(9):
		var x: int = rng.randi_range(1, TILE - 3)
		var y: int = rng.randi_range(1, TILE - 3)
		for dy in range(2):
			for dx in range(2):
				_blend(tile, x + dx, y + dy, Color("c4b89c"), 0.7)
