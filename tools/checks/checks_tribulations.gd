extends RefCounted
## M16 Breakthroughs and tribulations: the sanctuary's help, the outcome
## table, Defy Heaven's price, no miracle granting a realm, and lightning
## that harms only what lies within its storm.
const Sim = preload("res://scripts/sim/sim.gd")
const Data = preload("res://scripts/core/data.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Tribulations = preload("res://scripts/sim/tribulations.gd")
const Movement = preload("res://scripts/sim/movement.gd")

const NONE := Vector3i(-1, -1, -1)


## A Qi Refining cultivator at the peak, seated at `cell`.
static func _at_peak(sim: RefCounted, agent: RefCounted, cell: Vector3i, foundation: float) -> void:
	agent.cultivation = CultivationState.fresh(0.6, "none", 0.9)
	agent.cultivation.realm = 1
	agent.cultivation.progress = CultivationState.needed(agent.cultivation)
	agent.cultivation.foundation = foundation
	agent.cultivation.techniques = ["tree_breath"]
	agent.cell = cell
	agent.position = Movement.center(cell)
	agent.previous_position = agent.position


static func _tree_cell(sim: RefCounted, dx: int) -> Vector3i:
	var tree: Vector3i = sim.features.sacred_tree
	return sim.nav.nearest_walkable(tree + Vector3i(dx, 0, 3), 3)


## The tree's sanctuary is where it stands; the same trial there has better
## odds than away from it.
func check_the_sanctuary_improves_the_odds():
	var sim: RefCounted = Sim.create(11)
	var near: Vector3i = _tree_cell(sim, 2)
	var far: Vector3i = _tree_cell(sim, 30)
	if not Tribulations.in_sanctuary(sim, near) or Tribulations.in_sanctuary(sim, far):
		return "the sanctuary is not where the tree stands (%s, %s)" % [near, far]
	var agent: RefCounted = sim.agents[0]
	_at_peak(sim, agent, near, 0.6)
	var trial: Dictionary = {"severity": 0.6, "shield": 0.0, "preparation": 0.6, "sanctuary": true}
	var inside: float = Tribulations.odds(trial, agent)
	trial.sanctuary = false
	var outside: float = Tribulations.odds(trial, agent)
	if inside <= outside:
		return "odds %.2f in the sanctuary, %.2f outside" % [inside, outside]
	trial.shield = Data.tribulations().odds.severity
	if Tribulations.odds(trial, agent) <= outside or Tribulations.death_share(trial) >= Tribulations.death_share({"severity": 0.6, "shield": 0.0}):
		return "a shield did not soften the trial"
	return ""


## Every row of the outcome table does what it says: passing opens the next
## realm on a sound foundation, injury cracks it and sets progress back,
## death is death; fiercer storms are worse.
func long_check_the_outcome_table():
	var seen: Dictionary = {}
	var sim: RefCounted = Sim.create(100)
	var agent: RefCounted = sim.agents[0]
	for attempt in range(80):
		# The same person, made whole again for each try.
		agent.life = "present"
		agent.life_cause = ""
		agent.health.hp = 100.0
		_at_peak(sim, agent, _tree_cell(sim, 2), 0.45)
		var id: int = sim.tribulations.announce(sim, agent, agent.cell)
		var trial: Dictionary = sim.tribulations.entries[id]
		trial.severity = 0.9
		trial.state = "storm"
		trial.preparation = 0.5
		sim.tribulations._resolve(sim, trial, agent)
		var c: Dictionary = agent.cultivation
		match str(trial.outcome):
			"passed":
				if int(c.realm) != 2 or float(c.foundation) < 0.4 or bool(c.flawed):
					return "a pass left realm %d, foundation %.2f" % [int(c.realm), float(c.foundation)]
			"injured":
				if int(c.realm) != 1 or float(c.foundation) >= 0.45 or CultivationState.at_peak(c) or float(agent.health.hp) >= 100.0:
					return "an injury did not crack the foundation and set progress back"
			"died":
				if agent.is_present() or agent.life_cause != "cause_tribulation":
					return "a death left them alive or without its cause"
		seen[trial.outcome] = int(seen.get(trial.outcome, 0)) + 1
		if seen.size() == 3:
			break
	if seen.size() < 3:
		return "not every outcome came up in 80 fierce trials: %s" % str(seen)
	var calm: float = Tribulations.odds({"severity": 0.2, "shield": 0.0, "preparation": 0.9, "sanctuary": true}, Sim.create(11).agents[0])
	var fierce: float = Tribulations.odds({"severity": 0.95, "shield": 0.0, "preparation": 0.9, "sanctuary": true}, Sim.create(11).agents[0])
	if calm <= fierce:
		return "a fiercer storm did not lower the odds"
	return ""


## The same doomed trial twice: without the god the cultivator dies; with
## Defy Heaven they live and break through, their foundation damaged, less
## of a longer life ahead and a harder road to the next realm.
func check_defy_heaven_saves_a_doomed_cultivator():
	for seed in range(200, 260):
		var alone: Dictionary = _doomed(seed, false)
		if alone.outcome != "died":
			continue
		var helped: Dictionary = _doomed(seed, true)
		var agent: RefCounted = helped.agent
		if helped.outcome != "defied" or not agent.is_present():
			return "Defy Heaven did not turn the death aside (%s)" % helped.outcome
		var c: Dictionary = agent.cultivation
		if int(c.realm) != 2 or float(c.foundation) > 0.2 or not bool(c.flawed) or float(c.next_factor) <= 1.0:
			return "the defied breakthrough left no lasting price: %s" % str(c)
		if CultivationState.lifespan(c) >= CultivationState.lifespan({"realm": 2, "flawed": false, "next_factor": 1.0}):
			return "a defied breakthrough kept the full lifespan"
		var named: bool = false
		for entry in helped.sim.chronicle.entries:
			named = named or (entry.kind == "trial_defied" and str(entry.cause) == "cause_defy_heaven")
		return "" if named else "the chronicle does not say the god defied Heaven"
	return "no seed gave a doomed trial"


static func _doomed(seed: int, defy: bool) -> Dictionary:
	var sim: RefCounted = Sim.create(seed)
	var agent: RefCounted = sim.agents[0]
	# Inside the presence but beyond the sanctuary, so the god can reach them.
	_at_peak(sim, agent, _tree_cell(sim, 9), 0.05)
	agent.cultivation.techniques = []
	var id: int = sim.tribulations.announce(sim, agent, agent.cell)
	var trial: Dictionary = sim.tribulations.entries[id]
	trial.severity = 1.0
	if defy:
		sim.faith.current(sim).favour = 120.0
		sim.god.avatar_cell = agent.cell
		var result: Dictionary = sim.apply_command({"type": "cast_miracle", "miracle": "defy_heaven", "cell": agent.cell})
		if not result.ok:
			push_error("Defy Heaven was refused: " + str(result.reason))
			return {"outcome": "refused " + str(result.reason), "agent": agent, "sim": sim}
	trial.state = "storm"
	trial.preparation = 0.0
	sim.tribulations._resolve(sim, trial, agent)
	return {"outcome": trial.outcome, "agent": agent, "sim": sim}


## No miracle raises a realm: blessing, shielding and defying leave a
## cultivator's realm where their own trial leaves it.
func check_no_miracle_grants_a_realm():
	var sim: RefCounted = Sim.create(11)
	var agent: RefCounted = sim.agents[0]
	_at_peak(sim, agent, _tree_cell(sim, 2), 0.6)
	sim.faith.current(sim).favour = 120.0
	var cell: Vector3i = agent.cell
	for miracle in ["bless_cultivation", "shield_trial", "defy_heaven"]:
		sim.apply_command({"type": "cast_miracle", "miracle": miracle, "cell": cell, "agent": agent.id})
		if int(agent.cultivation.realm) != 1:
			return "%s raised the realm without a trial" % miracle
	sim.tribulations.announce(sim, agent, agent.cell)
	sim.faith.current(sim).favour = 120.0
	for miracle in ["shield_trial", "defy_heaven"]:
		sim.faith.current(sim).favour = 120.0
		var result: Dictionary = sim.apply_command({"type": "cast_miracle", "miracle": miracle, "cell": cell})
		if not result.ok:
			return "%s was refused on a called trial: %s" % [miracle, result.reason]
		if int(agent.cultivation.realm) != 1:
			return "%s raised the realm before the storm" % miracle
	return ""


## Lightning scorches and splits only what lies within its storm's radius
## round the cultivator, never the sacred tree, and the chronicle counts it.
func check_tribulation_damage_stays_within_its_radius():
	for seed in range(11, 31):
		var sim: RefCounted = Sim.create(seed)
		var agent: RefCounted = sim.agents[0]
		var site: Vector3i = _tree_cell(sim, 6)
		_at_peak(sim, agent, site, 0.6)
		var radius: int = int(Tribulations.kind_for(1).radius)
		var before: Dictionary = {}
		for dz in range(-radius - 6, radius + 7):
			for dx in range(-radius - 6, radius + 7):
				for dy in range(-6, 12):
					var cell := site + Vector3i(dx, dy, dz)
					before[cell] = sim.voxels.get_block(cell)
		var tree_blocks: int = _sacred_count(sim)
		var id: int = sim.tribulations.announce(sim, agent, site)
		var trial: Dictionary = sim.tribulations.entries[id]
		trial.start_tick = sim.calendar.tick + 1
		for i in range(trial.strikes.size()):
			trial.strikes[i] = sim.calendar.tick + 2 + i * 3
		trial.end_tick = sim.calendar.tick + 4 + trial.strikes.size() * 3
		for _i in range(trial.strikes.size() * 3 + 6):
			sim.tribulations.step(sim)
			sim.calendar.tick += 1
		if _sacred_count(sim) != tree_blocks:
			return "lightning harmed the sacred tree"
		var changed: int = 0
		for cell in before:
			if sim.voxels.get_block(cell) == before[cell]:
				continue
			changed += 1
			if Vector2(cell.x - site.x, cell.z - site.z).length() > radius * 1.42 + 0.5:
				return "lightning changed a block %s outside its radius" % cell
		if changed == 0:
			continue
		for entry in sim.chronicle.entries:
			if entry.kind == "trial_scorched" and int(entry.args.count) > 0:
				return ""
		return "the scorching was not chronicled"
	return "no storm scorched anything in twenty seeds"


static func _sacred_count(sim: RefCounted) -> int:
	var tree: Vector3i = sim.features.sacred_tree
	var count: int = 0
	var sacred: Array = [Data.block_id("sacred_tree"), Data.block_id("sacred_leaves")]
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			for dy in range(0, 20):
				if sacred.has(sim.voxels.get_block(tree + Vector3i(dx, dy, dz))):
					count += 1
	return count


## Core Formation: a Foundation Establishment cultivator at the peak faces
## the fiercer lightning that forms a core; passing opens the realm, and the
## tree learns of it as a new insight. Nothing lies beyond it yet.
func check_core_formation_is_the_next_trial():
	var sim: RefCounted = Sim.create(11)
	var kind: Dictionary = Tribulations.kind_for(2)
	if str(kind.get("id", "")) != "core_lightning" or float(kind.severity[0]) <= float(Tribulations.kind_for(1).severity[0]):
		return "Foundation Establishment's trial is not the fiercer core lightning: %s" % str(kind)
	var agent: RefCounted = sim.agents[0]
	var passed: bool = false
	for attempt in range(12):
		_at_peak(sim, agent, _tree_cell(sim, 2), 0.95)
		agent.cultivation.realm = 2
		agent.cultivation.progress = CultivationState.needed(agent.cultivation)
		agent.health.hp = 100.0
		agent.life = "present"
		var outcome: String = sim.tribulations.abstract_trial(sim, agent, agent.cell)
		if outcome == "passed":
			passed = true
			break
	if not passed:
		return "twelve well-founded trials in the sanctuary all failed"
	if int(agent.cultivation.realm) != 3 or Data.realms()[3].id != "core_formation":
		return "passing did not open Core Formation (realm %d)" % int(agent.cultivation.realm)
	if float(sim.tree_growth.insights.get("core_lightning", 0.0)) <= 0.0:
		return "the tree learned nothing from the core's lightning"
	agent.cultivation.progress = CultivationState.needed(agent.cultivation)
	if CultivationState.has_next(agent.cultivation) or sim.tribulations.announce(sim, agent, agent.cell) != 0:
		return "a trial was called beyond Core Formation"
	return ""
