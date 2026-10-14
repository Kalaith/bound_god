extends RefCounted
## Faith message receivers: the god's whispers and divine requests.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const Personality = preload("res://scripts/agents/personality.gd")

const KINDS: Array[String] = ["whisper", "divine_request"]


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


static func receive(sim: RefCounted, agent: RefCounted, message: Dictionary) -> bool:
	match str(message.kind):
		"whisper":
			_whisper(sim, agent, message)
		"divine_request":
			if sim.requests != null:
				return sim.requests.receive(sim, agent, message)
	return false


## Believers feel the god urge them, and that urging joins their reasoning
## for a day; the rest hear only a strange voice.
static func _whisper(sim: RefCounted, agent: RefCounted, message: Dictionary) -> void:
	var day: int = sim.calendar.ticks_per_day
	if FaithState.stage(agent.faith) >= 3:
		var bonus: float = Balance.number("faith.whisper_factor") * float(agent.faith.devotion) / 100.0
		agent.whispers.append({"kind": int(message.goal_kind), "target": int(message.target), "bonus": bonus, "until": sim.calendar.tick + day})
		Mind.add(agent, "whispered_to", day)
		agent.record(sim.calendar.tick, "message", {"text": "log_whispered", "args": {"nudge": "nudge_" + str(message.nudge)}})
		agent.next_deliberation = sim.calendar.tick
		return
	agent.change_need(Personality.Need.SAFETY, -5.0)
	Mind.add(agent, "strange_voice", day)
	agent.record(sim.calendar.tick, "message", {"text": "log_strange_voice", "args": {}})
	if agent.faith.knows:
		agent.faith.devotion = clampf(float(agent.faith.devotion) + 2.0 * (0.5 + maxf(agent.personality.curiosity, 0.0)), 0.0, 100.0)
