extends RefCounted
## Heavenly tribulations (M16). A cultivator at a realm's peak who decides
## to break through announces it; after a warning Heaven answers with a
## storm over wherever they are: lightning strikes them and the ground
## round them, scorching and splitting exposed blocks; those in danger flee,
## believers who see it pray. When the storm ends the outcome is rolled from
## foundation, preparation, technique, sanctuary and severity: success (a new
## realm), injury and a cracked foundation, or death. The god can only
## lower the severity (Shield the Trial) or turn a death aside (Defy Heaven).
## id -> {id, agent, kind, severity, shield, defy, site: Vector3i, sanctuary: bool,
##        preparation, start_tick, end_tick, strikes: Array[int] (ticks), struck: int,
##        scorched: int, state: "warning"|"storm"|"done", outcome: String}
const Balance = preload("res://scripts/core/balance.gd")
const SectPlaces = preload("res://scripts/sim/sect_places.gd")
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Lifecycle = preload("res://scripts/sim/lifecycle.gd")
const Movement = preload("res://scripts/sim/movement.gd")

var entries: Dictionary = {}
var next_id: int = 1
## Strikes and storms for the presentation: {kind, trial, cell, tick}.
var events: Array = []


static func kind_for(realm: int) -> Dictionary:
	for kind in Data.tribulations().kinds:
		if int(kind.realm_from) == realm:
			return kind
	return {}


## The trial a person is facing (warning or storm), or {}.
func of(agent_id: int) -> Dictionary:
	for id in entries:
		var trial: Dictionary = entries[id]
		if int(trial.agent) == agent_id and trial.state != "done":
			return trial
	return {}


## Storm ids are negative so they never meet a threat id.
static func storm_id(trial_id: int) -> int:
	return -1000 - trial_id


func storm_active(id: int) -> bool:
	var trial: Dictionary = entries.get(-1000 - id, {})
	return not trial.is_empty() and trial.state == "storm"


## Whether a cell stands within the tree's sanctuary.
static func in_sanctuary(sim: RefCounted, cell: Vector3i) -> bool:
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	if SectPlaces.ground_sanctuary(sim, cell):
		return true
	return tree.x >= 0 and Vector2(cell.x - tree.x - 1.0, cell.z - tree.z - 1.0).length() <= Balance.number("cultivation.sanctuary_radius")


## How ready a person is: rested, fed, and helped (blessed, or a teacher or
## fellow sect member at hand).
static func preparation(sim: RefCounted, agent: RefCounted) -> float:
	var helped: float = 0.0
	if int(agent.cultivation.get("blessed_until", -1)) > sim.calendar.tick:
		helped = 1.0
	for other_id in sim.spatial.near("agents", agent.cell, 6.0):
		var other: RefCounted = sim.agents[other_id]
		if other_id != agent.id and other.is_present() and (other_id == int(agent.cultivation.teacher) \
				or (int(agent.cultivation.sect_id) >= 0 and int(other.cultivation.sect_id) == int(agent.cultivation.sect_id))):
			helped = maxf(helped, 0.7)
	var fruit: float = float(Data.tree_growth().fruit.preparation) if bool(agent.cultivation.get("fruit", false)) else 0.0
	return clampf(0.35 * agent.need(Personality.Need.REST) / 100.0 + 0.35 * agent.need(Personality.Need.FOOD) / 100.0 + 0.3 * helped + fruit, 0.0, 1.0)


## The decision is made: Heaven will answer after the warning.
func announce(sim: RefCounted, agent: RefCounted, site: Vector3i) -> int:
	if not of(agent.id).is_empty():
		return 0
	var kind: Dictionary = kind_for(int(agent.cultivation.realm))
	if kind.is_empty() or not CultivationState.at_peak(agent.cultivation):
		return 0
	var severity: float = clampf(sim.rng.randf_range(float(kind.severity[0]), float(kind.severity[1]))
		+ float(kind.talent_severity) * (float(agent.cultivation.talent) - 0.5), 0.05, 1.0)
	var start: int = sim.calendar.tick + int(kind.warning_ticks)
	var end: int = start + int(kind.storm_ticks)
	var count: int = sim.rng.randi_range(int(kind.strikes[0]), int(kind.strikes[1]))
	var strikes: Array = []
	for i in range(count):
		strikes.append(start + int(float(kind.storm_ticks) * (i + 0.5) / count))
	var id: int = next_id
	next_id += 1
	entries[id] = {"id": id, "agent": agent.id, "kind": kind.id, "severity": severity, "shield": 0.0, "defy": false,
		"site": site, "sanctuary": in_sanctuary(sim, site), "preparation": 0.0, "start_tick": start, "end_tick": end,
		"strikes": strikes, "struck": 0, "scorched": 0, "state": "warning", "outcome": ""}
	var shrine: int = int(agent.faith.get("shrine_id", -1))
	if sim.faith != null and shrine < 0:
		shrine = sim.god.active_shrine_id
	if sim.faith != null and shrine >= 0:
		sim.faith.record_prayer(sim, agent, shrine, {"kind": "trial", "at": start})
	var where: String = "cause_trial_sanctuary" if entries[id].sanctuary else "cause_trial_elsewhere"
	sim.chronicle_event("trial_announced", agent.settlement_id, {"name": agent.full_name(), "clock": _clock(sim, start)}, where, [agent.id])
	return id


