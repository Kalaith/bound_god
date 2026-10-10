extends RefCounted
## A settlement's standing: a camp, a hamlet or a village, judged each day
## only from what it has (people, homes, food in its chests, the functions
## standing in its area and a living shrine). A village is the self-sustaining
## state the first steps grow toward. Rises and falls are chronicled.
const Balance = preload("res://scripts/core/balance.gd")

const LEVELS: Array[String] = ["camp", "hamlet", "village"]
## Why a settlement fell, by the first criterion it no longer meets.
const LACKS: Dictionary = {
	"residents": "cause_lack_residents", "housed": "cause_lack_housed", "food_days": "cause_lack_food_days",
	"dwelling": "cause_lack_dwelling", "storehouse": "cause_lack_storehouse", "hall": "cause_lack_hall",
	"garden": "cause_lack_garden", "shrine": "cause_lack_shrine",
}


## Food in a settlement's chests, in days for everyone living there.
static func food_days(sim: RefCounted, id: int) -> float:
	var residents: int = maxi(present(sim, id), 1)
	return float(sim.settlements.amount(id, "berries")) / (residents * Balance.number("settlements.berries_per_person_day"))


static func present(sim: RefCounted, id: int) -> int:
	var count: int = 0
	for agent_id in sim.settlements.entries[id].residents:
		if sim.agents[agent_id].is_present():
			count += 1
	return count


## What the settlement has, against what `level` asks: an Array of
## {key, have, need, met}, in a fixed order for the settlement panel.
static func report(sim: RefCounted, id: int, level: String) -> Array:
	var rule: Dictionary = Balance.dict("settlements.standing." + level)
	var settlement: Dictionary = sim.settlements.entries[id]
	var people: int = present(sim, id)
	var housed: int = 0
	for agent_id in settlement.residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and agent.home >= 0:
			housed += 1
	var counts: Dictionary = {}
	for entry in sim.structures.built():
		if sim.settlements.at_cell(entry.anchor) != id:
			continue
		for function in entry.functions:
			counts[function] = int(counts.get(function, 0)) + 1
	var result: Array = []
	result.append({"key": "residents", "have": people, "need": int(rule.residents), "met": people >= int(rule.residents)})
	var share: float = float(housed) / maxf(people, 1.0)
	var wanted: int = ceili(float(rule.housed) * people)
	result.append({"key": "housed", "have": housed, "need": wanted, "met": people > 0 and share >= float(rule.housed) - 0.001})
	var days: float = food_days(sim, id)
	if float(rule.food_days) > 0.0:
		result.append({"key": "food_days", "have": floori(days), "need": int(rule.food_days), "met": days >= float(rule.food_days)})
	var functions: Array = rule.functions.keys()
	functions.sort()
	for function in functions:
		var have: int = int(counts.get(function, 0))
		result.append({"key": function, "have": have, "need": int(rule.functions[function]), "met": have >= int(rule.functions[function])})
	if bool(rule.shrine):
		var active: bool = sim.faith != null and sim.faith.settlement_renown(sim, id) > 0.0
		result.append({"key": "shrine", "have": int(active), "need": 1, "met": active})
	return result


static func meets(lines: Array) -> bool:
	for line in lines:
		if not line.met:
			return false
	return true


## The highest level a settlement meets now.
static func judge(sim: RefCounted, id: int) -> String:
	var level: String = LEVELS[0]
	for index in range(1, LEVELS.size()):
		if not meets(report(sim, id, LEVELS[index])):
			break
		level = LEVELS[index]
	return level


## The next level up and what it still lacks, or "" at the top.
static func next_level(level: String) -> String:
	var index: int = LEVELS.find(level)
	return LEVELS[index + 1] if index >= 0 and index + 1 < LEVELS.size() else ""


static func rank(level: String) -> int:
	return maxi(LEVELS.find(level), 0)


## Daily: judge every settlement and chronicle a change with its reason.
static func daily(sim: RefCounted) -> void:
	for id in sim.settlements.ids():
		var settlement: Dictionary = sim.settlements.entries[id]
		var before: String = str(settlement.get("standing", LEVELS[0]))
		var now: String = judge(sim, id)
		settlement["standing"] = now
		if now == before:
			continue
		if rank(now) > rank(before):
			sim.chronicle_event("standing_rose", id, {"place": settlement.name, "standing": "standing_" + now}, "cause_standing_met")
		else:
			var lacking: String = ""
			for line in report(sim, id, before):
				if not line.met:
					lacking = LACKS.get(line.key, "")
					break
			sim.chronicle_event("standing_fell", id, {"place": settlement.name, "standing": "standing_" + now}, "cause_standing_lost|" + lacking)
