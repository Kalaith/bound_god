extends RefCounted
## The sacred tree learns (M17). A tribulation faced in its sanctuary gives it
## insight of that kind: most the first time, less each time after. Insights
## are knowledge, not something spent. Maturity grows by itself, day by day,
## and with what the tree learns; its phases widen the crown. An insight
## deep enough unlocks a capability: lightning lets the tree bear spirit
## fruit, a few a season, which strengthens a breakthrough's preparation.
## Lightning leaves scars on the bark; the god can nurture a spot into
## dense qi for a season. Everything is chronicled with its cause.
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Balance = preload("res://scripts/core/balance.gd")
const TreeAbilities = preload("res://scripts/sim/tree_abilities.gd")

## kind -> amount of insight
var insights: Dictionary = {}
## kind -> how many trials of it the tree has witnessed
var witnessed: Dictionary = {}
## Where each insight came from: Array of {tick, day, kind, name, outcome, gain}
var history: Array = []
var maturity: float = 0.0
## Index of the maturity phase the crown has grown to.
var phase: int = 0
## Unlock ids, in the order they came.
var unlocks: Array = []
## Spirit fruit hanging on the tree now, and how many grew this season.
var fruit: int = 0
var fruit_season: int = -1
var fruit_grown: int = 0
## Lightning scars on the bark: Array of {cell, side: Vector3i, tick}
var scars: Array = []
## Nurtured spots of dense qi: Array of {cell, radius, qi, until}
var nurtured: Array = []
## Relics great cultivators left at the tree: Array of {name, realm, tick}
var relics: Array = []
## Columns the root network reaches along worn paths (rebuilt daily and on
## load, not saved): Vector2i -> true.
var rooted: Dictionary = {}
var rooted_day: int = -1
## The worn path columns the roots run along (for drawing), sorted.
var rooted_paths: Array = []


static func data() -> Dictionary:
	return Data.tree_growth()


func has_unlock(id: String) -> bool:
	return unlocks.has(id)


## How much a trial of `kind` would teach the tree now.
func gain_for(kind: String, severity: float) -> float:
	var insight: Dictionary = data().insight
	var times: int = int(witnessed.get(kind, 0))
	var kind_weight: float = 1.0
	for entry in Data.tribulations().kinds:
		if entry.id == kind:
			kind_weight = float(entry.insight)
	return float(insight.first) * kind_weight * pow(float(insight.repeat_factor), times) * (float(insight.severity_base) + severity)


## A trial has ended. Only those faced in the sanctuary teach the tree.
func on_trial(sim: RefCounted, trial: Dictionary, agent: RefCounted) -> void:
	if not bool(trial.sanctuary):
		return
	var kind: String = str(trial.kind)
	var gain: float = gain_for(kind, float(trial.severity))
	var first: bool = int(witnessed.get(kind, 0)) == 0
	witnessed[kind] = int(witnessed.get(kind, 0)) + 1
	insights[kind] = float(insights.get(kind, 0.0)) + gain
	history.append({"tick": sim.calendar.tick, "day": sim.calendar.day(), "kind": kind, "name": agent.full_name(), "outcome": trial.outcome, "gain": gain})
	_grow(sim, gain * float(data().insight.maturity_share))
	sim.chronicle_event("tree_insight", int(agent.settlement_id), {"name": agent.full_name(), "kind": "insight_" + kind},
		"cause_first_insight" if first else "cause_deeper_insight", [agent.id])
	_scar(sim, trial)
	_check_unlocks(sim)


## The tree learns from more than lightning: a winter or a drought its
## people came through, the Way taught beneath it, a death in its shade.
## Each lesson of a kind teaches a little less than the one before; the
## first is chronicled, every one is kept (the latest few) as a source.
func lesson(sim: RefCounted, id: String, name: String = "", people: Array = []) -> void:
	var entry: Dictionary = _lesson(id)
	var kind: String = str(entry.insight)
	var times: int = int(witnessed.get(kind, 0))
	var gain: float = float(entry.first) * pow(float(entry.repeat_factor), times)
	witnessed[kind] = times + 1
	insights[kind] = float(insights.get(kind, 0.0)) + gain
	history.append({"tick": sim.calendar.tick, "day": sim.calendar.day(), "kind": kind, "name": name, "outcome": "lesson_" + id, "gain": gain})
	_trim_lessons(kind)
	_grow(sim, gain * float(data().insight.maturity_share))
	if times == 0:
		sim.chronicle_event("tree_learned", _tree_place(sim), {"kind": "insight_" + kind, "lesson": "lesson_" + id, "name": name}, "cause_first_insight", people)
	_check_unlocks(sim)


