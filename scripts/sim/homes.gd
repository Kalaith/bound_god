extends RefCounted
## Who sleeps where. A bed sleeps one person or a couple, so partners can
## always share the home of either; each day partners living apart move in
## together, and, while the valley is abstract (no one walks to a bed), the
## homeless take the free beds of their own settlement.
const Mind = preload("res://scripts/agents/mind.gd")


## Beds a dwelling's residents fill: a couple living there fills one.
static func beds_used(sim: RefCounted, entry: Dictionary) -> int:
	var used: int = 0
	for id in entry.residents:
		var partner: int = int(sim.agents[id].partner)
		# The second of a couple sharing the home shares the first's bed.
		if partner >= 0 and partner < id and entry.residents.has(partner):
			continue
		used += 1
	return used


## Whether `agent` could make this dwelling their home: a bed free, or their
## partner already living there.
static func has_room(sim: RefCounted, entry: Dictionary, agent: RefCounted) -> bool:
	if entry.is_empty() or entry.residents.has(agent.id):
		return false
	if agent.partner >= 0 and entry.residents.has(agent.partner):
		return true
	return int(entry.capacity.get("beds", 0)) - beds_used(sim, entry) > 0


## Beds no one sleeps in.
static func free_beds(sim: RefCounted, entry: Dictionary) -> int:
	return maxi(int(entry.capacity.get("beds", 0)) - beds_used(sim, entry), 0)


static func daily(sim: RefCounted, abstract: bool) -> void:
	_forget_the_gone(sim)
	_together(sim)
	if abstract:
		_claim_free_beds(sim)


## The dead and departed are no longer anyone's neighbours (older saves kept
## them on their settlement's list, where they counted as homeless).
static func _forget_the_gone(sim: RefCounted) -> void:
	for id in sim.settlements.ids():
		var residents: Array = sim.settlements.entries[id].residents
		for i in range(residents.size() - 1, -1, -1):
			if str(sim.agents[residents[i]].life) in ["dead", "departed"]:
				residents.remove_at(i)


## Partners living apart move in together: the homeless one joins the other,
## or, both housed, the one with the later id joins the other (a home
## freed for someone else).
static func _together(sim: RefCounted) -> void:
	for agent in sim.agents:
		if not agent.is_present() or agent.partner < 0 or agent.partner < agent.id:
			continue
		var other: RefCounted = sim.agents[agent.partner]
		if not other.is_present() or other.partner != agent.id or other.home == agent.home:
			continue
		var mover: RefCounted = other
		var stayer: RefCounted = agent
		if agent.home < 0 or (other.home >= 0 and not _usable(sim, other.home, other)):
			mover = agent
			stayer = other
		if stayer.home < 0 or not _usable(sim, stayer.home, stayer):
			continue
		sim.set_home(mover, stayer.home)
		Mind.add(mover, "moved_in", sim.calendar.ticks_per_day, stayer.id)
		sim.chronicle_event("moved_in_together", stayer.settlement_id, {"a": mover.given_name, "b": stayer.given_name}, "cause_partners", [mover.id, stayer.id])


static func _usable(sim: RefCounted, home: int, resident: RefCounted) -> bool:
	var entry: Dictionary = sim.structures.entries.get(home, {})
	return not entry.is_empty() and entry.functions.has("dwelling") and sim.settlements.at_cell(entry.anchor) == resident.settlement_id


## While abstract: homeless grown people take a free bed in their own
## settlement, couples first so they stay together, then by id.
static func _claim_free_beds(sim: RefCounted) -> void:
	var free: Array = []
	for entry in sim.structures.built():
		if entry.functions.has("dwelling") and free_beds(sim, entry) > 0:
			free.append(entry)
	if free.is_empty():
		return
	free.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	for agent in sim.agents:
		if not agent.is_present() or agent.home >= 0 or agent.is_child or bool(agent.backstory.get("wayfarer", false)):
			continue
		for entry in free:
			if sim.settlements.at_cell(entry.anchor) != agent.settlement_id or not has_room(sim, entry, agent):
				continue
			sim.set_home(agent, int(entry.id))
			if agent.partner >= 0 and sim.agents[agent.partner].is_present() and sim.agents[agent.partner].home < 0:
				sim.set_home(sim.agents[agent.partner], int(entry.id))
			break
