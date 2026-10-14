extends RefCounted
## Faith inside people, changed only by experience and read through their
## nature: seeing the god, witnessing miracles, answered and unheard prayers,
## stories, the devotion of friends, and slow neglect.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const Personality = preload("res://scripts/agents/personality.gd")

const Need = Personality.Need
## Which need a miracle relieves, for interpreting it and answering prayers.
const RELIEF: Dictionary = {"bless_growth": "food", "kindle": "shelter", "veil_of_fog": "safety", "mend": "shelter", "calm_sky": "shelter"}


## Devotion gains scaled by temperament: the pious feel more, sceptics less.
static func gain(agent: RefCounted, amount: float) -> void:
	var factor: float = 1.0
	if agent.has_trait("pious"):
		factor *= Balance.number("faith.pious_factor")
	if agent.has_trait("sceptic"):
		factor *= Balance.number("faith.sceptic_factor")
	if amount < 0.0:
		factor = 1.0
	agent.faith.devotion = clampf(float(agent.faith.devotion) + amount * factor, 0.0, 100.0)


static func shift_aspect(agent: RefCounted, aspect: int, amount: float) -> void:
	var aspects: PackedFloat32Array = agent.faith.aspects
	aspects[aspect] += amount
	FaithState.normalise(aspects)
	agent.faith.aspects = aspects


## The first person in a settlement to know the god is a story worth keeping.
static func _learn(sim: RefCounted, agent: RefCounted, how: String) -> void:
	if agent.faith.knows:
		return
	agent.faith.knows = true
	var first: bool = true
	for other in sim.agents:
		if other.id != agent.id and other.settlement_id == agent.settlement_id and other.faith.knows:
			first = false
			break
	if first:
		sim.chronicle_event("first_knew", agent.settlement_id, {"name": agent.full_name()}, how, [agent.id])


static func perceive(sim: RefCounted, agent: RefCounted, radius: float) -> bool:
	var day: int = sim.calendar.ticks_per_day
	var avatar: Vector3i = sim.god.avatar_cell
	if not sim.god.dormant and avatar.x >= 0 and Vector2(avatar.x - agent.cell.x, avatar.z - agent.cell.z).length() <= radius:
		if not agent.faith.saw_god:
			agent.faith.saw_god = true
			_learn(sim, agent, "cause_saw_god")
			var fearful: bool = agent.has_trait("cautious") and not (agent.has_trait("spiritual") or agent.has_trait("curious"))
			Mind.add(agent, "feared_the_god" if fearful else "saw_the_god", day)
			gain(agent, Balance.number("faith.first_sight_devotion"))
			if fearful:
				shift_aspect(agent, FaithState.ASPECTS.find("wrath"), 0.15)
	for event in sim.faith.events:
		if agent.faith.get("witnessed", []).has(int(event.uid)):
			continue
		var reach: float = radius + float(event.radius)
		if Vector2(event.cell.x - agent.cell.x, event.cell.z - agent.cell.z).length() > reach:
			continue
		_witness(sim, agent, event)
	for id in sim.faith.ids():
		var shrine: Dictionary = sim.faith.shrines[id]
		if Vector2(shrine.cell.x - agent.cell.x, shrine.cell.z - agent.cell.z).length() <= radius:
			agent.beliefs.places["shrine:%d" % id] = {"kind": "shrine", "id": id, "cell": shrine.cell, "state": shrine.state, "seen_tick": sim.calendar.tick}
	return false


## A miracle seen: devotion by its size and how much it mattered to them, its
## aspect in their idea of the god; one that contradicts the god's identity
## confuses instead.
static func _witness(sim: RefCounted, agent: RefCounted, event: Dictionary) -> void:
	var witnessed: Array = agent.faith.get("witnessed", [])
	witnessed.append(int(event.uid))
	if witnessed.size() > 12:
		witnessed.pop_front()
	agent.faith["witnessed"] = witnessed
	_learn(sim, agent, "cause_miracle")
	var relevance: float = 1.0
	match RELIEF.get(str(event.id), ""):
		"food":
			relevance = 1.5 if agent.need(Need.FOOD) < 50.0 else 1.0
		"shelter":
			relevance = 1.5 if agent.need(Need.SHELTER) < 50.0 else 1.0
		"safety":
			relevance = 1.5 if not agent.beliefs.threats.is_empty() else 1.0
	if bool(event.get("contradicts", false)):
		gain(agent, -2.0)
	else:
		gain(agent, Balance.number("faith.miracle_devotion") * relevance * float(event.get("scale", 1.0)))
	var aspect: int = FaithState.ASPECTS.find(str(event.aspect))
	if aspect >= 0:
		shift_aspect(agent, aspect, 0.15)
	Mind.add(agent, "witnessed_miracle", sim.calendar.ticks_per_day)


