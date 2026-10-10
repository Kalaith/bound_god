extends RefCounted
## Food that will not keep: each day, berries and meals stored longer than
## their shelf life rot in the chests, and loose food lying about rots the
## same way. A settlement that loses a good deal to rot hears of it once a
## season, so the chronicle says where the food went.
const Balance = preload("res://scripts/core/balance.gd")


static func daily(sim: RefCounted) -> void:
	var settlements: RefCounted = sim.settlements
	settlements.today = sim.calendar.day()
	var shelf: Dictionary = Balance.dict("food.spoil_days")
	## settlement id -> {resource: count lost}
	var lost: Dictionary = {}
	var cells: Array = settlements.lots.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return [a.y, a.z, a.x] < [b.y, b.z, b.x])
	for cell in cells:
		var held: Dictionary = settlements.lots[cell]
		var resources: Array = held.keys()
		resources.sort()
		for resource in resources:
			var oldest: int = settlements.today - int(shelf.get(resource, 9999))
			var rotten: int = 0
			for lot in held[resource]:
				if int(lot[0]) <= oldest:
					rotten += int(lot[1])
			if rotten > 0:
				settlements.chest_take(cell, resource, rotten)
				_tally(lost, settlements.at_cell(cell), resource, rotten)
	var ids: Array = sim.items.keys()
	ids.sort()
	for id in ids:
		var item: Dictionary = sim.items[id]
		if not shelf.has(item.resource) or int(item.get("day", settlements.today)) > settlements.today - int(shelf[item.resource]):
			continue
		sim.items.erase(id)
		_tally(lost, settlements.at_cell(item.cell), item.resource, int(ceil(float(item.amount))))
	_chronicle(sim, lost)


static func _tally(lost: Dictionary, settlement_id: int, resource: String, count: int) -> void:
	if settlement_id < 0:
		return
	var entry: Dictionary = lost.get(settlement_id, {})
	entry[resource] = int(entry.get(resource, 0)) + count
	lost[settlement_id] = entry


static func _chronicle(sim: RefCounted, lost: Dictionary) -> void:
	var season: int = (sim.calendar.day() - 1) / sim.calendar.days_per_season
	var ids: Array = lost.keys()
	ids.sort()
	for id in ids:
		var total: int = 0
		var worst: String = ""
		var resources: Array = lost[id].keys()
		resources.sort()
		for resource in resources:
			total += int(lost[id][resource])
			if worst.is_empty() or int(lost[id][resource]) > int(lost[id][worst]):
				worst = resource
		var settlement: Dictionary = sim.settlements.entries[id]
		if total < Balance.integer("food.spoil_note_at") or int(settlement.get("spoil_noted", -1)) == season:
			continue
		settlement["spoil_noted"] = season
		sim.chronicle_event("food_spoiled", id, {"place": settlement.name, "resource": "resource_" + worst, "amount": total}, "cause_kept_too_long")
