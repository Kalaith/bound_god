extends RefCounted
## The receiving side of every message protocol. Messages pushed in tick N
## arrive at the end of N and are read here in N+1, before deliberation.
## Returns true when a message demands an urgent rethink.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const InboxSocial = preload("res://scripts/sim/inbox_social.gd")
const InboxFaith = preload("res://scripts/sim/inbox_faith.gd")


static func process(sim: RefCounted, agent: RefCounted) -> bool:
	if agent.inbox.is_empty():
		return false
	var messages: Array = agent.inbox
	agent.inbox = []
	var urgent: bool = false
	for message in messages:
		match str(message.kind):
			"warn":
				urgent = _warn(sim, agent, message) or urgent
			"inform_site":
				_inform_site(sim, agent, message)
			"template_info":
				_template_info(sim, agent, message)
			_:
				if InboxSocial.handles(message.kind):
					urgent = InboxSocial.receive(sim, agent, message) or urgent
				elif InboxFaith.handles(message.kind):
					urgent = InboxFaith.receive(sim, agent, message) or urgent
				else:
					push_error("Unknown message kind " + str(message.kind))
	return urgent


static func trust(agent: RefCounted, sender: int) -> float:
	return clampf((agent.beliefs.opinion_of(sender) + 50.0) / 150.0, 0.0, 1.0)


static func _warn(sim: RefCounted, agent: RefCounted, message: Dictionary) -> bool:
	var fresh: bool = agent.beliefs.note_threat(int(message.threat), str(message.threat_kind), message.cell, bool(message.dangerous), sim.calendar.tick)
	if fresh and bool(message.dangerous):
		agent.interrupted_by = "interrupt_warned"
		return true
	return false


static func _inform_site(sim: RefCounted, agent: RefCounted, message: Dictionary) -> void:
	if agent.beliefs.opinion_of(int(message.from)) <= -15.0:
		return
	var id: int = int(message.site)
	var known: Dictionary = agent.beliefs.sites.get(id, {})
	if known.is_empty() or int(known.seen_tick) < int(message.seen_tick):
		agent.beliefs.note_site(id, str(message.site_kind), message.cell, int(message.amount), int(message.seen_tick))


static func _template_info(_sim: RefCounted, agent: RefCounted, message: Dictionary) -> void:
	if trust(agent, int(message.from)) > 0.3 and not agent.beliefs.known_templates.has(message.template_id):
		agent.beliefs.known_templates.append(message.template_id)
