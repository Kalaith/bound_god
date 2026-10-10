extends RefCounted
## First steps for a new god: one line naming the next thing worth trying,
## read from the state of the world. It never acts; it only points.
const Text = preload("res://scripts/core/text.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const StandingText = preload("res://scripts/presentation/ui/standing_text.gd")


## The guide's line for now, or "" once the god has found its way.
static func line(sim: RefCounted, library: RefCounted) -> String:
	if sim.god.dormant:
		return Text.label("guide_dormant")
	var gathered: bool = false
	var supplied: bool = false
	for entry in sim.command_log:
		var type: String = entry.command.get("type", "")
		if type == "edit_block" and int(entry.command.get("id", 0)) == 0:
			gathered = true
		elif type == "transfer" and int(entry.command.get("amount", 0)) > 0:
			supplied = true
	if not gathered:
		return Text.label("guide_gather")
	# The first build is a chest by the tree, where the people keep their goods.
	var hollow: int = sim.settlements.at_cell(sim.features.sacred_tree)
	if hollow >= 0 and sim.settlements.chest_cells(sim, hollow).is_empty():
		if not sim.god.hotbar.has(Registry.id("storage_chest")):
			return Text.label("guide_hotbar")
		return Text.label("guide_chest")
	if not supplied:
		return Text.label("guide_fill_chest")
	if not _home_near(sim, hollow):
		return Text.label("guide_build")
	if library.designs.is_empty():
		return Text.label("guide_capture")
	if sim.god.offered.is_empty():
		return Text.label("guide_offer")
	var believers: int = 0
	var closest: RefCounted = null
	for agent in sim.agents:
		if not agent.is_present() or not agent.faith.get("knows", false):
			continue
		if FaithState.stage(agent.faith) >= 3:
			believers += 1
		elif closest == null or float(agent.faith.devotion) > float(closest.faith.devotion):
			closest = agent
	if believers == 0:
		return _miracle_line(sim, closest)
	var village: String = _village_line(sim, hollow)
	if not village.is_empty():
		return village
	var ridge_active: bool = false
	for id in sim.faith.ids():
		if id != 1 and sim.faith.shrines[id].state == "active":
			ridge_active = true
	if sim.requests.requests.is_empty() and not ridge_active:
		return Text.label("guide_request")
	if ridge_active and sim.god.active_shrine_id == 1:
		return Text.label("guide_transfer")
	if sim.calendar.day() < 6:
		return Text.label("guide_rest")
	return ""


## Grow the settlement by the tree into a village, then send settlers out
## and give their new place a shrine. "" once all of that is under way.
static func _village_line(sim: RefCounted, hollow: int) -> String:
	if hollow < 0:
		return ""
	var advice: String = StandingText.advice(sim, hollow)
	if not advice.is_empty():
		return advice
	var asked: bool = false
	for id in sim.requests.ids():
		var request: Dictionary = sim.requests.requests[id]
		if request.state == "open" and request.kind in ["found_settlement", "raise_shrine"]:
			asked = true
	var founded: int = -1
	for id in sim.settlements.ids():
		if int(sim.settlements.entries[id].get("ground", -1)) >= 0:
			founded = id
			break
	if asked:
		return ""
	if founded < 0:
		return Text.format("guide_found", {"place": sim.settlements.entries[hollow].name})
	if not sim.faith.settlement_has_shrine(sim, founded):
		return Text.format("guide_found_shrine", {"place": sim.settlements.entries[founded].name})
	return ""


## How near the first believer is, so the god sees its miracles count.
static func _miracle_line(sim: RefCounted, closest: RefCounted) -> String:
	var shrine: Dictionary = sim.faith.current(sim)
	var favour: float = float(shrine.get("favour", 0.0))
	if favour < float(Data.miracle("kindle").cost):
		return Text.format("guide_miracle_favour", {"favour": floori(favour)})
	if closest == null or float(closest.faith.devotion) <= 0.0:
		return Text.label("guide_miracle")
	return Text.format("guide_miracle_progress", {"name": closest.given_name,
		"devotion": floori(float(closest.faith.devotion)), "needed": int(Balance.list("faith.stages")[1])})


## Whether a home stands in the settlement by the tree, built by anyone.
static func _home_near(sim: RefCounted, settlement_id: int) -> bool:
	for entry in sim.structures.built():
		if entry.functions.has("dwelling") and sim.settlements.at_cell(entry.anchor) == settlement_id:
			return true
	return false
