extends RefCounted
## Building steps: marking a site, delivering materials, placing blocks one
## at a time (walking between them), and repairing a known building.
const Balance = preload("res://scripts/core/balance.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const SiteFinder = preload("res://scripts/building/site_finder.gd")
const Blueprints = preload("res://scripts/sim/blueprints.gd")
const DeliberationWork = preload("res://scripts/agents/deliberation_work.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

const Op = Plans.Op
const Fail = Plans.Fail
const Skill = Personality.Skill


static func _within_reach(agent: RefCounted, cell: Vector3i) -> bool:
	return Vector3(agent.cell + Vector3i.UP).distance_to(Vector3(cell)) <= Balance.number("agents.reach") + 0.5 \
		and cell != agent.cell and cell != agent.cell + Vector3i.UP


## Walk toward a stand cell for `target`; RUNNING while moving, DONE when there.
static func _approach(sim: RefCounted, agent: RefCounted, stand: Vector3i) -> int:
	if stand.x < 0:
		return Fail.NO_PATH
	if agent.cell == stand:
		agent.path.clear()
		return Plans.DONE
	if agent.path.is_empty() or agent.path.back() != stand:
		if not sim.nav.can_path():
			return Plans.RUNNING
		var route: Array[Vector3i] = sim.nav.find_path(agent.cell, stand)
		if route.is_empty():
			return Fail.NO_PATH
		agent.path = route
	agent.activity = "walking"
	return Plans.RUNNING


static func _mark_site(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	if step_ticks == 0:
		var design: RefCounted = DeliberationWork.known_design(sim, agent, str(step.function))
		var settlement: Dictionary = sim.settlements.get_settlement(agent.settlement_id)
		if design == null or settlement.is_empty():
			return Fail.NO_SITE
		# The god's blueprint for this function, while its spot is free, first.
		var proposal: Dictionary = Blueprints.proposal(sim, agent, str(step.function))
		if not proposal.is_empty():
			agent.activity = "building"
			sim.effects.action("mark_site", agent.id, {"template_id": proposal.template.id, "origin": proposal.choice.origin, "rotation": proposal.choice.rotation,
				"order": proposal.choice.order, "purpose": step.purpose, "blueprint": proposal.blueprint})
			return Plans.RUNNING
		var memo: String = "%d:%s" % [agent.settlement_id, design.id]
		if int(sim.settlement_life.no_site_until.get(memo, -1)) > sim.calendar.tick:
			return Fail.NO_SITE
		var choice: Dictionary = SiteFinder.find(sim, design, settlement)
		if choice.is_empty():
			# Nowhere fits today; the settlement will not search again until tomorrow.
			sim.settlement_life.no_site_until[memo] = sim.calendar.tick + sim.calendar.ticks_per_day
			return Fail.NO_SITE
		agent.activity = "building"
		sim.effects.action("mark_site", agent.id, {"template_id": design.id, "origin": choice.origin, "rotation": choice.rotation,
			"order": choice.order, "purpose": step.purpose})
		return Plans.RUNNING
	if not agent.step_result.has("site"):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result.site) > 0 else Fail.OCCUPIED


static func _deliver(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	if sim.construction.get_site(int(step.site)).is_empty():
		return Fail.TARGET_GONE
	if agent.carrying.is_empty():
		return Plans.DONE
	if step_ticks == 0:
		sim.effects.action("deliver", agent.id, {"site": int(step.site)})
		agent.activity = "building"
		return Plans.RUNNING
	if not agent.step_result.has("delivered"):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result.delivered) > 0 else Fail.REFUSED


## Place blocks while materials last, walking to stand within reach of each.
static func _place(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var id: int = int(step.site)
	var site: Dictionary = sim.construction.get_site(id)
	if site.is_empty():
		return Plans.DONE if agent.step_result.get("completed", false) else Fail.TARGET_GONE
	if agent.step_result.get("pending", false):
		return Plans.RUNNING
	if agent.step_result.has("placed"):
		var waited: int = int(agent.step_result.get("waits", 0))
		if int(agent.step_result.placed) == 0 and agent.step_result.get("blocked", false):
			waited += 1
			if waited > 40:
				return Fail.OCCUPIED
		agent.step_result = {"waits": waited}
	var entry: Array = sim.construction.next_entry(id)
	if entry.is_empty():
		return Plans.DONE
	if not sim.construction.ready_to_build(id):
		return Plans.DONE if step_ticks > 0 else Fail.STOCK_EMPTY
	if step_ticks > Balance.integer("agents.move_timeout_ticks") * 4:
		return Fail.TIMED_OUT
	if not _within_reach(agent, entry[0]) or sim.construction.solid_left_has(id, agent.cell):
		var stand: Vector3i = sim.construction.stand_cell(sim, id, entry[0], agent.cell)
		var moving: int = _approach(sim, agent, stand)
		if moving != Plans.DONE:
			return moving
	agent.path.clear()
	agent.activity = "building"
	var work: int = maxi(2, int(Balance.number("construction.ticks_per_block") / Personality.speed(agent, Skill.CONSTRUCTION)))
	var done: int = int(agent.step_result.get("work", 0)) + 1
	agent.step_result["work"] = done
	Personality.practise(agent, Skill.CONSTRUCTION)
	if done >= work:
		agent.step_result["pending"] = true
		agent.step_result["work"] = 0
		sim.effects.action("place_block", agent.id, {"site": id, "index": int(site.cursor)})
	return Plans.RUNNING


static func _repair(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	if step.has("shrine") or step.has("altar_at"):
		return _restore(sim, agent, step, step_ticks)
	var structure: int = int(step.structure)
	if agent.step_result.get("pending", false):
		return Plans.RUNNING
	if agent.step_result.has("repaired") and int(agent.step_result.repaired) == 0:
		return Plans.DONE
	agent.step_result = {}
	var missing: Array = sim.settlement_life.missing_blocks(sim, structure)
	var usable: Array = []
	for entry in missing:
		var resource: String = Registry.build_resource(entry[1])
		if resource.is_empty() or agent.carried(resource) >= 1.0:
			usable = entry
			break
	if usable.is_empty():
		return Plans.DONE
	if not _within_reach(agent, usable[0]):
		var stand: Vector3i = sim.nav.nearest_walkable(usable[0], 3)
		var moving: int = _approach(sim, agent, stand)
		if moving != Plans.DONE:
			return moving if step_ticks < 600 else Fail.TIMED_OUT
	agent.activity = "building"
	agent.step_result["pending"] = true
	sim.effects.action("repair_block", agent.id, {"cell": usable[0], "block": usable[1], "meta": usable[2], "structure": structure})
	return Plans.RUNNING


## Put a shrine's old blocks back (the altar first), or set up a new altar.
static func _restore(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	if agent.step_result.get("pending", false):
		return Plans.RUNNING
	if agent.step_result.has("repaired") and int(agent.step_result.repaired) == 0:
		return Plans.DONE
	agent.step_result = {}
	if agent.carried("stone") < 1.0:
		return Plans.DONE
	var entry: Array = []
	if step.has("altar_at"):
		if sim.voxels.get_block(step.altar_at) == Registry.id("altar"):
			return Plans.DONE
		entry = [step.altar_at, Registry.id("altar"), 0]
	else:
		var missing: Array = sim.faith.missing_blocks(sim, int(step.shrine))
		if missing.is_empty():
			return Plans.DONE
		entry = missing[0]
	if not _within_reach(agent, entry[0]):
		var stand: Vector3i = sim.nav.nearest_walkable(entry[0] + Vector3i(1, 0, 0), 3)
		var moving: int = _approach(sim, agent, stand)
		if moving != Plans.DONE:
			return moving if step_ticks < 600 else Fail.TIMED_OUT
	agent.activity = "building"
	agent.step_result["pending"] = true
	sim.effects.action("repair_block", agent.id, {"cell": entry[0], "block": entry[1], "meta": entry[2], "structure": -1, "rubble": true})
	return Plans.RUNNING


static func run(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	match int(step.op):
		Op.MARK_SITE:
			return _mark_site(sim, agent, step, step_ticks)
		Op.DELIVER:
			return _deliver(sim, agent, step, step_ticks)
		Op.PLACE_BLOCK:
			return _place(sim, agent, step, step_ticks)
		Op.REPAIR_BLOCK:
			return _repair(sim, agent, step, step_ticks)
	return Fail.INTERRUPTED
