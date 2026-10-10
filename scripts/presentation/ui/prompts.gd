extends RefCounted
## Contextual prompts: one short line about something happening in the
## presence right now that the god could respond to, read from the state of
## the world, falling back to the first-steps guide. A prompt only points; it
## never acts. The player dismisses one with its key and it does not come
## back in this world (the ids are kept in the god's state).
## Later milestones add their own rules here (cultivation, trials, the tree).
const Text = preload("res://scripts/core/text.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const Guide = preload("res://scripts/presentation/ui/guide.gd")

const Need = Personality.Need


## {id, text} for the prompt to show now, or {}. `guide` is the player's
## setting: with it off only the contextual prompts show.
static func current(sim: RefCounted, library: RefCounted, guide: bool) -> Dictionary:
	var dismissed: Array = sim.god.prompts_dismissed
	for prompt in contextual(sim):
		if not dismissed.has(prompt.id):
			return prompt
	if not guide:
		return {}
	var step: Dictionary = Guide.step(sim, library)
	return {} if step.is_empty() or dismissed.has(step.id) else step


## Every contextual prompt that applies now, most pressing first.
static func contextual(sim: RefCounted) -> Array:
	var result: Array = []
	if sim.god.dormant:
		return result
	var hungry: RefCounted = null
	var cold: RefCounted = null
	for agent in sim.agents:
		if not agent.is_present() or not sim.in_zone(agent.position):
			continue
		if hungry == null and agent.need(Need.FOOD) < Balance.number("needs.urgent_threshold") and agent.settlement_id >= 0 \
				and Standing.food_days(sim, agent.settlement_id) < 0.5:
			hungry = agent
		if cold == null and agent.home < 0 and not sim.calendar.is_daylight() and agent.need(Need.SHELTER) < 30.0:
			cold = agent
	var threat: Dictionary = _threat(sim)
	if not threat.is_empty():
		result.append(_say("prompt_threat_" + str(threat.kind), {}))
	if hungry != null:
		result.append(_say("prompt_hungry", {"name": hungry.given_name}))
	if cold != null:
		result.append(_say("prompt_cold", {"name": cold.given_name}))
	var prayer: Dictionary = _fresh_prayer(sim)
	if not prayer.is_empty():
		result.append(_say("prompt_prayer", {"name": sim.agents[int(prayer.agent)].given_name,
			"intent": Text.label("intent_" + str(prayer.intent.get("kind", "thanks")))}))
	if _out_of_favour(sim):
		result.append(_say("prompt_no_favour", {}))
	return result


## A wolf or raider inside the presence.
static func _threat(sim: RefCounted) -> Dictionary:
	for threat in sim.threats_list():
		if sim.in_zone(Vector3(threat.cell)) and threat.kind in ["wolf", "raider"]:
			return threat
	return {}


## A prayer for something the god could answer, heard in the last hour.
static func _fresh_prayer(sim: RefCounted) -> Dictionary:
	var feed: Array = sim.faith.feed.get(sim.god.active_shrine_id, [])
	if feed.is_empty():
		return {}
	var last: Dictionary = feed.back()
	if sim.calendar.tick - int(last.tick) > sim.calendar.ticks_per_hour() or str(last.intent.get("kind", "thanks")) == "thanks":
		return {}
	return last


## Believers pray, yet the shrine holds too little Favour for any miracle.
static func _out_of_favour(sim: RefCounted) -> bool:
	var shrine: Dictionary = sim.faith.current(sim)
	if shrine.is_empty():
		return false
	var cheapest: float = INF
	for miracle in Data.miracles():
		if str(miracle.id) != "whisper":
			cheapest = minf(cheapest, float(miracle.cost))
	return float(shrine.favour) < cheapest and not shrine.prayers.is_empty()


static func _say(key: String, args: Dictionary) -> Dictionary:
	return {"id": key, "text": Text.format(key, args) if not args.is_empty() else Text.label(key)}
