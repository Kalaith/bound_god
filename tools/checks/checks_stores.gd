extends RefCounted
## Stores live in real chests: people use the chest that holds what they
## need, goods lie loose while there is no chest, a broken chest spills, the
## god's own stock is never the settlement's, and doors swing open and shut.
const Sim = preload("res://scripts/sim/sim.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Migration = preload("res://scripts/sim/save_migration.gd")
const Stores = preload("res://tools/checks/stores.gd")

const Need = Personality.Need


func _flat(people: bool = true) -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(48, 16, 48), "ground": 4, "people": people})


func _hungry(sim: RefCounted) -> RefCounted:
	var agent: RefCounted = sim.agents[0]
	agent.needs[Need.FOOD] = 10.0
	agent.carrying = {}
	agent.beliefs.sites.clear()
	agent.intention = {}
	agent.next_deliberation = sim.calendar.tick
	for other in sim.agents:
		if other != agent:
			other.carrying = {}
	return agent


func check_people_take_from_the_chest_that_holds_what_they_need():
	var sim: RefCounted = _flat()
	var empty: Vector3i = Stores.place_chest(sim, 1)
	var full: Vector3i = Stores.place_chest(sim, 1)
	if empty.x < 0 or full.x < 0:
		return "no room for two chests by the camp"
	sim.settlements.chest_add(full, "berries", 10)
	var agent: RefCounted = _hungry(sim)
	agent.beliefs.stock = sim.settlements.stock_of(1).duplicate()
	var start: float = agent.need(Need.FOOD)
	for _i in range(200):
		sim.step()
	if int(sim.settlements.chest_contents(full).get("berries", 0)) >= 10:
		return "nobody took berries from the chest that held them: %s" % str(agent.decisions.slice(0, 4))
	if not sim.settlements.chest_contents(empty).is_empty():
		return "the empty chest gained goods: %s" % str(sim.settlements.chest_contents(empty))
	if agent.need(Need.FOOD) <= start:
		return "the hungry person did not eat (food %.0f)" % agent.need(Need.FOOD)
	return ""


func check_without_a_chest_loads_lie_loose_and_feed_the_hungry():
	var sim: RefCounted = _flat()
	if sim.settlements.capacity(sim, 1) != 0:
		return "a settlement started with chests on a bare plain"
	var carrier: RefCounted = sim.agents[1]
	carrier.carrying = {"resource": "wood", "amount": 3.0}
	var agent: RefCounted = _hungry(sim)
	carrier.carrying = {"resource": "wood", "amount": 3.0}
	carrier.intention = {}
	carrier.next_deliberation = sim.calendar.tick
	var camp: Vector3i = sim.settlements.entries[1].camp
	sim.drop_item(camp, "berries", 4.0)
	var start: float = agent.need(Need.FOOD)
	var ate_loose: bool = false
	for _i in range(300):
		sim.step()
		ate_loose = ate_loose or agent.current_plan().get("id", "") == "eat_loose"
	if not ate_loose or agent.need(Need.FOOD) <= start:
		return "the hungry person did not eat the loose berries: %s" % str(agent.decisions.slice(0, 4))
	if not sim.settlements.stock_of(1).is_empty():
		return "loose goods were counted as stock: %s" % str(sim.settlements.stock_of(1))
	return ""


func check_a_broken_chest_spills_what_it_held():
	var sim: RefCounted = _flat(false)
	var chest: Vector3i = Stores.place_chest(sim, 1)
	sim.settlements.chest_add(chest, "stone", 7)
	if sim.settlements.amount(1, "stone") != 7:
		return "the chest's stone is not the settlement's stock"
	sim.set_block(chest, 0, 0, "test")
	if sim.settlements.chests.has(chest) or sim.settlements.amount(1, "stone") != 0:
		return "a broken chest still counts"
	var spilled: float = 0.0
	for id in sim.items:
		if sim.items[id].resource == "stone":
			spilled += float(sim.items[id].amount)
	if absf(spilled - 7.0) > 0.01:
		return "the chest spilled %.1f of 7 stone" % spilled
	return ""


func check_the_gods_stock_is_never_the_settlements():
	var sim: RefCounted = _flat(false)
	sim.god.add_stock("wood", 60)
	if sim.settlements.amount(1, "wood") != 0:
		return "the divine stock counts as the settlement's"
	var chest: Vector3i = Stores.place_chest(sim, 1)
	var given: Dictionary = sim.apply_command({"type": "transfer", "chest": chest, "resource": "wood", "amount": 50})
	if not given.ok or sim.settlements.amount(1, "wood") != 40 or sim.god.stock("wood") != 20:
		return "giving 50 wood to a chest of 40: %s, chest %d, god %d" % [str(given), sim.settlements.amount(1, "wood"), sim.god.stock("wood")]
	var full: Dictionary = sim.apply_command({"type": "transfer", "chest": chest, "resource": "wood", "amount": 1})
	if full.ok or full.reason != "transfer_full":
		return "a full chest took more: " + str(full)
	var taken: Dictionary = sim.apply_command({"type": "transfer", "chest": chest, "resource": "wood", "amount": -15})
	if not taken.ok or sim.settlements.amount(1, "wood") != 25 or sim.god.stock("wood") != 35:
		return "taking back from the chest: " + str(taken)
	return ""


func check_a_doorway_swings_open_and_shut_together():
	var sim: RefCounted = _flat(false)
	var door: int = Registry.id("door")
	var center: Vector3 = sim.zone_center()
	var low: Vector3i = sim.nav.surface(int(center.x) + 3, int(center.z) + 3)
	sim.set_block(low, door, 1, "test")
	sim.set_block(low + Vector3i.UP, door, 1, "test")
	var opened: Dictionary = sim.apply_command({"type": "toggle_door", "cell": low + Vector3i.UP})
	for cell in [low, low + Vector3i.UP]:
		if sim.voxels.block_meta(cell) != (1 | Registry.DOOR_OPEN):
			return "the doorway did not open together (%s: meta %d)" % [str(opened), sim.voxels.block_meta(cell)]
	sim.apply_command({"type": "toggle_door", "cell": low})
	for cell in [low, low + Vector3i.UP]:
		if sim.voxels.block_meta(cell) != 1:
			return "the doorway did not shut keeping its facing (meta %d)" % sim.voxels.block_meta(cell)
	if sim.apply_command({"type": "toggle_door", "cell": low + Vector3i(1, 0, 0)}).ok:
		return "a door was toggled where there is none"
	return ""


func check_an_old_save_puts_its_pooled_stock_into_chests():
	var sim: RefCounted = _flat(false)
	var chest: Vector3i = Stores.place_chest(sim, 1)
	var old: Dictionary = sim.settlements.to_dict()
	for id in old.entries:
		old.entries[id]["pile"] = old.entries[id].camp
		old.entries[id].erase("camp")
		old.entries[id]["stock"] = {"wood": 50}
	old.erase("chests")
	var migrated: Dictionary = Migration.settlements_from_1(sim, old)
	sim.settlements.from_dict(migrated)
	Migration.store_old_stock(sim, migrated.stocks)
	if not sim.settlements.chests.has(chest):
		return "the migration did not find the chest standing in the world"
	if sim.settlements.amount(1, "wood") != 40:
		return "the chest holds %d of the old 50 wood" % sim.settlements.amount(1, "wood")
	var loose: float = 0.0
	for id in sim.items:
		loose += float(sim.items[id].amount) if sim.items[id].resource == "wood" else 0.0
	if absf(loose - 10.0) > 0.01 or sim.settlements.entries[1].camp == null:
		return "the overflow was not left loose at the camp (%.1f)" % loose
	return ""