static func _clock(sim: RefCounted, tick: int) -> String:
	var hour: float = float(tick % sim.calendar.ticks_per_day) * 24.0 / sim.calendar.ticks_per_day
	return "%02d:%02d" % [int(hour), int((hour - floorf(hour)) * 60.0)]


func step(sim: RefCounted) -> void:
	if entries.is_empty():
		return
	var now: int = sim.calendar.tick
	# Nobody may be watching (headless): the presentation's events fade.
	while not events.is_empty() and int(events[0].tick) < now - 60:
		events.pop_front()
	var ids: Array = entries.keys()
	ids.sort()
	for id in ids:
		var trial: Dictionary = entries[id]
		# A finished trial lives on in the person's record and the chronicle.
		if trial.state == "done":
			entries.erase(id)
			continue
		var agent: RefCounted = sim.agents[int(trial.agent)]
		if not agent.is_present():
			trial.state = "done"
			trial.outcome = "gone"
			continue
		if trial.state == "warning" and now >= int(trial.start_tick):
			_begin(sim, trial, agent)
		if trial.state != "storm":
			continue
		if now % 10 == 0:
			_alarm(sim, trial, agent)
		while int(trial.struck) < trial.strikes.size() and now >= int(trial.strikes[int(trial.struck)]):
			_strike(sim, trial, agent)
			trial.struck = int(trial.struck) + 1
		if now >= int(trial.end_tick):
			_resolve(sim, trial, agent)


## The storm gathers over wherever the cultivator is now.
func _begin(sim: RefCounted, trial: Dictionary, agent: RefCounted) -> void:
	trial.state = "storm"
	trial.site = agent.cell
	trial.sanctuary = in_sanctuary(sim, agent.cell)
	trial.preparation = preparation(sim, agent)
	if bool(trial.sanctuary) and sim.tree_growth != null:
		trial.preparation = minf(float(trial.preparation) + sim.tree_growth.relic_preparation(), 1.0)
	# A spirit fruit kept for this moment is eaten now.
	if bool(agent.cultivation.get("fruit", false)):
		agent.cultivation.fruit = false
		trial["fruit"] = true
		sim.chronicle_event("fruit_eaten", agent.settlement_id, {"name": agent.full_name()}, "cause_before_trial", [agent.id])
	events.append({"kind": "storm", "trial": trial.id, "cell": agent.cell, "tick": sim.calendar.tick})
	var sight: float = Balance.number("agents.sight_radius") * 1.5
	for other_id in sim.spatial.near("agents", agent.cell, sight):
		var other: RefCounted = sim.agents[other_id]
		if other_id != agent.id and other.is_present() and Vector2(other.cell.x - agent.cell.x, other.cell.z - agent.cell.z).length() <= sight:
			Mind.add(other, "witnessed_trial", sim.calendar.ticks_per_day, agent.id)
	_alarm(sim, trial, agent)


## Anyone close enough to be struck knows a storm is on them and runs.
func _alarm(sim: RefCounted, trial: Dictionary, agent: RefCounted) -> void:
	var kind: Dictionary = kind_for(int(agent.cultivation.realm))
	var danger: float = float(kind.get("radius", 4)) + 2.0
	for other_id in sim.spatial.near("agents", agent.cell, danger):
		var other: RefCounted = sim.agents[other_id]
		if other_id == agent.id or not other.is_present():
			continue
		if Vector2(other.cell.x - agent.cell.x, other.cell.z - agent.cell.z).length() > danger:
			continue
		if other.beliefs.note_threat(storm_id(int(trial.id)), "storm", agent.cell, true, sim.calendar.tick):
			other.interrupted_by = "interrupt_storm"
			other.next_deliberation = sim.calendar.tick


