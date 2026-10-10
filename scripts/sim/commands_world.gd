extends RefCounted
## The god's commands beyond block edits: offering a design at the shrine
## and moving materials between the divine stock and a storage chest.
## Neither asks anyone to do anything; they change what people know and have.
const Balance = preload("res://scripts/core/balance.gd")
const Template = preload("res://scripts/building/template.gd")
const Registry = preload("res://scripts/world/block_registry.gd")


static func apply(sim: RefCounted, command: Dictionary) -> Dictionary:
	match str(command.get("type", "")):
		"offer_template":
			return _offer(sim, command)
		"transfer":
			return _transfer(sim, command)
		"toggle_door":
			return _toggle_door(sim, command)
		"set_hotbar":
			return _set_hotbar(sim, command)
		"follow":
			return _follow(sim, command)
		"dismiss_prompt":
			var id: String = str(command.get("prompt", ""))
			if id.is_empty():
				return {"ok": false, "reason": "command_unknown"}
			if not sim.god.prompts_dismissed.has(id):
				sim.god.prompts_dismissed.append(id)
			return {"ok": true, "reason": ""}
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


## The player's choice and order of blocks at hand: one placeable block or
## 0 (empty) per slot.
static func _set_hotbar(sim: RefCounted, command: Dictionary) -> Dictionary:
	var slots: Variant = command.get("slots")
	if not slots is Array or slots.size() != Balance.integer("avatar.hotbar_slots"):
		return {"ok": false, "reason": "command_unknown"}
	for block in slots:
		if not block is int or (block != 0 and (block < 0 or block >= Registry.placeable.size() or Registry.placeable[block] == 0)):
			return {"ok": false, "reason": "edit_unplaceable"}
	sim.god.hotbar = slots.duplicate()
	return {"ok": true, "reason": ""}


## Swings a doorway open or shut: every door block stacked in it together.
## Only the avatar is stopped by a shut door; people open doors as they pass.
static func _toggle_door(sim: RefCounted, command: Dictionary) -> Dictionary:
	var cell: Vector3i = command.get("cell", Vector3i(-1, -1, -1))
	var door: int = Registry.id("door")
	if sim.voxels.get_block(cell) != door:
		return {"ok": false, "reason": "interact_nothing"}
	if sim.god.dormant:
		return {"ok": false, "reason": "edit_dormant"}
	if not sim.in_zone(Vector3(cell) + Vector3(0.5, 0, 0.5)):
		return {"ok": false, "reason": "edit_outside_zone"}
	var opening: bool = sim.voxels.block_meta(cell) & Registry.DOOR_OPEN == 0
	var at: Vector3i = cell
	while sim.voxels.get_block(at + Vector3i.DOWN) == door:
		at += Vector3i.DOWN
	while sim.voxels.get_block(at) == door:
		var facing: int = sim.voxels.block_meta(at) & 1
		sim.set_block(at, door, facing | (Registry.DOOR_OPEN if opening else 0))
		at += Vector3i.UP
	return {"ok": true, "reason": "door_opened" if opening else "door_closed"}


## Moves goods between the divine stock and one storage chest: positive
## amounts go into the chest, negative ones back to the god.
static func _transfer(sim: RefCounted, command: Dictionary) -> Dictionary:
	var chest: Vector3i = command.get("chest", Vector3i(-1, -1, -1))
	var resource: String = str(command.get("resource", ""))
	var amount: int = int(command.get("amount", 0))
	if not sim.settlements.chests.has(chest) or amount == 0 or resource.is_empty() or resource == "soil":
		return {"ok": false, "reason": "transfer_invalid"}
	if sim.god.dormant:
		return {"ok": false, "reason": "edit_dormant"}
	if not sim.in_zone(Vector3(chest) + Vector3(0.5, 0, 0.5)):
		return {"ok": false, "reason": "edit_outside_zone"}
	if amount > 0:
		var given: int = sim.settlements.chest_add(chest, resource, mini(amount, sim.god.stock(resource)))
		if given <= 0:
			return {"ok": false, "reason": "transfer_full" if sim.god.stock(resource) > 0 else "transfer_nothing"}
		sim.god.add_stock(resource, -given)
		return {"ok": true, "reason": "transfer_given", "amount": given}
	var taken: int = sim.settlements.chest_take(chest, resource, -amount)
	if taken <= 0:
		return {"ok": false, "reason": "transfer_nothing"}
	sim.god.add_stock(resource, taken)
	return {"ok": true, "reason": "transfer_taken", "amount": taken}


## Pins or unpins a person. A pin changes only what the god watches.
static func _follow(sim: RefCounted, command: Dictionary) -> Dictionary:
	var id: int = int(command.get("agent", -1))
	if id < 0 or id >= sim.agents.size():
		return {"ok": false, "reason": "whisper_nobody"}
	if sim.god.followed.has(id):
		sim.god.followed.erase(id)
		return {"ok": true, "reason": ""}
	if sim.god.followed.size() >= Balance.integer("cultivation.followed_most"):
		return {"ok": false, "reason": "pin_full"}
	sim.god.followed.append(id)
	return {"ok": true, "reason": ""}