static func _lesson(id: String) -> Dictionary:
	for entry in data().lessons:
		if str(entry.id) == id:
			return entry
	push_error("Unknown tree lesson " + id)
	return {}


## Lessons come often; only the latest few of a kind are kept as sources.
func _trim_lessons(kind: String) -> void:
	var most: int = int(data().lesson_records)
	var count: int = 0
	for i in range(history.size() - 1, -1, -1):
		if str(history[i].kind) != kind or not str(history[i].outcome).begins_with("lesson_"):
			continue
		count += 1
		if count > most:
			history.remove_at(i)


## Whether a cell lies in the tree's shade, where it learns from what
## happens (while abstract, anyone of the tree's own settlement).
func in_shade(sim: RefCounted, cell: Vector3i, settlement_id: int) -> bool:
	if sim.meditating:
		return settlement_id == _tree_place(sim) and settlement_id >= 0
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	return tree.x >= 0 and Vector2(cell.x - tree.x, cell.z - tree.z).length() <= float(data().lesson_reach)


func daily(sim: RefCounted) -> void:
	_grow(sim, float(data().maturity.per_day))
	_check_unlocks(sim)
	var season: int = (sim.calendar.day() - 1) / sim.calendar.days_per_season
	if season != fruit_season:
		# Spring after a winter its people came through.
		if fruit_season >= 0 and sim.calendar.season_name() == "spring" and _tree_place(sim) >= 0 \
				and not sim.settlements.entries[_tree_place(sim)].residents.is_empty():
			lesson(sim, "winter")
		fruit_season = season
		fruit_grown = 0
	TreeAbilities.daily(sim)
	_bear_fruit(sim)
	var kept: Array = []
	for spot in nurtured:
		if int(spot.until) > sim.calendar.tick:
			kept.append(spot)
	if kept.size() != nurtured.size():
		nurtured = kept
		sim.qi.clear_cache()


func _check_unlocks(sim: RefCounted) -> void:
	for unlock in data().unlocks:
		if unlocks.has(unlock.id):
			continue
		var needs: Dictionary = unlock.requires
		# An unlock asks for an insight's depth, the tree's maturity (its
		# phase), an earlier unlock, or several of these together.
		if needs.has("maturity") and maturity < float(needs.maturity):
			continue
		if needs.has("insight") and float(insights.get(str(needs.insight), 0.0)) < float(needs.amount):
			continue
		if needs.has("unlock") and not unlocks.has(str(needs.unlock)):
			continue
		unlocks.append(unlock.id)
		var cause: String = "cause_insight_%s" % str(needs.insight) if needs.has("insight") else "cause_maturity"
		sim.chronicle_event("tree_unlock", _tree_place(sim), {"unlock": "unlock_" + str(unlock.id)}, cause, [])


## Spirit fruit ripens a few at a time through the season (none in winter),
## spaced so a season brings `per_season` and no more than `most` hang at once.
func _bear_fruit(sim: RefCounted) -> void:
	if not has_unlock("spirit_fruit") or sim.calendar.is_winter():
		return
	var settings: Dictionary = data().fruit
	var per_season: int = int(settings.per_season)
	if fruit_grown >= per_season or fruit >= int(settings.most):
		return
	var every: int = maxi(1, sim.calendar.days_per_season / per_season)
	if (sim.calendar.day_of_season() - 1) % every != 0:
		return
	fruit += 1
	fruit_grown += 1
	sim.chronicle_event("fruit_ripened", _tree_place(sim), {"count": fruit}, "cause_insight_lightning", [])


## Why the god cannot ripen a fruit now, or "".
func ripen_problem() -> String:
	if not has_unlock("spirit_fruit"):
		return "miracle_no_fruit"
	if fruit >= int(data().fruit.most):
		return "miracle_fruit_full"
	return ""


## The god ripens a fruit out of its season's turn (the Ripen Fruit miracle).
func ripen(sim: RefCounted) -> void:
	fruit += 1
	sim.chronicle_event("fruit_ripened", _tree_place(sim), {"count": fruit}, "cause_god", [])


## Someone picks a fruit from the tree. Returns whether there was one.
func pick(sim: RefCounted) -> bool:
	if fruit <= 0:
		return false
	fruit -= 1
	return true


static func _tree_place(sim: RefCounted) -> int:
	return sim.settlements.at_cell(sim.features.get("sacred_tree", Vector3i.ZERO))


