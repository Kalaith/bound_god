extends RefCounted
## First steps for a new god: one line naming the next thing worth trying,
## read from the state of the world. It never acts; it only points.
const Text = preload("res://scripts/core/text.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")


## The guide's line for now, or "" once the god has found its way.
static func line(sim: RefCounted, library: RefCounted) -> String:
	if sim.god.dormant:
		return Text.label("guide_dormant")
	var gathered: bool = false
	var placed: bool = false
	for entry in sim.command_log:
		if entry.command.get("type", "") == "edit_block":
			if int(entry.command.get("id", 0)) == 0:
				gathered = true
			else:
				placed = true
	if not gathered:
		return Text.label("guide_gather")
	if not placed:
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
