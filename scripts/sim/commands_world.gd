extends RefCounted
## The god's commands beyond block edits: offering a design at the shrine
## and moving materials between the divine stock and a settlement's stores.
## Neither asks anyone to do anything; they change what people know and have.
const Balance = preload("res://scripts/core/balance.gd")
const Template = preload("res://scripts/building/template.gd")


static func apply(sim: RefCounted, command: Dictionary) -> Dictionary:
	match str(command.get("type", "")):
		"offer_template":
			return _offer(sim, command)
		"transfer":
			return _transfer(sim, command)
	if sim.faith != null:
		return sim.faith.apply_command(sim, command)
	return {"ok": false, "reason": "command_unknown"}


## Offered designs become known to the people of the shrine's settlement who
## know the god (before faith exists, to everyone living there).
static func _offer(sim: RefCounted, command: Dictionary) -> Dictionary:
	if sim.god.dormant:
		return {"ok": false, "reason": "edit_dormant"}
	var parsed: Array = Template.from_dict(command.get("template", {}))
	if parsed[0] == null:
		return {"ok": false, "reason": parsed[1]}
	var template: RefCounted = parsed[0]
	if sim.god.offered.has(template.id):
		return {"ok": false, "reason": "offer_already"}
	sim.god.offered[template.id] = template.to_dict()
	sim.god.offered_at[template.id] = sim.god.active_shrine_id
	sim.forget_template_cache(template.id)
	var settlement_id: int = sim.settlements.at_cell(Vector3i(sim.zone_center()))
	var learned: Array = []
	if settlement_id >= 0:
		var settlement: Dictionary = sim.settlements.entries[settlement_id]
		if not settlement.known_templates.has(template.id):
			settlement.known_templates.append(template.id)
		for agent_id in settlement.residents:
			var agent: RefCounted = sim.agents[agent_id]
			if agent.is_present() and (sim.faith == null or sim.faith.hears_offer(sim, agent)):
				if not agent.beliefs.known_templates.has(template.id):
					agent.beliefs.known_templates.append(template.id)
				learned.append(agent.id)
	sim.chronicle_event("template_offered", settlement_id, {"design": template.name}, "cause_god", learned)
	return {"ok": true, "reason": "offer_done", "learned": learned.size()}


## Positive amounts go from the god to the stores, negative ones back.
static func _transfer(sim: RefCounted, command: Dictionary) -> Dictionary:
	var settlement_id: int = int(command.get("settlement", -1))
	var resource: String = str(command.get("resource", ""))
	var amount: int = int(command.get("amount", 0))
	var settlement: Dictionary = sim.settlements.get_settlement(settlement_id)
	if settlement.is_empty() or amount == 0 or resource.is_empty() or resource == "soil":
		return {"ok": false, "reason": "transfer_invalid"}
	if sim.god.dormant:
		return {"ok": false, "reason": "edit_dormant"}
	if not sim.in_zone(Vector3(settlement.pile)):
		return {"ok": false, "reason": "edit_outside_zone"}
	if amount > 0:
		var given: int = sim.settlements.add(sim, settlement_id, resource, mini(amount, sim.god.stock(resource)))
		if given <= 0:
			return {"ok": false, "reason": "transfer_nothing"}
		sim.god.add_stock(resource, -given)
		return {"ok": true, "reason": "transfer_given", "amount": given}
	var taken: int = sim.settlements.take(settlement_id, resource, -amount)
	if taken <= 0:
		return {"ok": false, "reason": "transfer_nothing"}
	sim.god.add_stock(resource, taken)
	return {"ok": true, "reason": "transfer_taken", "amount": taken}
