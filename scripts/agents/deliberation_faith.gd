extends RefCounted
## Faith candidates: praying, tending a shrine, restoring a fallen one,
## telling others of the god, and answering the god's requests.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")

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
	if sim.requests != null:
		sim.requests.candidates(sim, agent, out)
