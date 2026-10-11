extends RefCounted
## Craft work (M20): a sect's members refine pills at its alchemy room when
## the stores run short of them and herbs are to hand (weighed beside their
## cultivation, since the pills are for their own trials); a settlement's
## people forge tools at its smithy while it lacks them and ore and wood are
## to hand (weighed as work). Each is weighed from what the person believes.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Crafts = preload("res://scripts/sim/crafts.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")

const Kind = Goals.Kind


static func add(sim: RefCounted, agent: RefCounted, board: Dictionary, culture: Dictionary, crafting: float, push: Callable) -> void:
	_smith(sim, agent, board, culture, crafting, push)


## Whether the station's pot, the person's hands or the stores they believe
## in hold what one batch still lacks.
static func _supplied(sim: RefCounted, agent: RefCounted, station: String, id: int) -> bool:
	for resource in sim.station(station).lacking(id, 1):
		if agent.carried(resource) < 1.0 and not agent.beliefs.believes_stock(resource, int(sim.station(station).lacking(id, 1)[resource])):
			return false
	return true


## A sect member's wish to refine, as {room, utility}, or {}: stronger the
## more driven they are and the fewer pills are kept, weaker when someone
## already stands at the furnace.
static func refine(sim: RefCounted, agent: RefCounted) -> Dictionary:
	if int(agent.cultivation.get("sect_id", -1)) < 0 or agent.settlement_id < 0 or sim.settlement_life == null:
		return {}
	if Schedule.is_sleep_time(sim, agent):
		return {}
	var rooms: Array = sim.settlement_life.board(agent.settlement_id).get("alchemy", [])
	if rooms.is_empty():
		return {}
	var short: int = Crafts.pills_short(sim, agent.settlement_id)
	if short <= 0 or not _supplied(sim, agent, "alchemy_room", int(rooms[0])):
		return {}
	var goal: Dictionary = Goals.make(Kind.REFINE, int(rooms[0]))
	var others: int = 0
	for id in sim.pursuers(Goals.key(goal)):
		others += 1 if id != agent.id else 0
	var drive: float = 0.5 + 0.5 * float(agent.cultivation.drive)
	var need: float = 0.5 + 0.5 * float(short) / maxf(Balance.number("alchemy.pills_kept"), 1.0)
	var utility: float = Balance.number("alchemy.refine_pull") * drive * need * (0.3 if others > 0 else 1.0)
	return {"room": int(rooms[0]), "utility": utility}


static func _smith(sim: RefCounted, agent: RefCounted, board: Dictionary, culture: Dictionary, aptitude: float, push: Callable) -> void:
	var smithies: Array = board.get("smithies", [])
	if smithies.is_empty():
		return
	var short: int = Crafts.tools_short(sim, agent.settlement_id)
	if short <= 0 or not _supplied(sim, agent, "smithy", int(smithies[0])):
		return
	push.call(Goals.make(Kind.SMITH, int(smithies[0])), float(culture.build) * aptitude * Balance.number("tools.smith_pull"), "reason_smith")
