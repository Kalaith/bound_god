extends RefCounted
## Trade between regions (M22). Every few days (never in winter) a trader
## from a neighbouring region whose sect is not hostile stops at a settlement
## for a day, as a wayfarer does, and trades: the region's goods the
## settlement lacks, paid for with what it has to spare (wood and stone past
## a store, food past `trade.keep_days`), at the values in regions.json. A
## trader of a friendly sect may also leave a manual the settlement's sect
## lacks. Which regions send traders is the campaign's (`sim.traders`). The
## visits draw on a stream of their own, seeded from the world, the
## settlement and the day, as wayfarers' do; every trade is chronicled.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Regions = preload("res://scripts/sim/regions.gd")
const Food = preload("res://scripts/sim/food.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const Sects = preload("res://scripts/sim/sects.gd")


static func config() -> Dictionary:
	return Regions.config().trade


static func _stream(sim: RefCounted, id: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.world_seed, sim.region_id, id, sim.calendar.day(), "trader"])
	return rng


static func daily(sim: RefCounted) -> void:
	if sim.traders.is_empty():
		return
	var gap: Array = config().every_days
	for id in sim.settlements.ids():
		var settlement: Dictionary = sim.settlements.entries[id]
		if Standing.present(sim, id) == 0:
			continue
		var rng: RandomNumberGenerator = _stream(sim, id)
		if not settlement.has("next_trader"):
			settlement["next_trader"] = sim.calendar.tick + rng.randi_range(int(gap[0]), int(gap[1])) * sim.calendar.ticks_per_day
			continue
		if int(settlement.next_trader) > sim.calendar.tick or sim.calendar.is_winter():
			continue
		settlement["next_trader"] = sim.calendar.tick + rng.randi_range(int(gap[0]), int(gap[1])) * sim.calendar.ticks_per_day
		var trader: Dictionary = sim.traders[rng.randi_range(0, sim.traders.size() - 1)]
		_visit(sim, id, settlement, trader, rng)


## A trader stays a day and trades what they can.
static func _visit(sim: RefCounted, id: int, settlement: Dictionary, trader: Dictionary, rng: RandomNumberGenerator) -> void:
	var person: RefCounted = Generation.adult(rng, sim.agents.size())
	person.backstory["wayfarer"] = true
	person.backstory["trader"] = int(trader.region)
	var cell: Vector3i = sim.nav.nearest_walkable(settlement.camp + Vector3i(-3, 0, 3), 6)
	Population.arrive(sim, person, cell if cell.x >= 0 else settlement.camp, id, "")
	var guests: Array = settlement.get("guests", [])
	guests.append({"agent": person.id, "leave": sim.calendar.tick + sim.calendar.ticks_per_day})
	settlement["guests"] = guests
	var deal: Dictionary = exchange(sim, id, trader.goods)
	var manual: String = ""
	var sect: Dictionary = sim.sects.in_settlement(id) if sim.sects != null else {}
	var technique: String = str(trader.get("technique", ""))
	if bool(trader.get("friendly", false)) and not sect.is_empty() and not technique.is_empty() and not sect.get("manuals", []).has(technique):
		sect.manuals.append(technique)
		manual = technique
		sim.outbound.append({"kind": "relation", "sect": int(sect.id), "other_region": int(trader.region), "other_sect": int(trader.sect),
			"amount": float(config().manual_relation), "cause": "cause_manual_traded"})
	if deal.got.is_empty() and manual.is_empty():
		sim.chronicle_event("trader_came", id, {"name": person.full_name(), "region": str(trader.region_name)}, "cause_nothing_to_trade", [person.id])
		return
	sim.chronicle_event("traded", id, {"name": person.full_name(), "region": str(trader.region_name), "gave": _words(deal.gave), "got": _words(deal.got)},
		"cause_trader_manual|technique_" + manual if not manual.is_empty() else "cause_trader", [person.id])
	if not sect.is_empty() and not deal.got.is_empty():
		sim.outbound.append({"kind": "relation", "sect": int(sect.id), "other_region": int(trader.region), "other_sect": int(trader.sect),
			"amount": float(config().trade_relation), "cause": "cause_trader"})


## What a settlement can spare: {resource: count} past its stores' keep.
static func spare(sim: RefCounted, id: int) -> Dictionary:
	var stock: Dictionary = sim.settlements.stock_of(id)
	var result: Dictionary = {}
	var keep: Dictionary = config().keep
	var food_keep: float = float(config().keep_days) * Standing.present(sim, id) * Food.daily_need()
	var food_spare: float = maxf(Food.worth(stock) - food_keep, 0.0)
	var resources: Array = stock.keys()
	resources.sort()
	for resource in resources:
		var have: int = int(stock[resource])
		if Food.is_food(resource):
			var count: int = mini(have, floori(food_spare / maxf(Food.value(resource), 1.0)))
			if count > 0:
				result[resource] = count
				food_spare -= count * Food.value(resource)
		elif keep.has(resource) and have > int(keep[resource]):
			result[resource] = have - int(keep[resource])
	return result


## Trades the trader's goods the settlement lacks for what it can spare, by
## value. Returns {gave: {resource: n}, got: {resource: n}}.
static func exchange(sim: RefCounted, id: int, goods: Dictionary) -> Dictionary:
	var values: Dictionary = config().values
	var spare_now: Dictionary = spare(sim, id)
	var budget: float = 0.0
	for resource in spare_now:
		budget += float(values.get(resource, 0.0)) * int(spare_now[resource])
	var got: Dictionary = {}
	var spent: float = 0.0
	var most: int = int(config().most)
	var wanted: Array = goods.keys()
	wanted.sort()
	for resource in wanted:
		var price: float = float(values.get(resource, 0.0))
		if price <= 0.0 or sim.settlements.amount(id, resource) >= int(config().lacks_below):
			continue
		var count: int = mini(int(goods[resource]), floori((budget - spent) / price))
		count = mini(count, most)
		if count <= 0:
			continue
		got[resource] = count
		spent += count * price
		most -= count
	var gave: Dictionary = {}
	var owed: float = spent
	var payment: Array = spare_now.keys()
	payment.sort()
	for resource in payment:
		if owed <= 0.0:
			break
		var price: float = float(values.get(resource, 0.0))
		if price <= 0.0:
			continue
		var count: int = mini(int(spare_now[resource]), ceili(owed / price))
		var taken: int = sim.settlements.take_any(sim, id, resource, count)
		if taken > 0:
			gave[resource] = taken
			owed -= taken * price
	for resource in got:
		sim.settlements.store_any(sim, id, resource, int(got[resource]), sim.settlements.entries[id].camp)
	return {"gave": gave, "got": got}


## "3 resource_herb, 2 resource_ore" for the chronicle (worded on display).
static func _words(goods: Dictionary) -> String:
	var parts: Array = []
	var keys: Array = goods.keys()
	keys.sort()
	for resource in keys:
		parts.append("%d %s" % [int(goods[resource]), resource])
	return ", ".join(parts)
