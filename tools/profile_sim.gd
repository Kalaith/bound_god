extends SceneTree
## Headless sim profiler (kept out of the exported game).
## Run: Godot --headless --path . --script res://tools/profile_sim.gd [-- --people=60 --days=1 --warm=2 --seed=11]
## Fills Tree Hollow to `people` detailed residents with stores and the
## village designs, lets them settle for `warm` days, then times every phase
## of each tick for `days` days and reports the cost per tick and what that
## means per frame at 1x, 3x and 10x (60 fps, plan §3.3 budget 4 ms).
const Sim = preload("res://scripts/sim/sim.gd")
const Data = preload("res://scripts/core/data.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Template = preload("res://scripts/building/template.gd")
const Stores = preload("res://tools/checks/stores.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const Daily = preload("res://scripts/sim/daily.gd")
const Body = preload("res://scripts/sim/body.gd")
const Perception = preload("res://scripts/sim/perception.gd")
const Inbox = preload("res://scripts/sim/inbox.gd")
const Cognition = preload("res://scripts/sim/cognition.gd")
const Execute = preload("res://scripts/sim/execute.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")
const Lifecycle = preload("res://scripts/sim/lifecycle.gd")

const PHASES: Array[String] = ["daily", "hourly", "jobs", "threats", "buckets", "body", "perception", "inbox",
	"cognition", "execute", "movement", "effects", "homes"]

var _totals: Dictionary = {}


func _init() -> void:
	var people: int = 60
	var days: float = 1.0
	var warm: float = 2.0
	var seed: int = 11
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--people="):
			people = int(argument.trim_prefix("--people="))
		elif argument.begins_with("--days="):
			days = float(argument.trim_prefix("--days="))
		elif argument.begins_with("--warm="):
			warm = float(argument.trim_prefix("--warm="))
		elif argument.begins_with("--seed="):
			seed = int(argument.trim_prefix("--seed="))
	var sim: RefCounted = populate(seed, people)
	sim.run_ticks(int(warm * sim.calendar.ticks_per_day))
	for phase in PHASES:
		_totals[phase] = 0
	var ticks: int = int(days * sim.calendar.ticks_per_day)
	var costs: Array = []
	var worst_phases: Dictionary = {}
	var worst_tick: int = 0
	var started: int = Time.get_ticks_usec()
	for _i in range(ticks):
		var before: Dictionary = _totals.duplicate()
		var begin: int = Time.get_ticks_usec()
		_timed_step(sim)
		var cost: int = Time.get_ticks_usec() - begin
		if costs.is_empty() or cost > costs.max():
			worst_tick = sim.calendar.tick
			for phase in PHASES:
				worst_phases[phase] = int(_totals[phase]) - int(before[phase])
		costs.append(cost)
	var elapsed: float = (Time.get_ticks_usec() - started) / 1000.0
	costs.sort()
	var mean: float = elapsed / ticks
	var p95: float = costs[int(costs.size() * 0.95)] / 1000.0
	var worst: float = costs[-1] / 1000.0
	print("PROFILE seed %d, %d present after %.1f warm days, %d ticks" % [seed, sim.present_count(), warm, ticks])
	print("  mean %.2f ms/tick, median %.2f, p95 %.2f, worst %.2f; %.1f s per in-game day" % [mean, costs[costs.size() / 2] / 1000.0, p95, worst, mean * sim.calendar.ticks_per_day / 1000.0])
	var tps: float = Balance.number("time.ticks_per_second")
	for speed in [1.0, 3.0, 10.0]:
		var per_frame: float = tps * speed / 60.0
		print("  %dx: %.2f ticks/frame, mean sim %.2f ms/frame (budget 4.0)" % [int(speed), per_frame, per_frame * mean])
	var spikes: Array[String] = []
	for phase in PHASES:
		if int(worst_phases.get(phase, 0)) > 1000:
			spikes.append("%s %.1f" % [phase, worst_phases[phase] / 1000.0])
	print("  worst tick %d (hour %.1f): %s ms" % [worst_tick, float(worst_tick % sim.calendar.ticks_per_day) * 24.0 / sim.calendar.ticks_per_day, ", ".join(spikes)])
	var phases: Array = PHASES.duplicate()
	phases.sort_custom(func(a: String, b: String) -> bool: return int(_totals[a]) > int(_totals[b]))
	for phase in phases:
		print("  %-11s %7.3f ms/tick  %4.1f%%" % [phase, int(_totals[phase]) / 1000.0 / ticks, 100.0 * int(_totals[phase]) / 1000.0 / elapsed])
	quit(0)


## Seed `seed` with Tree Hollow filled to `people` residents, a chest of
## food and wood, and the village and food designs offered.
static func populate(seed: int, people: int) -> RefCounted:
	var sim: RefCounted = Sim.create(seed)
	var camp: Vector3i = sim.settlements.entries[1].camp
	var i: int = 0
	while sim.present_count() < people:
		var cell: Vector3i = sim.nav.nearest_walkable(camp + Vector3i(i % 6 - 3, 0, i / 6 - 3), 6)
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), cell, 1, "")
		i += 1
	sim.run_ticks(12)
	Stores.place_chest(sim, 1)
	Stores.fill(sim, 1, {"berries": 120, "wood": 60, "grain": 40})
	for id in ["timber_cottage", "store_shed", "village_hall", "garden_patch", "field_plot"]:
		var design: Dictionary = Template.from_starter(Data.starter(id)).to_dict()
		design.id = id + "_offered"
		sim.apply_command({"type": "offer_template", "template": design})
	return sim


func _lap(phase: String, begin: int) -> int:
	var now: int = Time.get_ticks_usec()
	_totals[phase] = int(_totals[phase]) + now - begin
	return now


## sim.step() with a stopwatch round each phase (kept in step with sim.gd).
func _timed_step(sim: RefCounted) -> void:
	var t: int = Time.get_ticks_usec()
	sim.calendar.tick += 1
	sim.nav.paths_this_tick = 0
	if sim.calendar.is_new_day():
		Daily.new_day(sim)
	t = _lap("daily", t)
	if sim.calendar.is_new_hour():
		Daily.new_hour(sim)
	t = _lap("hourly", t)
	if sim.calendar.tick % 10 == 0:
		sim.settlement_life.refresh_jobs(sim)
	t = _lap("jobs", t)
	sim.threats.step(sim)
	t = _lap("threats", t)
	sim._refresh_site_buckets()
	sim._refresh_agent_buckets()
	t = _lap("buckets", t)
	for agent in sim.agents:
		if not agent.is_present():
			continue
		Body.update(sim, agent)
		t = _lap("body", t)
		var alarmed: bool = Perception.perceive(sim, agent)
		t = _lap("perception", t)
		var urgent: bool = Inbox.process(sim, agent)
		if alarmed and agent.interrupted_by.is_empty():
			agent.interrupted_by = "interrupt_percept"
		t = _lap("inbox", t)
		Cognition.think(sim, agent, alarmed or urgent)
		t = _lap("cognition", t)
		Execute.run_step(sim, agent)
		t = _lap("execute", t)
		Movement.advance(sim, agent)
		t = _lap("movement", t)
	EffectsApply.apply(sim)
	Lifecycle.resolve_deaths(sim)
	t = _lap("effects", t)
	sim._reconcile_homes("npc")
	_lap("homes", t)