func _strike(sim: RefCounted, trial: Dictionary, agent: RefCounted) -> void:
	var kind: Dictionary = kind_for(int(agent.cultivation.realm))
	var radius: int = int(kind.get("radius", 4))
	var at_person: bool = int(trial.struck) == 0 or int(trial.struck) == trial.strikes.size() - 1 or sim.rng.randf() < 0.3
	var column := Vector2i(agent.cell.x, agent.cell.z)
	if not at_person:
		column += Vector2i(sim.rng.randi_range(-radius, radius), sim.rng.randi_range(-radius, radius))
	# On a tribulation ground the formation stones draw what would scorch.
	var stones: Array = SectPlaces.ground_at(sim, agent.cell).get("components", {}).get("formation", [])
	if not at_person and not stones.is_empty():
		var stone: Vector3i = stones[sim.rng.randi_range(0, stones.size() - 1)]
		events.append({"kind": "strike", "trial": trial.id, "cell": stone + Vector3i.UP, "tick": sim.calendar.tick})
		trial["drawn"] = int(trial.get("drawn", 0)) + 1
		return
	var top: int = sim.voxels.top_solid_y(column.x, column.y)
	var cell := Vector3i(column.x, top, column.y)
	events.append({"kind": "strike", "trial": trial.id, "cell": cell + Vector3i.UP, "tick": sim.calendar.tick})
	if at_person or top < 0:
		return
	if _scorch(sim, cell):
		trial.scorched = int(trial.scorched) + 1


## Lightning burns, chars, scorches or splits the exposed block it hits.
## The sacred tree takes no harm.
static func _scorch(sim: RefCounted, cell: Vector3i) -> bool:
	var block: int = sim.voxels.get_block(cell)
	var name: String = Registry.block_name(block)
	var scorch: Dictionary = Data.tribulations().scorch
	var above: Vector3i = cell + Vector3i.UP
	if Registry.block_name(sim.voxels.get_block(above)) in scorch.burned:
		return sim.set_block(above, 0, 0, "heaven")
	if name in scorch.burned:
		return sim.set_block(cell, 0, 0, "heaven")
	if name in scorch.charred_wood:
		return sim.set_block(cell, Registry.id("charred_wood"), 0, "heaven")
	if name in scorch.scorched_earth:
		return sim.set_block(cell, Registry.id("scorched_earth"), 0, "heaven")
	if name in scorch.split:
		return sim.set_block(cell, Registry.id(str(scorch.split_into)), 0, "heaven")
	return false


## The chance of passing, from what the person brings and what Heaven sends.
static func odds(trial: Dictionary, agent: RefCounted) -> float:
	var o: Dictionary = Data.tribulations().odds
	var severity: float = float(trial.severity) * (1.0 - float(trial.shield))
	var p: float = float(o.base) + float(o.foundation) * (float(agent.cultivation.foundation) - 0.5) \
		+ float(o.preparation) * (float(trial.preparation) - 0.5) - float(o.severity) * (severity - 0.5)
	if not agent.cultivation.techniques.is_empty():
		p += float(o.technique)
	if bool(trial.sanctuary):
		p += float(o.sanctuary)
	return clampf(p, float(o.least), float(o.most))


## Of those who fail, how many die: more the fiercer the storm.
static func death_share(trial: Dictionary) -> float:
	var o: Dictionary = Data.tribulations().odds
	return clampf(float(o.death_share_base) + float(o.death_share_severity) * float(trial.severity) * (1.0 - float(trial.shield)), 0.0, 0.9)


