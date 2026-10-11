extends RefCounted
## Herbs, alchemy and tools (M20): tiles painted after every older tile, from
## the same seeded stream, so the older tiles keep their look. `p` is the
## atlas painter (tools/make_atlas.gd) and its brushes.

const TILE: int = 32


static func paint(p: Object) -> void:
	_herb(p, Vector2i(7, 8), 0)
	_herb(p, Vector2i(0, 9), 1)
	_herb(p, Vector2i(1, 9), 2)
	_furnace_side(p, Vector2i(2, 9))
	_furnace_top(p, Vector2i(3, 9))
	_anvil(p, Vector2i(4, 9))


## A spirit herb: jade leaves on a slender stem; ripe, it bears pale blooms
## with a faint glow at their hearts.
static func _herb(p: Object, tile: Vector2i, stage: int) -> void:
	var height: int = [10, 18, 24][stage]
	var stem := Color("5e7a58")
	for y in range(TILE - height, TILE):
		p._px(tile, 15, y, stem)
		p._px(tile, 16, y, stem.darkened(0.15))
	var leaves: int = 2 + stage * 2
	for i in range(leaves):
		var y: float = TILE - 4.0 - float(i) * float(height - 4) / leaves
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var centre := Vector2(15.5 + side * 4.5, y)
		for dy in range(-2, 3):
			for dx in range(-4, 5):
				var point := Vector2(centre.x + dx, centre.y + dy)
				if absf(dx) / 4.5 + absf(dy) / 2.2 < 1.0 and p.rng.randf() < 0.95:
					p._px(tile, int(point.x), int(point.y), Color("7fb39a").darkened(p.rng.randf() * 0.2))
	if stage == 2:
		for bloom in [Vector2(15.5, 6), Vector2(10, 11), Vector2(21, 10)]:
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var d: float = Vector2(dx, dy).length()
					if d < 2.8:
						var colour := Color("f6c8d8") if d >= 1.2 else Color("fff4c0")
						p._px(tile, int(bloom.x) + dx, int(bloom.y) + dy, colour)


## An alchemy furnace: a squat bronze-banded stone body with a fire mouth.
static func _furnace_side(p: Object, tile: Vector2i) -> void:
	p._stone(tile, Color("6f655c"))
	for x in range(TILE):
		for y in [5, 6, 25, 26]:
			p._px(tile, x, y, Color("9a7a44").darkened(p.rng.randf() * 0.15))
	for y in range(14, 24):
		for x in range(10, 22):
			if Vector2(x - 15.5, (y - 23.0) * 1.2).length() < 7.0:
				p._px(tile, x, y, Color("2a1e18"))
	p._dab(tile, Vector2(15.5, 21), 3.0, Color("e0763a"), 0.85)
	p._dab(tile, Vector2(15.5, 21.5), 1.5, Color("f4c45a"), 0.9)


## The furnace's lid: a bronze ring round a dark cauldron mouth.
static func _furnace_top(p: Object, tile: Vector2i) -> void:
	p._stone(tile, Color("6f655c"))
	for y in range(TILE):
		for x in range(TILE):
			var d: float = Vector2(x - 15.5, y - 15.5).length()
			if d < 12.0 and d >= 9.0:
				p._px(tile, x, y, Color("a58248").darkened(p.rng.randf() * 0.2))
			elif d < 9.0:
				p._px(tile, x, y, Color("2e2620").lightened(p.rng.randf() * 0.05))
	p._dab(tile, Vector2(15.5, 15.5), 3.0, Color("bfe8c8"), 0.25)


## An anvil on a log stump: dark iron over pale wood.
static func _anvil(p: Object, tile: Vector2i) -> void:
	for y in range(18, TILE):
		for x in range(9, 23):
			p._px(tile, x, y, Color("8e6c50").darkened(p.rng.randf() * 0.15))
	for y in range(8, 18):
		var half: int = 12 if y < 12 else 6
		for x in range(16 - half, 16 + half):
			p._px(tile, x, y, Color("4a4846").lightened(0.1 if y == 8 else p.rng.randf() * 0.06))
