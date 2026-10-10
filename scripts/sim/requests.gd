extends RefCounted
## Divine requests posted at a shrine: carry the god's name to a place,
## bring materials, restore a shrine, or raise one. Requests are broadcast to
## the shrine's believers, who each decide whether to take them; a taken
## request is an ordinary intention that can fail, be abandoned or succeed.
## Boons are paid from the shrine's Favour on success.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const RequestPlans = preload("res://scripts/agents/plan_library_quest.gd")
const Text = preload("res://scripts/core/text.gd")
const FaithPeople = preload("res://scripts/sim/faith_people.gd")

const KINDS: Array[String] = ["carry_name", "bring", "restore_shrine", "raise_shrine", "found_settlement"]
const Kind = Goals.Kind

## id -> {id, kind, shrine_id, target, resource, amount, boon, slots, takers,
##        state (open|done|failed), posted_tick, deadline_tick, progress}
var requests: Dictionary = {}
var next_id: int = 1


func ids() -> Array:
	var keys: Array = requests.keys()
	keys.sort()
	return keys


func get_request(id: int) -> Dictionary:
	return requests.get(id, {})


## Post a request at the shrine the god stands at and tell its believers.
func post(sim: RefCounted, command: Dictionary) -> Dictionary:
	var kind: String = str(command.get("kind", ""))
	if not KINDS.has(kind):
		return {"ok": false, "reason": "request_unknown"}
	var shrine: Dictionary = sim.faith.current(sim)
	if sim.god.dormant or shrine.is_empty() or shrine.state != "active":
		return {"ok": false, "reason": "miracle_no_shrine"}
	var boon: float = clampf(float(command.get("boon", 10.0)), 0.0, 30.0)
	if float(shrine.favour) < boon:
		return {"ok": false, "reason": "miracle_favour"}
	var target: int = int(command.get("target", -1))
	match kind:
		"carry_name":
			if not sim.settlements.entries.has(target) or target == int(shrine.settlement_id):
				return {"ok": false, "reason": "request_target"}
		"restore_shrine":
			if sim.faith.get_shrine(target).get("state", "") != "fallen":
				return {"ok": false, "reason": "request_target"}
		"raise_shrine":
			if not sim.settlements.entries.has(target):
				return {"ok": false, "reason": "request_target"}
		"found_settlement":
			if target < 0 or target >= sim.features.get("grounds", []).size() or sim.settlements.on_ground(target) >= 0:
				return {"ok": false, "reason": "request_target"}
			if str(sim.settlements.get_settlement(int(shrine.settlement_id)).get("standing", "")) != "village":
				return {"ok": false, "reason": "request_not_village"}
	var id: int = next_id
	next_id += 1
	requests[id] = {"id": id, "kind": kind, "shrine_id": int(shrine.id), "target": target,
		"resource": str(command.get("resource", "")), "amount": int(command.get("amount", 0)), "boon": boon,
		"slots": int(command.get("slots", 1)), "takers": [], "state": "open", "posted_tick": sim.calendar.tick,
		"deadline_tick": sim.calendar.tick + sim.calendar.ticks_for_days(float(command.get("days", 10.0))), "progress": {"listeners": [], "delivered": 0}}
	var told: int = 0
	for agent in sim.agents:
		if agent.is_present() and FaithState.stage(agent.faith) >= 3 and (int(agent.faith.shrine_id) == int(shrine.id) or agent.settlement_id == int(shrine.settlement_id)):
			sim.effects.message(-1, agent.id, "divine_request", sim.calendar.tick, {"request": id})
			told += 1
	sim.chronicle_event("request_posted", int(shrine.settlement_id), {"request": _describe(sim, requests[id])}, "cause_god")
	return {"ok": true, "reason": "request_posted", "told": told, "id": id}


func _describe(sim: RefCounted, request: Dictionary) -> String:
	match str(request.kind):
		"carry_name", "raise_shrine":
			return Text.format("request_" + str(request.kind), {"place": sim.settlements.get_settlement(int(request.target)).get("name", "")})
		"restore_shrine":
			return Text.format("request_restore_shrine", {"shrine": sim.faith.shrine_name(sim, int(request.target))})
		"found_settlement":
			return Text.format("request_found_settlement", {"place": Text.label(sim.features.grounds[int(request.target)].name)})
	return Text.format("request_bring", {"amount": request.amount, "resource": Text.label("resource_" + str(request.resource)).to_lower()})


## A believer weighs a request: devotion, courage, curiosity and the boon
## against their needs and the danger they believe in.
func receive(sim: RefCounted, agent: RefCounted, message: Dictionary) -> bool:
	var request: Dictionary = requests.get(int(message.request), {})
	if request.is_empty() or request.state != "open" or agent.is_child or agent.quest_id >= 0:
		return false
	if request.takers.size() >= int(request.slots):
		return false
	if agent.need(agent.lowest_need()) < Balance.number("needs.urgent_threshold"):
		return false
	var danger: float = 0.4 if not agent.beliefs.threats.is_empty() else 0.0
	var score: float = float(agent.faith.devotion) / 100.0 + 0.3 * agent.personality.bravery + 0.2 * agent.personality.curiosity \
		+ float(request.boon) / 60.0 - danger
	if score <= Balance.number("faith.request_accept"):
		agent.record(sim.calendar.tick, "message", {"text": "log_request_declined", "args": {}})
		return false
	agent.quest_id = int(request.id)
	request.takers.append(agent.id)
	agent.next_deliberation = sim.calendar.tick
	agent.record(sim.calendar.tick, "message", {"text": "log_request_taken", "args": {}})
	sim.chronicle_event("request_taken", agent.settlement_id, {"name": agent.full_name(), "request": _describe(sim, request)}, "cause_devotion")
	return true


