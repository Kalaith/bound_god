extends RefCounted
## Social message receivers: help requests and replies, gossip, proposals,
## gifts and word of other places.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Beliefs = preload("res://scripts/agents/beliefs.gd")

const KINDS: Array[String] = ["request_help", "accept_help", "decline_help", "gossip", "propose", "accept_proposal",
	"reject_proposal", "delivered", "inform_place"]


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


static func receive(sim: RefCounted, agent: RefCounted, message: Dictionary) -> bool:
	var from: int = int(message.from)
	match str(message.kind):
		"request_help":
			_request(sim, agent, message)
		"accept_help":
			agent.record(sim.calendar.tick, "message", {"text": "log_help_coming", "args": {"name": sim.agents[from].given_name}})
		"decline_help":
			agent.record(sim.calendar.tick, "message", {"text": "log_help_declined", "args": {"name": sim.agents[from].given_name}})
			Beliefs.change_opinion(agent.beliefs.relation(from), -2.0)
		"gossip":
			_gossip(agent, from, int(message.about), float(message.opinion))
		"propose":
			_proposal(sim, agent, from)
		"accept_proposal":
			_partner(sim, agent, from)
		"reject_proposal":
			Mind.add(agent, "frustrated", sim.calendar.ticks_per_day, from)
			var relation: Dictionary = agent.beliefs.relation(from)
			relation.romance = float(relation.romance) * 0.5
			if Beliefs.bond(relation) == "stranger":
				Beliefs.change_opinion(relation, -3.0)
		"inform_place":
			if agent.beliefs.opinion_of(from) > -15.0:
				var known: Dictionary = agent.beliefs.places.get(message.key, {})
				if known.is_empty() or int(known.seen_tick) < int(message.place.seen_tick):
					agent.beliefs.places[message.key] = message.place
	return false


static func _willing(agent: RefCounted, from: int, need: int, asker: RefCounted = null) -> bool:
	# A student asking again renews a promise to teach not yet kept.
	if need == Goals.HelpNeed.TEACHING and int(agent.help_task.get("requester", -1)) == from and int(agent.help_task.get("need", -1)) == need:
		return true
	if not agent.help_task.is_empty() or agent.is_child:
		return false
	# Only someone who knows a technique the asker lacks can teach.
	if need == Goals.HelpNeed.TEACHING:
		if asker == null or int(agent.cultivation.get("realm", 0)) < 1:
			return false
		var lacks: bool = false
		for id in agent.cultivation.techniques:
			lacks = lacks or not asker.cultivation.techniques.has(id)
		if not lacks:
			return false
		# The Way is passed on more freely than bread: a stranger who asks is
		# taught unless the teacher dislikes them or is unkind.
		return agent.beliefs.opinion_of(from) + 20.0 + agent.personality.kindness * 20.0 > 0.0
	if agent.need(Personality.Need.FOOD) < 30.0 or agent.needs_care(Balance.number("health.care_threshold")):
		return false
	var bonus: float = 0.0
	match need:
		Goals.HelpNeed.CARE:
			bonus = agent.skills.levels[Personality.Skill.MEDICINE] * 2.0
		Goals.HelpNeed.DEFENCE:
			bonus = agent.personality.bravery * 30.0
	return agent.beliefs.opinion_of(from) + agent.personality.kindness * 40.0 + bonus > 5.0


static func _request(sim: RefCounted, agent: RefCounted, message: Dictionary) -> void:
	var from: int = int(message.from)
	var need: int = int(message.get("need", 0))
	if _willing(agent, from, need, sim.agents[from]):
		agent.help_task = {"requester": from, "need": need}
		agent.next_deliberation = sim.calendar.tick
		sim.effects.message(agent.id, from, "accept_help", sim.calendar.tick, {"need": need})
	else:
		sim.effects.message(agent.id, from, "decline_help", sim.calendar.tick, {"need": need})


static func _gossip(agent: RefCounted, from: int, about: int, opinion: float) -> void:
	if about == agent.id:
		return
	var trust: float = clampf((agent.beliefs.opinion_of(from) + 50.0) / 150.0, 0.0, 1.0)
	var weight: float = Balance.number("social.gossip_weight") * trust
	Beliefs.change_opinion(agent.beliefs.relation(about), (opinion - agent.beliefs.opinion_of(about)) * weight)


static func _proposal(sim: RefCounted, agent: RefCounted, from: int) -> void:
	var relation: Dictionary = agent.beliefs.relation(from)
	var accepts: bool = agent.partner < 0 and not agent.is_child and sim.agents[from].partner < 0 \
		and float(relation.opinion) > 40.0 and float(relation.romance) > Balance.number("social.partner_romance_threshold") * 0.7
	if accepts:
		_partner(sim, agent, from)
		sim.effects.message(agent.id, from, "accept_proposal", sim.calendar.tick)
		sim.chronicle_event("partnership", agent.settlement_id, {"a": agent.given_name, "b": sim.agents[from].given_name}, "", [agent.id, from])
	else:
		relation.romance = float(relation.romance) * 0.7
		sim.effects.message(agent.id, from, "reject_proposal", sim.calendar.tick)


static func _partner(sim: RefCounted, agent: RefCounted, other: int) -> void:
	if agent.partner == other:
		return
	agent.partner = other
	Mind.add(agent, "new_partner", sim.calendar.ticks_per_day, other)
