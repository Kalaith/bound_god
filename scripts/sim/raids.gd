extends RefCounted
## The raider band and the director that sends it. From day 12, every few
## days, the director weighs each settlement's wealth against its defenders;
## a chosen target is warned the day before (strangers are seen watching),
## then the band walks in from the valley edge. Each raid is written to the
## chronicle with its cause and its outcome.
const Schools = preload("res://scripts/sim/schools.gd")
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Text = preload("res://scripts/core/text.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Outlaws = preload("res://scripts/sim/outlaws.gd")

const NAMES: Array[String] = ["band_ashen", "band_crows", "band_hollow"]

## band id -> {id, name, settlement_id, members, loot: resource -> int, desecrated,
##             defenders, state (watching|raiding|over), start_tick}
var bands: Dictionary = {}
var next_band: int = 1


func band_size(id: int) -> int:
	var band: Dictionary = bands.get(id, {})
	var alive: int = 0
	for member in band.get("members", []):
		if member >= 0:
			alive += 1
	return maxi(alive, 1)


static func wealth(sim: RefCounted, id: int) -> float:
	var settlement: Dictionary = sim.settlements.entries[id]
	var structures: int = 0
	for entry in sim.structures.built():
		if Vector2(entry.anchor.x - settlement.center.x, entry.anchor.z - settlement.center.z).length() <= float(settlement.radius):
			structures += 1
	# A hidden school keeps its wealth out of sight.
	return (float(sim.settlements.total(id)) + structures * 5.0) * Schools.wealth_factor(sim, id)


static func defenders(sim: RefCounted, id: int) -> int:
	var count: int = 0
	for agent_id in sim.settlements.entries[id].residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and not agent.is_child and (agent.personality.bravery > 0.1 or agent.has_trait("leader")):
			count += 1
	return count


func daily(sim: RefCounted) -> void:
	for id in bands.keys():
		var band: Dictionary = bands[id]
		if band.state == "watching" and sim.calendar.tick >= int(band.start_tick):
			_launch(sim, band)
	var day: int = sim.calendar.day()
	var first: int = Balance.integer("threats.first_raid_day")
	if day < first or (day - first) % Balance.integer("threats.raid_every_days") != 0:
		return
	for id in bands:
		if bands[id].state != "over":
			return
	var best: int = -1
	var best_score: float = 0.0
	for id in sim.settlements.ids():
		if sim.settlements.entries[id].residents.is_empty():
			continue
		var score: float = wealth(sim, id) / float(defenders(sim, id) + 1)
		if score > best_score:
			best = id
			best_score = score
	if best < 0:
		return
	var chance: float = Balance.number("threats.raid_base_chance") + wealth(sim, best) * Balance.number("threats.raid_wealth_weight")
	if sim.rng.randf() >= chance:
		return
	var band_id: int = next_band
	next_band += 1
	bands[band_id] = {"id": band_id, "name": Text.label(NAMES[(band_id - 1) % NAMES.size()]), "settlement_id": best, "members": [],
		"loot": {}, "desecrated": false, "defenders": defenders(sim, best), "state": "watching", "start_tick": sim.calendar.tick + sim.calendar.ticks_per_day / 2,
		"wealth": wealth(sim, best)}
	# The warning: strangers are seen; believers there will pray about it.
	var settlement: Dictionary = sim.settlements.entries[best]
	for agent_id in settlement.residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present():
			Mind.add(agent, "strangers_watching", sim.calendar.ticks_per_day)
	sim.chronicle_event("raid_warning", best, {"band": bands[band_id].name}, "cause_wealth|%d|%d" % [int(bands[band_id].wealth), bands[band_id].defenders])


func _launch(sim: RefCounted, band: Dictionary) -> void:
	band.state = "raiding"
	var settlement: Dictionary = sim.settlements.get_settlement(int(band.settlement_id))
	if settlement.is_empty():
		band.state = "over"
		return
	var size: Array = Balance.list("threats.raider.band")
	var count: int = sim.rng.randi_range(int(size[0]), int(size[1]))
	var edge: Vector3i = _edge(sim, settlement.center)
	var knows_god: bool = sim.faith != null and sim.faith.settlement_has_shrine(sim, int(band.settlement_id))
	for i in range(count):
		var cell: Vector3i = sim.nav.nearest_walkable(edge + Vector3i(i, 0, i % 2), 6)
		if cell.x < 0:
			continue
		# The band are people who decide for themselves (M22, outlaws.gd).
		band.members.append(Outlaws.spawn(sim, band, cell, knows_god))
	sim.chronicle_event("raid_begins", int(band.settlement_id), {"band": band.name, "count": band.members.size()}, "")


## Where the band comes from: the valley edge nearest the target.
static func _edge(sim: RefCounted, center: Vector3i) -> Vector3i:
	var size: Vector3i = sim.voxels.size
	var options: Array = [Vector2i(center.x, 14), Vector2i(center.x, size.z - 15), Vector2i(14, center.z), Vector2i(size.x - 15, center.z)]
	var best: Vector3i = Vector3i(-1, -1, -1)
	var best_distance: float = INF
	for column in options:
		var cell: Vector3i = sim.nav.surface(column.x, column.y)
		if cell.x < 0:
			continue
		var d: float = Vector2(cell.x - center.x, cell.z - center.z).length()
		if d < best_distance and not sim.nav.find_path(cell, sim.settlements.entries[sim.settlements.at_cell(center)].camp if sim.settlements.at_cell(center) >= 0 else center).is_empty():
			best = cell
			best_distance = d
	return best


func note_loot(id: int, resource: String, amount: int) -> void:
	var band: Dictionary = bands.get(id, {})
	if not band.is_empty():
		band.loot[resource] = int(band.loot.get(resource, 0)) + amount


func note_desecration(id: int) -> void:
	var band: Dictionary = bands.get(id, {})
	if not band.is_empty():
		band.desecrated = true


func on_turned_back(sim: RefCounted, entry: Dictionary, cause: String) -> void:
	var band: Dictionary = bands.get(int(entry.band), {})
	if band.is_empty() or band.get("turned", false):
		return
	band["turned"] = true
	sim.chronicle_event("raid_turned_back", int(band.settlement_id), {"band": band.name}, cause)


func on_driven_off(sim: RefCounted, entry: Dictionary) -> void:
	_member_gone(sim, entry)


func on_left(sim: RefCounted, entry: Dictionary) -> void:
	_member_gone(sim, entry)


## When the last raider is gone, the raid is over and the chronicle says how.
func _member_gone(sim: RefCounted, entry: Dictionary) -> void:
	var band: Dictionary = bands.get(int(entry.band), {})
	if band.is_empty():
		return
	var index: int = band.members.find(int(entry.id))
	if index >= 0:
		band.members[index] = -1
	for member in band.members:
		if member >= 0 and sim.threats.exists(member) and member != int(entry.id):
			return
	band.state = "over"
	var taken: int = 0
	for resource in band.loot:
		taken += int(band.loot[resource])
	var settlement_id: int = int(band.settlement_id)
	for agent_id in sim.settlements.get_settlement(settlement_id).get("residents", []):
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present():
			Mind.add(agent, "raided", sim.calendar.ticks_per_day)
	var cause: String = "cause_raid_outcome|%s|%d|%d" % [band.name, int(band.defenders), band.members.size()]
	sim.chronicle_event("raid_over_desecrated" if band.desecrated else "raid_over", settlement_id, {"band": band.name, "loot": taken}, cause)


func to_dict() -> Dictionary:
	return {"bands": bands.duplicate(true), "next_band": next_band}


func from_dict(data: Dictionary) -> void:
	bands = data.bands
	next_band = int(data.next_band)
