extends RefCounted
## Blueprints (M19, GDD §5.4 leaning): the god lays a design it has offered
## as a ghost on a spot in its zone. It is a proposal, never an order: a
## founder who wants that design's function and knows the design takes the
## spot while it is still free; otherwise they find their own, and a
## blueprint nobody takes for a season fades. Kept in the god's state:
## {id, template_id, origin, rotation, settlement_id, laid_tick}.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const SiteFinder = preload("res://scripts/building/site_finder.gd")


## The `lay_blueprint` command: an offered design, a corner and a rotation,
## checked as a founder would check a site.
static func lay(sim: RefCounted, command: Dictionary) -> Dictionary:
	if sim.god.dormant:
		return {"ok": false, "reason": "edit_dormant"}
	var id: String = str(command.get("template", ""))
	if not sim.god.offered.has(id):
		return {"ok": false, "reason": "blueprint_not_offered"}
	var template: RefCounted = sim.template(id)
	var origin: Variant = command.get("origin")
	var rotation: int = int(command.get("rotation", 0))
	if template == null or not origin is Vector3i or rotation < 0 or rotation > 3:
		return {"ok": false, "reason": "command_unknown"}
	var size: Vector3i = template.rotated_size(rotation)
	var middle := Vector3(origin.x + size.x * 0.5, origin.y, origin.z + size.z * 0.5)
	if not sim.in_zone(middle):
		return {"ok": false, "reason": "edit_outside_zone"}
	var settlement_id: int = sim.settlements.at_cell(Vector3i(middle))
	if settlement_id < 0:
		return {"ok": false, "reason": "blueprint_no_settlement"}
	for entry in sim.god.blueprints:
		if _overlaps(entry, origin, size, sim):
			return {"ok": false, "reason": "blueprint_overlaps"}
	var choice: Dictionary = SiteFinder.check(sim, template, Vector2i(origin.x, origin.z), rotation, sim.settlements.entries[settlement_id])
	if choice.is_empty():
		return {"ok": false, "reason": "blueprint_bad_site"}
	var laid: Dictionary = {"id": int(sim.god.next_blueprint), "template_id": id, "origin": choice.origin, "rotation": rotation,
		"settlement_id": settlement_id, "laid_tick": sim.calendar.tick}
	sim.god.next_blueprint = int(sim.god.next_blueprint) + 1
	sim.god.blueprints.append(laid)
	sim.chronicle_event("blueprint_laid", settlement_id, {"design": template.name}, "cause_god")
	return {"ok": true, "reason": "blueprint_laid", "id": laid.id}


static func _overlaps(entry: Dictionary, origin: Vector3i, size: Vector3i, sim: RefCounted) -> bool:
	var template: RefCounted = sim.template(str(entry.template_id))
	if template == null:
		return false
	var other: Vector3i = template.rotated_size(int(entry.rotation))
	var a := Rect2i(origin.x, origin.z, size.x, size.z)
	var b := Rect2i(entry.origin.x, entry.origin.z, other.x, other.z)
	return a.intersects(b)


## The god's proposal a founder would take up for `function`: a blueprint in
## their settlement of a design they know with that function, whose spot is
## still free. {blueprint, template, choice} or {}.
static func proposal(sim: RefCounted, agent: RefCounted, function: String) -> Dictionary:
	for entry in sim.god.blueprints:
		if int(entry.settlement_id) != agent.settlement_id or not agent.beliefs.known_templates.has(entry.template_id):
			continue
		var found: Dictionary = still_free(sim, entry, function)
		if not found.is_empty():
			return found
	return {}


## The blueprint's site as a founder would mark it, if it still serves
## `function` and its ground is free; else {}.
static func still_free(sim: RefCounted, entry: Dictionary, function: String) -> Dictionary:
	var template: RefCounted = sim.template(str(entry.template_id))
	if template == null or not template.functions.has(function):
		return {}
	var settlement: Dictionary = sim.settlements.get_settlement(int(entry.settlement_id))
	if settlement.is_empty():
		return {}
	var choice: Dictionary = SiteFinder.check(sim, template, Vector2i(entry.origin.x, entry.origin.z), int(entry.rotation), settlement)
	if choice.is_empty():
		return {}
	return {"blueprint": int(entry.id), "template": template, "choice": choice}


## The god takes a blueprint back.
static func lift(sim: RefCounted, id: int) -> Dictionary:
	for i in range(sim.god.blueprints.size()):
		if int(sim.god.blueprints[i].id) == id:
			sim.god.blueprints.remove_at(i)
			return {"ok": true, "reason": "blueprint_lifted"}
	return {"ok": false, "reason": "command_unknown"}


## A founder has taken a blueprint up: it becomes their site.
static func taken(sim: RefCounted, id: int, agent: RefCounted) -> void:
	for i in range(sim.god.blueprints.size()):
		var entry: Dictionary = sim.god.blueprints[i]
		if int(entry.id) == id:
			sim.god.blueprints.remove_at(i)
			sim.chronicle_event("blueprint_taken", agent.settlement_id, {"name": agent.full_name(), "design": sim.template_name(str(entry.template_id))},
				"cause_god_proposed", [agent.id])
			return


## A blueprint nobody has taken for a season fades.
static func daily(sim: RefCounted) -> void:
	var season: int = sim.calendar.ticks_for_days(float(sim.calendar.days_per_season))
	var kept: Array = []
	for entry in sim.god.blueprints:
		if sim.calendar.tick - int(entry.laid_tick) >= season:
			sim.chronicle_event("blueprint_faded", int(entry.settlement_id), {"design": sim.template_name(str(entry.template_id))}, "cause_nobody_took_it")
		else:
			kept.append(entry)
	sim.god.blueprints = kept
