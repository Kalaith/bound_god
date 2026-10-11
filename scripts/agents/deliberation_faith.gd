extends RefCounted
## Faith candidates: praying, tending a shrine, restoring a fallen one,
## telling others of the god, and answering the god's requests.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const Relics = preload("res://scripts/sim/relics.gd")

const Kind = Goals.Kind
const Need = Personality.Need


static func _candidate(kind: int, utility: float, reason: String, target: int = -1, value: float = NAN) -> Dictionary:
	return {"goal": Goals.make(kind, target), "utility": utility, "reason": reason, "value": value}


## The shrine a person thinks of as theirs: the one they attend, else the
## nearest they believe stands in their settlement.
static func attended_shrine(sim: RefCounted, agent: RefCounted) -> int:
	var id: int = int(agent.faith.shrine_id)
	if sim.faith.shrines.has(id) and sim.faith.shrines[id].state != "fallen":
		return id
	var best: int = -1
	var best_distance: float = INF
	var keys: Array = agent.beliefs.places.keys()
	keys.sort()
	for key in keys:
		var place: Dictionary = agent.beliefs.places[key]
		if place.kind != "shrine" or place.state == "fallen":
			continue
		var d: float = Vector2(place.cell.x - agent.cell.x, place.cell.z - agent.cell.z).length()
		if d < best_distance:
			best = int(place.id)
			best_distance = d
	return best


static func add(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if sim.faith == null or not agent.faith.knows:
		return
	var stage: int = FaithState.stage(agent.faith)
	var devotion: float = float(agent.faith.devotion) / 100.0
	var lowest: int = agent.lowest_need()
	var low: float = agent.need(lowest)
	if stage >= 3 or (stage == 2 and low < Balance.number("needs.urgent_threshold")):
		var temperament: float = 1.0 + (0.5 if agent.has_trait("spiritual") else 0.0) + (0.5 if agent.has_trait("pious") else 0.0)
		var deficit: float = clampf((100.0 - low) / 100.0, 0.0, 1.0)
		var utility: float = 0.25 * devotion * temperament + 0.5 * deficit * deficit
		var hour: float = sim.calendar.hour()
		if absf(hour - Balance.number("time.dawn_hour")) < 1.0 or absf(hour - Balance.number("time.dusk_hour")) < 1.0:
			utility += 0.15
		# Prayer is a rhythm, not a constant: some hours must pass between.
		if sim.calendar.tick - int(agent.faith.last_prayer_tick) < sim.calendar.ticks_per_day / 3:
			utility *= 0.2
		out.append(_candidate(Kind.PRAY, utility, "reason_devotion", -1, float(agent.faith.devotion)))
	if stage >= 3:
		var shrine_id: int = attended_shrine(sim, agent)
		if shrine_id >= 0:
			var condition: float = float(sim.faith.shrines[shrine_id].condition)
			if condition < 80.0:
				out.append(_candidate(Kind.TEND_SHRINE, 0.3 * devotion * (1.0 - condition / 100.0) * 2.0, "reason_shrine_worn", shrine_id, condition))
	if stage >= 3:
		_preach(sim, agent, out, devotion)
		_restore(sim, agent, out, devotion, stage)
		var recovery: Dictionary = Relics.recovery(sim, agent)
		if not recovery.is_empty():
			out.append(_candidate(Kind.RECOVER_RELIC, float(recovery.utility), "reason_recover_relics", int(recovery.from)))
	if sim.requests != null:
		sim.requests.candidates(sim, agent, out)


## Tell someone who does not yet believe: friends, neighbours, strangers met.
static func _preach(sim: RefCounted, agent: RefCounted, out: Array, devotion: float) -> void:
	var listener: int = -1
	var best: float = INF
	var my_stage: int = FaithState.stage(agent.faith)
	for other_id in sim.spatial.near("agents", agent.cell, 30.0):
		var other: RefCounted = sim.agents[other_id]
		if other_id == agent.id or not other.available_to_talk() or FaithState.stage(other.faith) >= mini(my_stage, 3):
			continue
		var relation: Dictionary = agent.beliefs.relations.get(other_id, {})
		if sim.calendar.tick - int(relation.get("last_chat_tick", -9999)) < sim.calendar.ticks_per_day / 2:
			continue
		var d: float = Vector2(other.cell.x - agent.cell.x, other.cell.z - agent.cell.z).length()
		if d < 30.0 and d < best:
			listener = other_id
			best = d
	if listener < 0:
		return
	var utility: float = 0.2 * devotion * (1.0 + agent.personality.sociability)
	if agent.quest_id >= 0 and sim.requests.get_request(agent.quest_id).get("kind", "") == "carry_name":
		utility += 0.3
	if agent.has_trait("curious") or agent.ambition.get("id", "") == "map_the_wilds":
		utility += 0.1
	out.append(_candidate(Kind.PREACH, utility, "reason_unbelievers", listener))


## Believers who know of a fallen shrine near home want it standing again.
static func _restore(sim: RefCounted, agent: RefCounted, out: Array, devotion: float, stage: int) -> void:
	var keys: Array = agent.beliefs.places.keys()
	keys.sort()
	for key in keys:
		var place: Dictionary = agent.beliefs.places[key]
		if place.kind != "shrine" or not sim.faith.shrines.has(int(place.id)) or sim.faith.shrines[int(place.id)].state != "fallen":
			continue
		if Vector2(place.cell.x - agent.cell.x, place.cell.z - agent.cell.z).length() > 45.0:
			continue
		var utility: float = (0.6 if stage >= 4 else 0.35) * devotion
		if agent.ambition.get("id", "") == "raise_shrine":
			utility += 0.3
		out.append(_candidate(Kind.RESTORE_SHRINE, utility, "reason_fallen_shrine", int(place.id)))
		return
