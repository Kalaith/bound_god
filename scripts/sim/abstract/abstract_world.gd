extends RefCounted
## The abstract settlement model (plan §3.1): time passes in hourly steps
## with people frozen out of the BDI cycle. Begin freezes everyone; each hour
## advances the calendar, each person's body and each settlement's food by
## the detailed rules; each day runs the systems that do not touch blocks
## (spoilage, births and ageing, standing, faith, migrants) exactly as the
## detailed world does. Ending materialises the result: bushes and crops
## where the record says, people at plausible places, plans rebuilt.
## Outcomes come only from the same balance numbers, and every death,
## birth, arrival and harvest is chronicled with its cause.
## Randomness comes from the sim's rng, in settlement id order.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Spoilage = preload("res://scripts/sim/spoilage.gd")
const Lifecycle = preload("res://scripts/sim/lifecycle.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const DeliberationFaith = preload("res://scripts/agents/deliberation_faith.gd")
const ExecuteFaith = preload("res://scripts/sim/execute_faith.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const AbstractPeople = preload("res://scripts/sim/abstract/abstract_people.gd")
const AbstractEconomy = preload("res://scripts/sim/abstract/abstract_economy.gd")
const AbstractBuild = preload("res://scripts/sim/abstract/abstract_build.gd")
const AbstractCultivation = preload("res://scripts/sim/abstract/abstract_cultivation.gd")

## Chronicle kinds that wake a meditating god whoever they concern.
const WAKING: Array[String] = ["shrine_fell", "tree_unlock", "sect_master", "sect_founded"]

var from_tick: int = 0
## Hours one step covers (rates scale with it): longer meditations take
## longer steps so decades pass in seconds (see step_for).
var step: int = 1


## The step for a span of days: hourly within a year, two hours up to ten
## years, three beyond.
static func step_for(days: float, year_days: float) -> int:
	if days <= year_days:
		return 1
	return 2 if days <= year_days * 10.0 else 3
## settlement id -> economy record (abstract_economy.gd)
var records: Dictionary = {}


## Freezes every present person and surveys every settlement.
static func begin(sim: RefCounted) -> RefCounted:
	var model = load("res://scripts/sim/abstract/abstract_world.gd").new()
	model.from_tick = sim.calendar.tick
	for agent in sim.agents:
		if agent.is_present():
			freeze(agent)
	sim.goal_version += 1
	for id in sim.settlements.ids():
		model.records[id] = AbstractEconomy.survey(sim, id)
	return model


## A frozen person keeps everything they are and know; only what they were
## doing this moment is let go.
static func freeze(agent: RefCounted) -> void:
	agent.intention = {}
	agent.path.clear()
	agent.inside = -1
	agent.inbox.clear()
	agent.step_result = {}
	agent.interrupted_by = ""
	agent.mental_break = {}
	agent.help_task = {}


## Runs up to `hours` hours; stops early and returns the reason when
## something wakes the god ({} when it ran them all).
func run_hours(sim: RefCounted, hours: int) -> Dictionary:
	for _i in range(ceili(float(hours) / step)):
		var reason: Dictionary = step_hour(sim)
		if not reason.is_empty():
			return reason
	return {}


## One hour. Returns why the god should wake ({kind, agent, entry}), or {}.
func step_hour(sim: RefCounted) -> Dictionary:
	var seen: int = sim.chronicle.entries.size()
	var wake: Dictionary = {}
	var per_step: int = sim.calendar.ticks_per_hour() * step
	sim.calendar.tick = (sim.calendar.tick / per_step + 1) * per_step
	if sim.calendar.tick % sim.calendar.ticks_per_day == 0:
		_day(sim)
	var praying: bool = _prayer_hour(sim)
	var sitting: bool = _in_step(sim, AbstractCultivation.SITTINGS)
	var k: Dictionary = AbstractPeople.context(sim, step)
	## settlement id -> [working hands, people present], counted on the way.
	var counts: Dictionary = {}
	for agent in sim.agents:
		if not agent.is_present():
			continue
		var count: Array = counts.get(agent.settlement_id, [0.0, 0])
		count[1] = int(count[1]) + 1
		if not agent.is_child and AbstractPeople.at_work(k, agent):
			count[0] = float(count[0]) + agent.capacity()
		counts[agent.settlement_id] = count
		AbstractPeople.hour(sim, agent, records.get(agent.settlement_id, {}), step)
		if agent.is_present() and praying:
			_pray(sim, agent)
		if agent.is_present() and _leaving(sim, agent):
			EffectsApply._leave(sim, agent)
		if agent.is_present() and sitting:
			var facing: int = AbstractCultivation.hour(sim, agent, AbstractCultivation.SITTING_HOURS)
			if facing >= 0 and wake.is_empty():
				wake = {"kind": "trial", "agent": facing}
		if agent.is_present() and sim.god.followed.has(agent.id) and float(agent.health.hp) < 35.0 and wake.is_empty():
			wake = {"kind": "danger", "agent": agent.id}
	for id in sim.settlements.ids():
		if records.has(id):
			var count: Array = counts.get(id, [0.0, 0])
			AbstractBuild.hour(sim, id, AbstractEconomy.hour(sim, id, records[id], float(count[0]) * step, int(count[1])))
	sim.faith.hourly(sim)
	if wake.is_empty():
		wake = _woken_by(sim, seen)
	return wake


## Something new in the chronicle that wakes the god: a pinned person's
## death or new realm, a fallen shrine, a new phenomenon, a succession.
func _woken_by(sim: RefCounted, seen: int) -> Dictionary:
	for i in range(seen, sim.chronicle.entries.size()):
		var entry: Dictionary = sim.chronicle.entries[i]
		if WAKING.has(str(entry.kind)):
			return {"kind": str(entry.kind), "agent": -1, "entry": entry}
		for id in entry.agents:
			if sim.god.followed.has(int(id)) and str(entry.kind) in ["death", "departed", "trial_passed", "trial_injured", "trial_died", "trial_defied", "realm_reached"]:
				return {"kind": str(entry.kind), "agent": int(id), "entry": entry}
	return {}


func _day(sim: RefCounted) -> void:
	Spoilage.daily(sim)
	for id in sim.settlements.ids():
		if not records.has(id):
			records[id] = AbstractEconomy.survey(sim, id)
		AbstractEconomy.day(sim, id, records[id])
		# A new project is weighed every few days, not every morning.
		if (sim.calendar.day() + id) % AbstractBuild.PLAN_EVERY_DAYS == 0:
			AbstractBuild.day(sim, id, records[id])
	Lifecycle.daily(sim)
	sim.settlement_life.daily(sim)
	sim.sects.daily(sim)
	sim.tree_growth.daily(sim)
	AbstractCultivation.day(sim)
	sim.faith.daily(sim)
	if sim.requests != null:
		sim.requests.daily(sim)
	var day: int = sim.calendar.day()
	var first: int = Balance.integer("population.first_migrant_day")
	if day >= first and (day - first) % Balance.integer("population.migrant_roll_days") == 0:
		sim.director._migrants(sim)
	# Newcomers and children arrive frozen.
	for agent in sim.agents:
		if agent.is_present() and not agent.intention.is_empty():
			freeze(agent)


## Believers pray at dawn and dusk, as the detailed rhythm brings them to.
func _prayer_hour(sim: RefCounted) -> bool:
	return _in_step(sim, [Balance.number("time.dawn_hour"), Balance.number("time.dusk_hour")])


## Whether one of these hours of the day falls within this step.
func _in_step(sim: RefCounted, hours: Array) -> bool:
	var hour: float = sim.calendar.hour()
	for at in hours:
		if float(at) >= hour and float(at) < hour + step:
			return true
	return false


static func _pray(sim: RefCounted, agent: RefCounted) -> void:
	if not agent.faith.knows or agent.is_child:
		return
	var stage: int = FaithState.stage(agent.faith)
	if stage < 3 and not (stage == 2 and agent.need(agent.lowest_need()) < Balance.number("needs.urgent_threshold")):
		return
	var shrine: int = DeliberationFaith.attended_shrine(sim, agent)
	if shrine >= 0:
		sim.faith.record_prayer(sim, agent, shrine, ExecuteFaith.intent(sim, agent))


## Lasting misery past the departure point: they leave, as Migrate would
## take them (to another settlement they know, or out of the valley).
static func _leaving(sim: RefCounted, agent: RefCounted) -> bool:
	if agent.is_child or sim.calendar.day() - agent.joined_day < Balance.integer("mood.settle_days"):
		return false
	return float(agent.low_mood_ticks) / sim.calendar.ticks_per_day >= Balance.number("mood.departure_days")


## Materialise: the record's bushes and crops into the world, people at
## places they would plausibly be at this hour, and everyone deciding anew.
func finish(sim: RefCounted) -> void:
	for id in sim.settlements.ids():
		if records.has(id):
			_bushes(sim, records[id])
			_crops(sim, records[id])
	for site_id in sim.construction.ids():
		AbstractBuild.stamp(sim, sim.construction.get_site(site_id))
	for agent in sim.agents:
		if agent.is_present():
			thaw(sim, agent)
	sim.goal_version += 1


static func _bushes(sim: RefCounted, record: Dictionary) -> void:
	var count: int = record.bushes.size()
	if count == 0:
		return
	var most: int = Balance.integer("world.bush_max_berries")
	var left: int = int(floor(float(record.ripe)))
	var bush: int = Registry.id("berry_bush")
	for i in range(count):
		var site: Dictionary = sim.sites.get_site(record.bushes[i])
		if site.is_empty() or site.cells.is_empty() or sim.voxels.get_block(site.cells[0]) != bush:
			continue
		var share: int = mini(most, int(ceil(float(left) / float(count - i))))
		left -= share
		sim.set_block(site.cells[0], bush, share, "growth")


## Crops stand where the record's field cycle has them: none while fallow.
static func _crops(sim: RefCounted, record: Dictionary) -> void:
	var crop: Dictionary = Crops.staple()
	var block: int = Registry.id(crop.block)
	for farmland in record.fields:
		var cell: Vector3i = farmland + Vector3i.UP
		if sim.voxels.get_block(cell) == block:
			sim.set_block(cell, 0, 0, "growth")
		if int(record.growth) < 0 or not Crops.is_farmland(sim, farmland) or sim.voxels.get_block(cell) != 0:
			continue
		sim.crops.sow(sim, cell, crop, "growth")
		var stage: int = mini(int(record.growth) / int(crop.days_per_stage), int(crop.stages) - 1)
		sim.crops.plots[cell].days = int(record.growth) % int(crop.days_per_stage)
		if stage > 0:
			sim.set_block(cell, block, stage, "growth")


## A thawed person: at home by night, about the settlement by day.
static func thaw(sim: RefCounted, agent: RefCounted) -> void:
	freeze(agent)
	var settlement: Dictionary = sim.settlements.get_settlement(agent.settlement_id)
	var cell: Vector3i = Vector3i(-1, -1, -1)
	if agent.activity == "sleeping" and agent.home >= 0 and sim.structures.entries.has(agent.home):
		cell = sim.structure_access(agent.home, agent.cell)
	if cell.x < 0 and not settlement.is_empty():
		var center: Vector3i = settlement.camp
		cell = H.ring_cell(sim, Vector3(center.x + 0.5, center.y, center.z + 0.5), agent.id, 2.0, 7.0)
	if cell.x < 0 or not sim.nav.is_walkable(cell):
		cell = sim.nav.nearest_walkable(agent.cell, 6)
	if cell.x >= 0:
		agent.cell = cell
		agent.position = Movement.center(cell)
		agent.previous_position = agent.position
	agent.activity = "idle"
	agent.next_deliberation = sim.calendar.tick + agent.id % 3
	if sim.settlements.entries.has(agent.settlement_id):
		agent.beliefs.stock = sim.settlements.stock_of(agent.settlement_id).duplicate()