## Prayers answered within a day by an act that relieves what was asked.
static func answer_prayers(sim: RefCounted, miracle: String, cell: Vector3i, radius: float) -> int:
	var relief: String = RELIEF.get(miracle, "")
	if relief.is_empty():
		return 0
	var answered: int = 0
	var window: int = sim.calendar.ticks_per_day
	for id in sim.faith.ids():
		for prayer in sim.faith.shrines[id].prayers:
			if prayer.answered or sim.calendar.tick - int(prayer.tick) > window:
				continue
			var kind: String = str(prayer.intent.get("kind", ""))
			# Growth blessed against hunger also answers the fear of winter.
			if kind != relief and not (relief == "safety" and kind == "threat") and not (relief == "food" and kind in ["winter", "rain"]):
				continue
			var agent: RefCounted = sim.agents[int(prayer.agent)]
			if not agent.is_present() or Vector2(agent.cell.x - cell.x, agent.cell.z - cell.z).length() > radius + 16.0:
				continue
			prayer.answered = true
			answered += 1
			gain(agent, Balance.number("faith.answered_bonus"))
			Mind.add(agent, "prayer_answered", sim.calendar.ticks_per_day)
			agent.record(sim.calendar.tick, "message", {"text": "log_prayer_answered", "args": {}})
			sim.chronicle_event("prayer_answered", agent.settlement_id, {"name": agent.given_name, "intent": kind}, "cause_god", [agent.id])
	return answered


static func hourly(_sim: RefCounted) -> void:
	pass


## Daily: devotion drifts toward friends', fades without reinforcement, and
## desperate prayers left unanswered for a day hurt.
static func daily(sim: RefCounted) -> void:
	var now: int = sim.calendar.tick
	var day: int = sim.calendar.ticks_per_day
	var drift: float = Balance.number("faith.drift_per_day")
	var changes: Dictionary = {}
	for agent in sim.agents:
		if not agent.is_present() or not agent.faith.knows:
			continue
		var total: float = 0.0
		var count: int = 0
		for other_id in agent.beliefs.relations:
			var other: RefCounted = sim.agents[other_id]
			if other.is_present() and other.faith.knows and (other.id == agent.partner or agent.beliefs.opinion_of(other_id) >= Balance.number("social.friend_threshold")):
				total += float(other.faith.devotion)
				count += 1
		var change: float = 0.0
		if count > 0:
			change += (total / count - float(agent.faith.devotion)) * drift
		# Neglect wears at belief, not at a name merely heard.
		if now - int(agent.faith.last_prayer_tick) > day and FaithState.stage(agent.faith) >= 2:
			change -= Balance.number("faith.decay_per_day")
		changes[agent.id] = change
	for id in changes:
		var agent: RefCounted = sim.agents[id]
		agent.faith.devotion = clampf(float(agent.faith.devotion) + float(changes[id]), 0.0, 100.0)
	for shrine_id in sim.faith.ids():
		for prayer in sim.faith.shrines[shrine_id].prayers:
			if prayer.answered or prayer.get("unheard", false) or now - int(prayer.tick) < day:
				continue
			prayer["unheard"] = true
			if float(prayer.intent.get("level", 100.0)) < Balance.number("needs.urgent_threshold"):
				var agent: RefCounted = sim.agents[int(prayer.agent)]
				if agent.is_present():
					Mind.add(agent, "prayer_unheard", day)
					agent.faith.devotion = maxf(float(agent.faith.devotion) - Balance.number("faith.unheard_decay"), 0.0)


## A story of the god: strangers become Aware; the Aware and Curious grow in
## devotion by their trust in the teller, and take on the teller's idea of it.
static func tell_story(sim: RefCounted, teller: RefCounted, listener: RefCounted) -> void:
	if not teller.faith.knows:
		return
	var trust: float = clampf((listener.beliefs.opinion_of(teller.id) + 50.0) / 150.0, 0.0, 1.0)
	listener.faith.stories_heard = int(listener.faith.stories_heard) + 1
	teller.stats.stories_told += 1
	if not listener.faith.knows:
		_learn(sim, listener, "cause_story|" + teller.given_name)
		Mind.add(listener, "heard_of_god", sim.calendar.ticks_per_day)
		gain(listener, 8.0 + 12.0 * trust)
	else:
		var difference: float = float(teller.faith.devotion) - float(listener.faith.devotion)
		if difference > 0.0:
			gain(listener, Balance.number("faith.story_gain") * trust * difference / 100.0)
	var lerp_weight: float = Balance.number("faith.story_aspect_lerp") * trust
	var aspects: PackedFloat32Array = listener.faith.aspects
	for i in range(aspects.size()):
		aspects[i] = lerpf(aspects[i], teller.faith.aspects[i], lerp_weight)
	FaithState.normalise(aspects)
	listener.faith.aspects = aspects
	var key: String = "settlement:%d" % teller.settlement_id
	if teller.beliefs.places.has(key) and not listener.beliefs.places.has(key):
		listener.beliefs.places[key] = teller.beliefs.places[key].duplicate()
