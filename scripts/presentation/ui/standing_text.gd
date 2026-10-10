extends RefCounted
## A settlement's standing in words: what it is, what the next level asks
## and what it still lacks. Shared by the settlement panel and the guide.
const Text = preload("res://scripts/core/text.gd")
const Standing = preload("res://scripts/sim/standing.gd")


## "Tree Hollow is a hamlet."
static func title(settlement: Dictionary) -> String:
	return Text.format("standing_is", {"place": settlement.name, "standing": Text.label("standing_" + str(settlement.get("standing", "camp")))})


## One line per criterion of the next level, met or not, or [] at the top.
static func checklist(sim: RefCounted, id: int) -> Array:
	var settlement: Dictionary = sim.settlements.get_settlement(id)
	var next: String = Standing.next_level(str(settlement.get("standing", "camp")))
	if next.is_empty():
		return []
	var lines: Array = []
	for line in Standing.report(sim, id, next):
		lines.append({"text": Text.format("standing_line_" + str(line.key), {"have": line.have, "need": line.need}), "met": line.met})
	return lines


## The first thing the next level still lacks, as advice, or "".
static func advice(sim: RefCounted, id: int) -> String:
	var settlement: Dictionary = sim.settlements.get_settlement(id)
	var next: String = Standing.next_level(str(settlement.get("standing", "camp")))
	if next.is_empty():
		return ""
	var lines: Array = Standing.report(sim, id, next)
	var met: int = 0
	var lack: String = ""
	for line in lines:
		if line.met:
			met += 1
		elif lack.is_empty():
			lack = str(line.key)
	if lack.is_empty():
		return ""
	return Text.format("guide_standing", {"place": settlement.name, "standing": Text.label("standing_" + str(settlement.get("standing", "camp"))),
		"next": Text.label("standing_" + next), "met": met, "total": lines.size(), "advice": Text.label("guide_lack_" + lack)})
