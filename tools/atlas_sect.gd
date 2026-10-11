extends RefCounted
## The sect's halls (M19b): tiles painted after every older tile, from the
## same seeded stream, so the older tiles keep their look. `p` is the atlas
## painter (tools/make_atlas.gd) and its brushes.

const TILE: int = 32


static func paint(p: Object) -> void:
	_shelf_side(p, Vector2i(6, 4))
	_lectern_side(p, Vector2i(7, 4))
	_lectern_top(p, Vector2i(0, 7))
	_incense(p, Vector2i(1, 7))
	_cabinet_side(p, Vector2i(2, 7))
	_tablet(p, Vector2i(3, 7))
	_bell(p, Vector2i(4, 7))
	_array_top(p, Vector2i(5, 7))
	_spire_side(p, Vector2i(6, 7))
	_spire_top(p, Vector2i(7, 7))
	_jade(p, Vector2i(0, 8))
	_stele_side(p, Vector2i(1, 8))
	_banner(p, Vector2i(2, 8))
	_roof_tiles(p, Vector2i(3, 8))
	_pillar_side(p, Vector2i(4, 8))
	_pillar_top(p, Vector2i(5, 8))
	_paper_screen(p, Vector2i(6, 8))


## Shelves of rolled scrolls: dark boards, pale scroll ends tied with red.
static func _shelf_side(p: Object, tile: Vector2i) -> void:
	p._planks(tile, Color("7a5a40"), Color("4e3828"))
	for shelf in range(3):
		var top: int = 2 + shelf * 10
		for x in range(2, TILE - 2):
			for y in range(top, top + 7):
				p._px(tile, x, y, Color("3a2a20"))
		for roll in range(6):
			var centre := Vector2(5.0 + roll * 4.4, top + 3.5)
			p._dab(tile, centre, 2.0, Color("e8dcc0"), 1.0)
			p._dab(tile, centre, 0.8, Color("b4574a"), 0.9)


static func _lectern_side(p: Object, tile: Vector2i) -> void:
	for y in range(TILE):
		for x in range(TILE):
			var desk: bool = y >= 2 and y <= 9
			var stand: bool = x >= 12 and x <= 19 and y > 9
			var foot: bool = y >= 28 and x >= 6 and x <= 25
			if desk or stand or foot:
				p._px(tile, x, y, Color("8c5a3c").darkened(p.rng.randf() * 0.06))


## An open scroll laid on dark wood.
static func _lectern_top(p: Object, tile: Vector2i) -> void:
	p._planks(tile, Color("8c5a3c"), Color("5e3c28"))
	for y in range(8, 24):
		for x in range(5, 27):
			p._px(tile, x, y, Color("ece2c8").darkened(p.rng.randf() * 0.03))
	for line in range(4):
		for y in range(10, 22):
			if p.rng.randf() < 0.7:
				p._px(tile, 9 + line * 5, y, Color("3a3430"))


## A bronze burner with a curl of pale smoke.
static func _incense(p: Object, tile: Vector2i) -> void:
	p._wash(tile, Color("8a6a3a"), 0.08)
	p._strokes(tile, Color("5e4626"), 6, 8, 0.5, PI * 0.5)
	for y in range(TILE):
		var x: int = 16 + int(round(sin(y * 0.45) * 3.0))
		p._blend(tile, x, y, Color("dcd6c8"), 0.45 if y < 14 else 0.0)
	for x in range(TILE):
		p._px(tile, x, 22, Color("c9a35a"))
		p._px(tile, x, 23, Color("a8843f"))


## Rows of small drawers with brass pulls.
static func _cabinet_side(p: Object, tile: Vector2i) -> void:
	p._planks(tile, Color("a57c52"), Color("7a5a3c"))
	for row in range(4):
		for column in range(3):
			var x0: int = 2 + column * 10
			var y0: int = 2 + row * 7
			for x in range(x0, x0 + 9):
				p._px(tile, x, y0, Color("5e4230"))
				p._px(tile, x, y0 + 6, Color("5e4230"))
			for y in range(y0, y0 + 7):
				p._px(tile, x0, y, Color("5e4230"))
				p._px(tile, x0 + 8, y, Color("5e4230"))
			p._dab(tile, Vector2(x0 + 4.5, y0 + 3.5), 1.2, Color("d9b878"), 1.0)


## A black lacquered tablet with a gold column of characters.
static func _tablet(p: Object, tile: Vector2i) -> void:
	p._wash(tile, Color("2e2624"), 0.05)
	for y in range(TILE):
		for x in [2, 3, TILE - 4, TILE - 3]:
			p._px(tile, x, y, Color("8a3a30"))
	for y in range(5, 27):
		if (y % 5) != 0 and p.rng.randf() < 0.8:
			for x in range(14, 18):
				if p.rng.randf() < 0.75:
					p._px(tile, x, y, Color("d4ac62"))