func _resolve(sim: RefCounted, trial: Dictionary, agent: RefCounted) -> void:
	trial.state = "done"
	var p: float = odds(trial, agent)
	var outcome: String = "passed"
	if sim.rng.randf() >= p:
		outcome = "died" if sim.rng.randf() < death_share(trial) else "injured"
	if outcome == "died" and bool(trial.defy):
		outcome = "defied"
	trial.outcome = outcome
	events.append({"kind": "end", "trial": trial.id, "cell": agent.cell, "tick": sim.calendar.tick, "outcome": outcome})
	var record: Dictionary = {"tick": sim.calendar.tick, "kind": trial.kind, "outcome": outcome, "sanctuary": trial.sanctuary,
		"severity": trial.severity, "shield": trial.shield, "odds": p}
	agent.cultivation.trials.append(record)
	var outcomes: Dictionary = Data.tribulations().outcomes
	var where: String = "cause_trial_sanctuary" if bool(trial.sanctuary) else "cause_trial_elsewhere"
	match outcome:
		"passed":
			var weights: Array = outcomes.success_foundation
			_advance(sim, agent, clampf(float(weights[0]) + float(weights[1]) * float(trial.preparation), 0.1, 1.0), false)
			sim.chronicle_event("trial_passed", agent.settlement_id, {"name": agent.full_name(), "realm": _realm_key(agent)}, where, [agent.id])
		"injured":
			agent.health.hp = maxf(float(agent.health.hp) - float(outcomes.injury_damage) * float(trial.severity), 1.0)
			agent.cultivation.foundation = maxf(float(agent.cultivation.foundation) - float(outcomes.injury_crack), 0.05)
			agent.cultivation.progress = CultivationState.needed(agent.cultivation) * float(outcomes.injury_progress)
			agent.cultivation.peak_tick = -1
			Mind.add(agent, "failed_trial", sim.calendar.ticks_per_day)
			sim.chronicle_event("trial_injured", agent.settlement_id, {"name": agent.full_name()}, where, [agent.id])
		"defied":
			_advance(sim, agent, float(outcomes.defied_foundation), true)
			sim.chronicle_event("trial_defied", agent.settlement_id, {"name": agent.full_name(), "realm": _realm_key(agent)}, "cause_defy_heaven", [agent.id])
		"died":
			sim.chronicle_event("trial_died", agent.settlement_id, {"name": agent.full_name()}, where, [agent.id])
			Lifecycle.die(sim, agent, "cause_tribulation")
	if int(trial.scorched) > 0:
		sim.chronicle_event("trial_scorched", agent.settlement_id, {"name": agent.given_name, "count": trial.scorched}, "cause_heaven_lightning", [agent.id])
	if sim.tree_growth != null:
		sim.tree_growth.on_trial(sim, trial, agent)


static func _realm_key(agent: RefCounted) -> String:
	return "realm_" + str(Data.realm(int(agent.cultivation.realm)).id)


## Through Heaven's gate into the next realm. A breakthrough Heaven meant to
## end is imperfect: a damaged foundation, less of a longer life, and a
## harder road to the realm after.
static func _advance(sim: RefCounted, agent: RefCounted, foundation: float, flawed: bool) -> void:
	var c: Dictionary = agent.cultivation
	c.realm = int(c.realm) + 1
	c.progress = 0.0
	c.peak_tick = -1
	c.foundation = foundation
	if flawed:
		var outcomes: Dictionary = Data.tribulations().outcomes
		c.flawed = true
		c.next_factor = float(outcomes.defied_next_realm)
	else:
		c.next_factor = 1.0
	Mind.add(agent, "advanced_realm", sim.calendar.ticks_per_day)


func take_events() -> Array:
	var result: Array = events
	events = []
	return result


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "next_id": next_id}


func from_dict(data: Dictionary) -> void:
	entries = data.entries
	next_id = int(data.next_id)


## A trial while the valley passes abstractly (meditation): announced,
## faced and decided at once by the same odds and outcomes, without the
## storm's strikes. A protect rule the god set for this person spends Favour
## on a shield, and on Defy Heaven, within its limit, as the god would.
func abstract_trial(sim: RefCounted, agent: RefCounted, site: Vector3i) -> String:
	var id: int = announce(sim, agent, site)
	if id <= 0:
		return ""
	var trial: Dictionary = entries[id]
	_protect(sim, trial, agent)
	agent.cell = site
	_begin(sim, trial, agent)
	_resolve(sim, trial, agent)
	entries.erase(id)
	return str(trial.outcome)


func _protect(sim: RefCounted, trial: Dictionary, agent: RefCounted) -> void:
	var rule: Dictionary = sim.god.protect.get(agent.id, {})
	if rule.is_empty() or sim.faith == null:
		return
	var shrine: Dictionary = sim.faith.get_shrine(1)
	if shrine.is_empty():
		return
	var limit: float = float(rule.get("limit", 0.0))
	var spent: float = 0.0
	for miracle in ["shield_trial", "defy_heaven"]:
		if miracle == "defy_heaven" and str(rule.get("mode", "")) != "defy":
			continue
		var cost: float = float(Data.miracle(miracle).cost)
		if float(shrine.favour) < cost or spent + cost > limit:
			continue
		shrine.favour = float(shrine.favour) - cost
		spent += cost
		if miracle == "shield_trial":
			trial.shield = Balance.number("cultivation.shield_amount")
		else:
			trial.defy = true
		sim.chronicle_event("miracle", int(agent.settlement_id), {"miracle": miracle}, "cause_protect_rule|%s" % agent.given_name, [agent.id])
