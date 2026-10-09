extends RefCounted
## Turns an agent's reasoning into readable lines: goals with their targets,
## plan steps, decision log entries and reasons. All words come from text
## catalogs; this file only fills templates.
const Text = preload("res://scripts/core/text.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")


static func name_of(sim: RefCounted, id: int) -> String:
	if id < 0 or id >= sim.agents.size():
		return Text.label("someone")
	return sim.agents[id].given_name


static func goal(sim: RefCounted, value: Dictionary) -> String:
	if value.is_empty():
		return Text.label("goal_none")
	var kind: int = int(value.kind)
	var target: int = int(value.target)
	var args: Dictionary = {}
	if kind in Goals.TARGETS_AGENT:
		args["name"] = name_of(sim, target)
	match kind:
		Goals.Kind.GATHER:
			args["resource"] = Text.label("resource_" + sim_resource(target)).to_lower()
		Goals.Kind.PROPOSE_PROJECT:
			args["function"] = Text.label("function_" + function_name(target)).to_lower()
		Goals.Kind.MIGRATE:
			args["place"] = sim.settlements.get_settlement(target).get("name", Text.label("somewhere"))
	return Text.format("goal_" + Goals.NAMES[kind], args)


## Gather goals carry an index into the resource list as their target.
static func sim_resource(index: int) -> String:
	const RESOURCES: Array[String] = ["wood", "stone", "thatch", "berries", "ore"]
	return RESOURCES[index] if index >= 0 and index < RESOURCES.size() else ""


static func function_name(index: int) -> String:
	const FUNCTIONS: Array[String] = ["dwelling", "storehouse", "workshop", "shrine", "shelter"]
	return FUNCTIONS[index] if index >= 0 and index < FUNCTIONS.size() else "unrecognised"


static func plan(id: String) -> String:
	return Text.label("plan_" + id) if Text.has("plan_" + id) else id


static func reason(key: String, value: float) -> String:
	if key.is_empty():
		return ""
	if is_nan(value):
		return Text.label(key)
	return "%s %d" % [Text.label(key), roundi(value)]


static func step(sim: RefCounted, value: Dictionary) -> String:
	var op: int = int(value.op)
	var args: Dictionary = {}
	if op == Plans.Op.GO_TO:
		var where: Dictionary = value.target
		match int(where.type):
			Plans.T.AGENT:
				args["place"] = name_of(sim, int(where.id))
			Plans.T.STORE:
				args["place"] = Text.label("place_stores")
			Plans.T.SITE:
				var site: Dictionary = sim.sites.get_site(int(where.id))
				args["place"] = Text.label("site_" + str(site.get("kind", "gone")))
			Plans.T.STRUCTURE:
				var entry: Dictionary = sim.structures.entries.get(int(where.id), {})
				var functions: Array = entry.get("functions", [])
				args["place"] = Text.label("function_" + (functions[0] if not functions.is_empty() else "unrecognised")).to_lower()
			Plans.T.SHRINE:
				args["place"] = Text.label("place_shrine")
			Plans.T.CONSTRUCTION:
				args["place"] = Text.label("place_construction")
			_:
				args["place"] = Text.label("place_spot")
	if value.has("resource"):
		args["resource"] = Text.label("resource_" + str(value.resource)).to_lower()
	if value.has("to"):
		args["name"] = name_of(sim, int(value.to))
	if value.has("with"):
		args["name"] = name_of(sim, int(value.with))
	return Text.format("step_" + Plans.OP_NAMES[op], args)


static func entry(sim: RefCounted, value: Dictionary) -> String:
	match str(value.kind):
		"adopted":
			var line: String = Text.format("log_adopted", {"goal": goal(sim, value.goal)})
			var why: String = reason(str(value.reason), float(value.value))
			if not why.is_empty():
				line += " " + Text.format("log_reason", {"reason": why})
			if value.get("urged", false):
				line += " " + Text.label("log_urged")
			return line
		"plan":
			return Text.format("log_plan", {"plan": plan(value.plan)})
		"failed":
			return Text.format("log_failed", {"plan": plan(value.plan), "reason": Text.label("fail_" + Plans.FAIL_NAMES[int(value.reason)])})
		"gave_up":
			return Text.format("log_gave_up", {"goal": goal(sim, value.goal)})
		"achieved":
			return Text.format("log_achieved", {"goal": goal(sim, value.goal)})
		"interrupted":
			return Text.format("log_interrupted", {"by": Text.label(str(value.by))})
		"message":
			return Text.format(str(value.text), value.get("args", {}))
	return str(value.kind)


static func is_setback(value: Dictionary) -> bool:
	return str(value.kind) in ["failed", "gave_up", "interrupted"]


static func clock(sim: RefCounted, tick: int) -> String:
	var day_ticks: int = sim.calendar.ticks_per_day
	var hour: float = float(tick % day_ticks) * 24.0 / float(day_ticks)
	return "%d · %02d:%02d" % [tick / day_ticks + 1, int(hour), int((hour - floorf(hour)) * 60.0)]


static func need_name(index: int) -> String:
	return Text.label("need_" + Personality.NEEDS[index])


static func skill_name(index: int) -> String:
	return Text.label("skill_" + Personality.SKILLS[index])


static func bond(key: String) -> String:
	return Text.label("bond_" + key)
