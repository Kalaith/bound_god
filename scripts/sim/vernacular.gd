extends RefCounted
## Vernacular homes (M19): a settlement that has had people to house for a
## while (`construction.vernacular_after_days` since it was founded, so the
## god has time to offer a design first) and whose people still know no
## dwelling design devises one from what lies to hand: a small roofed
## room with a bed and a door, walled in stone where its deviser knows stone
## near (else planks between log corners) and roofed in thatch where grass is
## known (else planks). It is named from the place, chronicled with who
## devised it, and learned by everyone living there; from then on it travels
## like any other design. Devised designs live in `sim.settlements.designs`.
const Template = preload("res://scripts/building/template.gd")
const Construction = preload("res://scripts/sim/construction.gd")
const Text = preload("res://scripts/core/text.gd")
const Balance = preload("res://addons/hatchery/core/balance.gd")


static func daily(sim: RefCounted) -> void:
	var wait: int = sim.calendar.ticks_for_days(Balance.number("construction.vernacular_after_days"))
	for id in sim.settlements.ids():
		if sim.calendar.tick - int(sim.settlements.entries[id].get("founded_tick", 0)) < wait:
			continue
		if _homeless(sim, id) and not _knows_dwelling(sim, id):
			devise(sim, id)


static func _homeless(sim: RefCounted, id: int) -> bool:
	for agent_id in sim.settlements.entries[id].residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and agent.home < 0 and agent.age_years >= Balance.number("agents.adult_age_years") and not bool(agent.backstory.get("wayfarer", false)):
			return true
	return false


static func _knows_dwelling(sim: RefCounted, id: int) -> bool:
	var settlement: Dictionary = sim.settlements.entries[id]
	var known: Array = settlement.known_templates.duplicate()
	for agent_id in settlement.residents:
		if sim.agents[agent_id].is_present():
			known.append_array(sim.agents[agent_id].beliefs.known_templates)
	for template_id in known:
		var template: RefCounted = sim.template(str(template_id))
		if template != null and template.functions.has("dwelling"):
			return true
	return false


## The resident who works it out: the most diligent adult, the elder first.
static func _deviser(sim: RefCounted, id: int) -> RefCounted:
	var best: RefCounted = null
	for agent_id in sim.settlements.entries[id].residents:
		var agent: RefCounted = sim.agents[agent_id]
		if not agent.is_present() or agent.is_child:
			continue
		if best == null or agent.personality.diligence > best.personality.diligence \
				or (agent.personality.diligence == best.personality.diligence and agent.age_years > best.age_years):
			best = agent
	return best


## Works out a home for settlement `id`; returns the new design's id, or "".
static func devise(sim: RefCounted, id: int) -> String:
	var deviser: RefCounted = _deviser(sim, id)
	if deviser == null:
		return ""
	var settlement: Dictionary = sim.settlements.entries[id]
	var stone: bool = Construction.knows_near(sim, deviser, "stone")
	var grass: bool = Construction.knows_near(sim, deviser, "thatch")
	var width: int = 5 + sim.rng.randi_range(0, 1)
	var wall: String = "W"
	var ground: Array = []
	var upper: Array = []
	var roof: Array = []
	for z in range(5):
		var low: String = ""
		var high: String = ""
		for x in range(width):
			var edge: bool = x == 0 or z == 0 or x == width - 1 or z == 4
			var corner: bool = (x == 0 or x == width - 1) and (z == 0 or z == 4)
			var door: bool = z == 0 and x == width / 2
			if door:
				low += "D"
				high += "D"
			elif corner:
				low += "L"
				high += "L"
			elif edge:
				low += wall
				high += wall
			elif z == 3 and (x == 1 or (width > 5 and x == width - 2)):
				low += "B"
				high += "."
			else:
				low += "."
				high += "."
		ground.append(low)
		upper.append(high)
		roof.append("R".repeat(width))
	var number: int = int(sim.settlements.next_design)
	sim.settlements.next_design = number + 1
	var definition: Dictionary = {
		"id": "devised_%d_%d" % [id, number],
		"name": Text.format("design_vernacular", {"place": str(settlement.name)}),
		"author": deviser.full_name(),
		"legend": {".": "air", "W": "cobble" if stone else "planks", "L": "log", "D": "door", "B": "bed", "R": "thatch" if grass else "planks"},
		"entrance": [width / 2, 0, 0],
		"layers": [ground, upper, roof],
	}
	var template: RefCounted = Template.from_starter(definition)
	if not template.functions.has("dwelling"):
		push_error("a devised home is not a dwelling: " + str(template.functions))
		return ""
	sim.settlements.designs[template.id] = template.to_dict()
	sim.forget_template_cache(template.id)
	if not settlement.known_templates.has(template.id):
		settlement.known_templates.append(template.id)
	var learned: Array = []
	for agent_id in settlement.residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and not agent.beliefs.known_templates.has(template.id):
			agent.beliefs.known_templates.append(template.id)
			learned.append(agent.id)
	sim.chronicle_event("design_devised", id, {"name": deviser.full_name(), "design": template.name}, "cause_no_dwelling_design", [deviser.id])
	return template.id
