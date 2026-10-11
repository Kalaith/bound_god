extends RefCounted
## Alchemy actions applied at the end of the tick (M20b): a crafter puts
## what they carry on their bench (seat) in an alchemy building, and works
## the bench's batches into preparations they carry to the stores. A failed
## batch loses its herbs (written to their log). Refining practises
## medicine; the first to reach `alchemist_level` in it becomes known as an
## alchemist (chronicled), and the first of each preparation a settlement
## makes is chronicled.
const Data = preload("res://scripts/core/data.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Crafts = preload("res://scripts/sim/crafts.gd")
const Alchemy = preload("res://scripts/sim/alchemy.gd")


static func add(sim: RefCounted, agent: RefCounted, room: int, seat: int, recipe: String, batches: int) -> void:
	var entry: Dictionary = sim.structures.entries.get(room, {})
	if entry.is_empty() or Alchemy.tier_of(entry) <= 0 or agent.carrying.is_empty():
		agent.step_result = {"added": 0}
		return
	var resource: String = agent.carrying.resource
	var added: int = sim.alchemy.add(room, seat, recipe, resource, int(floor(float(agent.carrying.amount))), batches, entry.anchor)
	agent.carrying.amount = float(agent.carrying.amount) - added
	if float(agent.carrying.amount) < 0.05:
		agent.carrying = {}
	agent.step_result = {"added": added}


static func refine(sim: RefCounted, agent: RefCounted, room: int, seat: int) -> void:
	var entry: Dictionary = sim.structures.entries.get(room, {})
	var tier: int = Alchemy.tier_of(entry) if not entry.is_empty() else 0
	if tier <= 0 or not agent.carrying.is_empty():
		agent.step_result = {"cooked": 0}
		return
	var recipe: String = sim.alchemy.recipe_in(room, seat)
	var result: Dictionary = sim.alchemy.refine(sim, room, seat, agent, tier)
	if result.made.is_empty() and int(result.failed) == 0:
		agent.step_result = {"cooked": 0}
		return
	_alchemist(sim, agent)
	if int(result.failed) > 0:
		agent.record(sim.calendar.tick, "message", {"text": "log_batch_failed", "args": {"recipe": "recipe_" + recipe}})
	if result.made.is_empty():
		# The herbs are lost; nothing to carry, the plan goes on to the stores.
		agent.step_result = {"cooked": 1, "failed": int(result.failed)}
		return
	var made: String = result.made.keys()[0]
	agent.carrying = {"resource": made, "amount": float(result.made[made])}
	agent.step_result = {"cooked": int(result.made[made])}
	Crafts.first_made(sim, agent, sim.settlements.at_cell(entry.anchor), made)


## Someone skilled enough in medicine becomes known as an alchemist.
static func _alchemist(sim: RefCounted, agent: RefCounted) -> void:
	if bool(agent.cultivation.get("alchemist", false)):
		return
	if Personality.level(agent.skills, Personality.Skill.MEDICINE) < int(Data.alchemy().refining.alchemist_level):
		return
	agent.cultivation["alchemist"] = true
	sim.chronicle_event("became_alchemist", agent.settlement_id, {"name": agent.full_name()}, "cause_refining", [agent.id])
