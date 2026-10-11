extends RefCounted
## The sect's alchemy (M20b): herbs, the mortar, the drying rack, the great
## cauldron and the herb bed, painted after every older tile from the same
## seeded stream, so the older tiles keep their look. `p` is the atlas
## painter (tools/make_atlas.gd) and its brushes.

const TILE: int = 32


static func paint(p: Object) -> void:
	for stage in range(3):
		_ginseng(p, Vector2i(5 + stage, 9), stage)
	for stage in range(3):
		_thunder_root(p, Vector2i(stage, 10), stage)
	for stage in range(3):
		_frost_lotus(p, Vector2i(3 + stage, 10), stage)
	_mortar(p, Vector2i(6, 10))
	_rack(p, Vector2i(7, 10))
	_cauldron_side(p, Vector2i(0, 11))
	_cauldron_top(p, Vector2i(1, 11))
	_bed_side(p, Vector2i(2, 11))
	_bed_top(p, Vector2i(3, 11))


## A soft leaf: an ellipse of `colour` round `centre`, `w` wide and `h` high.
static func _leaf(p: Object, tile: Vector2i, centre: Vector2, w: float, h: float, colour: Color) -> void:
	for dy in range(-int(h) - 1, int(h) + 2):
		for dx in range(-int(w) - 1, int(w) + 2):
			if pow(dx / w, 2.0) + pow(dy / h, 2.0) < 1.0 and p.rng.randf() < 0.95:
				p._px(tile, int(centre.x) + dx, int(centre.y) + dy, colour.darkened(p.rng.randf() * 0.18))


## Jade ginseng: fans of five broad leaves on a low stem; ripe, a cluster of
## red berries at the heart.
static func _ginseng(p: Object, tile: Vector2i, stage: int) -> void:
	var height: int = [8, 14, 18][stage]
	var stem := Color("6b7d5a")
	for y in range(TILE - height, TILE):
		p._px(tile, 15, y, stem)
		p._px(tile, 16, y, stem.darkened(0.12))
	var top := Vector2(15.5, TILE - height)
	var fans: int = 1 + stage
	for fan in range(fans):
		var at: Vector2 = top + Vector2((fan - (fans - 1) / 2.0) * 7.0, 2.0 + fan % 2 * 3.0)
		for i in range(5):
			var angle: float = -PI * 0.5 + (i - 2) * 0.55
			_leaf(p, tile, at + Vector2.from_angle(angle) * 4.5, 2.2, 3.4, Color("5f9c7e"))
	if stage == 2:
		for berry in [Vector2(15, TILE - height - 2), Vector2(17, TILE - height - 1), Vector2(16, TILE - height - 4)]:
			p._dab(tile, berry, 1.6, Color("c4433a"), 1.0)


## Thunder root: a twisted dark root breaking the scorched earth, with
## jagged violet-white veins; ripe, it crackles with a pale glow.
static func _thunder_root(p: Object, tile: Vector2i, stage: int) -> void:
	var height: int = [9, 16, 22][stage]
	var x: float = 15.5
	for y in range(TILE - 1, TILE - height - 1, -1):
		x += p.rng.randf_range(-0.9, 0.9)
		var width: int = 2 if y > TILE - height / 2 else 1
		for dx in range(-width, width + 1):
			p._px(tile, int(x) + dx, y, Color("3b2e3a").lightened(p.rng.randf() * 0.1))
		if y % 4 == 0:
			p._px(tile, int(x), y, Color("b9a6e8"))
	for branch in range(stage + 1):
		var start := Vector2(15.5, TILE - height * (0.4 + 0.2 * branch))
		var direction: float = -1.0 if branch % 2 == 0 else 1.0
		for step in range(5 + stage * 2):
			var at: Vector2 = start + Vector2(direction * step, -step * 0.6 + (step % 2))
			p._px(tile, int(at.x), int(at.y), Color("5a4660"))
			if step % 3 == 2:
				p._px(tile, int(at.x), int(at.y) - 1, Color("d8ccff"))
	if stage == 2:
		p._dab(tile, Vector2(15.5, TILE - height), 3.0, Color("e6deff"), 0.8)
		p._dab(tile, Vector2(15.5, TILE - height), 1.2, Color("ffffff"), 1.0)


## Frost lotus: pale blue-green pads, then a closed bud, then an open
## white-and-ice bloom.
static func _frost_lotus(p: Object, tile: Vector2i, stage: int) -> void:
	for pad in [Vector2(9, 28), Vector2(22, 29)]:
		_leaf(p, tile, pad, 6.0, 2.0, Color("7fa8a0"))
	var height: int = [6, 14, 16][stage]
	for y in range(TILE - height, TILE - 2):
		p._px(tile, 15, y, Color("6f9488"))
	var heart := Vector2(15.5, TILE - height)
	if stage == 0:
		return
	if stage == 1:
		_leaf(p, tile, heart, 2.4, 4.0, Color("dcecf0"))
		return
	for i in range(7):
		var angle: float = PI + i * PI / 6.0
		_leaf(p, tile, heart + Vector2.from_angle(angle) * 4.5, 2.2, 3.6, Color("eef6fa"))
	for i in range(4):
		var angle: float = PI + 0.4 + i * PI / 4.5
		_leaf(p, tile, heart + Vector2.from_angle(angle) * 2.5, 1.6, 2.6, Color("bfe2f0"))
	p._dab(tile, heart, 1.8, Color("f6e7a8"), 1.0)


