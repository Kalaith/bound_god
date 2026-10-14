extends RefCounted
## Taking a preparation (M20b): what each does to a person, and the toxicity
## pills leave behind. Preparations are taken from the stores, never carried
## in the hands. Each `use` (alchemy.json `elixirs`):
## - trial: kept for the moment Heaven answers (a foundation pill steadies the
##   preparation, a thunder-warding pill softens the storm);
## - sitting: a while of faster progress on the Way (awakening tea for a
##   mortal, a qi-gathering pill for a cultivator);
## - heal: health at once and a little of a cracked foundation mended;
## - cleanse: toxicity cleared and a cracked foundation mended fully;
## - longevity: years more of life, once in a life.
## Plain data in `agent.cultivation`: toxicity: float, elixir_until: int (tick),
## elixir_factor: float, pill / warding: bool (kept for a trial), longevity:
## float (years added).
const Data = preload("res://scripts/core/data.gd")
const Balance = preload("res://addons/hatchery/core/balance.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const SectHalls = preload("res://scripts/sim/sect_halls.gd")

## The cultivation key a trial preparation is kept under.
const KEPT: Dictionary = {"pill": "pill", "warding_pill": "warding"}


static func toxicity_config() -> Dictionary:
	return Data.alchemy().toxicity


static func is_elixir(resource: String) -> bool:
	return not Data.elixir(resource).is_empty()


## A preparation's place in the catalog (a Medicate goal's target), and back.
static func index_of(id: String) -> int:
	var list: Array = Data.alchemy().elixirs
	for i in range(list.size()):
		if list[i].id == id:
			return i
	return -1


static func id_at(index: int) -> String:
	var list: Array = Data.alchemy().elixirs
	return str(list[index].id) if index >= 0 and index < list.size() else ""


static func toxicity(agent: RefCounted) -> float:
	return float(agent.cultivation.get("toxicity", 0.0))


## Whether a person would take a preparation now: not past their toxicity
## limit, not one already kept or still working, an elixir of long life only
## once, and only what suits their realm.
static func would_take(sim: RefCounted, agent: RefCounted, id: String) -> bool:
	var elixir: Dictionary = Data.elixir(id)
	if elixir.is_empty() or agent.cultivation.is_empty():
		return false
	var c: Dictionary = agent.cultivation
	var poison: float = float(elixir.toxicity)
	if poison > 0.0 and toxicity(agent) + poison > float(toxicity_config().limit):
		return false
	match str(elixir.use):
		"trial":
			return not bool(c.get(KEPT[id], false))
		"sitting":
			var cultivator: bool = CultivationState.is_cultivator(c)
			if (str(elixir.realm) == "mortal") == cultivator:
				return false
			return int(c.get("elixir_until", -1)) <= sim.calendar.tick
		"longevity":
			return float(c.get("longevity", 0.0)) <= 0.0
	return true


## The preparation this person would take before sitting, or "".
static func for_sitting(sim: RefCounted, agent: RefCounted) -> String:
	var id: String = "qi_pill" if CultivationState.is_cultivator(agent.cultivation) else "awakening_tea"
	return id if would_take(sim, agent, id) else ""


## What a person needs from the stores for themselves now, most pressing
## first: [resource, utility]. Read by the Medicate goal.
static func needs(sim: RefCounted, agent: RefCounted) -> Array:
	var result: Array = []
	if agent.cultivation.is_empty():
		return result
	var c: Dictionary = agent.cultivation
	var cracked: bool = SectHalls.cracked(agent)
	var care: float = Balance.number("health.care_threshold")
	if (float(agent.health.hp) < care or cracked) and would_take(sim, agent, "healing_draught"):
		var hurt: float = clampf((care - float(agent.health.hp)) / care, 0.0, 1.0)
		result.append(["healing_draught", Balance.number("alchemy.medicate_pull") * (0.6 + 0.4 * hurt)])
	if (toxicity(agent) >= float(toxicity_config().cleanse_at) or cracked) and would_take(sim, agent, "cleansing_pill"):
		result.append(["cleansing_pill", Balance.number("alchemy.medicate_pull") * (0.5 + toxicity(agent))])
	if int(c.get("sect_id", -1)) >= 0 and would_take(sim, agent, "longevity_elixir") \
			and agent.age_years >= CultivationState.lifespan(c) - Balance.number("alchemy.elixir_years"):
		result.append(["longevity_elixir", Balance.number("alchemy.medicate_pull") * 1.2])
	result.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return result


## Takes one preparation from the stores of `settlement` for `agent`;
## returns how many were taken (0 or 1).
static func take(sim: RefCounted, agent: RefCounted, settlement: int, id: String) -> int:
	if not would_take(sim, agent, id):
		return 0
	if sim.settlements.take(sim, settlement, id, 1, agent.cell) <= 0:
		return 0
	consume(sim, agent, id)
	return 1


## A preparation's effect on the person who takes it.
static func consume(sim: RefCounted, agent: RefCounted, id: String) -> void:
	var elixir: Dictionary = Data.elixir(id)
	var c: Dictionary = agent.cultivation
	c["toxicity"] = minf(toxicity(agent) + float(elixir.toxicity), 1.0)
	match str(elixir.use):
		"trial":
			c[KEPT[id]] = true
		"sitting":
			c["elixir_until"] = sim.calendar.tick + int(float(elixir.days) * sim.calendar.ticks_per_day)
			c["elixir_factor"] = float(elixir.factor)
		"heal":
			agent.health.hp = minf(float(agent.health.hp) + float(elixir.heal), 100.0)
			SectHalls.mend(sim, agent, float(elixir.mend), "cause_healing_draught")
		"cleanse":
			c["toxicity"] = 0.0
			if SectHalls.cracked(agent):
				SectHalls.mend(sim, agent, 1.0, "cause_cleansing_pill")
		"longevity":
			c["longevity"] = float(c.get("longevity", 0.0)) + float(elixir.years)
			sim.chronicle_event("longevity_taken", agent.settlement_id, {"name": agent.full_name(), "years": int(elixir.years)}, "cause_longevity_elixir", [agent.id])
	agent.record(sim.calendar.tick, "message", {"text": "log_took_elixir", "args": {"elixir": "resource_" + id}})


## How much faster a sitting goes for what the person has taken: an active
## pill or tea, slowed by the toxicity pills leave.
static func sitting_factor(sim: RefCounted, agent: RefCounted) -> float:
	var c: Dictionary = agent.cultivation
	var factor: float = 1.0
	if int(c.get("elixir_until", -1)) > sim.calendar.tick:
		factor = float(c.get("elixir_factor", 1.0))
	return factor * (1.0 - float(toxicity_config().rate) * toxicity(agent))


## A trial's preparation, less what toxicity takes from it; the foundation
## pill's help is added by the trial itself.
static func trial_preparation(agent: RefCounted) -> float:
	var pill: float = float(Data.elixir("pill").preparation) if bool(agent.cultivation.get("pill", false)) else 0.0
	return pill - float(toxicity_config().preparation) * toxicity(agent)


## Toxicity fades a day at a time.
static func daily(sim: RefCounted) -> void:
	var fade: float = float(toxicity_config().decay)
	for agent in sim.agents:
		if agent.is_present() and float(agent.cultivation.get("toxicity", 0.0)) > 0.0:
			agent.cultivation.toxicity = maxf(float(agent.cultivation.toxicity) - fade, 0.0)
