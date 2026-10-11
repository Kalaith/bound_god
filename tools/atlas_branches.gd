extends RefCounted
## Branches and sacred sites (M21): the spirit cutting, painted after every
## older tile from the same seeded stream, so the older tiles keep their
## look. `p` is the atlas painter (tools/make_atlas.gd) and its brushes.

const TILE: int = 32


static func paint(p: Object) -> void:
	_cutting(p, Vector2i(4, 11))


## A cutting of the sacred tree: a slender pale-barked stem bound with a red
## cord, tufts of the tree's own sea-green leaves and a faint glow at their
## tips, so it reads as kin to the tree and not as an ordinary sapling.
static func _cutting(p: Object, tile: Vector2i) -> void:
	for y in range(8, TILE):
		p._px(tile, 15, y, Color("9d9282"))
		p._px(tile, 16, y, Color("b3a896"))
	for x in range(13, 19):
		p._px(tile, x, 24, Color("b5473a"))
		p._px(tile, x, 25, Color("8f3a30"))
	for tuft in [Vector2(15.5, 6), Vector2(10, 10), Vector2(21, 10), Vector2(11, 16), Vector2(20, 17)]:
		for y in range(int(tuft.y) - 4, int(tuft.y) + 5):
			for x in range(int(tuft.x) - 4, int(tuft.x) + 5):
				if Vector2(x, y).distance_to(tuft) < 3.4 and p.rng.randf() < 0.92:
					p._px(tile, x, y, Color("5f9c92").darkened(p.rng.randf() * 0.2))
		p._dab(tile, tuft + Vector2(-0.5, -1.5), 1.3, Color("c6ecdf"), 0.9)