func _grow(sim: RefCounted, amount: float) -> void:
	maturity += amount
	var phases: Array = data().maturity.phases
	while phase + 1 < phases.size() and maturity >= float(phases[phase + 1].at):
		phase += 1
		_widen_crown(sim, float(phases[phase].crown))
		sim.chronicle_event("tree_grew", _tree_place(sim), {"phase": "phase_" + str(phases[phase].id)}, "cause_maturity", [])


## The crown spreads: sacred leaves fill the air just beyond it, as the
## world made it, a little wider each phase.
static func _widen_crown(sim: RefCounted, extra: float) -> void:
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	if tree.x < 0:
		return
	var crown: int = Registry.id("sacred_leaves")
	var top: int = tree.y - 1
	var middle := Vector3(tree.x + 0.5, top + 11, tree.z + 0.5)
	var reach: int = 6 + ceili(extra)
	var batch: Array = []
	for y in range(top + 6, top + 16):
		for z in range(tree.z - reach, tree.z + reach + 2):
			for x in range(tree.x - reach, tree.x + reach + 2):
				var cell := Vector3i(x, y, z)
				var offset := Vector3(x + 0.5, y + 0.5, z + 0.5) - middle
				offset.y *= 1.5
				var length: float = offset.length()
				if length >= 5.6 and length < 5.6 + extra and sim.voxels.get_block(cell) == 0 and not sim.is_occupied(cell):
					batch.append([cell, crown, 0])
	sim.set_blocks(batch, "growth")


## Lightning in the sanctuary marks the bark on the side it fell.
func _scar(sim: RefCounted, trial: Dictionary) -> void:
	var cells: Array = sim.features.get("sacred_tree_cells", [])
	if cells.is_empty():
		return
	var settings: Dictionary = data().scars
	var site: Vector3i = trial.site
	var trunk: Vector3i = cells[0]
	var side := Vector3i(signi(site.x - trunk.x), 0, signi(site.z - trunk.z))
	if side == Vector3i.ZERO:
		side = Vector3i(1, 0, 0)
	for i in range(int(settings.per_trial)):
		var base: Vector3i = cells[(int(trial.id) + i) % cells.size()]
		scars.append({"cell": base + Vector3i(0, 1 + (int(trial.id) * 3 + i * 2) % 7, 0), "side": side, "tick": sim.calendar.tick})
	while scars.size() > int(settings.most):
		scars.pop_front()


## The god deepens qi round a spot for a season.
func nurture(sim: RefCounted, cell: Vector3i) -> void:
	var settings: Dictionary = data().nurture
	nurtured.append({"cell": cell, "radius": float(settings.radius), "qi": float(settings.qi),
		"until": sim.calendar.tick + sim.calendar.ticks_for_days(float(settings.days))})
	sim.qi.clear_cache()


func phase_id() -> String:
	return str(data().maturity.phases[phase].id)


func to_dict() -> Dictionary:
	return {"insights": insights.duplicate(), "witnessed": witnessed.duplicate(), "history": history.duplicate(true),
		"maturity": maturity, "phase": phase, "unlocks": unlocks.duplicate(), "fruit": fruit, "fruit_season": fruit_season,
		"fruit_grown": fruit_grown, "scars": scars.duplicate(true), "nurtured": nurtured.duplicate(true), "relics": relics.duplicate(true)}


func from_dict(state: Dictionary) -> void:
	insights = state.insights
	witnessed = state.witnessed
	history = state.history
	maturity = float(state.maturity)
	phase = int(state.phase)
	unlocks = state.unlocks
	fruit = int(state.fruit)
	fruit_season = int(state.fruit_season)
	fruit_grown = int(state.fruit_grown)
	scars = state.scars
	nurtured = state.nurtured
	relics = state.get("relics", [])


## A cultivator of Foundation Establishment or beyond leaves a relic at the
## tree when they die; relics steady those who face Heaven in its sanctuary.
func leave_relic(sim: RefCounted, agent: RefCounted) -> void:
	relics.append({"name": agent.full_name(), "realm": int(agent.cultivation.realm), "tick": sim.calendar.tick})
	sim.chronicle_event("relic_left", _tree_place(sim), {"name": agent.full_name()}, "cause_great_cultivator", [agent.id])


## What the relics add to a trial's preparation in the sanctuary; `extra`
## more relics count where an ancestral hall's tablets keep them.
func relic_preparation(extra: int = 0) -> float:
	return minf(float(relics.size()), Balance.number("cultivation.relics_most") + extra) * Balance.number("cultivation.relic_preparation")