## A stone mortar on a low stand, its pestle leaning in it.
static func _mortar(p: Object, tile: Vector2i) -> void:
	for y in range(26, TILE):
		for x in range(10, 22):
			p._px(tile, x, y, Color("6e5a46").darkened(p.rng.randf() * 0.1))
	for y in range(12, 26):
		var half: float = 9.0 - (y - 12) * 0.3
		for x in range(int(16 - half), int(16 + half)):
			p._px(tile, x, y, Color("9a958a").darkened(p.rng.randf() * 0.12))
	for x in range(7, 25):
		p._px(tile, x, 12, Color("b8b2a4"))
		p._px(tile, x, 13, Color("4e4840"))
	for i in range(12):
		p._px(tile, 18 + i / 3, 12 - i, Color("8c6c4c"))
		p._px(tile, 19 + i / 3, 12 - i, Color("6e5238"))


## A drying rack: a light frame of poles hung with bundles of herbs, open
## between them.
static func _rack(p: Object, tile: Vector2i) -> void:
	var pole := Color("8a6a48")
	for y in range(TILE):
		for x in [1, 2, 29, 30]:
			p._px(tile, x, y, pole.darkened(p.rng.randf() * 0.1))
	for bar in [3, 15]:
		for x in range(1, 31):
			p._px(tile, x, bar, pole)
			p._px(tile, x, bar + 1, pole.darkened(0.2))
		for bundle in range(5):
			var cx: int = 6 + bundle * 5
			var colour: Color = [Color("7fa86a"), Color("a8b86a"), Color("6f9c84")][(bundle + bar) % 3]
			for y in range(bar + 2, bar + 10):
				var half: int = 1 + (y - bar - 2) / 3
				for dx in range(-half, half + 1):
					p._px(tile, cx + dx, y, colour.darkened(p.rng.randf() * 0.2))
			p._px(tile, cx, bar + 2, Color("b4574a"))


## The great cauldron: a broad bronze belly on three short legs, cast with
## a band of cloud-scrolls, a fire glowing beneath.
static func _cauldron_side(p: Object, tile: Vector2i) -> void:
	p._stone(tile, Color("5a5048"))
	for y in range(2, 27):
		var half: float = 14.0 - absf(y - 13.0) * 0.35
		for x in range(int(16 - half), int(16 + half)):
			p._px(tile, x, y, Color("8a6a3c").darkened(p.rng.randf() * 0.12 + absf(x - 16.0) * 0.012))
	for x in range(3, 29):
		p._px(tile, x, 2, Color("c09a5a"))
		p._px(tile, x, 3, Color("6a4c2a"))
	for scroll in range(4):
		var centre := Vector2(7.0 + scroll * 6.0, 13.0)
		for i in range(10):
			var angle: float = i * 0.7
			var at: Vector2 = centre + Vector2.from_angle(angle) * (0.4 + i * 0.25)
			p._px(tile, int(at.x), int(at.y), Color("c8a868"))
	for leg in [7, 16, 25]:
		for y in range(27, TILE):
			p._px(tile, leg, y, Color("6a4c2a"))
			p._px(tile, leg + 1, y, Color("6a4c2a"))
	p._dab(tile, Vector2(16, 30), 4.0, Color("e0763a"), 0.8)
	p._dab(tile, Vector2(16, 30.5), 2.0, Color("f4c45a"), 0.9)


## The cauldron's mouth: a heavy bronze rim round a dark brew with a jade
## gleam.
static func _cauldron_top(p: Object, tile: Vector2i) -> void:
	p._stone(tile, Color("5a5048"))
	for y in range(TILE):
		for x in range(TILE):
			var d: float = Vector2(x - 15.5, y - 15.5).length()
			if d < 15.0 and d >= 11.0:
				p._px(tile, x, y, Color("a8844a").darkened(p.rng.randf() * 0.2))
			elif d < 11.0:
				p._px(tile, x, y, Color("2c3a30").lightened(p.rng.randf() * 0.06))
	p._dab(tile, Vector2(12.5, 13.5), 3.0, Color("9fe0b8"), 0.35)
	p._dab(tile, Vector2(18.5, 18.0), 2.0, Color("cfeedc"), 0.3)


## A herb bed's side: a low frame of dark planks over pale earth.
static func _bed_side(p: Object, tile: Vector2i) -> void:
	p._planks(tile, Color("6e5238"), Color("4a3626"))
	for x in range(TILE):
		for y in range(0, 4):
			p._px(tile, x, y, Color("4e4034").lightened(p.rng.randf() * 0.08))


## Spirit soil: dark, fine earth flecked with jade, edged by the frame.
static func _bed_top(p: Object, tile: Vector2i) -> void:
	p._earth(tile, Color("4e4034"))
	for i in range(14):
		p._dab(tile, Vector2(p.rng.randf() * TILE, p.rng.randf() * TILE), p.rng.randf_range(0.6, 1.2), Color("8fd0a8"), 0.7)
	for i in range(TILE):
		for edge in [0, 1, 30, 31]:
			p._px(tile, i, edge, Color("6e5238"))
			p._px(tile, edge, i, Color("6e5238"))
