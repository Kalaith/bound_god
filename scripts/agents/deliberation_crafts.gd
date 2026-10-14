extends RefCounted
## Craft work (M20, alchemy M20b): people refine preparations at their
## settlement's alchemy buildings when the stores lack what someone needs
## and the herbs are to hand (a sect member's pills are weighed beside their
## cultivation, since they are for their own trials); a settlement's people
## forge tools at its smithy while it lacks them and ore and wood are to
## hand (weighed as work). Each is weighed from what the person believes.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Crafts = preload("res://scripts/sim/crafts.gd")
const Alchemy = preload("res://scripts/sim/alchemy.gd")
const Data = preload("res://scripts/core/data.gd")
const Personality = preload("res://scripts/agents/personality.gd")
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


## A wish to refine, as {room, seat, recipe, utility}, or {}: at the best
## alchemy building with a bench free, the most wanted preparation the
## person may work there and believes they can supply. Sect members refine
## for their own Way (stronger the more driven they are); anyone may brew
## the mixtures, as medicine work. An alchemist is drawn more, and a batch
## left half done draws whoever could finish it.
static func refine(sim: RefCounted, agent: RefCounted) -> Dictionary:
	if agent.settlement_id < 0 or agent.is_child or sim.settlement_life == null or Schedule.is_sleep_time(sim, agent):
		return {}
	for room in sim.settlement_life.board(agent.settlement_id).get("alchemy", []):
		var entry: Dictionary = sim.structures.entries.get(int(room), {})
		if entry.is_empty():
			continue
		var seat: int = free_seat(sim, agent, int(room), entry)
		if seat < 0:
			continue
		var choice: Dictionary = choose(sim, agent, int(room), seat)
		if choice.is_empty():
			continue
		var pull: float
		if int(agent.cultivation.get("sect_id", -1)) >= 0:
			pull = Balance.number("alchemy.refine_pull") * (0.5 + 0.5 * float(agent.cultivation.drive))
		else:
			pull = Balance.number("alchemy.mixture_pull") * (0.6 + 0.04 * Personality.level(agent.skills, Personality.Skill.MEDICINE))
		if bool(agent.cultivation.get("alchemist", false)):
			pull *= float(Data.alchemy().refining.alchemist_pull)
		if bool(choice.get("started", false)):
			pull *= Balance.number("alchemy.finish_pull")
		return {"room": int(room), "seat": seat, "recipe": choice.recipe, "utility": pull * (0.5 + 0.5 * minf(float(choice.score), 1.0))}
	return {}


## A bench at the building nobody else is working, or -1: one with a batch
## left half done first, then an empty one, the lowest seat first. A person
## already refining there keeps their seat.
static func free_seat(sim: RefCounted, agent: RefCounted, room: int, entry: Dictionary) -> int:
	var taken: Dictionary = {}
	for id in sim.pursuers(Goals.key(Goals.make(Kind.REFINE, room))):
		var goal: Dictionary = sim.agents[id].intention.goal
		if id == agent.id:
			return int(goal.extra)
		taken[int(goal.extra)] = true
	var empty: int = -1
	for seat in range(Alchemy.crafters(entry)):
		if taken.has(seat):
			continue
		if not sim.alchemy.recipe_in(room, seat).is_empty():
			return seat
		if empty < 0:
			empty = seat
	return empty


## What this person would refine at a bench: {recipe, score, started}, or
## {}. A batch left half done on the bench comes first, if theirs to work.
static func choose(sim: RefCounted, agent: RefCounted, room: int, seat: int) -> Dictionary:
	var entry: Dictionary = sim.structures.entries.get(room, {})
	if entry.is_empty():
		return {}
	var started: String = sim.alchemy.recipe_in(room, seat)
	if not started.is_empty():
		var recipe: Dictionary = Data.recipe(started)
		if not Alchemy.may_work(agent, recipe) or not _can_supply(sim, agent, room, seat, started):
			return {}
		return {"recipe": started, "score": 1.0, "started": true}
	for want in Alchemy.shortfall(sim, agent.settlement_id, Alchemy.tier_of(entry)):
		var recipe: Dictionary = Data.recipe(want.recipe)
		if Alchemy.may_work(agent, recipe) and _can_supply(sim, agent, room, seat, want.recipe):
			return {"recipe": want.recipe, "score": want.score}
	return {}


## Whether the person's hands or the stores they believe in hold what a
## batch still lacks on their bench.
static func _can_supply(sim: RefCounted, agent: RefCounted, room: int, seat: int, recipe: String) -> bool:
	var lacking: Dictionary = sim.alchemy.lacking(room, seat, recipe, 1)
	for resource in lacking:
		if agent.carried(resource) < float(lacking[resource]) and not agent.beliefs.believes_stock(resource, int(lacking[resource])):
			return false
	return true


static func _smith(sim: RefCounted, agent: RefCounted, board: Dictionary, culture: Dictionary, aptitude: float, push: Callable) -> void:
	var smithies: Array = board.get("smithies", [])
	if smithies.is_empty():
		return
	var short: int = Crafts.tools_short(sim, agent.settlement_id)
	if short <= 0 or not _supplied(sim, agent, "smithy", int(smithies[0])):
		return
	push.call(Goals.make(Kind.SMITH, int(smithies[0])), float(culture.build) * aptitude * Balance.number("tools.smith_pull"), "reason_smith")
