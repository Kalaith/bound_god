extends RefCounted
## First steps for a new god: one line naming the next thing worth trying,
## read from the state of the world. It never acts; it only points.
const Text = preload("res://scripts/core/text.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const Registry = preload("res://scripts/world/block_registry.gd")


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
	for agent in sim.agents:
		if agent.is_present() and FaithState.stage(agent.faith) >= 3:
			believers += 1
	if believers == 0:
		return Text.label("guide_miracle")
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


## Whether a home stands in the settlement by the tree, built by anyone.
static func _home_near(sim: RefCounted, settlement_id: int) -> bool:
	for entry in sim.structures.built():
		if entry.functions.has("dwelling") and sim.settlements.at_cell(entry.anchor) == settlement_id:
			return true
	return false