func candidates(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	var request: Dictionary = requests.get(agent.quest_id, {})
	if request.is_empty() or request.state != "open":
		return
	# A founder who already lives on the new ground has done their part.
	if request.kind == "found_settlement" and agent.settlement_id >= 0 and agent.settlement_id == sim.settlements.on_ground(int(request.target)):
		return
	var danger: float = 0.4 if not agent.beliefs.threats.is_empty() else 0.0
	var risk: float = 1.0 - 0.5 * danger * (1.0 - clampf(agent.personality.bravery, 0.0, 1.0))
	var utility: float = (0.4 + float(agent.faith.devotion) / 200.0 + float(request.boon) / 100.0) * risk
	out.append({"goal": Goals.make(Kind.QUEST, int(request.id)), "utility": utility, "reason": "reason_quest", "value": NAN})


func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	return RequestPlans.plans(sim, agent, goal, requests.get(int(goal.target), {}))


## Someone on a request told a story: count it if it was where it was asked.
func on_story(sim: RefCounted, teller: RefCounted, listener: RefCounted) -> void:
	var request: Dictionary = requests.get(teller.quest_id, {})
	if request.is_empty() or request.kind != "carry_name" or request.state != "open":
		return
	if listener.settlement_id != int(request.target) or request.progress.listeners.has(listener.id):
		return
	request.progress.listeners.append(listener.id)
	if request.progress.listeners.size() >= Balance.integer("faith.carry_name_listeners"):
		complete(sim, request)


func on_delivery(sim: RefCounted, agent: RefCounted, resource: String, amount: int) -> void:
	var request: Dictionary = requests.get(agent.quest_id, {})
	if request.is_empty() or request.kind != "bring" or request.state != "open" or resource != request.resource:
		return
	if agent.settlement_id != int(sim.faith.get_shrine(int(request.shrine_id)).get("settlement_id", -2)):
		return
	request.progress.delivered = int(request.progress.delivered) + amount
	if int(request.progress.delivered) >= int(request.amount):
		complete(sim, request)


func complete(sim: RefCounted, request: Dictionary) -> void:
	request.state = "done"
	var shrine: Dictionary = sim.faith.get_shrine(int(request.shrine_id))
	var paid: bool = not shrine.is_empty() and float(shrine.favour) >= float(request.boon)
	if paid:
		shrine.favour = float(shrine.favour) - float(request.boon)
	for id in request.takers:
		var agent: RefCounted = sim.agents[id]
		if agent.quest_id == int(request.id):
			agent.quest_id = -1
		Mind.add(agent, "quest_done", sim.calendar.ticks_per_day)
		if paid:
			Mind.add(agent, "blessed", sim.calendar.ticks_per_day)
			FaithPeople.gain(agent, 6.0)
	sim.chronicle_event("request_done", int(shrine.get("settlement_id", -1)), {"request": _describe(sim, request)}, "cause_devotion", request.takers)


func abandon(sim: RefCounted, agent: RefCounted) -> void:
	var request: Dictionary = requests.get(agent.quest_id, {})
	agent.quest_id = -1
	if request.is_empty():
		return
	request.takers.erase(agent.id)
	sim.chronicle_event("request_abandoned", agent.settlement_id, {"name": agent.full_name(), "request": _describe(sim, request)}, "cause_gave_up", [agent.id])


## Daily: overdue requests fail; restore and raise requests complete when the
## world shows them done.
func daily(sim: RefCounted) -> void:
	for id in ids():
		var request: Dictionary = requests[id]
		if request.state != "open":
			continue
		match str(request.kind):
			"restore_shrine":
				if sim.faith.get_shrine(int(request.target)).get("state", "fallen") != "fallen":
					complete(sim, request)
					continue
			"raise_shrine":
				if sim.faith.settlement_has_shrine(sim, int(request.target)):
					complete(sim, request)
					continue
			"found_settlement":
				if _settled(sim, request):
					complete(sim, request)
					continue
		if sim.calendar.tick > int(request.deadline_tick):
			request.state = "failed"
			for agent_id in request.takers:
				if sim.agents[agent_id].quest_id == id:
					sim.agents[agent_id].quest_id = -1
			sim.chronicle_event("request_failed", -1, {"request": _describe(sim, request)}, "cause_time")


## Done when the founders (as many as took it, up to the number needed) live
## in the new settlement and it has a chest.
func _settled(sim: RefCounted, request: Dictionary) -> bool:
	var id: int = sim.settlements.on_ground(int(request.target))
	if id < 0 or sim.settlements.chest_cells(sim, id).is_empty():
		return false
	var living: int = 0
	for agent_id in sim.settlements.entries[id].residents:
		if sim.agents[agent_id].is_present():
			living += 1
	return living >= mini(maxi(request.takers.size(), 1), Balance.integer("population.founders_needed"))


func to_dict() -> Dictionary:
	return {"requests": requests.duplicate(true), "next_id": next_id}


func from_dict(data: Dictionary) -> void:
	requests = data.requests
	next_id = int(data.next_id)