## A green-bronze bell with raised bands.
static func _bell(p: Object, tile: Vector2i) -> void:
	p._wash(tile, Color("6f8a74"), 0.08)
	p._strokes(tile, Color("4e6a58"), 8, 10, 0.4, PI * 0.5)
	for band in [5, 6, 24, 25, 28]:
		for x in range(TILE):
			p._px(tile, x, band, Color("b39a5a"))
	for knob in range(4):
		p._dab(tile, Vector2(5.0 + knob * 7.0, 14.0), 1.6, Color("b39a5a"), 0.9)


## A carved stone disc: rings and the eight trigram marks.
static func _array_top(p: Object, tile: Vector2i) -> void:
	p._stone(tile, Color("9aa59c"))
	for y in range(TILE):
		for x in range(TILE):
			var d: float = Vector2(x - 15.5, y - 15.5).length()
			if absf(d - 13.5) < 0.8 or absf(d - 8.5) < 0.7 or d < 2.2:
				p._blend(tile, x, y, Color("4e6a5a"), 0.85)
	for mark in range(8):
		var at := Vector2(15.5, 15.5) + Vector2.from_angle(mark * TAU / 8.0) * 11.0
		p._dab(tile, at, 1.3, Color("c6ecdf"), 0.9)


## A dark stone shaft bound in bronze.
static func _spire_side(p: Object, tile: Vector2i) -> void:
	p._stone(tile, Color("5c5a56"))
	for band in [3, 4, 15, 16, 27, 28]:
		for x in range(TILE):
			p._px(tile, x, band, Color("b39a5a"))
	p._glow_lines(tile)


static func _spire_top(p: Object, tile: Vector2i) -> void:
	p._stone(tile, Color("5c5a56"))
	p._dab(tile, Vector2(15.5, 15.5), 7.0, Color("b39a5a"), 1.0)
	p._dab(tile, Vector2(15.5, 15.5), 3.0, Color("e6d8a0"), 1.0)


## Pale green spirit jade, clouded and veined with light.
static func _jade(p: Object, tile: Vector2i) -> void:
	p._wash(tile, Color("8ec4a8"), 0.1)
	p._strokes(tile, Color("c6ecdf"), 10, 12, 0.5, 0.6)
	p._strokes(tile, Color("5f9c82"), 8, 8, 0.4, -0.4)


## Grey stone with columns of cut characters.
static func _stele_side(p: Object, tile: Vector2i) -> void:
	p._stone(tile, Color("a8a49a"))
	for column in range(4):
		for y in range(4, 28):
			if y % 4 != 0 and p.rng.randf() < 0.7:
				p._px(tile, 6 + column * 6, y, Color("5c5a56"))
				p._px(tile, 7 + column * 6, y, Color("6c6862"))


## A long red banner with a pale emblem, hung from a pole.
static func _banner(p: Object, tile: Vector2i) -> void:
	p._wash(tile, Color("a8483c"), 0.06)
	p._strokes(tile, Color("7e3028"), 6, 14, 0.4, PI * 0.5)
	p._dab(tile, Vector2(15.5, 13.0), 6.0, Color("ece2c8"), 0.9)
	p._dab(tile, Vector2(15.5, 13.0), 2.5, Color("a8483c"), 0.9)
	for x in range(TILE):
		p._px(tile, x, 0, Color("5e4230"))
		p._px(tile, x, 1, Color("5e4230"))


## Grey-blue clay roof tiles in overlapping rows.
static func _roof_tiles(p: Object, tile: Vector2i) -> void:
	p._wash(tile, Color("6c7680"), 0.06)
	for row in range(4):
		var y0: int = row * 8
		for x in range(TILE):
			var curve: int = int(round(absf(sin(PI * (x + row * 4) / 8.0)) * 3.0))
			p._blend(tile, x, y0 + 7 - curve, Color("3e4650"), 0.85)
			p._blend(tile, x, y0 + 1, Color("8e98a0"), 0.35)


## Red lacquered wood with a gilt band at the top and foot.
static func _pillar_side(p: Object, tile: Vector2i) -> void:
	p._wash(tile, Color("9e3a2e"), 0.05)
	p._strokes(tile, Color("7a2a22"), 8, 16, 0.4, PI * 0.5)
	p._strokes(tile, Color("b8564a"), 5, 12, 0.3, PI * 0.5)
	for band in [0, 1, 30, 31]:
		for x in range(TILE):
			p._px(tile, x, band, Color("c9a35a"))


static func _pillar_top(p: Object, tile: Vector2i) -> void:
	p._wash(tile, Color("9e3a2e"), 0.05)
	p._dab(tile, Vector2(15.5, 15.5), 9.0, Color("c9a35a"), 0.8)
	p._dab(tile, Vector2(15.5, 15.5), 6.0, Color("9e3a2e"), 1.0)


## Rice paper in a dark wooden lattice.
static func _paper_screen(p: Object, tile: Vector2i) -> void:
	p._wash(tile, Color("ece4d0"), 0.03)
	for i in range(TILE):
		for line in [0, 1, 15, 16, 30, 31]:
			p._px(tile, i, line, Color("6a4e38"))
			p._px(tile, line, i, Color("6a4e38"))
		for line in [8, 23]:
			p._blend(tile, i, line, Color("6a4e38"), 0.7)
			p._blend(tile, line, i, Color("6a4e38"), 0.7)
