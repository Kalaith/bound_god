extends RefCounted
## Places a sect builds for its Way (M19): meditation halls, where sitting on
## a mat goes faster, and tribulation grounds, where a trial counts as the
## tree's sanctuary within its reach and formation stones draw the lightning.
## Both are ordinary structures; this only finds them and their parts.
const Balance = preload("res://scripts/core/balance.gd")

const NONE := Vector3i(-1, -1, -1)


## Standing structures of one function belonging to a settlement, in id order.
static func of(sim: RefCounted, settlement_id: int, function: String) -> Array:
	var result: Array = []
	for entry in sim.structures.built():
		if entry.functions.has(function) and sim.settlements.at_cell(entry.anchor) == settlement_id:
			result.append(entry)
	return result


## Whether a cell lies inside a meditation hall.
static func in_hall(sim: RefCounted, cell: Vector3i) -> bool:
	var entry: Dictionary = sim.structures.containing(cell)
	return not entry.is_empty() and entry.functions.has("meditation_hall")


## The free mat nearest this person in one of their settlement's halls.
static func hall_mat(sim: RefCounted, agent: RefCounted) -> Vector3i:
	var best: Vector3i = NONE
	var best_distance: float = INF
	for entry in of(sim, agent.settlement_id, "meditation_hall"):
		for mat in entry.components.get("mat", []):
			var other: int = int(sim.occupied.get(mat, -1))
			if other >= 0 and other != agent.id and sim.agents[other].activity == "cultivating":
				continue
			if not sim.nav.is_walkable(mat):
				continue
			var distance: float = Vector3(mat - agent.cell).length()
			if distance < best_distance:
				best = mat
				best_distance = distance
	return best


## The tribulation ground a settlement's cultivators would face Heaven on.
static func ground(sim: RefCounted, settlement_id: int) -> Dictionary:
	var grounds: Array = of(sim, settlement_id, "tribulation_ground")
	return grounds[0] if not grounds.is_empty() else {}


## Where to stand on a ground: the walkable cell of it farthest from its
## formation stones (the middle of the platform).
static func ground_cell(sim: RefCounted, entry: Dictionary) -> Vector3i:
	var stones: Array = entry.components.get("formation", [])
	var best: Vector3i = NONE
	var best_score: float = -1.0
	var cells: Array = entry.inside.keys()
	cells.sort()
	for cell in cells:
		if not sim.nav.is_walkable(cell):
			continue
		var score: float = INF
		for stone in stones:
			score = minf(score, Vector3(cell - stone).length())
		if score > best_score:
			best = cell
			best_score = score
	return best


## The ground a cell stands on, if any.
static func ground_at(sim: RefCounted, cell: Vector3i) -> Dictionary:
	var entry: Dictionary = sim.structures.containing(cell)
	return entry if not entry.is_empty() and entry.functions.has("tribulation_ground") else {}


## A ground counts as the tree's sanctuary within the sanctuary's reach.
static func ground_sanctuary(sim: RefCounted, cell: Vector3i) -> bool:
	var tree: Vector3i = sim.features.get("sacred_tree", NONE)
	if tree.x < 0 or ground_at(sim, cell).is_empty():
		return false
	return Vector2(cell.x - tree.x, cell.z - tree.z).length() <= Balance.number("cultivation.sanctuary_reach")


## Whether a person is their sect's master or one of its elders.
static func leads(sim: RefCounted, agent: RefCounted) -> bool:
	if sim.sects == null:
		return false
	var sect: Dictionary = sim.sects.in_settlement(agent.settlement_id)
	return not sect.is_empty() and str(sect.members.get(agent.id, "")) in ["master", "elder"]


## What a sect would build for its Way: a hall once it has four members and
## none stands, a ground once one of them has faced Heaven. Only its master
## and elders propose them; `agent` null asks for the settlement as a whole.
static func wants(sim: RefCounted, settlement_id: int, have: Dictionary, agent: RefCounted = null) -> Array:
	var result: Array = []
	if sim.sects == null:
		return result
	var sect: Dictionary = sim.sects.in_settlement(settlement_id)
	if sect.is_empty() or (agent != null and not leads(sim, agent)):
		return result
	var members: int = 0
	var tried: bool = false
	for id in sect.members:
		var member: RefCounted = sim.agents[int(id)]
		if member.is_present():
			members += 1
			tried = tried or not member.cultivation.get("trials", []).is_empty()
	if members >= Balance.integer("cultivation.hall_members") and int(have.get("meditation_hall", 0)) == 0:
		result.append(["meditation_hall", "reason_no_meditation_hall", 0.7])
	if tried and int(have.get("tribulation_ground", 0)) == 0:
		result.append(["tribulation_ground", "reason_no_trial_ground", 0.6])
	return result
